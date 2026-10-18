import SmartTubeIOSCore
import SwiftUI
import os

private let offlineDetailLog = Logger(subsystem: appSubsystem, category: "OfflinePlayback")

/// Saved-video page: pick saved audio and translation, play a saved file, add variants online.
struct OfflineVideoDetail: View {
    let videoID: String
    var isEmbedded = false
    @State private var coordinator = OfflineCoordinator.shared
    @State private var available: [OfflineTrack] = []
    @State private var audioID: String?
    /// Not remembered: every visit starts without translation.
    @State private var translationID: String?
    @State private var error: String?
    @State private var refreshing = false
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
            }
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
                let videos = entry.assets.filter { [.video, .hls].contains($0.track.kind) }
                Section {
                    VStack(alignment: .leading, spacing: VFSpace.s4) {
                        Text(OfflinePresentation.title(of: entry.id, in: [entry]))
                            .font(.title3.weight(.semibold))
                        if !entry.video.channelTitle.isEmpty {
                            Text(entry.video.channelTitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if videos.isEmpty {
                        Label {
                            Text("Video is not downloaded yet. Open Downloads to see progress.", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.clock)
                        }
                    }
                }
                Section {
                    Picker(selection: $audioID) {
                        Text("Included audio", bundle: .module).tag(nil as String?)
                        ForEach(entry.assets.filter { $0.track.kind == .audio }) { asset in
                            Text(asset.track.label).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Original or dubbed audio", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineAudioPicker)
                    Picker(selection: $translationID) {
                        Text("Without translation", bundle: .module).tag(nil as String?)
                        ForEach(entry.assets.filter { $0.track.kind == .translation }) { asset in
                            Text(asset.track.label).tag(Optional(asset.id))
                        }
                    } label: {
                        Text("Yandex translation", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineTranslationPicker)
                } header: {
                    Text("Saved audio", bundle: .module)
                } footer: {
                    Text(
                        "Included audio is the sound inside the video file, or the first saved audio track when the file has none.",
                        bundle: .module)
                }
                if !videos.isEmpty {
                    Section {
                        ForEach(videos) { asset in
                            Button {
                                play(entry, asset: asset)
                            } label: {
                                Label(savedLabel(asset), systemImage: AppSymbol.play)
                            }
                            .disabled(asset.track.kind == .hls && audioID != nil)
                            .accessibilityIdentifier(AccessibilityID.offlinePlay(asset.id))
                        }
                    } header: {
                        Text("Play saved video", bundle: .module)
                    } footer: {
                        if audioID != nil, videos.contains(where: { $0.track.kind == .hls }) {
                            Text(
                                "Choose Included audio to play an HLS package. Separate audio tracks apply to direct video files.",
                                bundle: .module)
                        }
                    }
                }
                Section {
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
                            Text("Find available variants (online)", bundle: .module)
                        }
                    }
                    .disabled(refreshing)
                    .accessibilityIdentifier(AccessibilityID.offlineFindVariants)
                    ForEach(available) { track in
                        let saved = entry.assets.contains { $0.id == track.id }
                        let loading = isLoading(track)
                        Button {
                            enqueue(track, of: entry)
                        } label: {
                            variantRow(track.label, track: track, saved: saved)
                        }
                        .disabled(saved || loading || isLocked)
                        .accessibilityIdentifier(
                            saved ? AccessibilityID.offlineSaved(track.id) : AccessibilityID.offlineDownload(track.id))
                    }
                } header: {
                    Text("Add video quality or audio", bundle: .module)
                }
                Section {
                    ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                        let track = OfflineTrack.translation(language)
                        let saved = entry.assets.contains { $0.id == track.id }
                        Button {
                            enqueue(track, of: entry)
                        } label: {
                            variantRow(
                                OfflinePresentation.languageName(language), track: track, saved: saved)
                        }
                        .disabled(saved || isLoading(track) || isLocked)
                        .accessibilityIdentifier(
                            saved
                                ? AccessibilityID.offlineSaved(track.id)
                                : AccessibilityID.offlineDownloadTranslation(language))
                    }
                } header: {
                    Text("Add Yandex translation (online)", bundle: .module)
                }
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

    private func variantRow(_ name: String, track: OfflineTrack, saved: Bool) -> some View {
        let job = job(for: track)
        return HStack {
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(name).foregroundStyle(.primary)
                if !saved, let job {
                    OfflinePresentation.status(job).label
                    if let reason = job.error {
                        Text(OfflinePresentation.failureText(reason))
                            .font(.footnote)
                            .foregroundStyle(VFColor.danger)
                    }
                }
            }
            Spacer(minLength: VFSpace.s8)
            if saved {
                Text("Saved", bundle: .module).foregroundStyle(.secondary)
            } else if let job, OfflinePresentation.action(job) == .retry {
                Text("Retry", bundle: .module)
            } else if isLoading(track) {
                ProgressView()
                    .accessibilityHidden(true)
            } else {
                // Semantic colour and a symbol: the macOS and tvOS accent has no contrast-safe text variant.
                HStack(spacing: VFSpace.s4) {
                    Image(systemName: AppSymbol.download).accessibilityHidden(true)
                    Text("Download", bundle: .module)
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private func savedLabel(_ asset: OfflineAsset) -> String {
        guard let sizes = asset.savedVideoSizes, !sizes.isEmpty else { return asset.track.label }
        return asset.track.label + " · " + sizes.map { "\($0.width)×\($0.height)" }.joined(separator: ", ")
    }
    private func play(_ entry: OfflineEntry, asset: OfflineAsset) {
        offlineDetailLog.notice("[offline-start] tap videoId=\(entry.id, privacy: .public)")
        Task {
            do {
                let audio =
                    entry.assets.first { $0.id == audioID }
                    ?? (asset.track.hasAudio ? nil : entry.assets.first { $0.track.kind == .audio })
                let translation = entry.assets.first { $0.id == translationID }
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
