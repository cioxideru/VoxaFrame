import Foundation
import Testing

@testable import SmartTubeIOSCore

// OQ-0025: when YouTube reports a video as fully watched, playback starts from the beginning instead of resuming at an
// older position saved on this device.

@Suite("Resume follows YouTube's full completion")
struct RemoteCompletionResumeTests {

    private let videoId = "watchedvid1"

    private func makeStore() async -> VideoStateStore {
        let store = VideoStateStore(suiteName: "test-\(UUID().uuidString)")
        await store.save(videoId: videoId, position: 30, duration: 100)
        return store
    }

    private func video(watchProgress: Double?) -> Video {
        Video(id: videoId, title: "Watched", channelTitle: "Channel", duration: 100, watchProgress: watchProgress)
    }

    @Test("A full YouTube watch starts from the beginning and drops the saved position")
    func fullRemoteWatchStartsFromZero() async {
        let store = await makeStore()
        #expect(await store.resumeState(for: video(watchProgress: 1)) == nil)
        #expect(await store.state(for: videoId) == nil)
    }

    @Test("Partial or missing YouTube progress keeps the saved position", arguments: [nil, 0.5, 0.99] as [Double?])
    func partialRemoteProgressKeepsSavedPosition(remote: Double?) async {
        let store = await makeStore()
        #expect(await store.resumeState(for: video(watchProgress: remote))?.position == 30)
        #expect(await store.state(for: videoId)?.position == 30)
    }

    @Test("A full YouTube watch without a saved position starts from the beginning")
    func fullRemoteWatchWithoutSavedPosition() async {
        let store = VideoStateStore(suiteName: "test-\(UUID().uuidString)")
        #expect(await store.resumeState(for: video(watchProgress: 1)) == nil)
    }
}
