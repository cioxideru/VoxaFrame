import SmartTubeIOSCore
import SwiftUI
import VideoToolbox
import os

private let offlineDetailLog = Logger(subsystem: appSubsystem, category: "OfflinePlayback")
private let offlineHardwareCodecs: Set<VideoCodec> = {
    #if targetEnvironment(simulator)
    return []
    #else
    var codecs = Set<VideoCodec>()
    if VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) { codecs.insert(.av1) }
    if HLSPlaybackPolicy.isVP9DecodingAvailable { codecs.insert(.vp9) }
    return codecs
    #endif
}()

/// Play saved files first; adding media online is a separate, secondary action.
struct OfflineVideoDetail: View {
    let videoID: String
    var isEmbedded = false
    @State private var coordinator = OfflineCoordinator.shared
    @State private var available: [OfflineTrack] = []
    @State private var selection = OfflineDetailPresentation.Selection()
    @State private var error: String?
    @State private var refreshing = false
    @State private var sponsorUpdating = false
    @State private var sponsorFailed = false
    @Environment(\.innerTubeAPI) private var api
    #if os(iOS)
    @Environment(PlayerRouter.self) private var router
    #else
    @State private var selectedVideo: Video?
    #endif
    private var entry: OfflineEntry? { coordinator.snapshot.entries.first { $0.id == videoID } }
    /// `enqueue` is ignored while storage is blocked and fails while a removal is pending.
    private var isLocked: Bool {
        OfflinePresentation.isLocked(
            storageError: coordinator.error, persistenceBlocked: coordinator.persistenceBlocked,
            pendingRemovals: coordinator.snapshot.pendingRemovals)
    }

    var body: some View {
        Group {
            if isEmbedded {
                detailList
            } else {
                detailList
                    .navigationTitle(entry.map { Text($0.video.title) } ?? Text("Offline video", bundle: .module))
                    .toolbarTitleDisplayMode(.inline)
                    #if os(iOS)
                .toolbar {
                    // Retain the navigation title for the back stack; the visible title is in the header.
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                }
                    #endif
            }
        }
        .onChange(of: entry.map { [$0.id] + $0.assets.map(\.id) }, initial: true) {
            if let entry { selection.update(entry: entry) }
        }
        #if os(macOS)
        // Use the main window's player surface so system full screen is available for saved videos too.
        .navigationDestination(item: $selectedVideo) { video in PlayerView(video: video, api: api) }
        #elseif !os(iOS)
        .sheet(item: $selectedVideo) { video in PlayerView(video: video, api: api) }
        #endif
    }

