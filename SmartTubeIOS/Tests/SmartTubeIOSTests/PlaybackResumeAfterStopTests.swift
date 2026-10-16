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

    @Test("stop() clears the suspend and interruption resume flags")
    func stopClearsResumeFlags() {
        let vm = PlaybackViewModel()  // currentVideo nil: stop() starts no HLS re-extraction
        vm.wasPlayingBeforeSuspend = true
        vm.wasPlayingBeforeInterruption = true

        vm.stop()

        #expect(vm.wasPlayingBeforeSuspend == false)
        #expect(vm.wasPlayingBeforeInterruption == false)
    }

    @Test("togglePlayPause() on a parked item un-parks it so resume() works again")
    func togglePlayUnparks() async {
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        vm.player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/dev/null")))
        vm.parkedVideoId = "parked-1"

        vm.togglePlayPause()
        await vm.audioPlaybackTask?.value
        #expect(vm.parkedVideoId == nil)
        #expect(vm.isPlaying)

        vm.player.pause()
        vm.isPlaying = false
        vm.resume()
        await vm.audioPlaybackTask?.value
        #expect(vm.isPlaying)
    }
}
