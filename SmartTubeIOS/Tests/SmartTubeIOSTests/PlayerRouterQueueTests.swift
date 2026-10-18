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

private final class EmptyRelatedVideosURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, ["next", "search", "empty"].contains(url.lastPathComponent) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        // The async redirect delegate can hold the request without sending this URLProtocol across actors.
        if url.lastPathComponent == "search" {
            let destination = url.appendingPathComponent("empty")
            guard
                let redirect = HTTPURLResponse(
                    url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": destination.absoluteString])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: redirect)
            return
        }
        guard
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class HeldSearchDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var heldSearch: CheckedContinuation<Void, Never>?
    private var finished = false

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard !finished else { return nil }
        await withCheckedContinuation { heldSearch = $0 }
        return request
    }

    func finishSearch() {
        finished = true
        let continuation = heldSearch
        heldSearch = nil
        continuation?.resume()
    }
}

@MainActor
private final class HeldPlaybackQueue: PlaybackQueue {
    let store: CurrentQueueStore
    let holdClear: Bool
    private var shouldHold = true
    private(set) var heldOperation: CheckedContinuation<Void, Never>?
    private(set) var clearCount = 0

    init(store: CurrentQueueStore, holdClear: Bool) {
        self.store = store
        self.holdClear = holdClear
    }

    func videoAt(index: Int) async -> Video? {
        let video = await store.videoAt(index: index)
        if !holdClear { await holdOnce() }
        return video
    }

    func remainingVideos(after index: Int) async -> [Video] {
        let videos = await store.remainingVideos(after: index)
        if !holdClear { await holdOnce() }
        return videos
    }

    func clear() async {
        clearCount += 1
        await store.clear()
        if holdClear { await holdOnce() }
    }

    private func holdOnce() async {
        guard shouldHold else { return }
        shouldHold = false
        await withCheckedContinuation { heldOperation = $0 }
    }

    func finish(holdNext: Bool = false) {
        shouldHold = holdNext
        heldOperation?.resume()
        heldOperation = nil
    }
}

// MARK: - PlayerRouterQueueTests (A2)
//
// Play Next asks the router where the playing video sits in the Current Queue. Picking the playing video again from
// another list keeps it playing and must move that position, also when the queue holds the video twice.

