import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// The offline row hides its cover (and the progress bar on it) from VoiceOver, so the row itself must read the
// watched share, with the same text as a video card and from the same displayed value (Android 348cbe28).
@Suite("Offline row reads its watch progress")
struct OfflineRowWatchProgressTests {

    private func row(_ video: Video, saved: Double?) -> OfflineEntryLabel {
        OfflineEntryLabel(
            entry: OfflineEntry(video: video, assets: []), title: video.title, isSelected: false,
            status: .ready, tracks: [], progress: video.displayedWatchProgress(saved: saved))
    }

    @Test("YouTube 100 % with a saved 30 % reads as fully watched")
    func remoteCompletionIsRead() throws {
        let video = Video(id: "done", title: "Done", channelTitle: "C", watchProgress: 1)
        let value = try #require(row(video, saved: 0.3).watchedAccessibilityValue)
        #expect(value == WatchProgressBar.accessibilityText(for: 1))
        // "100%" in the current locale's digits and percent sign, formatted here rather than through the helper.
        let fullyWatched = (1.0).formatted(.percent.precision(.fractionLength(0)))
        #expect(value.contains(fullyWatched))
    }

    @Test("A partial saved position is read as that share")
    func savedPositionIsRead() {
        let video = Video(id: "part", title: "Part", channelTitle: "C", watchProgress: 0.1)
        #expect(row(video, saved: 0.3).watchedAccessibilityValue == WatchProgressBar.accessibilityText(for: 0.3))
    }

    @Test("A row without progress reads no watched value")
    func noProgressReadsNothing() {
        let video = Video(id: "new", title: "New", channelTitle: "C")
        #expect(row(video, saved: nil).watchedAccessibilityValue == nil)
        #expect(row(video, saved: 0).watchedAccessibilityValue == nil)
    }
}