    private var detailList: some View {
        List {
            if let storageError = coordinator.error { OfflineStorageNotice(message: storageError) }
            if let entry {
                #if DEBUG
                if OfflineUITestFixture.baseURL != nil {
                    // Real rows at the top stay observable without opening pickers or changing selections.
                    Section {
                        ForEach(entry.assets) { asset in
                            Text(
                                [.video, .hls].contains(asset.track.kind)
                                    ? OfflineDetailPresentation.savedVideoLabel(asset) : asset.track.label
                            )
                            .font(.caption)
                            .accessibilityIdentifier(AccessibilityID.offlineSaved(asset.id))
                        }
                    }
                }
                #endif
                header(entry)
                watchWith(entry)
                sponsorBlock(entry)
                downloadMore(entry)
            }
            if let error {
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: AppSymbol.warning)
                }
                .foregroundStyle(VFColor.danger)
            }
        }
        .accessibilityIdentifier(AccessibilityID.offlineDetailList)
    }

    private func header(_ entry: OfflineEntry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: VFSpace.s8) {
                Text(OfflinePresentation.title(of: entry.id, in: [entry]))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if !entry.video.channelTitle.isEmpty {
                    Text(entry.video.channelTitle).font(.footnote).foregroundStyle(.secondary)
                }
                if let video = selection.video(in: entry.assets) {
                    if entry.assets.filter({ [.video, .hls].contains($0.track.kind) }).count == 1 {
                        Text(OfflineDetailPresentation.savedVideoLabel(video))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let bytes = video.track.estimatedBytes, bytes > 0 {
                        Text("Approx. \(OfflinePresentation.bytesText(bytes))", bundle: .module)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        play(entry, asset: video)
                    } label: {
                        Label {
                            Text("Play", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.play)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier(AccessibilityID.offlinePlay(video.id))
                    Text(
                        OfflineDetailPresentation.summary(video: video, selection: selection, assets: entry.assets).text
                    )
                    .font(.subheadline)
                    .accessibilityIdentifier(AccessibilityID.offlinePlaySummary)
                } else {
                    Label {
                        Text("Video is not downloaded yet. Open Downloads to see progress.", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.clock)
                    }
                }
            }
            .padding(.vertical, VFSpace.s8)
        }
    }

    @ViewBuilder private func watchWith(_ entry: OfflineEntry) -> some View {
        let videos = entry.assets.filter { [.video, .hls].contains($0.track.kind) }
        let audio = entry.assets.filter { $0.track.kind == .audio }.map(\.track)
        let translations = entry.assets.filter { $0.track.kind == .translation }
        let video = selection.video(in: entry.assets)
        let includesAudio = video?.track.hasAudio == true || video?.track.kind == .hls
        let showsAudio = video != nil && !audio.isEmpty && (includesAudio || audio.count > 1)
        if videos.count > 1 || showsAudio || !translations.isEmpty {
            Section {
                if videos.count > 1 {
                    Picker(selection: $selection.videoID) {
                        ForEach(videos) { asset in
                            Text(OfflineDetailPresentation.savedVideoLabel(asset)).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Video", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineVideoPicker)
                    .accessibilityValue(video.map(OfflineDetailPresentation.savedVideoLabel) ?? "")
                }
                if showsAudio, let video {
                    Picker(
                        selection: Binding(
                            get: { selection.audio(for: video, in: entry.assets)?.id },
                            set: { selection.audioID = $0 }
                        )
                    ) {
                        ForEach(OfflineDetailPresentation.audioOptions(for: video.track, saved: audio)) { option in
                            Text(option.label).tag(option.id)
                        }
                    } label: {
                        Text("Audio", bundle: .module)
                    }
                    .disabled(video.track.kind == .hls)
                    .accessibilityIdentifier(AccessibilityID.offlineAudioPicker)
                    if video.track.kind == .hls {
                        Text("HLS uses the audio saved inside the video.", bundle: .module)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !translations.isEmpty {
                    Picker(
                        selection: Binding(get: { selection.translationID }, set: { selection.chooseTranslation($0) })
                    ) {
                        Text("Off", bundle: .module).tag(nil as String?)
                        ForEach(translations) { asset in
                            Text(OfflineDetailPresentation.languageName(asset.track.language)).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Voice-over (Yandex)", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineTranslationPicker)
                    .accessibilityValue(
                        selection.translation(in: entry.assets).map {
                            OfflineDetailPresentation.languageName($0.track.language)
                        } ?? String(localized: "Off", bundle: .module))
                }
            } header: {
                Text("Watch with", bundle: .module)
            }
        }
    }

}

extension OfflineVideoDetail {
    private func sponsorBlock(_ entry: OfflineEntry) -> some View {
        Section {
            Button {
                sponsorUpdating = true
                Task {
                    sponsorFailed = !(await coordinator.refreshSponsorSegments(videoID: entry.id))
                    sponsorUpdating = false
                }
            } label: {
                HStack(spacing: VFSpace.s4) {
                    if sponsorUpdating { ProgressView().accessibilityHidden(true) }
                    Label {
                        Text("Update SponsorBlock", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.updateSponsorBlock)
                    }
                }
            }
            .disabled(sponsorUpdating || isLocked || !coordinator.sponsor.isEnabled() || entry.assets.isEmpty)
            .accessibilityIdentifier(AccessibilityID.offlineUpdateSponsorBlock)
            Group {
                if sponsorFailed {
                    Text("Could not update. Check your connection and try again.", bundle: .module)
                } else if let sponsor = entry.sponsor {
                    Text(
                        "\(sponsor.segments.count) segments · updated \(sponsor.fetchedAt.formatted(date: .abbreviated, time: .omitted))",
                        bundle: .module)
                } else {
                    Text("No SponsorBlock segments saved yet.", bundle: .module)
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier(AccessibilityID.offlineSponsorBlockStatus)
        } header: {
            Text("SponsorBlock", bundle: .module)
        }
    }

    @ViewBuilder private func downloadMore(_ entry: OfflineEntry) -> some View {
        let catalog = OfflineDetailPresentation.catalog(
            available, saved: entry.assets, targetLanguages: YandexVOTClient.targetLanguages.sorted(),
            hardwareCodecs: offlineHardwareCodecs)
        Section {
            findVariants(entry)
        } header: {
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text("Download more", bundle: .module)
                Text("Internet required", bundle: .module).font(.caption).textCase(nil)
            }
        }
        #if os(tvOS)
        ForEach(catalog.videoGroups) { group in
            Section {
                ForEach(group.tracks) { track in
                    videoDownloadButton(track, group: group, entry: entry, showsQuality: false)
                }
            } header: {
                Text(String(localized: "Video", bundle: .module) + " · " + group.title)
            }
            .accessibilityIdentifier(AccessibilityID.offlineQualityGroup(group.height))
        }
        #else
        if !catalog.videoGroups.isEmpty {
            Section {
                ForEach(catalog.videoGroups) { group in
                    if group.tracks.count == 1, let track = group.tracks.first {
                        videoDownloadButton(track, group: group, entry: entry, showsQuality: true)
                    } else {
                        DisclosureGroup {
                            ForEach(group.tracks) { track in
                                videoDownloadButton(track, group: group, entry: entry, showsQuality: false)
                            }
                        } label: {
                            Text(group.title)
                        }
                        .disclosureGroupStyle(OfflineQualityDisclosureStyle(height: group.height))
                    }
                }
            } header: {
                Text("Video", bundle: .module)
            }
        }
        #endif
        if !catalog.audio.isEmpty {
            Section {
                ForEach(catalog.audio) { track in
                    downloadButton(
                        track, of: entry, name: OfflineDetailPresentation.audioLabel(track),
                        detail: OfflineDetailPresentation.audioDetail(track))
                }
            } header: {
                Text("Audio tracks", bundle: .module)
            }
        }
        if !catalog.translationLanguages.isEmpty {
            Section {
                ForEach(catalog.translationLanguages, id: \.self) { language in
                    downloadButton(
                        .translation(language), of: entry, name: OfflineDetailPresentation.languageName(language))
                }
            } header: {
                Text("Voice-over in another language", bundle: .module)
            }
        }
    }

    private func videoDownloadButton(
        _ track: OfflineTrack, group: OfflineDetailPresentation.VideoGroup, entry: OfflineEntry, showsQuality: Bool
    ) -> some View {
        let format = OfflineDetailPresentation.videoDetail(track)
        var details = showsQuality ? [format] : []
        if !OfflineDetailPresentation.isPlayable(track, hardwareCodecs: offlineHardwareCodecs) {
            details.append(String(localized: "May not play on this device", bundle: .module))
        } else if track.id == group.recommendedID {
            details.append(String(localized: "Recommended", bundle: .module))
        }
        return downloadButton(
            track, of: entry, name: showsQuality ? group.title : format,
            detail: details.isEmpty ? nil : details.joined(separator: " · "))
    }

    private func findVariants(_ entry: OfflineEntry) -> some View {
        Button {
            refreshing = true
            Task {
                defer { refreshing = false }
                do {
                    available = try await coordinator.catalog(video: entry.video)
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        } label: {
            if refreshing {
                HStack(spacing: VFSpace.s8) {
                    Text("Loading available variants…", bundle: .module)
                    ProgressView()
                }
            } else {
                Text("Other quality or audio…", bundle: .module)
            }
        }
        .disabled(refreshing)
        .accessibilityIdentifier(AccessibilityID.offlineFindVariants)
    }

    private func downloadButton(
        _ track: OfflineTrack, of entry: OfflineEntry, name: String, detail: String? = nil
    ) -> some View {
        Button {
            enqueue(track, of: entry)
        } label: {
            // A plain button only hit-tests drawn content; make the Spacer gap tappable too.
            variantRow(name, detail: detail, track: track).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading(track) || isLocked)
        .accessibilityIdentifier(
            track.kind == .translation
                ? AccessibilityID.offlineDownloadTranslation(track.language ?? "")
                : AccessibilityID.offlineDownload(track.id))
    }

    /// Checked again at tap time: a removal may have started in another window.
    private func enqueue(_ track: OfflineTrack, of entry: OfflineEntry) {
        guard !isLocked else { return }
        if let job = job(for: track), OfflinePresentation.action(job) == .retry {
            coordinator.retry(job)
        } else {
            coordinator.enqueue(video: entry.video, tracks: [track])
        }
    }

    private func job(for track: OfflineTrack) -> OfflineJob? {
        coordinator.snapshot.jobs.last { $0.videoID == videoID && $0.track.id == track.id }
    }

    private func isLoading(_ track: OfflineTrack) -> Bool {
        coordinator.snapshot.jobs.contains {
            $0.videoID == videoID && $0.track.id == track.id && [.queued, .resolving, .downloading].contains($0.state)
        }
    }

    private func variantRow(_ name: String, detail: String?, track: OfflineTrack) -> some View {
        let job = job(for: track)
        return ViewThatFits(in: .horizontal) {
            HStack {
                variantDescription(name, detail: detail, job: job)
                Spacer(minLength: VFSpace.s8)
                downloadState(track, job: job)
            }
            VStack(alignment: .leading, spacing: VFSpace.s8) {
                variantDescription(name, detail: detail, job: job)
                downloadState(track, job: job)
            }
        }
    }

    private func variantDescription(_ name: String, detail: String?, job: OfflineJob?) -> some View {
        VStack(alignment: .leading, spacing: VFSpace.s4) {
            Text(name).foregroundStyle(.primary)
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            if let job {
                OfflinePresentation.status(job).label
                if let reason = job.error {
                    Text(OfflinePresentation.failureText(reason)).font(.footnote).foregroundStyle(VFColor.danger)
                }
            }
        }
    }

    @ViewBuilder private func downloadState(_ track: OfflineTrack, job: OfflineJob?) -> some View {
        if let job, OfflinePresentation.action(job) == .retry {
            Text("Retry", bundle: .module)
        } else if isLoading(track) {
            HStack(spacing: VFSpace.s4) {
                ProgressView().accessibilityHidden(true)
                Text("Downloading…", bundle: .module)
            }
        } else {
            Label {
                Text("Download", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.download)
            }
            .foregroundStyle(.primary)
        }
    }

    private func play(_ entry: OfflineEntry, asset: OfflineAsset) {
        offlineDetailLog.notice("[offline-start] tap videoId=\(entry.id, privacy: .public)")
        let audio = selection.audio(for: asset, in: entry.assets)
        let translation = selection.translation(in: entry.assets)
        Task {
            do {
                let video = try await coordinator.playbackVideo(
                    entry: entry, videoAsset: asset, audio: audio, translation: translation)
                #if os(iOS)
                router.open(video: video, api: api)
                #else
                selectedVideo = video
                #endif
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

#if !os(tvOS)
private struct OfflineQualityDisclosureStyle: DisclosureGroupStyle {
    let height: Int

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isExpanded.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isExpanded ? AppSymbol.chevronDown : AppSymbol.chevronRight)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.offlineQualityGroup(height))
        .accessibilityValue(
            configuration.isExpanded ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module))
        if configuration.isExpanded { configuration.content }
    }
}
#endif
