import SmartTubeIOSCore
import SwiftUI

// MARK: - QueueView
//
// The play queue, read straight from `CurrentQueueStore` (PLAN-0027 A1): it never waits for account
// playlists and needs no sign-in. Shown by Library › Queue, the iPad and Mac sidebar Queue item and Home's
// Current Queue row (through `PlaylistView`). Clear Queue asks first (B3). Reorder and remove are A3.
// It does not listen for `.openChannel`: its host screen does. `PlaylistViewModel` loads the queue and drops
// cards on Not Interested / Don't Recommend Channel, as on any playlist; Hide Shorts applies as there.

struct QueueView: View {
    let api: InnerTubeAPI
    @Environment(SettingsStore.self) private var store
    @State private var vm: PlaylistViewModel
    @State private var isLoaded = false
    /// Stored videos, hidden ones included: Clear Queue stays while any are stored.
    @State private var storedCount = 0
    @State private var confirmsClear = false
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #else
    @State private var selectedVideo: Video?
    #endif

    init(api: InnerTubeAPI) {
        self.api = api
        _vm = State(initialValue: PlaylistViewModel(api: api))
    }

    var body: some View {
        Group {
            if !isLoaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if storedCount == 0 {
                emptyState
            } else {
                list(displayVideos)
            }
        }
        // Runs on every appearance, so the queue is current after playing a list elsewhere.
        .task { await reload() }
        #if !os(iOS)
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .accessibilityIdentifier(AccessibilityID.queueView)
    }

    private var displayVideos: [Video] {
        vm.videos.filter { !store.settings.hideShorts || !$0.isShort }
    }

    private func reload() async {
        await vm.refresh(playlistId: CurrentQueueStore.playlistID)
        storedCount = await loader.storedCount()
        isLoaded = true
    }

    private let loader = CurrentQueuePlaylistLoader()

    /// Hands the visible list to the player as the queue, so hidden videos are not played next.
    private func play(_ video: Video, from visible: [Video]) {
        Task {
            let toPlay = await loader.play(video, from: visible)
            #if os(iOS)
            playerRouter.open(video: toPlay, api: api)
            #else
            selectedVideo = toPlay
            #endif
        }
    }

    private func list(_ videos: [Video]) -> some View {
        ScrollView {
            header(count: storedCount)
            if videos.isEmpty {
                // Everything stored is hidden (e.g. only Shorts with Hide Shorts on); Clear Queue stays above.
                Text("Every video in the queue is hidden by Hide Shorts or Not Interested.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VFSpace.s16)
            }
            VideoGridSection(videos: videos, onSelect: { play($0, from: videos) })
        }
        .refreshable { await reload() }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.s12) {
            Text("\(count) videos · on this device", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                confirmsClear = true
            } label: {
                Label {
                    Text("Clear Queue", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.trash)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(AccessibilityID.queueClearButton)
            // B3: nothing is cleared without this answer; Cancel is the default.
            .confirmationDialog(
                Text("Clear the Queue?", bundle: .module), isPresented: $confirmsClear, titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    Task {
                        await CurrentQueueStore.shared.clear()
                        await reload()
                    }
                } label: {
                    Text("Clear Queue", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.queueClearConfirm)
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text("Offline videos and playlists stay as they are.", bundle: .module)
            }
        }
        .padding(.horizontal, VFSpace.s16)
        .padding(.vertical, VFSpace.s8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("Queue Is Empty", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.queue)
            }
        } description: {
            Text(
                "Playing a list makes it the queue. Add single videos with Add to Queue in a video's menu.",
                bundle: .module)
        }
    }
}
