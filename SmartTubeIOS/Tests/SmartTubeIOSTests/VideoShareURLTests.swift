import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - VideoShareURLTests (#104)
//
// All four of the app's own Share entry points (VideoCardView, ShortsCardView,
// PlayerView+Overlays, and the since-removed embed player) already built a clean watch?v=<id> URL with no
// tracking query params before this task — they just duplicated the string literal
// four times with no test locking that in. Extracted to Video.shareURL so there's one
// place to check (and one test to catch a regression) instead of four.

@Suite("Video.shareURL (#104)")
struct VideoShareURLTests {

    @Test("shareURL contains only watch?v=<id>, no query parameters")
    func shareURLHasNoTrackingParams() {
        let video = Video(id: "dQw4w9WgXcQ", title: "Test", channelTitle: "Test Channel")

        let url = video.shareURL

        #expect(url?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        let queryItems = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        #expect(
            queryItems == [URLQueryItem(name: "v", value: "dQw4w9WgXcQ")],
            "shareURL must carry only the required v= video-id parameter — no si= or any other tracking query parameter"
        )
    }
}
