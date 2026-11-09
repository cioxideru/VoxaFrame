import AVFoundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - SponsorBlockSkipManager unit tests
//
// Tests verify the four key behaviours from task #63:
//   1. .skip category seeks past the segment and returns true
//   2. isSkippingSegment guard prevents re-entry while a seek is in-flight
//   3. .showToast category surfaces currentToastSegment without auto-seeking
//   4. Near-end segment calls handlePlaybackEnd instead of seeking

// MARK: - Test double

@MainActor
private final class SpyDelegate: SponsorBlockDelegate {
    var settings: AppSettings
    var duration: Double = 100.0
    var seekCalled: Double? = nil
    var playbackEndCalled = false
    var showControlsCalled = false
    var snapCalled: Double? = nil
    var snappedTimes: [Double] = []

    init(sponsorBlockEnabled: Bool = true) {
        var s = AppSettings()
        s.sponsorBlockEnabled = sponsorBlockEnabled
        self.settings = s
    }

    func seek(to seconds: Double) { seekCalled = seconds }
    func handlePlaybackEnd() { playbackEndCalled = true }
    func showControls() { showControlsCalled = true }
    func snapCurrentTime(to seconds: Double) {
        snapCalled = seconds
        snappedTimes.append(seconds)
    }
}

@MainActor
private final class SeekSpy: SponsorBlockSeeking {
    var sponsorBlockDuration: Double? = 100
    var finished = true
    var targets: [Double] = []
    var holdSeek = false
    private var pendingSeek: CheckedContinuation<Bool, Never>?
    var toleranceBefore: Double?
    var toleranceAfter: Double?

    func seekSponsorSegment(to target: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) async -> Bool {
        targets.append(target.seconds)
        self.toleranceBefore = toleranceBefore.seconds
        self.toleranceAfter = toleranceAfter.seconds
        if holdSeek { return await withCheckedContinuation { pendingSeek = $0 } }
        return finished
    }

    func finishSeek() {
        pendingSeek?.resume(returning: finished)
        pendingSeek = nil
    }
}

// MARK: - Tests

@Suite("SponsorBlockSkipManager")
struct SponsorBlockSkipManagerTests {
    @Test @MainActor
    func manualSkipOnlySeeksAnEligibleSegment() {
        let delegate = SpyDelegate()
        let manager = SponsorBlockSkipManager()
        manager.delegate = delegate
        let segment = SponsorSegment(start: 10, end: 30, category: .sponsor)
        manager.currentToastSegment = segment
        manager.skipToastSegment()
        #expect(delegate.seekCalled == nil && !delegate.playbackEndCalled)

        manager.sponsorSegments = [segment]
        manager.currentToastSegment = segment
        manager.skipToastSegment()
        #expect(delegate.seekCalled == segment.end)
        #expect(delegate.showControlsCalled)
    }

    // MARK: - 1. .skip category triggers seek

    @Test("Auto-skip preserves precise seek tolerances and only snaps after success", arguments: [true, false])
    @MainActor func skipCategorySeeks(finished: Bool) async {
        let manager = SponsorBlockSkipManager()
        let delegate = SpyDelegate()
        let player = SeekSpy()
        manager.waitAfterSeek = {}
        player.finished = finished
        manager.delegate = delegate
        manager.player = player
        manager.sponsorSegments = [SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)]
        delegate.settings.sponsorBlockActions[.sponsor] = .skip

