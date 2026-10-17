import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - HideWatchedVideosTests (#121)

@Suite("Video.isWatched(threshold:) (#121)")
struct HideWatchedVideosTests {

    private func makeVideo(watchProgress: Double?) -> Video {
        Video(id: "vid1", title: "Test", channelTitle: "Test Channel", watchProgress: watchProgress)
    }

    @Test("nil watchProgress is never considered watched")
    func nilProgressNeverWatched() {
        let video = makeVideo(watchProgress: nil)
        #expect(!video.isWatched(threshold: 0.9))
    }

    @Test("progress below threshold is not watched")
    func belowThresholdNotWatched() {
        let video = makeVideo(watchProgress: 0.5)
        #expect(!video.isWatched(threshold: 0.9))
    }

    @Test("progress at threshold is watched")
    func atThresholdIsWatched() {
        let video = makeVideo(watchProgress: 0.9)
        #expect(video.isWatched(threshold: 0.9))
    }

    @Test("progress above threshold is watched")
    func aboveThresholdIsWatched() {
        let video = makeVideo(watchProgress: 0.95)
        #expect(video.isWatched(threshold: 0.9))
    }

    @Test("a lower threshold setting hides more videos")
    func lowerThresholdHidesMore() {
        let video = makeVideo(watchProgress: 0.6)
        #expect(!video.isWatched(threshold: 0.9))
        #expect(video.isWatched(threshold: 0.5))
    }

    @Test("low thresholds include the exact boundary and keep unknown/zero progress", arguments: [5, 10, 25, 45])
    func lowThreshold(percent: Int) {
        let threshold = Double(percent) / 100
        #expect(makeVideo(watchProgress: threshold).isWatched(threshold: threshold))
        #expect(!makeVideo(watchProgress: threshold - 0.01).isWatched(threshold: threshold))
        #expect(!makeVideo(watchProgress: nil).isWatched(threshold: threshold))
        #expect(!makeVideo(watchProgress: 0).isWatched(threshold: threshold))
    }
}

// MARK: - AppSettings.hideWatchedVideos / hideWatchedThreshold

@Suite("AppSettings.hideWatchedVideos (#121)")
struct HideWatchedVideosSettingTests {

    @Test("defaults to disabled with a 0.9 threshold")
    func defaults() {
        let settings = AppSettings()
        #expect(settings.hideWatchedVideos == false)
        #expect(settings.hideWatchedThreshold == 0.9)
    }

    @Test("encode/decode round-trip preserves both fields", arguments: [0.05, 0.25, 0.75, 1.0])
    func roundTrip(threshold: Double) throws {
        var original = AppSettings()
        original.hideWatchedVideos = true
        original.hideWatchedThreshold = threshold

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.hideWatchedVideos == true)
        #expect(decoded.hideWatchedThreshold == threshold)
    }

    @Test("old JSON missing these fields decodes to defaults instead of failing")
    func missingFieldsDecodeToDefaults() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        #expect(settings.hideWatchedVideos == false)
        #expect(settings.hideWatchedThreshold == 0.9)
    }

    @Test("stepping down through 50 percent retains exact threshold boundaries")
    func integerSteps() {
        var settings = AppSettings()
        while settings.hideWatchedThresholdPercent > AppSettings.hideWatchedThresholdPercentRange.lowerBound {
            settings.hideWatchedThresholdPercent -= AppSettings.hideWatchedThresholdPercentStep
            let video = Video(
                id: "boundary", title: "Boundary", channelTitle: "Fixture",
                watchProgress: Double(settings.hideWatchedThresholdPercent) / 100)
            settings.hideWatchedVideos = true
            #expect(settings.shouldHideWatched(video, in: .home))
        }
        #expect(settings.hideWatchedThreshold == 0.05)
        #expect(settings.hideWatchedThresholdPercent == 5)
    }

    @Test("all feed sections share the filter except History", arguments: BrowseSection.SectionType.allCases)
    func sectionPolicy(section: BrowseSection.SectionType) {
        var settings = AppSettings()
        settings.hideWatchedThresholdPercent = 25
        for isShort in [false, true] {
            let video = Video(
                id: "watched", title: "Watched", channelTitle: "Fixture", isShort: isShort,
                watchProgress: 0.25)
            settings.hideWatchedVideos = false
            #expect(!settings.shouldHideWatched(video, in: section))
            settings.hideWatchedVideos = true
            #expect(settings.shouldHideWatched(video, in: section) == (section != .history))
        }
    }
}
