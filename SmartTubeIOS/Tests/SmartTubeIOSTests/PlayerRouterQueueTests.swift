#if os(iOS)
import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class OfflineURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

// MARK: - PlayerRouterQueueTests (A2)
//
// Play Next asks the router where the playing video sits in the Current Queue. Picking the playing video again from
// another list keeps it playing and must move that position, also when the queue holds the video twice.

@Suite("Play Next position through PlayerRouter")
@MainActor
struct PlayerRouterQueueTests {
    private let api: InnerTubeAPI = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineURLProtocol.self]
        return InnerTubeAPI(authToken: nil, session: URLSession(configuration: config))
    }()

    private func video(_ id: String) -> Video { Video(id: id, title: id, channelTitle: "C") }

    private func makeQueue(_ ids: [String]) async -> CurrentQueueStore {
        let queue = CurrentQueueStore(suiteName: "router-queue-\(UUID().uuidString)")
        await queue.replaceAll(with: ids.map(video))
        return queue
    }

    /// A router whose player is playing `video`, as after an earlier `open`. Callers step the router without
    /// suspending: at an `await` the player's observers would mark the stand-in item as paused.
    private func makeRouter(
        playing video: Video, queue: CurrentQueueStore? = nil
    ) throws -> (router: PlayerRouter, state: PlayerStateStore) {
        let state = PlayerStateStore(api: api)
        if let queue { state.queue = queue }
        state.vm.localHistory = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "router-history-\(UUID().uuidString)")))
        state.vm.resetPlaybackForLoad(video: video, incognito: false)
        state.vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        state.vm.isPlaying = true
        return (PlayerRouter(playerState: state, settingsStore: SettingsStore()), state)
    }

    @Test("Picking the video that is still loading in another list moves the Play Next position too")
    func sameSourceWhileLoading() async throws {
        let playing = try #require(await makeQueue(["a", "b"]).videoAt(index: 0))
        let otherList = await makeQueue(["x", "a", "c"])
        let picked = try #require(await otherList.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing)
        state.vm.isPlaying = false
        state.vm.isLoading = true
        let inFlight = Task { @MainActor in }
        state.vm.loadTask = inFlight
        defer { inFlight.cancel() }

        router.open(video: picked, api: api)
        let after = router.playingQueueIndex

        #expect(!inFlight.isCancelled)
        #expect(after == 1)
        await otherList.playNext(video("new"), playingIndex: after)
        #expect(await otherList.videos.map(\.id) == ["x", "a", "new", "c"])
    }

    @Test("Stopping right after the adoption leaves Next off")
    func stopCancelsSuccessorCheck() async throws {
        let playing = try #require(await makeQueue(["a"]).videoAt(index: 0))
        let otherList = await makeQueue(["x", "a", "c"])
        let picked = try #require(await otherList.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing, queue: otherList)
        state.vm.hasNext = false

        router.open(video: picked, api: api)
        let check = try #require(state.successorCheck)
        state.stop()
        await check.value

        #expect(check.isCancelled)
        #expect(!state.vm.hasNext)
    }

    @Test("A successor in the adopted queue enables Next without reloading")
    func adoptedQueueEnablesNext() async throws {
        let playing = try #require(await makeQueue(["a"]).videoAt(index: 0))
        let otherList = await makeQueue(["x", "a", "c"])
        let picked = try #require(await otherList.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing, queue: otherList)
        let item = state.vm.player.currentItem
        state.vm.hasNext = false

        router.open(video: picked, api: api)

        #expect(state.vm.player.currentItem === item)
        await waitForTasks { state.vm.hasNext }
        #expect(state.vm.hasNext)
    }

    @Test("Picking the playing video in another list moves the Play Next position without reloading")
    func sameSourceFromAnotherList() async throws {
        let playing = try #require(await makeQueue(["a", "b"]).videoAt(index: 0))
        let otherList = await makeQueue(["x", "a"])
        let picked = try #require(await otherList.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing)
        let item = state.vm.player.currentItem
        let before = router.playingQueueIndex

        router.open(video: picked, api: api)
        let after = router.playingQueueIndex

        #expect(state.vm.player.currentItem === item)
        #expect(before == 0)
        #expect(after == 1)
        await otherList.playNext(video("new"), playingIndex: after)
        #expect(await otherList.videos.map(\.id) == ["x", "a", "new"])
    }

    @Test("A video queued twice takes the position of the occurrence picked last")
    func duplicateOccurrences() async throws {
        let queue = await makeQueue(["a", "b", "a"])
        let first = try #require(await queue.videoAt(index: 0))
        let second = try #require(await queue.videoAt(index: 2))
        let (router, state) = try makeRouter(playing: first)
        let item = state.vm.player.currentItem

        router.open(video: second, api: api)
        let afterSecond = router.playingQueueIndex
        router.open(video: first, api: api)
        let afterFirst = router.playingQueueIndex

        #expect(state.vm.player.currentItem === item)
        #expect(afterSecond == 2)
        #expect(afterFirst == 0)
        await queue.playNext(video("new"), playingIndex: afterSecond)
        #expect(await queue.videos.map(\.id) == ["a", "b", "a", "new"])
    }

    @Test("Picking the playing video outside the queue leaves nothing from the queue playing")
    func sameSourceOutsideQueue() async throws {
        let playing = try #require(await makeQueue(["a", "b"]).videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing)
        let item = state.vm.player.currentItem

        router.open(video: video("b"), api: api)

        #expect(state.vm.player.currentItem === item)
        #expect(router.playingQueueIndex == nil)
    }
}
#endif
