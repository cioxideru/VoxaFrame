import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Playback load isolation (PLAN-0009)")
@MainActor
struct PlaybackLoadStateTests {
    private func makeVM() -> PlaybackViewModel {
        let vm = PlaybackViewModel(api: InnerTubeAPI())
        vm.settings.historyState = .disabled
        return vm
    }

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
