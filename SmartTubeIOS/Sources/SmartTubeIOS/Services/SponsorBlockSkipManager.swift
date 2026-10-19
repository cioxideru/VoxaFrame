import AVFoundation
import Observation
import SmartTubeIOSCore

/// The native seek surface used by SponsorBlock; decisions remain in Core.
@MainActor
public protocol SponsorBlockSeeking: AnyObject {
    var sponsorBlockDuration: Double? { get }
    func seekSponsorSegment(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) async -> Bool
}

extension AVPlayer: SponsorBlockSeeking {
    public var sponsorBlockDuration: Double? { currentItem?.duration.seconds }

    public func seekSponsorSegment(to target: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) async -> Bool {
        await seek(to: target, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
}

// MARK: - SponsorBlockDelegate

/// Implemented by PlaybackViewModel to give SponsorBlockSkipManager the minimal
/// cross-boundary surface it needs without taking a direct reference to the full VM.
@MainActor
public protocol SponsorBlockDelegate: AnyObject {
    var settings: AppSettings { get }
    var duration: Double { get }
    func seek(to seconds: Double)
    func handlePlaybackEnd()
    func showControls()
    /// Snaps the observable `currentTime` to `seconds` after a seek completes,
    /// so the UI does not flash the pre-seek position while AVPlayer settles.
    func snapCurrentTime(to seconds: Double)
}

// MARK: - SponsorBlockSkipManager

/// Owns `sponsorSegments`, `currentToastSegment`, and `isSkippingSegment`.
/// Called from the PlaybackViewModel time observer; all logic migrated from
/// PlaybackViewModel+SponsorBlock.swift.
@MainActor
@Observable
public final class SponsorBlockSkipManager {

    // MARK: - State

    public var sponsorSegments: [SponsorSegment] = []
    public var currentToastSegment: SponsorSegment?
    /// True while a SponsorBlock auto-skip seek is in-flight. Guards against the
    /// periodic time observer re-triggering before the seek completes.
    public private(set) var isSkippingSegment: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored public weak var delegate: (any SponsorBlockDelegate)?
    @ObservationIgnored public var player: (any SponsorBlockSeeking)?

    @ObservationIgnored private(set) var skipTask: Task<Void, Never>?
    @ObservationIgnored var waitAfterSeek: @MainActor () async throws -> Void = {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    // MARK: - Init

    public init() {}

    deinit { skipTask?.cancel() }

    // MARK: - Interface

    func cancelPendingSkip() {
        skipTask?.cancel()
        skipTask = nil
        isSkippingSegment = false
    }

    public func reset() {
        cancelPendingSkip()
        sponsorSegments = []
        currentToastSegment = nil
        isSkippingSegment = false
    }

    /// Called from the time observer. Handles per-category actions:
    ///   `.skip`      → seeks past the segment automatically.
    ///   `.showToast` → surfaces `currentToastSegment` for the skip button.
    ///   `.nothing`   → no-op.
    /// Returns true if an auto-seek was triggered.
    @discardableResult
    public func checkSponsorSkip(at time: TimeInterval) -> Bool {
        guard let delegate else {
            currentToastSegment = nil
            return false
        }
        let effectiveDuration = player?.sponsorBlockDuration ?? delegate.duration
        let decision = SponsorBlockDecisionEngine.decide(
            at: time,
            segments: sponsorSegments,
            settings: delegate.settings,
            isSkipInProgress: isSkippingSegment,
            duration: effectiveDuration
        )
        switch decision {
        case .clearToast:
            currentToastSegment = nil
            return false
        case .showToast(let seg):
            currentToastSegment = seg
            return false
        case .skipToPlaybackEnd:
            currentToastSegment = nil
            delegate.handlePlaybackEnd()
            return true
        case .skip(let target, _):
            currentToastSegment = nil
            guard let player else { return true }
            isSkippingSegment = true
            let waitAfterSeek = waitAfterSeek
            skipTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                let finished = await player.seekSponsorSegment(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
                )
                guard !Task.isCancelled else { return }
                if finished { self?.delegate?.snapCurrentTime(to: target) }
                do { try await waitAfterSeek() } catch { return }
                guard !Task.isCancelled else { return }
                self?.isSkippingSegment = false
                self?.skipTask = nil
            }
            return true
        case .none:
            return true
        }
    }

    /// Manually skip the segment shown in `currentToastSegment` (called by skip button).
    public func skipToastSegment() {
        guard let seg = currentToastSegment else { return }
        currentToastSegment = nil
        // Settings may have changed since the toast appeared (category, minimum length, enable switch).
        guard sponsorSegments.contains(where: { $0.id == seg.id }),
            delegate?.settings.sponsorAction(for: seg.category) != AppSettings.SponsorBlockAction.nothing
        else { return }
        let effectiveDuration = player?.sponsorBlockDuration ?? delegate?.duration ?? 0
        if effectiveDuration > 0 && seg.end >= effectiveDuration - 2.0 {
            delegate?.handlePlaybackEnd()
            return
        }
        delegate?.seek(to: seg.end)
        delegate?.showControls()
    }
}
