import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class SurfaceTapURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

// MARK: - PlayerSurfaceTapTests (PLAN-0049)
//
// While YouTube end cards show (the last seconds of a video), a tap on the player
// outside the cards must still toggle the controls; before the fix the surface
// ignored every tap and the player looked frozen.

@Suite("Player surface tap with end cards (PLAN-0049)")
@MainActor
struct PlayerSurfaceTapTests {
    private func makeVM() -> PlaybackViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SurfaceTapURLProtocol.self]
        let vm = PlaybackViewModel(api: InnerTubeAPI(authToken: nil, session: URLSession(configuration: config)))
        vm.endCards = [
            EndCard(
                id: "card", style: .video, videoId: "next", title: "Next", thumbnailURL: nil,
                left: 60, top: 10, width: 30, aspectRatio: 1.778, startMs: 10_000, endMs: 20_000)
        ]
        vm.currentTime = 15
        return vm
    }

    @Test("A surface tap shows and hides the controls while an end card is visible")
    func tapTogglesControlsDuringEndCards() {
        let vm = makeVM()
        #expect(vm.hasVisibleEndCards)
        #expect(!vm.controlsVisible)

        vm.handleSurfaceTap()
        #expect(vm.controlsVisible)

        vm.handleSurfaceTap()
        #expect(!vm.controlsVisible)
        vm.cancelControlsHide()
    }
}
