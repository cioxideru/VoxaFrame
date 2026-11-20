import Foundation
import Testing

@testable import SmartTubeIOSCore

// PLAN-0052: the signed-in full-screen Shorts feed follows the account's `reel/reel_watch_sequence`.

/// TVHTML5 `reel/reel_watch_sequence` responses in the shape captured for upstream #189 (2026-11-11, ads
/// 2026-11-12), trimmed to the fields the parser reads; IDs and tokens are replaced. Also used by
/// ShortsFeedRequestTests.
enum SequenceFixture {
    static let page = """
        {
          "responseContext": {
            "serviceTrackingParams": [
              {"service": "CSI", "params": [{"key": "c", "value": "TVHTML5"}]},
              {"service": "GFEEDBACK", "params": [{"key": "logged_in", "value": "1"}]}
            ]
          },
          "entries": [
            {"command": {"reelWatchEndpoint": {"videoId": "seq-1", "videoType": "REEL_VIDEO_TYPE_VIDEO",
              "thumbnail": {"thumbnails": [
                {"url": "https://i.ytimg.com/vi/seq-1/frame0.jpg", "width": 405, "height": 720},
                {"url": "https://i.ytimg.com/vi/seq-1/oar2.jpg", "width": 1080, "height": 1920}]}}}},
            {"command": {"reelWatchEndpoint": {"videoId": "ad-both", "videoType": "REEL_VIDEO_TYPE_AD",
              "adClientParams": {"isAd": true}}}},
            {"command": {"reelWatchEndpoint": {"videoId": "ad-flag", "videoType": "REEL_VIDEO_TYPE_VIDEO",
              "adClientParams": {"isAd": true}}}},
            {"command": {"reelWatchEndpoint": {"videoId": "ad-type", "videoType": "REEL_VIDEO_TYPE_AD"}}},
            {"command": {"reelWatchEndpoint": {"videoId": "seq-2",
              "thumbnail": {"thumbnails": [{"url": "//i.ytimg.com/vi/seq-2/frame0.jpg", "width": 405}]}}}},
            {"command": {"reelWatchEndpoint": {"videoId": "seq-1"}}},
            {"command": {"reelWatchEndpoint": {"videoType": "REEL_VIDEO_TYPE_VIDEO"}}},
            {"command": {"reelWatchEndpoint": {"videoId": ""}}},
            {"command": {}},
            {"unexpected": true},
            {"command": {"reelWatchEndpoint": {"videoId": "seq-3"}}}
          ],
          "continuation": "TV-NEXT"
        }
        """

    static let webContinuation = """
        {"entries": [{"command": {"reelWatchEndpoint": {"videoId": "web-1"}}}],
         "continuationEndpoint": {"continuationCommand": {"token": "WEB-NEXT"}}}
        """

    static let signedOut = """
        {"responseContext": {"serviceTrackingParams": [
           {"service": "GFEEDBACK", "params": [{"key": "logged_in", "value": "0"}]}]},
         "entries": [{"command": {"reelWatchEndpoint": {"videoId": "anon-1"}}}], "continuation": "ANON"}
        """

    /// `logged_in=0` with a `null` beside it on both levels.
    static let signedOutBesideNull = """
        {"responseContext": {"serviceTrackingParams": [null,
           {"service": "GFEEDBACK", "params": [null, {"key": "logged_in", "value": "0"}]}]},
         "entries": [{"command": {"reelWatchEndpoint": {"videoId": "anon-1"}}}], "continuation": "ANON"}
        """

    static let errorAnswer = """
        {"error": {"code": 400, "message": "Request contains an invalid argument.", "status": "INVALID_ARGUMENT"}}
        """

    static let empty = """
        {"responseContext": {"serviceTrackingParams": [
           {"service": "GFEEDBACK", "params": [{"key": "logged_in", "value": "1"}]}]}, "entries": []}
        """

    static let adsOnly = """
        {"entries": [{"command": {"reelWatchEndpoint": {"videoId": "ad", "adClientParams": {"isAd": true}}}}],
         "continuation": "ADS"}
        """

    /// A signed-out WEB search page, the anonymous path's shape.
    static let search = """
        {"contents": {"sectionListRenderer": {"contents": [{"itemSectionRenderer": {"contents": [
          {"videoRenderer": {"videoId": "search-short", "title": {"simpleText": "Search Short"},
            "lengthText": {"simpleText": "0:45"},
            "navigationEndpoint": {"reelWatchEndpoint": {"videoId": "search-short"}}}},
          {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "search-next"}}}}
        ]}}]}}}
        """

