import SmartTubeIOSCore
import SwiftUI

struct OfflineWatchButton: View {
    let video: Video
    let action: () -> Void
    private var isQueued: Bool {
        OfflineCoordinator.shared.snapshot.jobs.contains {
            $0.videoID == video.id && [.queued, .resolving, .downloading].contains($0.state)
        }
    }
    var body: some View {
        Button(action: action) {
            Label(isQueued ? "Offline watch · queued" : "Offline watch", systemImage: AppSymbol.download)
        }
        .accessibilityIdentifier(AccessibilityID.offlineWatch)
        .disabled(video.isLive || video.isUpcoming || video.isDownloaded)
    }
}

struct OfflineVideosView: View {
    @State private var coordinator = OfflineCoordinator.shared
    @State private var showsProgress = false
    @State private var deletion: (videoID: String, jobID: UUID?)?
    var body: some View {
        VStack {
            Picker("Offline videos", selection: $showsProgress) {
                Text("Library").tag(false)
                Text("Downloads").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier(AccessibilityID.offlinePagePicker)
            if let error = coordinator.error {
                Text(error).foregroundStyle(.red).padding()
                Button("Retry library storage") { coordinator.retryStorage() }
            }
            if showsProgress { progressList } else { libraryList }
        }
        .navigationTitle("Offline videos")
        .task { coordinator.start() }
        .confirmationDialog(
            "Delete downloaded files?",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletion { coordinator.remove(videoID: deletion.videoID, jobID: deletion.jobID) }
                deletion = nil
            }
        } message: {
            Text(
                deletion?.jobID == nil
                    ? "This removes the video, all downloaded audio and translations, and its pending downloads."
                    : "This removes the task and its downloaded files. Other saved tracks are kept.")
        }
    }
    private var libraryList: some View {
        List {
            if coordinator.snapshot.entries.isEmpty {
                Text("Choose Offline watch from a video's menu. Accepted downloads continue when you leave this page.")
            }
            ForEach(coordinator.snapshot.entries) { entry in
                HStack {
                    NavigationLink {
                        OfflineVideoDetail(videoID: entry.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.video.title)
                            Text("\(entry.assets.count) saved variants and audio tracks").font(.caption)
                                .foregroundStyle(
                                    .secondary)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineEntry(entry.id))
                    Button(role: .destructive) {
                        deletion = (entry.id, nil)
                    } label: {
                        Label("Delete video and files", systemImage: AppSymbol.trash)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(AccessibilityID.offlineDeleteEntry(entry.id))
                }
            }
        }
    }
    private var progressList: some View {
        List {
            if coordinator.isYielding { Text("Downloads are paused while playback needs the connection.") }
            ForEach(coordinator.snapshot.jobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(coordinator.snapshot.entries.first { $0.id == job.videoID }?.video.title ?? job.videoID)
                    Text(job.track.label).font(.caption)
                    Text(
                        job.state == .queued && job.nextResolutionAt != nil
                            ? "Waiting for translation" : job.state.rawValue.capitalized
                    ).font(.caption)
                    if job.state == .downloading {
                        ProgressView(value: job.progress)
                        Text(job.progress, format: .percent.precision(.fractionLength(0))).font(.caption)
                    }
                    if let error = job.error { Text(error).foregroundStyle(.red).font(.caption) }
                    if [.queued, .resolving, .downloading].contains(job.state) {
                        Button("Cancel", role: .destructive) { coordinator.cancel(job) }
                            .accessibilityIdentifier(AccessibilityID.offlineCancel(job.id))
                    } else if [.failed, .cancelled].contains(job.state) {
                        Button("Retry") { coordinator.retry(job) }
                            .accessibilityIdentifier(AccessibilityID.offlineRetry(job.id))
                    }
                    Button("Delete task and files", role: .destructive) { deletion = (job.videoID, job.id) }
                        .accessibilityIdentifier(AccessibilityID.offlineDeleteJob(job.id))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.offlineJob(job.id))
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct OfflineVideoDetail: View {
    let videoID: String
    @State private var coordinator = OfflineCoordinator.shared
    @State private var available: [OfflineTrack] = []
    @State private var audioID: String?
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
    var body: some View {
        List {
            if let entry {
                Section("Saved audio") {
                    Picker("Original or dubbed audio", selection: $audioID) {
                        Text("Included audio").tag(nil as String?)
                        ForEach(entry.assets.filter { $0.track.kind == .audio }) { asset in
                            Text(asset.track.label).tag(Optional(asset.id))
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineAudioPicker)
                    Picker("Yandex translation", selection: $translationID) {
                        Text("Without translation").tag(nil as String?)
                        ForEach(entry.assets.filter { $0.track.kind == .translation }) { asset in
                            Text(asset.track.label).tag(Optional(asset.id))
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.offlineTranslationPicker)
                }
                Section("Play saved video") {
                    if audioID != nil, entry.assets.contains(where: { $0.track.kind == .hls }) {
                        Text(
                            "Choose Included audio to play an HLS package. Separate audio tracks apply to direct video files."
                        )
                    }
                    ForEach(entry.assets.filter { [.video, .hls].contains($0.track.kind) }) { asset in
                        Button(savedLabel(asset)) { play(entry, asset: asset) }
                            .disabled(asset.track.kind == .hls && audioID != nil)
                            .accessibilityIdentifier(AccessibilityID.offlinePlay(asset.id))
                    }
                    if !entry.assets.contains(where: { [.video, .hls].contains($0.track.kind) }) {
                        Text("Video is not downloaded yet. Open Downloads to see progress.")
                    }
                }
                Section("Add video quality or audio") {
                    Button(refreshing ? "Loading available variants…" : "Find available variants (online)") {
                        refreshing = true
                        Task {
                            defer { refreshing = false }
                            do {
                                available = try await coordinator.catalog(video: entry.video)
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(refreshing)
                        .accessibilityIdentifier(AccessibilityID.offlineFindVariants)
                    ForEach(available) { track in
                        let saved = entry.assets.contains { $0.id == track.id }
                        let loading = coordinator.snapshot.jobs.contains {
                            $0.videoID == videoID && $0.track.id == track.id
                                && [.queued, .resolving, .downloading].contains($0.state)
                        }
                        Button("\(track.label) · \(saved ? "Saved" : loading ? "Downloading" : "Download")") {
                            coordinator.enqueue(video: entry.video, tracks: [track])
                        }.disabled(saved || loading)
                            .accessibilityIdentifier(AccessibilityID.offlineDownload(track.id))
                    }
                }
                Section("Add Yandex translation (online)") {
                    ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                        let track = OfflineTrack.translation(language)
                        Button(track.label) { coordinator.enqueue(video: entry.video, tracks: [track]) }
                            .disabled(entry.assets.contains { $0.id == track.id })
                            .accessibilityIdentifier(AccessibilityID.offlineDownloadTranslation(language))
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(entry?.video.title ?? "Offline video")
        #if !os(iOS)
        .sheet(item: $selectedVideo) { video in PlayerView(video: video, api: api) }
        #endif
    }
    private func savedLabel(_ asset: OfflineAsset) -> String {
        guard let sizes = asset.savedVideoSizes, !sizes.isEmpty else { return asset.track.label }
        return asset.track.label + " · " + sizes.map { "\($0.width)×\($0.height)" }.joined(separator: ", ")
    }
    private func play(_ entry: OfflineEntry, asset: OfflineAsset) {
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
