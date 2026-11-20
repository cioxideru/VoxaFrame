import Foundation
import Testing

@testable import SmartTubeIOSCore

// Android SmartTube 348cbe28: when YouTube reports a video 100 % watched, an earlier position saved on this device
// must not replace that completion on cards, offline rows and in VoiceOver.

private let completedTileJSON = #"""
    {"contents": {"sectionListRenderer": {"contents": [{"itemSectionRenderer": {"contents": [{"tileRenderer": {
      "contentType": "TILE_CONTENT_TYPE_VIDEO",
      "onSelectCommand": {"watchEndpoint": {"videoId": "watchedvid1"}},
      "metadata": {"tileMetadataRenderer": {"title": {"simpleText": "Watched"}}},
      "header": {"tileHeaderRenderer": {"thumbnailOverlays": [
        {"thumbnailOverlayResumePlaybackRenderer": {"percentDurationWatched": PERCENT}}
      ]}}
    }}]}}]}}}
    """#

@Suite("Remote completion beats an earlier local position")
struct RemoteCompletionProgressTests {

    /// A video parsed from a fake TV browse response reporting `percent` watched.
    private func parsedVideo(percent: Int) async throws -> Video {
        let json = completedTileJSON.replacingOccurrences(of: "PERCENT", with: String(percent))
        let response = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil)
        return try #require(group.videos.first)
    }

    /// The fraction an isolated store keeps after 30 s of a 100 s video.
    private func savedFraction(for id: String) async throws -> Double {
        let store = VideoStateStore(suiteName: "test-\(UUID().uuidString)")
        await store.save(videoId: id, position: 30, duration: 100)
        return try #require(await store.state(for: id)?.watchedFraction)
    }

    @Test("YouTube 100 % wins over a saved 30 %")
    func remoteCompletionWins() async throws {
        let video = try await parsedVideo(percent: 100)
        #expect(video.watchProgress == 1.0)
        let saved = try await savedFraction(for: video.id)
        #expect(saved == 0.3)
        #expect(video.displayedWatchProgress(saved: saved) == 1.0)
    }

    @Test("Partial YouTube progress still yields to the saved position")
    func partialRemoteKeepsLocal() async throws {
        let video = try await parsedVideo(percent: 10)
        #expect(video.watchProgress == 0.1)
        #expect(video.displayedWatchProgress(saved: try await savedFraction(for: video.id)) == 0.3)
    }

    @Test("Without a saved position the YouTube value is shown, and without either nothing")
    func missingValues() {
        let watched = Video(id: "a", title: "A", channelTitle: "C", watchProgress: 1)
        #expect(watched.displayedWatchProgress(saved: nil) == 1)
        let unknown = Video(id: "b", title: "B", channelTitle: "C")
        #expect(unknown.displayedWatchProgress(saved: 0.3) == 0.3)
        #expect(unknown.displayedWatchProgress(saved: nil) == nil)
    }
}
