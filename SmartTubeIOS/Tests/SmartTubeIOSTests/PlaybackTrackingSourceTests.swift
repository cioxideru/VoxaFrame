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

// MARK: - PlaybackTrackingSourceTests (PLAN-0046)
//
// VISIONOS HLS wins the first stream attempt and starts Phase 2 through `launchPhase2(video:info:)`, which has no
// load context. The authenticated tracking fetch used to travel only in that context, so its account-bound URLs were
// dropped and the anonymous player's URLs reported the watch (iPad log, 2026-11-09).

@Suite("Playback tracking URL source")
@MainActor
struct PlaybackTrackingSourceTests {
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

    @Test("Phase 2 started without the load context uses the account fetch")
    func launchPhase2UsesAccountFetch() async {
        let video = Video(id: "source-\(UUID().uuidString)", title: "T", channelTitle: "C")
        let vm = makeVM(video: video)
        let accountURLs: PlaybackTrackingURLs? = PlaybackTrackingURLs(
            playbackURL: account, watchtimeURL: account, isAccountBound: true)
        vm.trackingURLSource = .init(videoId: video.id, cached: nil, accountFetch: Task { accountURLs })

        vm.launchPhase2(video: video, info: playerInfo(for: video))
        await vm.phase2Task?.value

        #expect(vm.tracker.trackingURLs?.isAccountBound == true)
        #expect(vm.tracker.trackingURLs?.watchtimeURL == account)
    }

    @Test("A source for another video is ignored")
    func otherVideoSourceIsIgnored() async {
        let video = Video(id: "source-\(UUID().uuidString)", title: "T", channelTitle: "C")
        let vm = makeVM(video: video)
        let accountURLs: PlaybackTrackingURLs? = PlaybackTrackingURLs(
            playbackURL: account, watchtimeURL: account, isAccountBound: true)
        vm.trackingURLSource = .init(videoId: "previous", cached: nil, accountFetch: Task { accountURLs })

        vm.launchPhase2(video: video, info: playerInfo(for: video))
        await vm.phase2Task?.value

        #expect(vm.tracker.trackingURLs?.isAccountBound == false)
        #expect(vm.tracker.trackingURLs?.watchtimeURL == anonymous)
    }
}
