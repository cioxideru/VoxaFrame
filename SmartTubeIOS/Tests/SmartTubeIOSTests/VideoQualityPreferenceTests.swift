import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Quality matching and persistence")
struct VideoQualityPreferenceTests {
    private func format(_ height: Int, _ codec: VideoCodec) -> VideoFormat {
        VideoFormat(
            label: "\(height)p", width: height * 16 / 9, height: height, fps: 30,
            mimeType: "video/mp4; codecs=\"\(codec.rawValue)\"",
            url: URL(string: "https://example.com/\(height)/\(codec.rawValue)"))
    }

    @Test("Exact resolution and codec beat another codec at that resolution")
    func exactMatch() {
        let requested = VideoQualityPreference(height: 1080, codec: .vp9)
        let expected = format(1080, .vp9)
        #expect(requested.bestMatch(in: [format(1080, .h264), expected]) == expected)
    }

    @Test("Resolution takes priority over matching codec")
    func resolutionBeforeCodec() {
        let requested = VideoQualityPreference(height: 1080, codec: .vp9)
        let expected = format(1080, .h264)
        #expect(requested.bestMatch(in: [format(720, .vp9), expected]) == expected)
    }

    @Test("Nearest resolution can be higher, rather than always capping below the request")
    func nearestHigherResolution() {
        let requested = VideoQualityPreference(height: 1080, codec: .h264)
        let expected = format(1440, .vp9)
        #expect(requested.bestMatch(in: [format(480, .h264), expected]) == expected)
        #expect(requested.closestHeight(in: [480, 1440]) == 1440)
    }

    @Test("Codec breaks equal resolution-distance ties, then the lower resolution wins")
    func equalDistances() {
        let formats = [format(720, .h264), format(1440, .vp9)]
        #expect(VideoQualityPreference(height: 1080, codec: .vp9).bestMatch(in: formats)?.height == 1440)
        #expect(VideoQualityPreference(height: 1080).bestMatch(in: formats)?.height == 720)
    }

    @Test("Auto leaves format selection to the existing automatic policy")
    func autoAndEmptyLadders() {
        #expect(VideoQualityPreference.auto.bestMatch(in: [format(1080, .h264)]) == nil)
        #expect(VideoQualityPreference.auto.closestHeight(in: [720, 1080]) == nil)
        #expect(VideoQualityPreference(height: 720).bestMatch(in: []) == nil)
        #expect(VideoQualityPreference(height: 720).bestMatch(in: [format(0, .h264)]) == nil)
    }

    @Test(
        "Settings retain manual, non-standard and explicit Auto choices",
        arguments: [
            VideoQualityPreference(height: 1080, codec: .vp9),
            VideoQualityPreference(height: 540, codec: .h264),
            .auto,
        ])
    func settingsRoundTrip(_ preference: VideoQualityPreference) throws {
        var settings = AppSettings()
        settings.preferredQuality = .q2160
        settings.lastVideoQuality = preference
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.videoQualityPreference == preference)
    }

    @Test("Old settings still use their default, and unknown codecs retain the chosen resolution")
    func migration() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"preferredQuality":"720p"}"#.utf8))
        #expect(old.videoQualityPreference == VideoQualityPreference(height: 720))
        let future = try JSONDecoder().decode(
            VideoQualityPreference.self, from: Data(#"{"height":1080,"codec":"future-codec"}"#.utf8))
        #expect(future == VideoQualityPreference(height: 1080))
    }

    @Test("HLS keeps codec alternatives and excludes unsupported ladders before matching")
    func actualManifestTracks() {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="vp09.00.41.08,mp4a.40.2"
            vp9-1080.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
            h264-1080.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=2560x1440,CODECS="vp09.00.41.08,mp4a.40.2"
            vp9-1440.m3u8
            """
        let tracks = parseHLSVideoFormats(manifest, baseURL: URL(string: "https://example.com/")!)
        #expect(tracks.count == 3)
        let preference = VideoQualityPreference(height: 1440, codec: .vp9)
        let policy = HLSPlaybackPolicy.resolve(label: "VisionOS/HLS", isHLS: true, vp9Available: false)
        let playable = policy.playableManifestFormats(tracks)
        #expect(playable.count == 1)
        #expect(preference.bestMatch(in: playable)?.videoCodec == .h264)
        #expect(preference.bestMatch(in: playable)?.height == 1080)
    }

    @Test("Cached HLS variants retain codec metadata and invalidate together")
    func cacheRetainsCodecs() throws {
        var cache = HLSManifestCache()
        let formats = [format(1080, .h264), format(1080, .vp9)]
        cache.store([1080: try #require(formats[0].url)], formats: formats, for: "video")
        #expect(cache.formats(for: "video") == formats)
        cache.invalidate(for: "video")
        #expect(cache.formats(for: "video") == nil)
        #expect(cache.variants(for: "video") == nil)
    }
}
