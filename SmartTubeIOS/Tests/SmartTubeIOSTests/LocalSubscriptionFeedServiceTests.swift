import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - LocalSubscriptionFeedServiceTests

@Suite("Local Subscription Feed Service", .serialized)  // RouterURLProtocol.routes is shared
@MainActor
struct LocalSubscriptionFeedServiceTests {

    // MARK: - Helpers

    private func makeStore(suiteName: String? = nil) -> LocalSubscriptionStore {
        LocalSubscriptionStore(suiteName: suiteName ?? "test-feedsvc-\(UUID().uuidString)")
    }

    private func makeCache() -> LocalSubscriptionFeedCache {
        LocalSubscriptionFeedCache()
    }

    private func makeChannel(id: String, title: String = "Channel") -> LocalChannel {
        LocalChannel(id: id, title: title)
    }

    /// Builds a `LocalSubscriptionFeedService` backed by `RouterURLProtocol`,
    /// seeding its routes for this test. `RouterURLProtocol.routes` is a
    /// shared static — callers must clear it (e.g. `defer { RouterURLProtocol.routes = [:] }`)
    /// so a route set here can't leak into a concurrently-running test.
    private func makeService(with routes: [String: Data]) -> LocalSubscriptionFeedService {
        RouterURLProtocol.routes = routes
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RouterURLProtocol.self]
        return LocalSubscriptionFeedService(session: URLSession(configuration: config))
    }

    // MARK: - Empty store

    @Test("fetchFeed returns empty array when no channels are followed")
    func fetchFeedEmptyStore() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        let service = LocalSubscriptionFeedService()

        let videos = await service.fetchFeed(store: store, cache: cache, api: api)
        #expect(videos.isEmpty)
    }

    // MARK: - Cache hit

    @Test("fetchFeed returns cached videos without calling InnerTube API")
    func fetchFeedCacheHit() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()

        let channel = makeChannel(id: "UCcache1")
        await store.follow(channel)

        // Pre-populate cache
        let cachedVideo = Video(id: "vid-cached", title: "Cached Video", channelTitle: "Channel")
        await cache.store(videos: [cachedVideo], for: "UCcache1")

        let service = LocalSubscriptionFeedService()
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        // Should return the cached video
        #expect(videos.map(\.id).contains("vid-cached"))
        // InnerTube should NOT have been called for channel videos
        let channelVideoCalls = api.calls.filter { $0.method == "fetchChannelVideos" }
        #expect(channelVideoCalls.isEmpty)
    }

    // MARK: - InnerTube fallback (when RSS would fail, InnerTube is tried)

    @Test("fetchFeed falls back to InnerTube when RSS returns no data")
    func fetchFeedInnerTubeFallback() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()

        // Configure mock to return a video for channel videos
        let mockVideo = Video(id: "vid-innertube", title: "InnerTube Video", channelTitle: "Channel")
        api.channelVideosResult = VideoGroup(title: "ChVideos", videos: [mockVideo])

        let channel = makeChannel(id: "UCfallback")
        await store.follow(channel)

        // Use a service with a session that will fail all RSS requests
        let session = URLSession(
            configuration: {
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [AlwaysFailURLProtocol.self]
                return config
            }())
        let service = LocalSubscriptionFeedService(session: session)
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        // InnerTube fallback should have provided the video
        #expect(videos.map(\.id).contains("vid-innertube"))
    }

    // MARK: - Deduplication

    @Test("fetchFeed deduplicates videos that appear in multiple channels")
    func fetchFeedDeduplicates() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()

        // Two channels, both with the same video in cache
        await store.follow(makeChannel(id: "UC1"))
        await store.follow(makeChannel(id: "UC2"))

        let sharedVideo = Video(id: "vid-shared", title: "Shared", channelTitle: "A")
        await cache.store(videos: [sharedVideo], for: "UC1")
        await cache.store(videos: [sharedVideo], for: "UC2")

        let service = LocalSubscriptionFeedService()
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        let sharedCount = videos.filter { $0.id == "vid-shared" }.count
        #expect(sharedCount == 1)
    }

    // MARK: - Arrival order (no date sort)

    @Test("fetchFeed returns videos in arrival order, not sorted by date")
    func fetchFeedPreservesArrivalOrder() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()

        await store.follow(makeChannel(id: "UCsort"))

        // Cache stores them with older first — arrival order, not newest-first.
        let older = Video(
            id: "vid-old", title: "Old", channelTitle: "C",
            publishedAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = Video(
            id: "vid-new", title: "New", channelTitle: "C",
            publishedAt: Date(timeIntervalSince1970: 2_000_000))
        await cache.store(videos: [older, newer], for: "UCsort")

        let service = LocalSubscriptionFeedService()
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        // Arrival order is preserved: older appears before newer because that's
        // how they were stored in the cache (RSS/InnerTube fetch order).
        #expect(videos.first?.id == "vid-old")
        #expect(videos.last?.id == "vid-new")
    }

    // MARK: - Shorts RSS enrichment

    @Test("RSS: video appearing in Shorts playlist feed is marked isShort = true")
    func rssShortMarkedWhenAppearsInShortsPlaylistFeed() async {
        let channelId = "UCtest1111111111111111111"
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        await store.follow(makeChannel(id: channelId))

        let uploadsXML = rssXML(channelId: channelId, videoIds: ["vid1", "vid2"])
        let shortsXML = rssXML(channelId: channelId, videoIds: ["vid2"])

        let uploadsURL = YouTubeRSS.feedURL(for: channelId).absoluteString
        let shortsURL = YouTubeRSS.shortsFeedURL(for: channelId).absoluteString

        let service = makeService(with: [uploadsURL: uploadsXML, shortsURL: shortsXML])
        defer { RouterURLProtocol.routes = [:] }
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        let vid1 = videos.first(where: { $0.id == "vid1" })
        let vid2 = videos.first(where: { $0.id == "vid2" })
        #expect(vid1?.isShort == false, "vid1 should not be marked as Short")
        #expect(vid2?.isShort == true, "vid2 appears in Shorts feed — should be marked isShort")
    }

    @Test("RSS: nil Shorts playlist feed does not crash and leaves isShort unchanged")
    func rssShortNilShortsPlaylistDoesNotCrash() async {
        let channelId = "UCtest2222222222222222222"
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        await store.follow(makeChannel(id: channelId))

        let uploadsXML = rssXML(channelId: channelId, videoIds: ["vid1", "vid2"])
        let uploadsURL = YouTubeRSS.feedURL(for: channelId).absoluteString

        // Shorts URL returns failure; uploads URL returns data normally.
        let service = makeService(with: [uploadsURL: uploadsXML])
        defer { RouterURLProtocol.routes = [:] }
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)

        #expect(videos.allSatisfy { !$0.isShort }, "No video should be marked isShort when Shorts feed is unavailable")
    }

    // MARK: - RSS XML builder

    @Test("Valid empty RSS is cached without invoking fallback")
    func validEmptyIsCached() async {
        let channelId = "UCempty"
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        await store.follow(makeChannel(id: channelId))
        let service = makeService(with: [
            YouTubeRSS.feedURL(for: channelId).absoluteString: rssXML(channelId: channelId, videoIds: [])
        ])
        defer { RouterURLProtocol.routes = [:] }
        #expect(await service.fetchFeed(store: store, cache: cache, api: api).isEmpty)
        #expect(await cache.videos(for: channelId)?.isEmpty == true)
        RouterURLProtocol.routes = [:]
        #expect(await service.fetchFeed(store: store, cache: cache, api: api).isEmpty)
        #expect(api.calls.isEmpty)
    }

    @Test(arguments: ["<html><body>Error</body></html>", "<feed xmlns='http://www.w3.org/2005/Atom'>"])
    func failedResponsesAreNotCached(body: String) async {
        let channelId = "UCfailed"
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        api.errorToThrow = URLError(.notConnectedToInternet)
        await store.follow(makeChannel(id: channelId))
        let service = makeService(with: [YouTubeRSS.feedURL(for: channelId).absoluteString: Data(body.utf8)])
        defer { RouterURLProtocol.routes = [:] }
        for _ in 0..<2 {
            #expect(await service.fetchFeed(store: store, cache: cache, api: api).isEmpty)
            #expect(await cache.videos(for: channelId) == nil)
        }
        #expect(api.calls.filter { $0.method == "fetchChannelVideos" }.count == 2)
    }

    @Test(arguments: [1, 20])
    func cancelledFeedCanRetryWithoutCachedFailureOrFallback(channelCount: Int) async {
        let channelId = "UCcancel"
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        await store.follow(makeChannel(id: channelId, title: "Original"))
        for index in 1..<channelCount { await store.follow(makeChannel(id: "UCcancel\(index)")) }
        let service = makeService(with: [
            YouTubeRSS.feedURL(for: channelId).absoluteString: rssXML(channelId: channelId, videoIds: ["retry"])
        ])
        RouterURLProtocol.reset(holding: true)
        defer {
            RouterURLProtocol.routes = [:]
            RouterURLProtocol.reset(holding: false)
        }
        let task = Task { await service.fetchFeed(store: store, cache: cache, api: api) }
        let expectedStarts = min(channelCount, LocalSubscriptionFeedService.maxConcurrentChannels) * 2
        await waitUntil { RouterURLProtocol.startedCount == expectedStarts }
        task.cancel()
        #expect(await task.value.isEmpty)
        #expect(await cache.videos(for: channelId) == nil)
        #expect(api.calls.isEmpty)
        #expect(RouterURLProtocol.startedCount == expectedStarts)
        let channels = await store.allChannels()
        #expect(channels.first(where: { $0.id == channelId })?.title == "Original")
        for channel in channels { #expect(await cache.videos(for: channel.id) == nil) }
        RouterURLProtocol.reset(holding: false)
        let videos = await service.fetchFeed(store: store, cache: cache, api: api)
        #expect(videos.map(\.id) == ["retry"])
        #expect(await cache.videos(for: channelId)?.map(\.id) == ["retry"])
    }

    @Test func manyChannelsHaveBoundedActiveRequests() async {
        let store = makeStore()
        let cache = makeCache()
        let api = MockInnerTubeAPI()
        var routes: [String: Data] = [:]
        for index in 0..<20 {
            let id = "UCbound\(index)"
            await store.follow(makeChannel(id: id))
            routes[YouTubeRSS.feedURL(for: id).absoluteString] = rssXML(channelId: id, videoIds: ["v\(index)"])
            routes[YouTubeRSS.shortsFeedURL(for: id).absoluteString] = rssXML(channelId: id, videoIds: [])
        }
        let service = makeService(with: routes)
        RouterURLProtocol.reset(holding: true)
        defer {
            RouterURLProtocol.routes = [:]
            RouterURLProtocol.reset(holding: false)
        }
        var completed = false
        let task = Task {
            let result = await service.fetchFeed(store: store, cache: cache, api: api)
            completed = true
            return result
        }
        await waitUntil { RouterURLProtocol.startedCount >= LocalSubscriptionFeedService.maxConcurrentChannels * 2 }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !completed, ContinuousClock.now < deadline {
            RouterURLProtocol.releasePending()
            await Task.yield()
        }
        if !completed { task.cancel() }
        #expect(await task.value.count == 20)
        #expect(RouterURLProtocol.peakCount <= LocalSubscriptionFeedService.maxConcurrentChannels * 2)
        #expect(RouterURLProtocol.startedCount == 40)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }

    private func rssXML(channelId: String, videoIds: [String]) -> Data {
        let entries = videoIds.map { id in
            """
            <entry>
              <yt:videoId>\(id)</yt:videoId>
              <title>Video \(id)</title>
              <author><name>Channel</name></author>
            </entry>
            """
        }.joined(separator: "\n")
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
                  xmlns="http://www.w3.org/2005/Atom">
              <title>Channel</title>
              \(entries)
            </feed>
            """
        return Data(xml.utf8)
    }
}

// MARK: - AlwaysFailURLProtocol

/// URLProtocol subclass that fails every request immediately.
/// Used to force the InnerTube fallback path in feed service tests.
private final class AlwaysFailURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

// MARK: - RouterURLProtocol

/// URLProtocol that returns pre-registered `Data` for matching URL strings,
/// and fails all other requests. Used to mock RSS feeds in tests.
private final class RouterURLProtocol: URLProtocol {
    /// Map from URL absolute string → response body. Set before creating the session.
    nonisolated(unsafe) static var routes: [String: Data] = [:]
    private static let lock = NSLock()
    // Every read and write is protected by lock.
    nonisolated(unsafe) private static var holding = false
    // Every read and write is protected by lock.
    nonisolated(unsafe) private static var pending: [ObjectIdentifier: RouterURLProtocol] = [:]
    // Every read and write is protected by lock.
    nonisolated(unsafe) private static var started = 0
    // Every read and write is protected by lock.
    nonisolated(unsafe) private static var peak = 0

    static var startedCount: Int { lock.withLock { started } }
    static var peakCount: Int { lock.withLock { peak } }

    static func reset(holding shouldHold: Bool) {
        lock.withLock {
            holding = shouldHold
            pending.removeAll()
            started = 0
            peak = 0
        }
    }

    static func releasePending() {
        let requests = lock.withLock {
            let requests = Array(pending.values)
            pending.removeAll()
            return requests
        }
        for request in requests { request.respond() }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let held = Self.lock.withLock {
            Self.started += 1
            if Self.holding {
                Self.pending[ObjectIdentifier(self)] = self
                Self.peak = max(Self.peak, Self.pending.count)
            }
            return Self.holding
        }
        if !held { respond() }
    }

    private func respond() {
        let key = request.url?.absoluteString ?? ""
        if let data = Self.routes[key] {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
        }
    }
    override func stopLoading() {
        _ = Self.lock.withLock { Self.pending.removeValue(forKey: ObjectIdentifier(self)) }
    }
}
