import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Player item readiness deadlines (PLAN-0009)", .timeLimit(.minutes(1)))
@MainActor
struct PlayerItemReadinessTests {
    @Test func unknownItemFinishesAtDeadlineWithoutInventingFailure() async {
        let item = AVPlayerItem(asset: AVMutableComposition())
        var statuses: [AVPlayerItem.Status] = []
        for await status in item.statusStream(timeout: .zero) { statuses.append(status) }

        #expect(item.status == .unknown)
        #expect(item.error == nil)
        #expect(statuses.allSatisfy { $0 == .unknown })
    }

    @Test func swipingAwayCancelsAnUnreadyItemWait() async {
        let item = AVPlayerItem(asset: AVMutableComposition())
        var observedInitialStatus = false
        let observer = Task { @MainActor in
            for await _ in item.statusStream(timeout: .seconds(3_600)) {
                observedInitialStatus = true
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !observedInitialStatus, ContinuousClock.now < deadline { await Task.yield() }
        #expect(observedInitialStatus)
        observer.cancel()
        await observer.value
        #expect(item.status == .unknown)
    }

    @Test func expiredObservationForAnOldItemCannotStartAnotherRetry() async {
        let vm = PlaybackViewModel(api: InnerTubeAPI())
        vm.settings.historyState = .disabled
        let video = Video(id: "old-short", title: "Old Short", channelTitle: "Channel", isShort: true)
        let oldItem = AVPlayerItem(asset: AVMutableComposition())
        let info = PlayerInfo(
            video: video, formats: [], hlsURL: nil, dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])
        vm.observeInitialPlayerItem(oldItem, info: info, isHLS: true, timeout: .zero)
        await vm.itemObserverTask?.value

        #expect(vm.player.currentItem == nil)
        #expect(vm.exhaustiveRetryTask == nil)
        #expect(vm.error == nil)
    }
}