@Suite("Play Next position through PlayerRouter", .serialized)
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
        playing video: Video, queue: (any PlaybackQueue)? = nil, api: InnerTubeAPI? = nil
    ) throws -> (router: PlayerRouter, state: PlayerStateStore) {
        let state = PlayerStateStore(api: api ?? self.api)
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

    @Test("Finishing an empty related-video load preserves Next in the adopted queue", arguments: [false, true])
    func adoptedQueueSurvivesRelatedLoad(whileLoading: Bool) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmptyRelatedVideosURLProtocol.self]
        let search = HeldSearchDelegate()
        let session = URLSession(configuration: config, delegate: search, delegateQueue: nil)
        let api = InnerTubeAPI(authToken: nil, session: session)
        let id = UUID().uuidString
        let oldQueue = await makeQueue(["old-0", "old-1", "old-2", id])
        let playing = try #require(await oldQueue.videoAt(index: 3))
        let queue = await makeQueue([])
        var successor = video("successor-\(id)")
        successor.localFileURL = URL(fileURLWithPath: "/dev/null")  // Next cannot start a live stream.
        await queue.replaceAll(with: [video("before"), video(id), successor])
        let picked = try #require(await queue.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing, queue: queue, api: api)
        let item = state.vm.player.currentItem
        let cached = CachedVideoData(
            playerInfo: nil, trackingURLs: nil, nextInfo: nil, endCards: [],
            sponsorSegments: [], deArrowBranding: nil, staleFields: [])
        let info = PlayerInfo(
            video: playing, formats: [], hlsURL: nil, dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])
        // Run the actual enrichment stage without stream resolution or decoding.
        let phase2 = Task { @MainActor in
            await state.vm.loadAsyncPhase2(
                video: playing, cached: cached, info: info, cachedTrackingURLs: nil,
                authTrackingTask: nil, sponsorCached: true)
        }
        state.vm.phase2Task = phase2
        defer {
            search.finishSearch()
            state.stop()
            session.invalidateAndCancel()
        }
        await waitForTasks { search.heldSearch != nil }
        try #require(search.heldSearch != nil)
        state.vm.isLoading = whileLoading
        state.vm.isPlaying = !whileLoading
        router.open(video: picked, api: api)
        let check = try #require(state.successorCheck)
        await check.value

        #expect(!phase2.isCancelled)
        #expect(state.vm.player.currentItem === item)
        #expect(state.vm.hasNext)
        #expect(router.playingQueueIndex == 1)

        search.finishSearch()
        await phase2.value

        #expect(state.vm.relatedVideos.isEmpty)
        #expect(state.vm.hasNext)
        #expect(router.playingQueueIndex == 1)
        state.vm.playNext()
        await waitForTasks { state.vm.currentVideo?.id == successor.id }
        state.vm.loadTask?.cancel()
        #expect(state.vm.currentVideo?.id == successor.id)
        #expect(router.playingQueueIndex == 2)
    }

    @Test("Pending queue navigation uses an adopted position", arguments: ["next", "autoplay", "shuffle"])
    func pendingNavigationUsesAdoptedQueue(action: String) async throws {
        let playing = try #require(await makeQueue(["old-0", "old-1", "old-2", "a"]).videoAt(index: 3))
        let queue = await makeQueue([])
        var successor = video("successor")
        successor.localFileURL = URL(fileURLWithPath: "/dev/null")
        await queue.replaceAll(with: [video("before"), video("a"), successor])
        let picked = try #require(await queue.videoAt(index: 1))
        let (router, state) = try makeRouter(playing: playing, queue: queue)
        defer { state.stop() }
        state.vm.settings.loopEnabled = false
        state.vm.settings.queueShuffleEnabled = action == "shuffle"
        if action == "next" { state.vm.playNext() } else { state.vm.handlePlaybackEnd() }
        // Reselect before the queued navigation Task gets to read the queue.
        router.open(video: picked, api: api)
        state.vm.settings.loopEnabled = false
        state.vm.settings.queueShuffleEnabled = action == "shuffle"
        await waitForTasks { state.vm.currentVideo?.id == successor.id }
        state.vm.loadTask?.cancel()

        #expect(state.vm.currentVideo?.id == successor.id)
        #expect(router.playingQueueIndex == 2)
        #expect(await queue.videos.count == 3)
    }

    @Test(
        "Suspended queue navigation retries the adopted position",
        arguments: ["next", "autoplay", "shuffle"], [false, true])
    func suspendedNavigationUsesAdoptedQueue(action: String, holdClear: Bool) async throws {
        let queue = await makeQueue(["old-0", "old-1", "old-2", "a"])
        let playing = try #require(await queue.videoAt(index: 3))
        let heldQueue = HeldPlaybackQueue(store: queue, holdClear: holdClear)
        let (router, state) = try makeRouter(playing: playing, queue: heldQueue)
        defer {
            heldQueue.finish()
            state.stop()
        }
        state.vm.settings.loopEnabled = false
        state.vm.settings.queueShuffleEnabled = action == "shuffle"
        if action == "next" { state.vm.playNext() } else { state.vm.handlePlaybackEnd() }
        await waitForTasks { heldQueue.heldOperation != nil }
        try #require(heldQueue.heldOperation != nil)

        var successor = video("successor")
        successor.localFileURL = URL(fileURLWithPath: "/dev/null")
        await queue.replaceAll(with: [video("before"), video("a"), successor])
        let picked = try #require(await queue.videoAt(index: 1))
        state.vm.isPlaying = true
        router.open(video: picked, api: api)
        state.vm.settings.queueShuffleEnabled = action == "shuffle"
        #expect(router.playingQueueIndex == 1)

        // Release the old lookup/clear only after the new queue position has been adopted.
        heldQueue.finish()
        await waitForTasks { state.vm.currentVideo?.id == successor.id }
        state.vm.loadTask?.cancel()

        #expect(state.vm.currentVideo?.id == successor.id)
        #expect(router.playingQueueIndex == 2)
        #expect(await queue.videos.count == 3)
        #expect(heldQueue.clearCount == (holdClear ? 1 : 0))
    }

    @Test("Repeated queue changes bound autoplay and mark the video ended", arguments: [false, true])
    func repeatedQueueChangesEndAutoplay(shuffle: Bool) async throws {
        let queue = await makeQueue(["a"])
        let playing = try #require(await queue.videoAt(index: 0))
        let heldQueue = HeldPlaybackQueue(store: queue, holdClear: false)
        let (_, state) = try makeRouter(playing: playing, queue: heldQueue)
        defer {
            heldQueue.finish()
            state.stop()
        }
        state.vm.settings.loopEnabled = false
        state.vm.settings.queueShuffleEnabled = shuffle
        state.vm.handlePlaybackEnd()
        for attempt in 0..<PlaybackTuning.maxQueueContextAttempts {
            await waitForTasks { heldQueue.heldOperation != nil }
            try #require(heldQueue.heldOperation != nil)
            state.vm.currentVideo?.setVideoId = "adoption-\(attempt)"
            heldQueue.finish(holdNext: true)
        }
        await waitForTasks { state.vm.videoEnded }

        #expect(state.vm.videoEnded)
        #expect(state.vm.currentVideo?.id == playing.id)
        #expect(heldQueue.clearCount == 0)
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

    @Test("Selecting the playing video on the queue screen after hiding one before it keeps Next on the queue")
    func queueScreenHandoffWhilePlaying() async throws {
        let queue = await makeQueue(["hidden", "b", "c"])
        let playing = try #require(await queue.videoAt(index: 1))
        let loader = CurrentQueuePlaylistLoader(store: queue)
        let stored = await loader.loadQueuedVideos(for: CurrentQueueStore.playlistID) ?? []
        let visible = stored.filter { $0.id != "hidden" }  // Not Interested or Hide Shorts
        let picked = await loader.play(visible[0], from: visible)
        #expect(picked.playlistId == CurrentQueueStore.playlistID)
        #expect(picked.playlistIndex == 0)
        let (router, state) = try makeRouter(playing: playing, queue: queue)
        let item = state.vm.player.currentItem
        state.vm.hasNext = false

        router.open(video: picked, api: api)

        #expect(state.vm.player.currentItem === item)  // no reload
        #expect(router.playingQueueIndex == 0)
        await waitForTasks { state.vm.hasNext }
        #expect(await queue.videoAt(index: 1)?.id == "c")
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
