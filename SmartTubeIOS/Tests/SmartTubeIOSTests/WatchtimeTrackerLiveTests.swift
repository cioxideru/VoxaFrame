import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchtimeTrackerLiveTests (PLAN-0048)
//
// A live HLS item has no length, so the player's duration stays 0 and the tracker used to send nothing at all: four
// live streams watched on the iPad (2026-11-09) produced no stats ping and never reached the account's history.

private final class StatsQueryURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    // Every read, append and reset is protected by the static NSLock above.
    nonisolated(unsafe) private static var urls: [URL] = []

    static func reset() { lock.withLock { urls = [] } }
    static func statsURLs() -> [URL] { lock.withLock { urls.filter { $0.path.hasPrefix("/api/stats/") } } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.withLock { Self.urls.append(url) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URL {
    func query(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

@MainActor
@Suite("WatchtimeTracker with live streams", .serialized)
struct WatchtimeTrackerLiveTests {
    private let account = URL(string: "https://www.youtube.com/api/stats/watchtime?ei=E&vm=V&of=O")!

    private func makeLiveTracker() -> (WatchtimeTracker, String) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatsQueryURLProtocol.self]
        let tracker = WatchtimeTracker(
            api: InnerTubeAPI(authToken: "token", session: URLSession(configuration: config)))
        let videoId = "live-\(UUID().uuidString)"
        _ = tracker.transition(to: videoId, cpn: "cpn", flushPosition: 0, flushDuration: 0)
        tracker.setTrackingURLs(
            PlaybackTrackingURLs(playbackURL: account, watchtimeURL: account, isAccountBound: true))
        return (tracker, videoId)
    }

    @Test("a live stream is reported with zero length, never as finished, and saves no position")
    func liveCheckpointsReportWithZeroLength() async {
        StatsQueryURLProtocol.reset()
        let (tracker, videoId) = makeLiveTracker()
        tracker.markLiveStream()

        await tracker.checkpoint(position: 10, duration: 0)
        await tracker.checkpoint(position: 40, duration: 0)

        let urls = StatsQueryURLProtocol.statsURLs()
        #expect(urls.map(\.path) == ["/api/stats/playback", "/api/stats/watchtime", "/api/stats/watchtime"])
        #expect(urls.allSatisfy { $0.query("len") == "0.000" })
        #expect(urls.allSatisfy { $0.query("final") == nil })
        #expect(urls.last?.query("st") == "10.000")
        #expect(urls.last?.query("et") == "40.000")
        #expect(await VideoStateStore.shared.state(for: videoId) == nil)
    }

    @Test("without the live mark a playback with no length still sends nothing")
    func unknownLengthWithoutMarkSendsNothing() async {
        StatsQueryURLProtocol.reset()
        let (tracker, _) = makeLiveTracker()
        await tracker.checkpoint(position: 10, duration: 0)
        await tracker.checkpoint(position: 40, duration: 0)
        #expect(StatsQueryURLProtocol.statsURLs().isEmpty)
    }

    @Test("switching away from a live stream flushes it as live and clears the mark")
    func transitionFlushesLiveStream() async {
        StatsQueryURLProtocol.reset()
        let (tracker, _) = makeLiveTracker()
        tracker.markLiveStream()
        await tracker.checkpoint(position: 10, duration: 0)
        StatsQueryURLProtocol.reset()

        let flush = tracker.transition(to: "next-video", cpn: "cpn2", flushPosition: 50, flushDuration: 0)
        #expect(!tracker.isLiveStream)
        await flush()

        let urls = StatsQueryURLProtocol.statsURLs()
        #expect(urls.map(\.path) == ["/api/stats/playback", "/api/stats/watchtime"])
        #expect(urls.allSatisfy { $0.query("len") == "0.000" })
        #expect(urls.last?.query("st") == "10.000")
        #expect(urls.last?.query("et") == "50.000")
    }
}
