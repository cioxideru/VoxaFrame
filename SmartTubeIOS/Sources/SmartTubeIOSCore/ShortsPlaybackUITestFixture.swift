#if DEBUG
import Foundation

/// Local HLS fixture for repeatable device/simulator measurements, never a production source.
public enum ShortsPlaybackUITestFixture {
    public static var baseURL: URL? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting"),
            let raw = ProcessInfo.processInfo.environment["SHORTS_TEST_MEDIA_URL"],
            let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1"
        else { return nil }
        return url
    }

    static func playerInfo(videoId: String) -> PlayerInfo? {
        guard let baseURL else { return nil }
        let url = baseURL.appendingPathComponent(videoId).appendingPathComponent("master.m3u8")
        let format = VideoFormat(
            label: "360p", width: 360, height: 640, fps: 30,
            mimeType: "video/mp4; codecs=\"avc1.4d401e\"",
            url: URL(string: url.absoluteString + "?c=VISIONOS"), bitrate: 600_000)
        return PlayerInfo(
            video: Video(id: videoId, title: videoId, channelTitle: "Local fixture", isShort: true),
            formats: [format], hlsURL: url, dashURL: nil, captionTracks: [], trackingURLs: nil, endCards: [])
    }

    public static var translationAudioURL: URL? { baseURL?.appendingPathComponent("voice.mp3") }
}
#endif
