import SmartTubeIOSCore
import SwiftUI
import VideoToolbox

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

/// File management for a library video; playback lives on its library card.
struct OfflineVideoDetail: View {
    let videoID: String
    var isEmbedded = false
    @State private var coordinator = OfflineCoordinator.shared
    @State private var available: [OfflineTrack] = []
    @State private var error: String?
    @State private var refreshing = false
    @State private var sponsorUpdating = false
    @State private var sponsorFailed = false
    @State private var showsDownloads = false
    @Environment(\.innerTubeAPI) private var api
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
        .sheet(isPresented: $showsDownloads) { OfflineDownloadsSheet(videoID: videoID) }

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
                if !isEmbedded { header(entry) }
                Section {
                    Button {
                        showsDownloads = true
                    } label: {
                        Label {
                            Text("Downloads", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.download)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineVideoDownloads)
                }
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
            if let entry { sponsorBlock(entry) }
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
            }
            .padding(.vertical, VFSpace.s8)
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
            Text("Try Again", bundle: .module)
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
