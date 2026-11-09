import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class OfflineURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

// MARK: - PlaybackAccountSourceTests (PLAN-0046, PLAN-0047)
//
// VISIONOS HLS wins the first stream attempt and starts Phase 2 through `launchPhase2(video:info:)`, which has no
// load context. The authenticated player fetch used to travel only in that context, so its account-bound URLs were
// dropped and the anonymous player's URLs reported the watch (iPad log, 2026-11-09). The same response now supplies
// the end cards the anonymous WEB player no longer returns.

@Suite("Playback account player source")
@MainActor
struct PlaybackAccountSourceTests {
    private let anonymous = URL(string: "https://s.youtube.com/api/stats/watchtime?ei=A&vm=A&of=A")!
    private let account = URL(string: "https://www.youtube.com/api/stats/watchtime?ei=B&vm=B&of=B")!

    private func makeVM(video: Video) -> PlaybackViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineURLProtocol.self]
        var settings = AppSettings()
        settings.sponsorBlockEnabled = false
        settings.deArrowEnabled = false
        let vm = PlaybackViewModel(
            api: InnerTubeAPI(authToken: nil, session: URLSession(configuration: config)), settings: settings)
        vm.currentVideo = video
        return vm
    }

    private func playerInfo(for video: Video) -> PlayerInfo {
        PlayerInfo(
            video: video, formats: [], hlsURL: anonymous, dashURL: nil, captionTracks: [],
            trackingURLs: PlaybackTrackingURLs(playbackURL: anonymous, watchtimeURL: anonymous), endCards: [])
    }

    private func accountResponse() -> AccountPlayerResponse {
        let card = EndCard(
            id: "account-card", style: .video, videoId: "next", title: "Next", thumbnailURL: nil,
            left: 10, top: 20, width: 30, aspectRatio: 1.778, startMs: 1000, endMs: 2000)
        return AccountPlayerResponse(
            trackingURLs: PlaybackTrackingURLs(playbackURL: account, watchtimeURL: account, isAccountBound: true),
            endCards: [card])
    }

    @Test("Phase 2 started without the load context uses the account fetch")
    func launchPhase2UsesAccountFetch() async {
        let video = Video(id: "source-\(UUID().uuidString)", title: "T", channelTitle: "C")
        let vm = makeVM(video: video)
        let response: AccountPlayerResponse? = accountResponse()
        vm.accountPlayerSource = .init(videoId: video.id, cachedTrackingURLs: nil, accountFetch: Task { response })

        vm.launchPhase2(video: video, info: playerInfo(for: video))
        await vm.phase2Task?.value

        #expect(vm.tracker.trackingURLs?.isAccountBound == true)
        #expect(vm.tracker.trackingURLs?.watchtimeURL == account)
        #expect(vm.endCards.map(\.id) == ["account-card"])
    }

    @Test("A source for another video is ignored")
    func otherVideoSourceIsIgnored() async {
        let video = Video(id: "source-\(UUID().uuidString)", title: "T", channelTitle: "C")
        let vm = makeVM(video: video)
        let response: AccountPlayerResponse? = accountResponse()
        vm.accountPlayerSource = .init(videoId: "previous", cachedTrackingURLs: nil, accountFetch: Task { response })

        vm.launchPhase2(video: video, info: playerInfo(for: video))
        await vm.phase2Task?.value

        #expect(vm.tracker.trackingURLs?.isAccountBound == false)
        #expect(vm.tracker.trackingURLs?.watchtimeURL == anonymous)
        #expect(vm.endCards.isEmpty)
    }
}