    /// Search page `number` in the same shape: one Short, then the continuation `P<number + 1>`.
    static func searchPage(_ number: Int) -> String { searchPage(ids: ["search-\(number)"], next: "P\(number + 1)") }

    /// A search page in the same shape with these Shorts, then `next` if any.
    static func searchPage(ids: [String], next: String?) -> String {
        let shorts = ids.map {
            """
            {"videoRenderer": {"videoId": "\($0)", "title": {"simpleText": "\($0)"},
              "lengthText": {"simpleText": "0:45"}, "navigationEndpoint": {"reelWatchEndpoint": {"videoId": "\($0)"}}}}
            """
        }
        let more = next.map {
            #"{"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "\#($0)"}}}}"#
        }
        let contents = (shorts + [more].compactMap { $0 }).joined(separator: ",")
        return #"{"contents": {"sectionListRenderer": {"contents": [{"itemSectionRenderer": {"contents": ["#
            + contents + "]}}]}}}"
    }

    static func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

@Suite("Shorts sequence parser (PLAN-0052)")
struct ShortsSequenceParserTests {

    @Test("Shorts in YouTube's order, without repeats, ads or entries lacking an ID")
    func parsesOrderedShorts() throws {
        let page = ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.page))
        #expect(page.videos.map(\.id) == ["seq-1", "seq-2", "seq-3"])
        #expect(page.videos.allSatisfy { $0.isShort && $0.title.isEmpty && $0.channelTitle.isEmpty })
        #expect(page.continuation == "TV-NEXT")
        #expect(page.isLoggedIn == true)
        #expect(page.hasError == false)
    }

    @Test("The widest thumbnail is portrait; a protocol-relative URL becomes https; none falls back to the CDN")
    func readsThumbnails() throws {
        let videos = ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.page)).videos
        #expect(videos[0].thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/seq-1/oar2.jpg")
        #expect(videos[0].hasPortraitThumbnail)
        #expect(videos[1].thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/seq-2/frame0.jpg")
        #expect(videos[2].thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/seq-3/hqdefault.jpg")
        #expect(!videos[2].hasPortraitThumbnail)
    }

    @Test(
        "Either ad marker alone leaves the entry out",
        arguments: [
            (["adClientParams": ["isAd": true]], true),
            (["videoType": "REEL_VIDEO_TYPE_AD"], true),
            (["adClientParams": ["isAd": false], "videoType": "REEL_VIDEO_TYPE_VIDEO"], false),
            ([:], false),
        ] as [([String: any Sendable], Bool)])
    func adMarkers(markers: [String: any Sendable], isAd: Bool) {
        var endpoint: [String: Any] = ["videoId": "candidate"]
        for (key, value) in markers { endpoint[key] = value }
        #expect(ShortsSequence.isAd(endpoint) == isAd)
        #expect((ShortsSequence.video(fromReelWatchEndpoint: endpoint) == nil) == isAd)
    }

    @Test("The WEB continuationEndpoint shape is read too")
    func readsWebContinuation() throws {
        let page = ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.webContinuation))
        #expect(page.videos.map(\.id) == ["web-1"])
        #expect(page.continuation == "WEB-NEXT")
        #expect(page.isLoggedIn == nil)
    }

    @Test("logged_in=0, an error answer and an empty page are told apart")
    func readsRefusalSignals() throws {
        #expect(ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.signedOut)).isLoggedIn == false)
        let error = ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.errorAnswer))
        #expect(error.hasError && error.videos.isEmpty && error.continuation == nil)
        let empty = ShortsSequence.parse(try SequenceFixture.json(SequenceFixture.empty))
        #expect(empty.videos.isEmpty && empty.isLoggedIn == true && !empty.hasError)
    }

    @Test("An entry of another type is skipped alone: its neighbours keep their order")
    func skipsANullEntry() throws {
        let json = try SequenceFixture.json(
            """
            {"entries": [{"command": {"reelWatchEndpoint": {"videoId": "n-1"}}}, null, "text",
                         {"command": {"reelWatchEndpoint": {"videoId": "n-2"}}}], "continuation": "N"}
            """)
        let page = ShortsSequence.parse(json)
        #expect(page.videos.map(\.id) == ["n-1", "n-2"])
        #expect(page.continuation == "N")
    }

    @Test("Seed sequenceParams encode the video ID as protobuf field 1")
    func seedParams() throws {
        let encoded = ShortsSequence.seedParams(videoId: "UV6pckLzL_c")
        #expect(encoded == "CgtVVjZwY2tMekxfYyoCGAJQGWgA")  // value #189 verified against YouTube
        let data = try #require(Data(base64Encoded: encoded))
        #expect(data.prefix(2) == Data([0x0A, 0x0B]))
        #expect(String(data: data.dropFirst(2).prefix(11), encoding: .utf8) == "UV6pckLzL_c")
    }
}

