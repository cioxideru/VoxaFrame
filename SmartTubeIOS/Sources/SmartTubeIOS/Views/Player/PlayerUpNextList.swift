#if os(iOS) || os(macOS)
import SmartTubeIOSCore
import SwiftUI

/// What the Up next list depends on: the playing video and, for a Current Queue item, its position,
/// so consecutive duplicates ([A, A, B]) still refresh. Mirrors the queue check in `playNext()`.
struct UpNextSource: Hashable {
    let videoID: String?
    let queueIndex: Int?

    init(_ video: Video?) {
        videoID = video?.id
        queueIndex = CurrentQueueStore.queueIndex(of: video)
    }

    /// The queue items `playNext()` walks after this position; empty outside the queue.
    func remainingQueue(in store: CurrentQueueStore = .shared) async -> [Video] {
        guard let queueIndex else { return [] }
        return await store.remainingVideos(after: queueIndex)
    }
}

/// Shared by the Mac inspector and the iPhone/iPad Up Next panel.
struct PlayerUpNextList: View {
    let vm: PlaybackViewModel
    let onSelect: (Video) -> Void
    @State private var queue: [Video] = []

    var body: some View {
        ScrollView {
            let videos = queue.isEmpty ? vm.relatedVideos : queue
            if videos.isEmpty {
                if vm.isLoading {
                    ProgressView().padding(VFSpace.s32)
                } else {
                    Text("Nothing up next.", bundle: .module)
                        .foregroundStyle(.secondary)
                        .padding(VFSpace.s32)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: VFSpace.s8) {
                    ForEach(videos, id: \.upNextSource) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            UpNextRow(video: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            AccessibilityID.playerUpNextVideo(item.id, queueIndex: item.playlistIndex))
                    }
                }
                .padding()
            }
        }
        // Same order as `playNext()`, including repeated videos at different queue positions.
        .task(id: UpNextSource(vm.currentVideo)) {
            let remaining = await UpNextSource(vm.currentVideo).remainingQueue()
            if !Task.isCancelled { queue = remaining }
        }
    }
}

private extension Video {
    var upNextSource: UpNextSource { UpNextSource(self) }
}

private struct UpNextRow: View {
    let video: Video

    var body: some View {
        HStack(alignment: .top, spacing: VFSpace.s8) {
            ThumbnailFillView(primaryURL: video.thumbnailURL)
                .frame(width: 120, height: 120 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(video.title)
                    .font(.callout)
                    .lineLimit(2)
                if !video.channelTitle.isEmpty {
                    Text(video.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: VFTarget.touch)
        .contentShape(Rectangle())
    }
}
#endif
