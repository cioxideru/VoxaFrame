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
}
