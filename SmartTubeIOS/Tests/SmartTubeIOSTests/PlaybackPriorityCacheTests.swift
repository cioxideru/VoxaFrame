import Foundation
import Testing

@testable import SmartTubeIOSCore

// URLProtocol owns per-request callbacks; shared request bookkeeping is protected by State.lock.
private final class DemandCacheProtocol: URLProtocol, @unchecked Sendable {
    // Every mutable field is read and written while holding lock.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var held: [DemandCacheProtocol] = []
        var started: [String] = []
        var stopped: [String] = []
    }
    private static let state = State()
    private var key = ""

    static func reset() {
        state.lock.withLock {
            state.held = []
            state.started = []
            state.stopped = []
        }
    }
    static var starts: [String] { state.lock.withLock { state.started } }
    static var stops: [String] { state.lock.withLock { state.stopped } }

    static func finish(_ key: String) {
        let matches = state.lock.withLock {
            let matches = state.held.filter { $0.key == key }
            state.held.removeAll { $0.key == key }
            return matches
        }
        for request in matches {
            let videoID = key.replacingOccurrences(of: "stream:", with: "")
            request.respond(
                key.hasPrefix("stream:")
                    ? """
                    {"playabilityStatus":{"status":"OK"},
                    "videoDetails":{"videoId":"\(videoID)","title":"Fixture","author":"Test"},
                    "streamingData":{"hlsManifestUrl":"https://example.test/master.m3u8","formats":[]}}
                    """ : "{}")
        }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(bytes, count: count)
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let context = json?["context"] as? [String: Any]
        let name = (context?["client"] as? [String: Any])?["clientName"] as? String
        let videoID = json?["videoId"] as? String ?? ""
        let path = request.url?.path ?? ""
        if path.hasSuffix("/player"), name == "VISIONOS" {
            key = "stream:\(videoID)"
        } else if path.hasSuffix("/next") {
            key = "next:\(videoID)"
        } else {
            key = path
        }
        stateRecordStart()
        if key.hasPrefix("stream:") || key.hasPrefix("next:") { return }
        respond(path.hasSuffix("/visitor_id") ? #"{"responseContext":{"visitorData":"fixture"}}"# : "{}")
    }

    private func stateRecordStart() {
        Self.state.lock.withLock {
            Self.state.started.append(key)
            if key.hasPrefix("stream:") || key.hasPrefix("next:") { Self.state.held.append(self) }
        }
    }

    private func respond(_ body: String) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.state.lock.withLock {
            Self.state.stopped.append(key)
            Self.state.held.removeAll { $0 === self }
        }
    }
}

@Suite("Playback priority cache (PLAN-0020)", .serialized)
struct PlaybackPriorityCacheTests {
    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(predicate())
    }

    private func waitForWorkers(_ cache: VideoPreloadCache) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while await cache.activeWorkerCount != 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await cache.activeWorkerCount == 0)
    }

    @Test func cancelledWorkersCannotAccumulateUnboundedSharedStreams() async throws {
        DemandCacheProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemandCacheProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = VideoPreloadCache(
            api: InnerTubeAPI(authToken: nil, session: session),
            sponsorBlock: SponsorBlockService(session: session), deArrow: DeArrowService(session: session),
            monitorNetwork: false)
        let ids = (0..<VideoPreloadCache.maxWorkersWiFi).map { "held-\($0)" }
        for id in ids { await cache.prefetch(videoId: id, sponsorCategories: [], authToken: nil) }
        try await eventually {
            ids.allSatisfy {
                DemandCacheProtocol.starts.contains("stream:\($0)") && DemandCacheProtocol.starts.contains("next:\($0)")
            }
        }
        await cache.setPlaybackYielding(true)
        for id in ids { await cache.cancelPrefetch(for: id) }
        let deadline = ContinuousClock.now + .seconds(3)
        while await cache.activeWorkerCount != 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await cache.activeWorkerCount == 0)
        await cache.prefetch(videoId: "later", sponsorCategories: [], authToken: nil)
        await cache.setPlaybackYielding(false)
        #expect(await cache.activeWorkerCount == 0)
        #expect(!DemandCacheProtocol.starts.contains("stream:later"))
        DemandCacheProtocol.finish("stream:held-0")
        try await eventually { DemandCacheProtocol.starts.contains("stream:later") }
        await cache.cancelPrefetch(for: "later")
        for id in ids + ["later"] {
            let fetch = await cache.inFlightPlayerFetch(videoId: id)
            DemandCacheProtocol.finish("stream:\(id)")
            _ = await fetch?.value
        }
        await waitForWorkers(cache)
    }

    @Test func queuedWorkResumesAndPromotedStreamSurvivesOptionalCancellation() async throws {
        DemandCacheProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemandCacheProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = VideoPreloadCache(
            api: InnerTubeAPI(authToken: nil, session: session),
            sponsorBlock: SponsorBlockService(session: session), deArrow: DeArrowService(session: session),
            monitorNetwork: false)
        await cache.setPlaybackYielding(true)
        await cache.prefetch(videoId: "foreground", sponsorCategories: [], authToken: nil)
        #expect(DemandCacheProtocol.starts.isEmpty)
        await cache.setPlaybackYielding(false)
        try await eventually {
            DemandCacheProtocol.starts.contains("stream:foreground")
                && DemandCacheProtocol.starts.contains("next:foreground")
        }
        let promoted = try #require(await cache.inFlightPlayerFetch(videoId: "foreground"))
        let duplicate = await cache.getOrFetchPlayerInfo(videoId: "foreground")
        #expect(promoted == duplicate)
        await cache.setPlaybackYielding(true)
        await cache.cancelPrefetch(for: "foreground")
        await cache.prefetch(videoId: "next", sponsorCategories: [], authToken: nil)
        try await eventually { DemandCacheProtocol.stops.contains("next:foreground") }
        #expect(!promoted.isCancelled)
        #expect(!DemandCacheProtocol.stops.contains("stream:foreground"))
        #expect(!DemandCacheProtocol.starts.contains("stream:next"))
        DemandCacheProtocol.finish("stream:foreground")
        #expect(await promoted.value?.hlsURL != nil)
        #expect(await cache.consume(videoId: "foreground").playerInfo != nil)
        await cache.setPlaybackYielding(false)
        try await eventually { DemandCacheProtocol.starts.contains("stream:next") }
        let next = await cache.inFlightPlayerFetch(videoId: "next")
        DemandCacheProtocol.finish("stream:next")
        DemandCacheProtocol.finish("next:next")
        await cache.cancelPrefetch(for: "next")
        _ = await next?.value
        await waitForWorkers(cache)
        #expect(DemandCacheProtocol.starts.filter { $0 == "stream:foreground" }.count == 1)
    }
}
