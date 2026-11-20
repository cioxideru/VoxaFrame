import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - Timeline layout and VoiceOver value (PLAN-0027 stage 4)

@Suite("Player timeline")
struct PlayerTimelineTests {
    @Test("Position is clamped to the video and zero while the duration is unknown")
    func fraction() {
        #expect(PlayerTimeline.fraction(30, of: 120) == 0.25)
        #expect(PlayerTimeline.fraction(-5, of: 120) == 0)
        #expect(PlayerTimeline.fraction(500, of: 120) == 1)
        #expect(PlayerTimeline.fraction(30, of: 0) == 0)
        #expect(PlayerTimeline.fraction(.nan, of: 120) == 0)
    }

    @Test("Segments are clamped to the video; segments outside it are dropped")
    func span() {
        #expect(PlayerTimeline.span(start: 30, end: 60, duration: 120) == 0.25...0.5)
        #expect(PlayerTimeline.span(start: 100, end: 200, duration: 120) == (100.0 / 120)...1)
        #expect(PlayerTimeline.span(start: -10, end: 12, duration: 120) == 0...0.1)
        #expect(PlayerTimeline.span(start: 60, end: 60, duration: 120) == 0.5...0.5)
        #expect(PlayerTimeline.span(start: 130, end: 140, duration: 120) == nil)
        #expect(PlayerTimeline.span(start: 60, end: 30, duration: 120) == nil)
        #expect(PlayerTimeline.span(start: 10, end: 20, duration: 0) == nil)
    }

    @Test("Buffered part is the loaded range that contains the playhead (PLAN-0051)")
    func bufferedInside() {
        #expect(PlayerTimeline.bufferedSpan(ranges: [30...60], playhead: 40, duration: 120) == 0.25...0.5)
        // Both ends count as inside: a playhead paused at the buffered end keeps it.
        #expect(PlayerTimeline.bufferedSpan(ranges: [30...60], playhead: 30, duration: 120) == 0.25...0.5)
        #expect(PlayerTimeline.bufferedSpan(ranges: [30...60], playhead: 60, duration: 120) == 0.25...0.5)
    }

    @Test("No buffered part while the playhead is before, after or between the loaded ranges")
    func bufferedOutside() {
        #expect(PlayerTimeline.bufferedSpan(ranges: [30...60], playhead: 10, duration: 120) == nil)
        #expect(PlayerTimeline.bufferedSpan(ranges: [30...60], playhead: 90, duration: 120) == nil)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...20, 60...90], playhead: 40, duration: 120) == nil)
        #expect(PlayerTimeline.bufferedSpan(ranges: [], playhead: 40, duration: 120) == nil)
    }

    @Test("Of several ranges only the one under the playhead counts; touching ranges are one stretch")
    func bufferedSeveral() {
        let ranges: [ClosedRange<TimeInterval>] = [60...90, 0...24]  // AVFoundation does not promise an order
        #expect(PlayerTimeline.bufferedSpan(ranges: ranges, playhead: 12, duration: 120) == 0...0.2)
        #expect(PlayerTimeline.bufferedSpan(ranges: ranges, playhead: 72, duration: 120) == 0.5...0.75)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...30, 30...60], playhead: 10, duration: 120) == 0...0.5)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...40, 20...60], playhead: 50, duration: 120) == 0...0.5)
    }

    @Test(
        "No buffered part while the length is unknown, zero or indefinite (live)",
        arguments: [0, -1, Double.nan, Double.infinity])
    func bufferedWithoutLength(duration: TimeInterval) {
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...30], playhead: 10, duration: duration) == nil)
    }

    @Test("Buffered part is clamped to the video and ignores a non-finite playhead or range")
    func bufferedClamped() {
        #expect(PlayerTimeline.bufferedSpan(ranges: [90...130], playhead: 100, duration: 120) == 0.75...1)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...120], playhead: 120, duration: 120) == 0...1)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...30], playhead: .nan, duration: 120) == nil)
        #expect(PlayerTimeline.bufferedSpan(ranges: [0...(.infinity)], playhead: 10, duration: 120) == nil)
    }

    @Test("A new buffered part is published only when it changes noticeably")
    func bufferedPublishing() {
        let step = PlayerTimeline.bufferedPublishStep
        #expect(!PlayerTimeline.bufferedSpanChanged(from: nil, to: nil))
        #expect(PlayerTimeline.bufferedSpanChanged(from: nil, to: 0...0.1))
        #expect(PlayerTimeline.bufferedSpanChanged(from: 0...0.1, to: nil))
        #expect(!PlayerTimeline.bufferedSpanChanged(from: 0...0.1, to: 0...(0.1 + step / 2)))
        #expect(PlayerTimeline.bufferedSpanChanged(from: 0...0.1, to: 0...(0.1 + step * 1.5)))
        #expect(PlayerTimeline.bufferedSpanChanged(from: 0.2...0.4, to: (0.2 + step * 1.5)...0.4))
        // Reaching the end of the video always shows, however small the last step.
        #expect(PlayerTimeline.bufferedSpanChanged(from: 0...(1 - step / 2), to: 0...1))
    }

    @Test("VoiceOver value names the time, the chapter and the segment under the playhead")
    func accessibilityValue() {
        let chapters = [Chapter(title: "Intro", startTime: 0), Chapter(title: "Valley", startTime: 60)]
        let segments = [SponsorSegment(start: 70, end: 80, category: .sponsor)]
        // Expected text comes from the app's catalog, so the test holds in any host language.
        func position(_ time: String, _ duration: String) -> String {
            String(localized: "\(time) of \(duration)", bundle: .module)
        }
        #expect(
            PlayerTimeline.accessibilityValue(time: 75, duration: 120, chapters: chapters, segments: segments)
                == "\(position("1:15", "2:00")), Valley, \(SponsorSegment.Category.sponsor.displayName)")
        #expect(
            PlayerTimeline.accessibilityValue(time: 30, duration: 120, chapters: chapters, segments: segments)
                == "\(position("0:30", "2:00")), Intro")
        #expect(
            PlayerTimeline.accessibilityValue(time: 5, duration: 9, chapters: [], segments: [])
                == position("0:05", "0:09"))
    }
}