@Suite("Shorts feed seed (PLAN-0052)")
struct ShortsFeedSeedTests {
    private func shelf(_ count: Int) -> [Video] {
        (0..<count).map { Video(id: "shelf-\($0)", title: "Shelf", channelTitle: "Test", isShort: true) }
    }

    @Test("The Short opened from a shelf seeds the feed, not the shelf's first Short")
    func selectedShortSeeds() {
        let window = ShortsFeedWindow(videos: shelf(5), startIndex: 2)
        #expect(window.seedVideoId == "shelf-2")
        #expect(window.videos.map(\.id) == shelf(5).map(\.id))  // The shelf stays whole.
    }

    @Test("The seed survives moving past it and trimming, and an empty presentation has none")
    func seedSurvivesTrimming() {
        var window = ShortsFeedWindow(videos: shelf(40), startIndex: 1)
        window.move(to: 30)
        #expect(!window.videos.contains { $0.id == "shelf-1" })
        #expect(window.seedVideoId == "shelf-1")
        #expect(ShortsFeedWindow(videos: [], startIndex: 3).seedVideoId == nil)
        #expect(ShortsFeedWindow(videos: shelf(3), startIndex: 9).seedVideoId == "shelf-2")
    }
}

@Suite("Shorts feed ends (PLAN-0052)")
struct ShortsFeedEndsTests {
    private func shorts(_ ids: [String]) -> [Video] {
        ids.map { Video(id: $0, title: $0, channelTitle: "Test", isShort: true) }
    }

    private func shelf(_ count: Int) -> [Video] { shorts((0..<count).map { "shelf-\($0)" }) }

    @Test("Back from the shelf's first Short, then forward past its end: the first sequence page is at the end")
    func backThenForwardKeepsTheFirstSequencePage() {
        var window = ShortsFeedWindow(videos: shelf(3), startIndex: 0)
        #expect(window.cursor(prepending: true) == nil)
        let earlier = VideoGroup(title: "Shorts", videos: shorts(["sub-1"]), nextPageToken: "subs:BACK")
        #expect(window.accept(earlier, requestedWith: nil, prepending: true) == 1)
        #expect(window.cursor(prepending: true) == "subs:BACK")
        // Loading back spent nothing of the sequence: at a signed-in end this token still gets the sequence's first
        // page (ShortsFeedRequestTests.endStartsTheSequence).
        #expect(window.canLoadMore(prepending: false))

        window.move(to: window.videos.count - 1)
        let token = window.cursor(prepending: false)
        let first = VideoGroup(title: "Shorts", videos: shorts(["seq-1", "seq-2"]), nextPageToken: "reel:TV-NEXT")
        #expect(window.accept(first, requestedWith: token, prepending: false) == 2)
        #expect(window.videos.map(\.id) == ["sub-1", "shelf-0", "shelf-1", "shelf-2", "seq-1", "seq-2"])
        #expect(window.cursor(prepending: false) == "reel:TV-NEXT")
        #expect(window.cursor(prepending: true) == "subs:BACK")
    }

    @Test("After a refusal the end keeps the search on its own `reel:` cursor; loading back keeps the presentation's")
    func refusedSequenceKeepsTheEndsCursor() {
        var window = ShortsFeedWindow(videos: shelf(3), startIndex: 0)
        window.accept(
            VideoGroup(videos: shorts(["sub-1"]), nextPageToken: "subs:BACK"), requestedWith: nil, prepending: true)
        window.accept(
            VideoGroup(videos: shorts(["search-1"]), nextPageToken: "reel:srch:P2"), requestedWith: "subs:BACK",
            prepending: false)
        #expect(window.cursor(prepending: false) == "reel:srch:P2")
        #expect(window.cursor(prepending: true) == "subs:BACK")
    }

