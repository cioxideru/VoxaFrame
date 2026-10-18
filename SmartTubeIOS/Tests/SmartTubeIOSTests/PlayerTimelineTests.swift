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

    @Test("VoiceOver value names the time, the chapter and the segment under the playhead")
    func accessibilityValue() {
        let chapters = [Chapter(title: "Intro", startTime: 0), Chapter(title: "Valley", startTime: 60)]
        let segments = [SponsorSegment(start: 70, end: 80, category: .sponsor)]
        #expect(
            PlayerTimeline.accessibilityValue(time: 75, duration: 120, chapters: chapters, segments: segments)
                == "1:15 of 2:00, Valley, Sponsor")
        #expect(
            PlayerTimeline.accessibilityValue(time: 30, duration: 120, chapters: chapters, segments: segments)
                == "0:30 of 2:00, Intro")
        #expect(PlayerTimeline.accessibilityValue(time: 5, duration: 9, chapters: [], segments: []) == "0:05 of 0:09")
    }
}
