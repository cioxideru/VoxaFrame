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

    @Test("encode/decode round-trip preserves both fields")
    func roundTrip() throws {
        var original = AppSettings()
        original.hideWatchedVideos = true
        original.hideWatchedThreshold = 0.75

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.hideWatchedVideos == true)
        #expect(decoded.hideWatchedThreshold == 0.75)
    }

    @Test("old JSON missing these fields decodes to defaults instead of failing")
    func missingFieldsDecodeToDefaults() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        #expect(settings.hideWatchedVideos == false)
        #expect(settings.hideWatchedThreshold == 0.9)
    }
}
