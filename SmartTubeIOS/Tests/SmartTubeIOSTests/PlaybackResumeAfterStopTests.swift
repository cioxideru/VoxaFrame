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

    @Test("togglePlayPause() on a parked item un-parks it so resume() works again")
    func togglePlayUnparks() {
        let vm = PlaybackViewModel()
        vm.player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        vm.parkedVideoId = "parked-1"

        vm.togglePlayPause()
        #expect(vm.parkedVideoId == nil)
        #expect(vm.isPlaying)

        vm.player.pause()
        vm.isPlaying = false
        vm.resume()
        #expect(vm.isPlaying)
    }
}
