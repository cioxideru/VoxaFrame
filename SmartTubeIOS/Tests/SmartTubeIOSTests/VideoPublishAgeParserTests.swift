import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - VideoPublishAgeParserTests
//
// Tests for task #97: video publish age (publishedAt) extraction in parser functions.
//
// Root cause: parseVideoRenderer and parseLockupViewModel hardcoded publishedAt: nil.
// parseTileRenderer already extracted it correctly (TV client). These tests verify the
// fix extracts the relative-date string from the JSON and populates Video.publishedAt.
//
// All assertions are pure value transforms — no SwiftUI, no network.

// MARK: - Helpers

/// Wraps a videoRenderer in the minimal sectionListRenderer structure for parseVideoGroupForTesting.
private func makeVideoRendererAgeResponse(_ renderer: [String: Any]) -> [String: Any] {
    [
        "contents": [
            "sectionListRenderer": [
                "contents": [
                    [
                        "itemSectionRenderer": [
                            "contents": [["videoRenderer": renderer]]
                        ]
                    ]
                ]
            ]
        ]
    ]
}

/// Wraps a lockupViewModel in the minimal structure that the walker handles at the dict level.
private func makeLockupViewModelAgeResponse(_ lockup: [String: Any]) -> [String: Any] {
    [
        "contents": [
            "sectionListRenderer": [
                "contents": [
                    [
                        "itemSectionRenderer": [
                            "contents": [["lockupViewModel": lockup]]
                        ]
                    ]
                ]
            ]
        ]
    ]
}

/// Returns the approximate expected Date for a relative string like "2 years ago".
private func approximateDate(yearsAgo: Int) -> Date {
    Date(timeIntervalSinceNow: -TimeInterval(yearsAgo * 365 * 86_400))
}

// MARK: - parseVideoRenderer publishedAt

@Suite("Task #97 — parseVideoRenderer publishedAt extraction")
struct VideoRendererPublishAgeTests {

    // A minimal valid videoRenderer dict with a publishedTimeText.simpleText field.
    private func makeRenderer(publishedTimeText: Any?) -> [String: Any] {
        var r: [String: Any] = [
            "videoId": "testvidid",
            "title": ["simpleText": "Test Video"],
            "ownerText": [
                "runs": [
                    [
                        "text": "Test Channel",
                        "navigationEndpoint": ["browseEndpoint": ["browseId": "UCtest"]],
                    ]
                ]
            ],
            "thumbnail": ["thumbnails": [["url": "https://i.ytimg.com/vi/testvidid/hqdefault.jpg"]]],
        ]
        if let pubText = publishedTimeText {
            r["publishedTimeText"] = pubText
        }
        return r
    }

    @Test("parseVideoRenderer with simpleText publishedTimeText populates publishedAt")
    func videoRenderer_simpleText_populatesPublishedAt() async throws {
        let response = makeVideoRendererAgeResponse(
            makeRenderer(
                publishedTimeText: ["simpleText": "2 years ago"]
            ))
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first, "Expected at least one video from response")
        let publishedAt = try #require(video.publishedAt, "publishedAt should be non-nil for '2 years ago'")
        let expectedDate = approximateDate(yearsAgo: 2)
        // Allow 7-day tolerance for calendar approximations in parseRelativeDate.
        #expect(
            abs(publishedAt.timeIntervalSince(expectedDate)) < 7 * 86_400,
            "publishedAt should be approximately 2 years ago")
    }

    @Test("parseVideoRenderer with runs publishedTimeText populates publishedAt")
    func videoRenderer_runsText_populatesPublishedAt() async throws {
        let response = makeVideoRendererAgeResponse(
            makeRenderer(
                publishedTimeText: ["runs": [["text": "3 months ago"]]]
            ))
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first, "Expected at least one video from response")
        #expect(
            video.publishedAt != nil,
            "publishedAt should be non-nil for runs-format '3 months ago'")
    }

    @Test("parseVideoRenderer without publishedTimeText leaves publishedAt nil")
    func videoRenderer_noPublishedTimeText_publishedAtIsNil() async throws {
        let response = makeVideoRendererAgeResponse(makeRenderer(publishedTimeText: nil))
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first, "Expected at least one video from response")
        #expect(
            video.publishedAt == nil,
            "publishedAt should be nil when publishedTimeText is absent from JSON")
    }
}

// MARK: - parseLockupViewModel publishedAt

@Suite("Task #97 — parseLockupViewModel publishedAt extraction")
struct LockupViewModelPublishAgeTests {

    /// Builds a minimal valid lockupViewModel with configurable metadataRows.
    private func makeLockup(metadataRows: [[String: Any]]) -> [String: Any] {
        [
            "rendererContext": [
                "commandContext": [
                    "onTap": [
                        "innertubeCommand": [
                            "watchEndpoint": ["videoId": "lockupvid"]
                        ]
                    ]
                ]
            ],
            "metadata": [
                "lockupMetadataViewModel": [
                    "title": ["content": "Lockup Video"],
                    "metadata": [
                        "contentMetadataViewModel": [
                            "metadataRows": metadataRows
                        ]
                    ],
                ]
            ],
            "contentImage": [
                "thumbnailViewModel": [
                    "image": ["thumbnails": [["url": "https://i.ytimg.com/vi/lockupvid/hqdefault.jpg"]]]
                ]
            ],
        ]
    }

