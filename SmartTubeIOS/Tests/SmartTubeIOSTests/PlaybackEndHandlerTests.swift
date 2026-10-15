import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - PlaybackEndHandlerTests
//
// `onPlaybackEnd` replaces the regular autoplay, so a finished Short never
// starts an unrelated video inside the Shorts player.

@Suite("Playback end handler")
@MainActor
struct PlaybackEndHandlerTests {
    @Test("onPlaybackEnd runs instead of recommendation autoplay")
    func handlerOverridesAutoplay() {
        let vm = PlaybackViewModel()
        vm.settings.loopEnabled = false
        vm.settings.autoplayEnabled = true
        let current = Video(id: "short-1", title: "S", channelTitle: "C")
        vm.currentVideo = current
        vm.relatedVideos = [Video(id: "unrelated", title: "U", channelTitle: "C")]
        var calls = 0
        vm.onPlaybackEnd = { calls += 1 }

        vm.handlePlaybackEnd()

        #expect(calls == 1)
        #expect(vm.currentVideo?.id == current.id)
    }

    @Test("Stopping releases an end handler that retains its player")
    func stopBreaksHandlerCycle() {
        weak var dismissedVM: PlaybackViewModel?
        do {
            let vm = PlaybackViewModel()
            dismissedVM = vm
            // Reproduce the Shorts view's strong capture of its own state-held VM.
            vm.onPlaybackEnd = { vm.videoEnded = true }

            vm.stop()

            #expect(vm.onPlaybackEnd == nil)
        }
        #expect(dismissedVM == nil)
    }

    @Test("Temporary suspension preserves the end handler")
    func suspendKeepsHandler() {
        let vm = PlaybackViewModel()
        var calls = 0
        vm.onPlaybackEnd = { calls += 1 }

        vm.suspend()
        vm.handlePlaybackEnd()

        #expect(calls == 1)
        vm.stop()
    }
}
