import AVFoundation

// MARK: - Buffered range on the timeline (PLAN-0051)
//
// The timeline shows the loaded stretch of the current item that contains the playhead. It is measured when the
// item's loaded ranges or its length change (KVO), when the periodic time observer ticks and when a seek completes;
// there is no timer of its own. The length is observed because it can turn finite after readyToPlay while the
// player is paused and the ranges no longer change. Both KVO paths go through `currentItem`, so every writer of the
// item (load, quality, HLS language, audio-only, fallback paths) is covered without touching them, and an item swap
// is seen as a change.

extension PlaybackViewModel {

    func setupBufferedRangeObserver() {
        invalidateBufferedRangeObservers()
        bufferedRangeObservers = [
            observeForBufferedSpan(\AVPlayer.currentItem?.loadedTimeRanges),
            observeForBufferedSpan(\AVPlayer.currentItem?.duration),
        ]
    }

    func invalidateBufferedRangeObservers() {
        bufferedRangeObservers.forEach { $0.invalidate() }
        bufferedRangeObservers = []
    }

    /// The handler only hops to the main actor; the state is read there, against the player that is current then.
    private func observeForBufferedSpan<Value>(_ keyPath: KeyPath<AVPlayer, Value>) -> NSKeyValueObservation {
        player.observe(keyPath) { [weak self] source, _ in
            guard self != nil else { return }
            Task { @MainActor [weak self, weak source] in
                guard let self, self.player === source else { return }
                self.refreshBufferedSpan()
            }
        }
    }

    /// Measures the current item and publishes the result: always when the item changed, otherwise only when the
    /// change passes `PlayerTimeline.bufferedSpanChanged`, so loading does not re-render the controls each time.
    func refreshBufferedSpan() {
        let item = player.currentItem
        publishBufferedSpan(item.flatMap(measuredBufferedSpan(of:)), for: item)
    }

    func publishBufferedSpan(_ span: ClosedRange<Double>?, for item: AVPlayerItem?) {
        if item !== bufferedSpanItem {
            bufferedSpanItem = item
            if bufferedSpan != span { bufferedSpan = span }
        } else if PlayerTimeline.bufferedSpanChanged(from: bufferedSpan, to: span) {
            bufferedSpan = span
        }
    }

    func measuredBufferedSpan(of item: AVPlayerItem) -> ClosedRange<Double>? {
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return nil }
        if item === localPlaybackItem, item.status == .readyToPlay { return 0...1 }
        let ranges = item.loadedTimeRanges.map(\.timeRangeValue).compactMap { range -> ClosedRange<TimeInterval>? in
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, start <= end else { return nil }
            return start...end
        }
        return PlayerTimeline.bufferedSpan(ranges: ranges, playhead: item.currentTime().seconds, duration: duration)
    }
}
