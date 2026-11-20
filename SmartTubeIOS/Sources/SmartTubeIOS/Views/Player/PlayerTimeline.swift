import Foundation
import SmartTubeIOSCore

// MARK: - PlayerTimeline
//
// Where chapters and SponsorBlock segments sit on the player's timeline, and what VoiceOver reads for it.
// Pure values, so the drawing code in PlayerControlsOverlay and the tests share one rule.

enum PlayerTimeline {
    /// VoiceOver adjusts the timeline by this many seconds per swipe (design: VF/Timeline).
    static let accessibilityStep: TimeInterval = 10

    /// Position of `time` on a timeline of `duration`, from 0 to 1; 0 while the duration is unknown.
    static func fraction(_ time: TimeInterval, of duration: TimeInterval) -> Double {
        guard duration > 0, time.isFinite else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    /// The part of the timeline a segment covers, clamped to the video; `nil` when it lies outside the video.
    /// A highlight is a point (`start == end`) and keeps an empty range, which the drawing widens to a mark.
    static func span(start: TimeInterval, end: TimeInterval, duration: TimeInterval) -> ClosedRange<Double>? {
        guard duration > 0, start <= end, end >= 0, start <= duration else { return nil }
        return fraction(start, of: duration)...fraction(end, of: duration)
    }

    // MARK: Buffered range (PLAN-0051)

    /// The buffered part moves on the screen only when one of its ends shifts by at least this share of the
    /// timeline (0.5 %, 2 pt on a 400 pt bar), so the loaded ranges do not re-render the controls on every change.
    static let bufferedPublishStep: Double = 0.005

    /// The loaded stretch the playhead is in, as a part of the timeline; `nil` when the playhead is outside every
    /// loaded range or the length is unknown, zero or indefinite (a live stream). Ranges that touch or overlap
    /// count as one stretch; both of its ends count as inside, so a playhead paused at the buffered end keeps it.
    static func bufferedSpan(
        ranges: [ClosedRange<TimeInterval>], playhead: TimeInterval, duration: TimeInterval
    ) -> ClosedRange<Double>? {
        guard duration.isFinite, duration > 0, playhead.isFinite else { return nil }
        let sorted =
            ranges
            .filter { $0.lowerBound.isFinite && $0.upperBound.isFinite }
            .sorted { $0.lowerBound < $1.lowerBound }
        var stretch: ClosedRange<TimeInterval>?
        for range in sorted {
            if let current = stretch, range.lowerBound <= current.upperBound {
                stretch = current.lowerBound...max(current.upperBound, range.upperBound)
                continue
            }
            if let current = stretch, current.contains(playhead) { break }
            stretch = range
        }
        guard let stretch, stretch.contains(playhead) else { return nil }
        return span(start: stretch.lowerBound, end: stretch.upperBound, duration: duration)
    }

    /// Whether a new buffered part is worth publishing: it appears, disappears, reaches the end of the video,
    /// or one of its ends moves by `bufferedPublishStep`.
    static func bufferedSpanChanged(from old: ClosedRange<Double>?, to new: ClosedRange<Double>?) -> Bool {
        guard let old, let new else { return (old == nil) != (new == nil) }
        if (new.upperBound >= 1) != (old.upperBound >= 1) { return true }
        return abs(new.lowerBound - old.lowerBound) >= bufferedPublishStep
            || abs(new.upperBound - old.upperBound) >= bufferedPublishStep
    }

    /// "6:24 of 18:42", then the chapter and any SponsorBlock segment at that moment, so the values
    /// VoiceOver reads carry what the colours and marks on the timeline show.
    static func accessibilityValue(
        time: TimeInterval, duration: TimeInterval, chapters: [Chapter], segments: [SponsorSegment]
    ) -> String {
        var parts = [
            String(localized: "\(formatDuration(time)) of \(formatDuration(duration))", bundle: .module)
        ]
        if let chapter = chapters.last(where: { $0.startTime <= time }) { parts.append(chapter.title) }
        if let segment = segments.first(where: { $0.start <= time && time < $0.end }) {
            parts.append(segment.category.displayName)
        }
        return parts.joined(separator: ", ")
    }
}
