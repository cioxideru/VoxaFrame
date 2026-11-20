import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private func bufferTime(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

private func timeRanges(_ ranges: [ClosedRange<Double>]) -> [NSValue] {
    ranges.map { NSValue(timeRange: CMTimeRange(start: bufferTime($0.lowerBound), end: bufferTime($0.upperBound))) }
}

/// An item that reports set loaded ranges, length, playhead and readiness without loading anything. Changing the
/// ranges or the length posts KVO the way AVFoundation does, so the model's observation can be exercised.
private final class BufferedTestItem: AVPlayerItem {
    private var ranges: [NSValue]
    private var length: CMTime
    let fixedTime: CMTime
    let fixedStatus: AVPlayerItem.Status

    init(
        ranges: [ClosedRange<Double>], duration: CMTime, time: Double,
        status: AVPlayerItem.Status = .readyToPlay
    ) {
        self.ranges = timeRanges(ranges)
        length = duration
        fixedTime = bufferTime(time)
        fixedStatus = status
        super.init(asset: AVMutableComposition(), automaticallyLoadedAssetKeys: nil)
    }

    override var loadedTimeRanges: [NSValue] { ranges }
    override var duration: CMTime { length }
    override var status: AVPlayerItem.Status { fixedStatus }
    override func currentTime() -> CMTime { fixedTime }

    func load(_ newRanges: [ClosedRange<Double>]) {
        willChangeValue(forKey: "loadedTimeRanges")
        ranges = timeRanges(newRanges)
        didChangeValue(forKey: "loadedTimeRanges")
    }

    func resolveDuration(_ newLength: CMTime) {
        willChangeValue(forKey: "duration")
        length = newLength
        didChangeValue(forKey: "duration")
    }
}

// MARK: - Buffered range in the player model (PLAN-0051)

@Suite("Playback buffered range (PLAN-0051)")
@MainActor
struct PlaybackBufferedRangeTests {
    private func makeVM() -> PlaybackViewModel {
        let vm = PlaybackViewModel(api: InnerTubeAPI())
        vm.settings.historyState = .disabled
        return vm
    }

    /// A model whose periodic time observer is removed. Paused, AVPlayer does not tick it; here an item swap would
    /// still fire it once on the main queue, late enough to stand in for the observation under test.
    private func makePausedVM() -> PlaybackViewModel {
        let vm = makeVM()
        if let observer = vm.timeObserver { observer.player.removeTimeObserver(observer.token) }
        vm.timeObserver = nil
        return vm
    }

    /// Yields until the observation has delivered the expected state, with a failure deadline.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
    }

    @Test("The loaded range under the playhead is measured; a live item and a gap show nothing")
    func measurement() {
        let vm = makeVM()
        let ranges: [ClosedRange<Double>] = [0...30, 60...90]
        #expect(
            vm.measuredBufferedSpan(of: BufferedTestItem(ranges: ranges, duration: bufferTime(120), time: 10))
                == 0...0.25)
        #expect(
            vm.measuredBufferedSpan(of: BufferedTestItem(ranges: ranges, duration: bufferTime(120), time: 45)) == nil)
        #expect(vm.measuredBufferedSpan(of: BufferedTestItem(ranges: ranges, duration: .indefinite, time: 10)) == nil)
        // The length can arrive after readyToPlay; until it does nothing is drawn.
        #expect(vm.measuredBufferedSpan(of: BufferedTestItem(ranges: ranges, duration: .invalid, time: 10)) == nil)
    }

    @Test("A ready local item is buffered end to end; before it is ready, it is measured like any item")
    func localItemIsFullyBuffered() {
        let vm = makeVM()
        let local = BufferedTestItem(ranges: [], duration: bufferTime(100), time: 40)
        vm.localPlaybackItem = local
        #expect(vm.measuredBufferedSpan(of: local) == 0...1)
        let preparing = BufferedTestItem(ranges: [], duration: bufferTime(100), time: 0, status: .unknown)
        vm.localPlaybackItem = preparing
        #expect(vm.measuredBufferedSpan(of: preparing) == nil)
        let remote = BufferedTestItem(ranges: [], duration: bufferTime(100), time: 40)
        #expect(vm.measuredBufferedSpan(of: remote) == nil)
    }

    @Test("Small changes on the same item are not published; larger ones and the end of the video are")
    func publishesOnlyNoticeableChanges() {
        let vm = makeVM()
        let item = AVPlayerItem(asset: AVMutableComposition())
        let step = PlayerTimeline.bufferedPublishStep
        vm.publishBufferedSpan(0...0.2, for: item)
        #expect(vm.bufferedSpan == 0...0.2)
        vm.publishBufferedSpan(0...(0.2 + step / 2), for: item)
        #expect(vm.bufferedSpan == 0...0.2)
        vm.publishBufferedSpan(0...0.3, for: item)
        #expect(vm.bufferedSpan == 0...0.3)
        vm.publishBufferedSpan(0...1, for: item)
        #expect(vm.bufferedSpan == 0...1)
        vm.publishBufferedSpan(nil, for: item)
        #expect(vm.bufferedSpan == nil)
    }

    @Test("A new item replaces the old value at once, however close")
    func itemChangeResets() {
        let vm = makeVM()
        let old = AVPlayerItem(asset: AVMutableComposition())
        vm.publishBufferedSpan(0...0.2, for: old)
        let next = AVPlayerItem(asset: AVMutableComposition())
        vm.publishBufferedSpan(0...(0.2 + PlayerTimeline.bufferedPublishStep / 2), for: next)
        #expect(vm.bufferedSpan == 0...(0.2 + PlayerTimeline.bufferedPublishStep / 2))
        #expect(vm.bufferedSpanItem === next)
    }

    // The tests below never call `refreshBufferedSpan()`: the value has to arrive through the model's observation of
    // the player, as it does while paused, when the periodic time observer does not tick.

    @Test("Loading more while paused reaches the timeline through observation")
    func observedRangesWhilePaused() async {
        let vm = makePausedVM()
        let item = BufferedTestItem(ranges: [0...30], duration: bufferTime(120), time: 10)
        vm.player.replaceCurrentItem(with: item)
        await waitUntil { vm.bufferedSpanItem === item && vm.bufferedSpan == 0...0.25 }
        #expect(vm.bufferedSpan == 0...0.25)
        item.load([0...60])
        await waitUntil { vm.bufferedSpan == 0...0.5 }
        #expect(vm.bufferedSpan == 0...0.5)
        vm.player.replaceCurrentItem(with: nil)
    }

    @Test("A length that turns finite while paused shows the unchanged ranges")
    func observedLateDurationWhilePaused() async {
        let vm = makePausedVM()
        let item = BufferedTestItem(ranges: [0...60], duration: .indefinite, time: 10)
        vm.player.replaceCurrentItem(with: item)
        await waitUntil { vm.bufferedSpanItem === item }
        #expect(vm.bufferedSpanItem === item)
        #expect(vm.bufferedSpan == nil)
        item.resolveDuration(bufferTime(120))
        await waitUntil { vm.bufferedSpan == 0...0.5 }
        #expect(vm.bufferedSpan == 0...0.5)
        vm.player.replaceCurrentItem(with: nil)
    }

    @Test("Replacing or removing the player's item is observed and resets the value")
    func observedItemChanges() async {
        let vm = makePausedVM()
        let first = BufferedTestItem(ranges: [0...60], duration: bufferTime(120), time: 10)
        vm.player.replaceCurrentItem(with: first)
        await waitUntil { vm.bufferedSpanItem === first && vm.bufferedSpan == 0...0.5 }
        #expect(vm.bufferedSpan == 0...0.5)
        // A quality, language or fallback swap installs an item that has loaded nothing yet.
        let empty = BufferedTestItem(ranges: [], duration: bufferTime(120), time: 10)
        vm.player.replaceCurrentItem(with: empty)
        await waitUntil { vm.bufferedSpanItem === empty }
        #expect(vm.bufferedSpanItem === empty)
        #expect(vm.bufferedSpan == nil)
        let loaded = BufferedTestItem(ranges: [0...60], duration: bufferTime(120), time: 10)
        vm.player.replaceCurrentItem(with: loaded)
        await waitUntil { vm.bufferedSpanItem === loaded && vm.bufferedSpan == 0...0.5 }
        #expect(vm.bufferedSpan == 0...0.5)
        vm.player.replaceCurrentItem(with: nil)
        await waitUntil { vm.bufferedSpanItem == nil && vm.bufferedSpan == nil }
        #expect(vm.bufferedSpanItem == nil)
        #expect(vm.bufferedSpan == nil)
    }

    @Test("An item that played and was then replaced is released")
    func replacedItemIsReleased() async {
        let vm = makePausedVM()
        weak var replaced: AVPlayerItem?
        autoreleasepool {
            let item = BufferedTestItem(ranges: [0...60], duration: bufferTime(120), time: 10)
            replaced = item
            vm.player.replaceCurrentItem(with: item)
        }
        await waitUntil { replaced != nil && vm.bufferedSpanItem === replaced && vm.bufferedSpan == 0...0.5 }
        #expect(vm.bufferedSpan == 0...0.5)
        let next = BufferedTestItem(ranges: [], duration: bufferTime(120), time: 0)
        vm.player.replaceCurrentItem(with: next)
        await waitUntil { vm.bufferedSpanItem === next && replaced == nil }
        #expect(vm.bufferedSpanItem === next)
        #expect(replaced == nil)
        vm.player.replaceCurrentItem(with: nil)
    }
}
