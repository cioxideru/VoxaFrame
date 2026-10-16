import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class ReadyIdentityPlayerItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

@Suite("Playback load isolation (PLAN-0009)")
@MainActor
struct PlaybackLoadStateTests {
    private func makeVM() -> PlaybackViewModel {
        let vm = PlaybackViewModel(api: InnerTubeAPI())
        vm.settings.historyState = .disabled
        return vm
    }

    @Test(
        "Next, Previous and autoplay publish the requested video without retaining an old display",
        arguments: ["next", "previous", "autoplay"])
    func navigationIdentity(action: String) {
        let vm = makeVM()
        let first = makeVideo("first")
        let next = makeVideo("next")
        vm.currentVideo = first
        vm.player.replaceCurrentItem(with: ReadyIdentityPlayerItem(asset: AVMutableComposition()))
        vm.relatedVideos = [next]
        vm.history = [next]
        vm.settings.autoplayEnabled = true
        vm.settings.shuffleEnabled = false
        vm.settings.loopEnabled = false
        #expect(vm.displayedVideo == first)

        switch action {
        case "previous": vm.playPrevious()
        case "autoplay": vm.handlePlaybackEnd()
        default: vm.playNext()
        }
        vm.loadTask?.cancel()  // Verify synchronous navigation without starting network work.
        #expect(vm.currentVideo == next)
        #expect(vm.isLoading)
        #expect(vm.displayedVideo == nil)
        #expect(vm.player.currentItem == nil)

        vm.player.replaceCurrentItem(with: ReadyIdentityPlayerItem(asset: AVMutableComposition()))
        vm.isLoading = false
        #expect(vm.displayedVideo == next)
        vm.currentVideo?.title = "Updated metadata"
        #expect(vm.displayedVideo?.title == "Updated metadata")
    }

    @Test("Recovery keeps the ready item's metadata while a new load has no displayed video")
    func recoveryDisplayIdentity() {
        let vm = makeVM()
        vm.currentVideo = makeVideo("current")
        vm.player.replaceCurrentItem(with: ReadyIdentityPlayerItem(asset: AVMutableComposition()))
        vm.isLoading = true
        #expect(vm.displayedVideo == vm.currentVideo)
        vm.player.replaceCurrentItem(with: nil)
        #expect(vm.displayedVideo == nil)
    }

    #if os(iOS)
    @Test(
        "Presentation reads current playback through minimize, expand, hidden PiP and stop",
        arguments: ["next", "previous", "autoplay"])
    func presentationIdentity(action: String) {
        let store = PlayerStateStore(api: InnerTubeAPI())
        store.vm.settings.historyState = .disabled
        store.vm.currentVideo = makeVideo("first")
        store.vm.player.replaceCurrentItem(with: ReadyIdentityPlayerItem(asset: AVMutableComposition()))
        store.expand()
        store.vm.relatedVideos = [makeVideo("next")]
        store.vm.history = [makeVideo("next")]
        store.vm.settings.autoplayEnabled = true
        store.vm.settings.shuffleEnabled = false
        store.vm.settings.loopEnabled = false
        switch action {
        case "previous": store.vm.playPrevious()
        case "autoplay": store.vm.handlePlaybackEnd()
        default: store.vm.playNext()
        }
        store.vm.loadTask?.cancel()
        #expect(store.currentVideo?.id == "next")
        #expect(store.playingVideo == nil)
        store.vm.player.replaceCurrentItem(with: ReadyIdentityPlayerItem(asset: AVMutableComposition()))
        store.vm.isLoading = false
        store.minimize()
        #expect(store.currentVideo?.id == "next")
        #expect(store.playingVideo?.id == "next")
        store.expand()
        #expect(store.presentation == .fullScreen)
        store.isPiPActive = true
        store.presentation = .hidden
        #expect(store.currentVideo?.id == "next")
        #expect(store.playingVideo?.id == "next")

        store.stop()
        #expect(store.currentVideo == nil)
        #expect(store.playingVideo == nil)
        #expect(store.vm.player.currentItem != nil)
        #expect(store.vm.currentVideo?.id == "next")
        store.isPiPActive = false
        store.play(video: makeVideo("next"), settings: store.vm.settings)
        store.vm.loadTask?.cancel()
        #expect(store.currentVideo?.id == "next")
        #expect(store.playingVideo?.id == "next")
        #expect(store.presentation == .fullScreen)
        store.stop()
    }
    #endif

    @Test func newShortClearsPendingSeekAndDurationObservation() {
        let vm = makeVM()
        vm.savedPositionToRestore = 120
        vm.duration = 180
        vm.isScrubbing = true
        let oldDuration = Task { @MainActor in }
        let oldStatus = Task { @MainActor in }
        vm.durationObserverTask = oldDuration
        vm.itemObserverTask = oldStatus

        vm.resetPlaybackForLoad(
            video: Video(id: "next", title: "Next", channelTitle: "Channel", isShort: true), incognito: false)

        #expect(vm.savedPositionToRestore == nil)
        #expect(vm.duration == 0)
        #expect(vm.currentTime == 0)
        #expect(!vm.isScrubbing)
        #expect(oldDuration.isCancelled)
        #expect(oldStatus.isCancelled)
    }

    @Test(arguments: [true, false])
    func onlyRegularVideosRestoreWatchPosition(isShort: Bool) {
        let vm = makeVM()
        let video = Video(id: "watched", title: "Watched", channelTitle: "Channel", isShort: isShort)
        vm.restoreSavedPosition(.init(position: 30, watchedFraction: 0.5), for: video)
        #expect(vm.savedPositionToRestore == (isShort ? nil : 30))
        vm.restoreSavedPosition(nil, for: video)
        #expect(vm.savedPositionToRestore == nil)
    }

    @Test func retryResetsTheSameVideoWithoutAddingHistory() {
        let vm = makeVM()
        let video = Video(id: "retry", title: "Retry", channelTitle: "Channel", isShort: true)
        vm.resetPlaybackForLoad(video: video, incognito: true)
        vm.savedPositionToRestore = 90
        vm.error = URLError(.timedOut)
        let oldLoad = Task { @MainActor in }
        vm.loadTask = oldLoad

        vm.retryLoad()
        vm.loadTask?.cancel()  // Exercise synchronous state reset without a network request.

        #expect(oldLoad.isCancelled)
        #expect(vm.currentVideoId == video.id)
        #expect(vm.history.isEmpty)
        #expect(vm.isIncognito)
        #expect(vm.isLoading)
        #expect(vm.error == nil)
        #expect(vm.savedPositionToRestore == nil)
    }
}