        #expect(manager.checkSponsorSkip(at: 15))
        #expect(manager.isSkippingSegment)
        #expect(manager.checkSponsorSkip(at: 16))
        await waitForTasks { !manager.isSkippingSegment }
        #expect(player.targets == [30])
        #expect(player.toleranceBefore == 0)
        #expect(player.toleranceAfter == 0.5)
        #expect(delegate.snapCalled == (finished ? 30 : nil))
        #expect(!delegate.playbackEndCalled)
    }

    @Test("Reset or stop before the queued skip starts prevents the native seek", arguments: [true, false])
    @MainActor func resetBeforeSeekStarts(reset: Bool) async {
        let player = SeekSpy()
        do {
            let manager = SponsorBlockSkipManager()
            let delegate = SpyDelegate()
            delegate.settings.sponsorBlockActions[.sponsor] = .skip
            manager.delegate = delegate
            manager.player = player
            manager.sponsorSegments = [SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)]
            manager.checkSponsorSkip(at: 15)
            let queuedSkip = manager.skipTask
            if reset {
                manager.reset()
            } else {
                manager.cancelPendingSkip()
            }
            await queuedSkip?.value
            #expect(manager.sponsorSegments.count == (reset ? 0 : 1))
            #expect(!manager.isSkippingSegment)
        }
        #expect(player.targets.isEmpty)
    }

    @Test("Reset ignores an old seek completion while a new skip is pending")
    @MainActor func resetRejectsLateSeek() async {
        let manager = SponsorBlockSkipManager()
        manager.waitAfterSeek = {}
        let delegate = SpyDelegate()
        delegate.settings.sponsorBlockActions[.sponsor] = .skip
        manager.delegate = delegate
        let oldPlayer = SeekSpy()
        oldPlayer.holdSeek = true
        manager.player = oldPlayer
        manager.sponsorSegments = [SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)]
        manager.checkSponsorSkip(at: 15)
        await waitForTasks { oldPlayer.targets.count == 1 }
        let oldSkip = manager.skipTask
        manager.reset()
        let newPlayer = SeekSpy()
        newPlayer.holdSeek = true
        manager.player = newPlayer
        manager.sponsorSegments = [SponsorSegment(id: UUID(), start: 40, end: 60, category: .sponsor)]
        manager.checkSponsorSkip(at: 45)
        await waitForTasks { newPlayer.targets.count == 1 }
        oldPlayer.finishSeek()
        await oldSkip?.value
        #expect(manager.isSkippingSegment)
        #expect(delegate.snappedTimes.isEmpty)
        newPlayer.finishSeek()
        await waitForTasks { !manager.isSkippingSegment }
        #expect(delegate.snappedTimes == [60])
        #expect(newPlayer.targets == [60])
    }

    // MARK: - 2. isSkippingSegment guard prevents re-entry

    @Test("checkSponsorSkip returns true immediately when isSkippingSegment is set")
    @MainActor func isSkippingSegmentGuard() async {
        let manager = SponsorBlockSkipManager()
        let delegate = SpyDelegate()
        manager.delegate = delegate
        manager.player = SeekSpy()
        manager.sponsorSegments = [
            SponsorSegment(
                id: UUID(), start: 5.0, end: 20.0, category: .sponsor
            )
        ]
        var settings = AppSettings()
        settings.sponsorBlockEnabled = true
        settings.sponsorBlockActions[.sponsor] = .skip
        delegate.settings = settings

        // First call sets isSkippingSegment = true
        _ = manager.checkSponsorSkip(at: 10.0)
        #expect(manager.isSkippingSegment == true)

        // Second call while flag is set should still return true (guard path)
        let secondResult = manager.checkSponsorSkip(at: 10.0)
        #expect(secondResult == true)
    }

    // MARK: - 3. .showToast category surfaces currentToastSegment

    @Test(".showToast segment sets currentToastSegment without seeking")
    @MainActor func showToastSetsCurrent() async {
        let manager = SponsorBlockSkipManager()
        let delegate = SpyDelegate()
        manager.delegate = delegate
        let seg = SponsorSegment(id: UUID(), start: 5.0, end: 15.0, category: .selfPromo)
        manager.sponsorSegments = [seg]
        var settings = AppSettings()
        settings.sponsorBlockEnabled = true
        settings.sponsorBlockActions[.selfPromo] = .showToast
        delegate.settings = settings

        let result = manager.checkSponsorSkip(at: 8.0)
        #expect(result == false)
        #expect(manager.currentToastSegment?.id == seg.id)
        #expect(delegate.seekCalled == nil)
    }

    // MARK: - 4. Near-end segment calls handlePlaybackEnd

    @Test("segment ending within 2s of duration calls handlePlaybackEnd")
    @MainActor func nearEndSegmentEndsPlayback() async {
        let manager = SponsorBlockSkipManager()
        let delegate = SpyDelegate()
        delegate.duration = 30.0
        manager.delegate = delegate
        manager.player = nil  // no real player, uses delegate.duration
        manager.sponsorSegments = [
            SponsorSegment(
                id: UUID(), start: 25.0, end: 29.5, category: .sponsor
            )
        ]
        var settings = AppSettings()
        settings.sponsorBlockEnabled = true
        settings.sponsorBlockActions[.sponsor] = .skip
        delegate.settings = settings

        let result = manager.checkSponsorSkip(at: 26.0)
        #expect(result == true)
        #expect(delegate.playbackEndCalled == true)
        #expect(delegate.seekCalled == nil)
    }

    // MARK: - 5. reset() clears all state

    @Test("reset() clears segments, toast, and isSkippingSegment")
    @MainActor func resetClearsState() async {
        let manager = SponsorBlockSkipManager()
        manager.sponsorSegments = [SponsorSegment(id: UUID(), start: 0, end: 10, category: .sponsor)]
        manager.currentToastSegment = SponsorSegment(id: UUID(), start: 5, end: 8, category: .selfPromo)
        manager.reset()
        #expect(manager.sponsorSegments.isEmpty)
        #expect(manager.currentToastSegment == nil)
        #expect(manager.isSkippingSegment == false)
    }

    // MARK: - 6. A skipped or entered segment can be watched

    /// The manager holds its delegate weakly, so the fixture keeps it alive.
    @MainActor private struct Fixture {
        let manager = SponsorBlockSkipManager()
        let player = SeekSpy()
        let delegate = SpyDelegate()

        init(_ segment: SponsorSegment, action: AppSettings.SponsorBlockAction = .skip) {
            delegate.settings.sponsorBlockActions[segment.category] = action
            manager.waitAfterSeek = {}
            manager.delegate = delegate
            manager.player = player
            manager.sponsorSegments = [segment]
        }
    }

    @Test("Seeking back into a skipped segment offers the button instead of skipping again")
    @MainActor func skippedSegmentCanBeWatched() async {
        let segment = SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)
        let fixture = Fixture(segment)
        let manager = fixture.manager
        manager.checkSponsorSkip(at: 9.5)
        #expect(manager.checkSponsorSkip(at: 10))
        await waitForTasks { !manager.isSkippingSegment }
        #expect(!manager.checkSponsorSkip(at: 12))
        #expect(manager.currentToastSegment == segment)
        #expect(fixture.player.targets == [30])
    }

    @Test("A user seek into a segment offers the button; playing into one still skips")
    @MainActor func userSeekIntoSegmentDoesNotSkip() {
        let segment = SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)
        let fixture = Fixture(segment)
        let manager = fixture.manager
        manager.checkSponsorSkip(at: 2)
        #expect(!manager.checkSponsorSkip(at: 20))
        #expect(manager.currentToastSegment == segment)
        #expect(fixture.player.targets.isEmpty)

        let other = SponsorSegment(id: UUID(), start: 40, end: 50, category: .sponsor)
        manager.sponsorSegments = [segment, other]
        manager.checkSponsorSkip(at: 39.5)
        #expect(manager.checkSponsorSkip(at: 40))
    }

    @Test("The skip button leaves after a few seconds inside the segment and returns on re-entry")
    @MainActor func skipButtonTimesOut() {
        let segment = SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)
        let fixture = Fixture(segment, action: .showToast)
        let manager = fixture.manager
        let limit = PlaybackTuning.sponsorSkipButtonDuration
        manager.checkSponsorSkip(at: 10)
        manager.checkSponsorSkip(at: 10 + limit - 0.5)
        #expect(manager.currentToastSegment == segment)
        manager.checkSponsorSkip(at: 10 + limit)
        #expect(manager.currentToastSegment == nil)
        manager.checkSponsorSkip(at: 31)
        manager.checkSponsorSkip(at: 15)
        #expect(manager.currentToastSegment == segment)
    }

    @Test("reset() forgets handled segments")
    @MainActor func resetForgetsHandledSegments() {
        let segment = SponsorSegment(id: UUID(), start: 10, end: 30, category: .sponsor)
        let fixture = Fixture(segment)
        let manager = fixture.manager
        manager.checkSponsorSkip(at: 2)
        manager.checkSponsorSkip(at: 20)
        #expect(manager.handledSegmentIDs == [segment.id])
        manager.reset()
        #expect(manager.handledSegmentIDs.isEmpty)
    }
}
