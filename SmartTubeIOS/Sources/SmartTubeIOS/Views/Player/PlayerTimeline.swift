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