    @Test("parseLockupViewModel extracts publishedAt from second metadataRow")
    func lockupViewModel_secondRow_populatesPublishedAt() async throws {
        let rows: [[String: Any]] = [
            // Row 0: channel name
            ["metadataParts": [["text": ["content": "Channel Name"]]]],
            // Row 1: view count + published date (both in same row — mirrors real YouTube layout)
            [
                "metadataParts": [
                    ["text": ["content": "1.2M views"]],
                    ["text": ["content": "2 years ago"]],
                ]
            ],
        ]
        let response = makeLockupViewModelAgeResponse(makeLockup(metadataRows: rows))
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first, "Expected at least one video from lockupViewModel response")
        let publishedAt = try #require(
            video.publishedAt, "publishedAt should be non-nil when metadataRows contain '2 years ago'")
        let expectedDate = approximateDate(yearsAgo: 2)
        #expect(
            abs(publishedAt.timeIntervalSince(expectedDate)) < 7 * 86_400,
            "publishedAt should be approximately 2 years ago")
    }

    @Test("parseLockupViewModel reads a lone metadata row (channel pages, playlists)")
    func lockupViewModel_singleRow_populatesDateAndViews() async throws {
        let rows: [[String: Any]] = [
            [
                "metadataParts": [
                    ["text": ["content": "2.8M views"]],
                    ["text": ["content": "1 day ago"]],
                ]
            ]
        ]
        let response = makeLockupViewModelAgeResponse(makeLockup(metadataRows: rows))
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first)
        let publishedAt = try #require(video.publishedAt)
        #expect(abs(publishedAt.timeIntervalSinceNow + 86_400) < 60)
        #expect(video.viewCount == 2_800_000)
        #expect(video.channelTitle.isEmpty, "a views/date row is not a channel name")
    }

    @Test("parseLockupViewModel keeps a lone channel-name row as the channel")
    func lockupViewModel_singleChannelRow_keepsChannelTitle() async throws {
        let rows: [[String: Any]] = [["metadataParts": [["text": ["content": "Channel Name"]]]]]
        let response = makeLockupViewModelAgeResponse(makeLockup(metadataRows: rows))
        let video = try #require(try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil).videos.first)
        #expect(video.channelTitle == "Channel Name")
        #expect(video.publishedAt == nil)
    }

    @Test("parseLockupViewModel does not read a date out of the channel name")
    func lockupViewModel_channelNameLikeDate_isNotTheDate() async throws {
        let rows: [[String: Any]] = [
            ["metadataParts": [["text": ["content": "10 Years Ago"]]]],
            ["metadataParts": [["text": ["content": "1.2M views"]], ["text": ["content": "2 days ago"]]]],
        ]
        let response = makeLockupViewModelAgeResponse(makeLockup(metadataRows: rows))
        let video = try #require(try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil).videos.first)
        #expect(video.channelTitle == "10 Years Ago")
        let publishedAt = try #require(video.publishedAt)
        #expect(abs(publishedAt.timeIntervalSinceNow + 2 * 86_400) < 60)
    }

    @Test("parseLockupViewModel with no relative-date text leaves publishedAt nil")
    func lockupViewModel_noRelativeDate_publishedAtIsNil() async throws {
        let rows: [[String: Any]] = [
            ["metadataParts": [["text": ["content": "Channel Name"]]]],
            ["metadataParts": [["text": ["content": "1.2M views"]]]],
            // No relative date in any row
        ]
        let response = makeLockupViewModelAgeResponse(makeLockup(metadataRows: rows))
        let api = InnerTubeAPI()
        let group = try await api.parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first, "Expected at least one video from lockupViewModel response")
        #expect(
            video.publishedAt == nil,
            "publishedAt should be nil when no row contains a relative date string")
    }
}

// MARK: - Age label under feed videos

@Suite("Video age label")
struct VideoAgeLabelTests {
    private let en = Locale(identifier: "en_US")
    private let day: TimeInterval = 86_400

    private func label(_ seconds: TimeInterval) -> String { Video.ageLabel(seconds, locale: en) }

    @Test("minutes, hours and days count whole units")
    func shortAges() {
        #expect(label(20) == "1 minute")
        #expect(label(45 * 60) == "45 minutes")
        #expect(label(6.7 * 3_600) == "6 hours")
        #expect(label(1 * day) == "1 day")
        #expect(label(5.9 * day) == "5 days")
    }

    @Test("weeks, months and years round to the nearest half")
    func longAges() {
        #expect(label(7 * day) == "1 week")
        #expect(label(10 * day) == "1.5 weeks")
        #expect(label(45 * day) == "1.5 months")
        #expect(label(5 * 30 * day) == "5 months")
        #expect(label(2 * 365 * day) == "2 years")
    }

    @Test("decimal separator follows the locale")
    func localizedSeparator() {
        #expect(Video.ageLabel(10 * day, locale: Locale(identifier: "ru_RU")) == "1,5 weeks")
    }

    @Test("dated videos use the date; undated ones fall back to the API text")
    func publishedAgeLabel() {
        let now = Date()
        var video = Video(id: "a", title: "t", channelTitle: "c", publishedAt: now.addingTimeInterval(-6 * 3_600))
        #expect(video.publishedAgeLabel(now: now, locale: en) == "6 hours")
        video.publishedAt = nil
        video.publishedTimeText = "Streamed 3 years ago"
        #expect(video.publishedAgeLabel(now: now, locale: en) == "3 years")
        video.publishedTimeText = nil
        #expect(video.publishedAgeLabel(now: now, locale: en) == nil)
    }
}