    @Test("The sequence stops on its own last page; the shared source's last page stops both ends, as before")
    func lastPagesStopTheirSource() {
        var personal = ShortsFeedWindow(videos: shelf(3), startIndex: 1)
        personal.accept(
            VideoGroup(videos: shorts(["seq-1"]), nextPageToken: "reel:2"), requestedWith: nil, prepending: false)
        personal.accept(
            VideoGroup(videos: shorts(["seq-2"]), nextPageToken: nil), requestedWith: "reel:2", prepending: false)
        #expect(!personal.canLoadMore(prepending: false))
        #expect(personal.canLoadMore(prepending: true))

        var guest = ShortsFeedWindow(videos: shelf(3), startIndex: 1)
        guest.accept(
            VideoGroup(videos: shorts(["search-1"]), nextPageToken: nil), requestedWith: nil, prepending: false)
        #expect(!guest.canLoadMore(prepending: false))
        #expect(!guest.canLoadMore(prepending: true))

        // After the start's last page the end asks once, with a bare `reel:`: only the sequence may start there.
        var ended = ShortsFeedWindow(videos: shelf(3), startIndex: 0)
        ended.accept(
            VideoGroup(videos: shorts(["search-1"]), nextPageToken: nil), requestedWith: nil, prepending: true)
        #expect(!ended.canLoadMore(prepending: true))
        #expect(ended.canLoadMore(prepending: false))
        #expect(ended.cursor(prepending: false) == InnerTubeAPI.shortsSequencePrefix)
        ended.accept(VideoGroup(), requestedWith: InnerTubeAPI.shortsSequencePrefix, prepending: false)
        #expect(!ended.canLoadMore(prepending: false))
    }

    @Test("Shorts loaded back but trimmed at once were never there to watch: the sequence may bring them later")
    func trimmedAtOnceAreNotRemembered() {
        var window = ShortsFeedWindow(videos: shelf(3), startIndex: 0)
        let back = VideoGroup(videos: shorts((0..<20).map { "sub-\($0)" }), nextPageToken: "subs:N")
        #expect(window.accept(back, requestedWith: nil, prepending: true) == 20)
        #expect(window.videos.first?.id == "sub-8")  // Only 12 stay before the playing Short.
        window.move(to: window.videos.count - 1)
        #expect(!window.videos.contains { $0.id == "sub-8" })

        let page = VideoGroup(videos: shorts(["sub-0", "sub-7", "sub-8", "seq-1"]), nextPageToken: "reel:2")
        #expect(window.accept(page, requestedWith: nil, prepending: false) == 3)
        #expect(window.videos.suffix(3).map(\.id) == ["sub-0", "sub-7", "seq-1"])  // sub-8 was there to watch.
    }

    @Test("A Short the feed held before is not repeated at the end once trimmed: loaded back or added at the end")
    func shortsHeldBeforeAreNotRepeated() {
        var window = ShortsFeedWindow(videos: shelf(20), startIndex: 0)
        window.accept(
            VideoGroup(videos: shorts(["sub-1"]), nextPageToken: "subs:N"), requestedWith: nil, prepending: true)
        window.accept(
            VideoGroup(videos: shorts(["seq-1"]), nextPageToken: "reel:1"), requestedWith: nil, prepending: false)
        window.accept(
            VideoGroup(videos: shorts((2..<16).map { "seq-\($0)" }), nextPageToken: "reel:2"), requestedWith: "reel:1",
            prepending: false)
        window.move(to: window.videos.count - 1)
        #expect(!window.videos.contains { $0.id == "sub-1" || $0.id == "seq-1" })

        let page = VideoGroup(videos: shorts(["sub-1", "seq-1", "seq-16"]), nextPageToken: "reel:3")
        #expect(window.accept(page, requestedWith: "reel:2", prepending: false) == 1)
        #expect(window.videos.last?.id == "seq-16")
        #expect(!window.videos.contains { $0.id == "sub-1" || $0.id == "seq-1" })
    }

    @Test("A sequence Short repeating a presented one is dropped, also once it was trimmed from the window")
    func presentedShortsAreNotRepeated() {
        var window = ShortsFeedWindow(videos: shelf(20), startIndex: 0)
        window.move(to: 19)
        #expect(!window.videos.contains { $0.id == "shelf-0" })
        let page = VideoGroup(videos: shorts(["shelf-0", "shelf-19", "seq-1", "seq-1"]), nextPageToken: "reel:N")
        #expect(window.accept(page, requestedWith: nil, prepending: false) == 1)
        #expect(window.videos.map(\.id).suffix(2) == ["shelf-19", "seq-1"])
    }
}
