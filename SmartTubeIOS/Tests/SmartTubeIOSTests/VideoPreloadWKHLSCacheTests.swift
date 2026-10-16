import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Video preload WK-HLS lifetime")
struct VideoPreloadWKHLSCacheTests {
    private let url = URL(string: "https://example.com/audio.m3u8")!

    @Test("WK-HLS entries share the capacity limit, including token-only writes", arguments: [false, true])
    func capacity(tokenOnly: Bool) async {
        let cache = VideoPreloadCache()
        let capacity = VideoPreloadCache.maxVideoEntries
        for index in 0..<(capacity + 5) {
            if !tokenOnly { await cache.store(wkHLSManifestURL: url, for: "\(index)", isPreWarm: true) }
            await cache.store(wkHLSPoToken: "token-\(index)", for: "\(index)")
        }
        for index in 0..<(capacity + 5) {
            let retained = index >= 5
            #expect(await cache.cachedPoToken(for: "\(index)") == (retained ? "token-\(index)" : nil))
            #expect(await cache.cachedWKHLSURL(for: "\(index)") == (retained && !tokenOnly ? url : nil))
            #expect(await cache.cachedWKHLSIsPreWarm(for: "\(index)") == (retained && !tokenOnly))
        }
    }

    @Test("ordinary cache writes also evict all WK-HLS fields")
    func sharedCapacity() async {
        let cache = VideoPreloadCache()
        await cache.store(wkHLSManifestURL: url, for: "old", isPreWarm: true)
        await cache.store(wkHLSPoToken: "token", for: "old")
        for index in 0..<VideoPreloadCache.maxVideoEntries {
            await cache.store(trackingURLs: nil, for: "tracking-\(index)")
        }
        #expect(await cache.cachedWKHLSURL(for: "old") == nil)
        #expect(await cache.cachedPoToken(for: "old") == nil)
        #expect(await cache.cachedWKHLSIsPreWarm(for: "old") == false)
    }

    @Test("every WK-HLS accessor refreshes LRU access, not the URL timestamp", arguments: [0, 1, 2, 3])
    func recentAccess(accessor: Int) async {
        let clock = Clock()
        let cache = VideoPreloadCache(wkHLSNow: { clock.now })
        for index in 0..<VideoPreloadCache.maxVideoEntries {
            await cache.store(wkHLSManifestURL: url, for: "\(index)", isPreWarm: true)
            await cache.store(wkHLSPoToken: "token", for: "\(index)")
        }
        clock.advance(5)
        switch accessor {
        case 0: #expect(await cache.cachedWKHLSURL(for: "0") == url)
        case 1: #expect(await cache.cachedPoToken(for: "0") == "token")
        case 2: #expect(await cache.cachedWKHLSIsPreWarm(for: "0"))
        default: #expect(await cache.isWKHLSURLFresh(for: "0"))
        }
        await cache.store(wkHLSPoToken: "new", for: "new")
        #expect(await cache.cachedWKHLSURL(for: "0") == url)
        #expect(await cache.cachedPoToken(for: "1") == nil)
        clock.advance(6)
        #expect(await cache.isWKHLSURLFresh(for: "0") == false)
    }

    @Test("expiry through any accessor removes URL, token and origin together", arguments: [0, 1, 2, 3])
    func expiry(accessor: Int) async {
        let clock = Clock()
        let cache = VideoPreloadCache(wkHLSNow: { clock.now })
        await cache.store(wkHLSManifestURL: url, for: "video", isPreWarm: true)
        await cache.store(wkHLSPoToken: "token", for: "video")
        clock.advance(VideoPreloadCache.wkHLSTTL + 1)
        switch accessor {
        case 0: #expect(await cache.cachedWKHLSURL(for: "video") == nil)
        case 1: #expect(await cache.cachedPoToken(for: "video") == nil)
        case 2: #expect(await cache.cachedWKHLSIsPreWarm(for: "video") == false)
        default: #expect(await cache.isWKHLSURLFresh(for: "video", within: .infinity) == false)
        }
        await cache.invalidateWKHLSURL(for: "video")
        #expect(await cache.cachedWKHLSURL(for: "video") == nil)
        #expect(await cache.cachedPoToken(for: "video") == nil)
        #expect(await cache.cachedWKHLSIsPreWarm(for: "video") == false)
        await cache.store(wkHLSManifestURL: url, for: "video")
        #expect(await cache.cachedPoToken(for: "video") == nil)
    }

    @Test("token-only entries can be invalidated and expire without a URL")
    func tokenOnlyLifetime() async {
        let clock = Clock()
        let cache = VideoPreloadCache(wkHLSNow: { clock.now })
        await cache.store(wkHLSPoToken: "token", for: "video")
        #expect(await cache.cachedPoToken(for: "video") == "token")
        #expect(await cache.cachedWKHLSURL(for: "video") == nil)
        #expect(await cache.isWKHLSURLFresh(for: "video") == false)
        await cache.invalidateWKHLSURL(for: "video")
        #expect(await cache.cachedPoToken(for: "video") == nil)
        await cache.store(wkHLSPoToken: "token", for: "video")
        clock.advance(VideoPreloadCache.wkHLSTTL + 1)
        #expect(await cache.cachedPoToken(for: "video") == nil)
    }

    @Test("writing a token does not extend the URL TTL or recent-extraction window")
    func tokenDoesNotRenewURL() async {
        let clock = Clock()
        let cache = VideoPreloadCache(wkHLSNow: { clock.now })
        await cache.store(wkHLSManifestURL: url, for: "video", isPreWarm: true)
        clock.advance(VideoPreloadCache.wkHLSTTL - 1)
        await cache.store(wkHLSPoToken: "token", for: "video")
        #expect(await cache.cachedWKHLSURL(for: "video") == url)
        #expect(await cache.isWKHLSURLFresh(for: "video") == false)
        clock.advance(2)
        #expect(await cache.cachedPoToken(for: "video") == nil)
        #expect(await cache.cachedWKHLSURL(for: "video") == nil)
        #expect(await cache.cachedWKHLSIsPreWarm(for: "video") == false)
    }

    @Test("consume preserves replay data and live extraction updates its origin")
    func replay() async {
        let clock = Clock()
        let cache = VideoPreloadCache(wkHLSNow: { clock.now })
        let videoID = UUID().uuidString
        await cache.store(wkHLSPoToken: "token", for: videoID)
        clock.advance(VideoPreloadCache.wkHLSTTL - 1)
        await cache.store(wkHLSManifestURL: url, for: videoID, isPreWarm: true)
        clock.advance(2)
        _ = await cache.consume(videoId: videoID)
        _ = await cache.consume(videoId: videoID)
        #expect(await cache.cachedWKHLSURL(for: videoID) == url)
        #expect(await cache.cachedPoToken(for: videoID) == "token")
        #expect(await cache.cachedWKHLSIsPreWarm(for: videoID))
        #expect(await cache.isWKHLSURLFresh(for: videoID))
        await cache.store(wkHLSManifestURL: url, for: videoID)
        #expect(await cache.cachedWKHLSIsPreWarm(for: videoID) == false)
        #expect(await cache.cachedPoToken(for: videoID) == "token")
    }

    // The same lock protects every read and advance of the test clock.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 0)
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
    }
}
