import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Playback resume after stop (TD-10)")
@MainActor
struct PlaybackResumeAfterStopTests {

    @Test("resume() does not restart an item parked by stop()")
    func resumeIgnoresParkedItem() {
        let vm = PlaybackViewModel()
        vm.player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        vm.parkedVideoId = "parked-1"

        vm.resume()

        #expect(vm.isPlaying == false)
        #expect(vm.player.rate == 0)
    }
}
