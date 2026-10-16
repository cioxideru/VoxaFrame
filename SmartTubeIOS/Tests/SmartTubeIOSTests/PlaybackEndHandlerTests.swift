import AVFoundation
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
    @Test("Native stream attempts observe the installed item's end notification")
    func nativeAttemptObservesEnd() async throws {
        let vm = PlaybackViewModel()
        defer { vm.stop() }
        let video = Video(id: "native-end-test", title: "Short", channelTitle: "Test")
        vm.currentVideo = video
        vm.isIncognito = true
        var calls = 0
        vm.onPlaybackEnd = { calls += 1 }
        let info = PlayerInfo(
            video: video, formats: [], hlsURL: nil, dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])

        // A local invalid asset exercises item installation without a live stream.
        _ = await vm.attemptURL(URL(fileURLWithPath: "/dev/null"), for: video, info: info, label: "test/muxed")
        let item = try #require(vm.player.currentItem)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while calls == 0, ContinuousClock.now < deadline { await Task.yield() }

        #expect(calls == 1)
    }

    @Test("Queued notifications from a replaced item cannot end or stall the new Short")
    func replacedItemNotificationsAreIgnored() async {
        let vm = PlaybackViewModel()
        defer { vm.stop() }
        let oldItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let newItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        vm.player.replaceCurrentItem(with: oldItem)
        vm.observePlaybackEndAndStalls(for: oldItem)
        var calls = 0
        vm.onPlaybackEnd = { calls += 1 }
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: oldItem)
        NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: oldItem)
        vm.player.replaceCurrentItem(with: newItem)
        await vm.endObserverTask?.value
        await vm.stallObserverTask?.value

        #expect(calls == 0)
        #expect(vm.stallCount == 0)
    }

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
