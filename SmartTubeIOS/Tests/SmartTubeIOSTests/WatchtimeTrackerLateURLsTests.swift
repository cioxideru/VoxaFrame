import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchtimeTrackerLateURLsTests (PLAN-0046)
//
// The account-bound tracking URLs arrive after the first checkpoint (iPad log, 2026-11-09). The tracker used to mark
// the watch record open although its playback ping was skipped for lack of session params, so for 30 minutes every
// watchtime ping went out without a record and YouTube ignored them.

private final class StatsPathURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    // Every read, append and reset is protected by the static NSLock above.
    nonisolated(unsafe) private static var paths: [String] = []

    static func reset() { lock.withLock { paths = [] } }
    static func statsPaths() -> [String] { lock.withLock { paths.filter { $0.hasPrefix("/api/stats/") } } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.withLock { Self.paths.append(url.path) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("WatchtimeTracker with late tracking URLs", .serialized)
struct WatchtimeTrackerLateURLsTests {
    private let bound = URL(string: "https://s.youtube.com/api/stats/watchtime?ei=E&vm=V&of=O")!
    private let account = URL(string: "https://www.youtube.com/api/stats/watchtime?ei=F&vm=W&of=P")!

    private func makeTracker() -> WatchtimeTracker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatsPathURLProtocol.self]
        let tracker = WatchtimeTracker(
            api: InnerTubeAPI(authToken: "token", session: URLSession(configuration: config)))
        _ = tracker.transition(to: "late-\(UUID().uuidString)", cpn: "cpn", flushPosition: 0, flushDuration: 0)
        return tracker
    }

    @Test("URLs that arrive after the first checkpoint open the watch record at the next one")
    func lateURLsOpenTheRecord() async {
        StatsPathURLProtocol.reset()
        let tracker = makeTracker()
        await tracker.checkpoint(position: 0, duration: 1000)  // no URLs yet: both pings skipped
        #expect(StatsPathURLProtocol.statsPaths().isEmpty)

        tracker.setTrackingURLs(
            PlaybackTrackingURLs(playbackURL: bound, watchtimeURL: bound, isAccountBound: true))
        await tracker.checkpoint(position: 30, duration: 1000)
        #expect(StatsPathURLProtocol.statsPaths() == ["/api/stats/playback", "/api/stats/watchtime"])
    }

    @Test("new URLs in the middle of a session open a new watch record")
    func replacedURLsOpenANewRecord() async {
        StatsPathURLProtocol.reset()
        let tracker = makeTracker()
        tracker.setTrackingURLs(PlaybackTrackingURLs(playbackURL: bound, watchtimeURL: bound))
        await tracker.checkpoint(position: 10, duration: 1000)
        await tracker.checkpoint(position: 40, duration: 1000)
        tracker.setTrackingURLs(
            PlaybackTrackingURLs(playbackURL: account, watchtimeURL: account, isAccountBound: true))
        await tracker.checkpoint(position: 70, duration: 1000)
        #expect(StatsPathURLProtocol.statsPaths().filter { $0 == "/api/stats/playback" }.count == 2)
    }

    @Test("the same URLs set again keep the open watch record")
    func repeatedURLsKeepTheRecord() async {
        StatsPathURLProtocol.reset()
        let tracker = makeTracker()
        let urls = PlaybackTrackingURLs(playbackURL: bound, watchtimeURL: bound, isAccountBound: true)
        tracker.setTrackingURLs(urls)
        await tracker.checkpoint(position: 10, duration: 1000)
        tracker.setTrackingURLs(urls)  // a second Phase 2 of the same playback
        await tracker.checkpoint(position: 40, duration: 1000)
        #expect(StatsPathURLProtocol.statsPaths().filter { $0 == "/api/stats/playback" }.count == 1)
    }
}
