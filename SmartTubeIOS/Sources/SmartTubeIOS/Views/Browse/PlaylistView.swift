import SmartTubeIOSCore
import SwiftUI

// MARK: - PlaylistView
//
// Shows the videos inside a user playlist.
// Mirrors the Android `PlaylistFragment`.

public struct PlaylistView: View {
    public let playlistId: String
    public let playlistTitle: String

    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.isLandscapeLayout) private var isLandscapeLayout
    @State private var vm: PlaylistViewModel
    @State private var selectedVideo: Video?
    @State private var channelDestination: ChannelDestination?
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif

    public init(playlistId: String, playlistTitle: String, api: InnerTubeAPI) {
        self.playlistId = playlistId
        self.playlistTitle = playlistTitle
        _vm = State(initialValue: PlaylistViewModel(api: api))
    }

    public var body: some View {
        Group {
            if isQueue {
                // The queue has its own screen (A1): read from the store, Clear Queue with confirmation (B3).
                QueueView(api: api)
            } else if vm.isLoading && vm.videos.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.videos.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(playlistTitle)
        .onAppear {
            guard !isQueue else { return }
            vm.load(playlistId: playlistId)
        }
        #if !os(iOS)
        // tvOS and macOS push the player in this stack, like a card click elsewhere.
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .navigationDestination(item: $channelDestination) { dest in
            ChannelView(channelId: dest.channelId, api: api)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        .alert("Error", isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button("Retry") { vm.load(playlistId: playlistId) }
            Button("Dismiss", role: .cancel) { vm.error = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
    }

    private var content: some View {
        ScrollView {
            if store.settings.compactThumbnails {

                LazyVStack(spacing: 0) {
                    ForEach(displayVideos) { video in
                        #if os(tvOS)
                        VideoCardView(
                            video: video, compact: true, currentPlaylistId: playlistId,
                            onSelect: {
                                Task { @MainActor in
                                    let captured = displayVideos
                                    await CurrentQueueStore.shared.replaceAll(with: captured)
                                    let startIdx =
                                        video.playlistIndex ?? captured.firstIndex(where: { $0.id == video.id }) ?? 0
                                    selectedVideo = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                                }
                            }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, VFSpace.s8)
                        .onAppear { vm.loadMoreIfNeeded(lastVideo: video) }
                        #else
                        VideoCardView(video: video, compact: true, currentPlaylistId: playlistId)
                            .padding(.horizontal)
                            .padding(.vertical, VFSpace.s8)
                            .onTapGesture {
                                #if os(iOS)
                                Task { @MainActor in
                                    let captured = displayVideos
                                    await CurrentQueueStore.shared.replaceAll(with: captured)
                                    let startIdx =
                                        video.playlistIndex ?? captured.firstIndex(where: { $0.id == video.id }) ?? 0
                                    let toPlay = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                                    playerRouter.open(video: toPlay, api: api)
                                }
                                #else
                                selectedVideo = video
                                #endif
                            }
                            .onAppear { vm.loadMoreIfNeeded(lastVideo: video) }
                        #endif
                        Divider().padding(.horizontal)
                    }
                    if vm.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
            } else {
                #if os(tvOS)
                let columnCount = 4
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stride(from: 0, to: displayVideos.count, by: columnCount)), id: \.self) { startIdx in
                        let rowVideos = Array(
                            displayVideos[startIdx..<min(startIdx + columnCount, displayVideos.count)])
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(rowVideos) { video in
                                VideoCardView(
                                    video: video, compact: false, currentPlaylistId: playlistId,
                                    onSelect: {
                                        Task { @MainActor in
                                            let captured = displayVideos
                                            await CurrentQueueStore.shared.replaceAll(with: captured)
                                            let startIdx =
                                                video.playlistIndex ?? captured.firstIndex(where: { $0.id == video.id })
                                                ?? 0
                                            selectedVideo =
                                                await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)
                            }
                            let remainder = columnCount - rowVideos.count
                            if remainder > 0 {
                                ForEach(0..<remainder, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .onAppear {
                            if let last = rowVideos.last { vm.loadMoreIfNeeded(lastVideo: last) }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                #else
                LazyVGrid(
                    columns: videoGridColumns(store.settings, landscape: isLandscapeLayout),
                    spacing: videoGridRowSpacing
                ) {
                    ForEach(displayVideos) { video in
                        VideoCardView(video: video, compact: false, currentPlaylistId: playlistId)
                            .onTapGesture {
                                #if os(iOS)
                                Task { @MainActor in
                                    let captured = displayVideos
                                    await CurrentQueueStore.shared.replaceAll(with: captured)
                                    let startIdx =
                                        video.playlistIndex ?? captured.firstIndex(where: { $0.id == video.id }) ?? 0
                                    let toPlay = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                                    playerRouter.open(video: toPlay, api: api)
                                }
                                #else
                                Task { @MainActor in
                                    let captured = displayVideos
                                    await CurrentQueueStore.shared.replaceAll(with: captured)
                                    let startIdx =
                                        video.playlistIndex ?? captured.firstIndex(where: { $0.id == video.id }) ?? 0
                                    selectedVideo = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                                }
                                #endif
                            }
                            .onAppear { vm.loadMoreIfNeeded(lastVideo: video) }
                    }
                }
                .id(isLandscapeLayout)  // reset on column-count change — see VideoGridSection (#82)
                .padding(.horizontal)
                .padding(.vertical, 8)
                #endif
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
        }
        .accessibilityIdentifier("playlistView.feed")
        .refreshable { vm.load(playlistId: playlistId, refresh: true) }
    }

    private var isQueue: Bool { playlistId == CurrentQueueStore.playlistID }

    private var displayVideos: [Video] {
        vm.videos.filter { !store.settings.hideShorts || !$0.isShort }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No videos in this playlist", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.stackLayers)
                    .accessibilityHidden(true)
            }
        } actions: {
            Button {
                vm.load(playlistId: playlistId, refresh: true)
            } label: {
                Text("Refresh", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
