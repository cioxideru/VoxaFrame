import Foundation

// MARK: - ShortsSequence
//
// YouTube's own Shorts order for an account (PLAN-0052, from upstream milika/SmartTubeIOS#189). The TVHTML5 client
// on youtubei.googleapis.com pages it with `reel/reel_watch_sequence`: the first page takes `sequenceParams` built
// from the Short the feed starts at, later pages take the response's `continuation`. A continuation sent back as
// `sequenceParams` is accepted but returns the first page again. Entries carry the video ID and a thumbnail only,
// no title or channel: those come from each Short's `reel/reel_item_watch` overlay (`metadata(from:)`).

/// The request parameters and the parsers for `reel/reel_watch_sequence` and a Short's `reel/reel_item_watch`.
public enum ShortsSequence {

    /// A Short's title and channel from the overlay of its `reel/reel_item_watch`.
    public struct Metadata: Sendable, Equatable {
        public var title: String
        public var channelTitle: String
        public var channelId: String?
    }

    /// `params` of a per-Short `reel/reel_item_watch` that answers its overlay (sent with `disablePlayerResponse`).
    static let metadataParams = "CAUwAg%3D%3D"

    /// One parsed page: Shorts in YouTube's order, the next-page token and whether YouTube served it signed in.
    public struct Page: Sendable, Equatable {
        public var videos: [Video]
        public var continuation: String?
        /// `responseContext.serviceTrackingParams[].params[logged_in]`; nil when the response has no such field.
        public var isLoggedIn: Bool?
        /// The response carried an InnerTube `error` object.
        public var hasError: Bool
    }

    /// `sequenceParams` for a sequence that starts at `videoId`: the protobuf the official clients put in
    /// `reelWatchEndpoint.sequenceParams` (field 1 = the video ID, then the fixed feed-type fields they always send).
    public static func seedParams(videoId: String) -> String {
        let id = Data(videoId.utf8)
        var bytes = Data([0x0A, UInt8(truncatingIfNeeded: id.count)])
        bytes.append(id)
        bytes.append(contentsOf: [0x2A, 0x02, 0x18, 0x02, 0x50, 0x19, 0x68, 0x00])
        return bytes.base64EncodedString()
    }

    /// Shorts in order without repeats; ads, entries without a video ID and entries of another type (a `null`) are left
    /// out one by one, so their neighbours keep their places.
    public static func parse(_ json: [String: Any]) -> Page {
        let entries = (json["entries"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        var seen = Set<String>()
        let videos: [Video] = entries.compactMap { entry in
            guard let command = entry["command"] as? [String: Any],
                let endpoint = command["reelWatchEndpoint"] as? [String: Any],
                let video = video(fromReelWatchEndpoint: endpoint),
                seen.insert(video.id).inserted
            else { return nil }
            return video
        }
        return Page(
            videos: videos, continuation: continuationToken(json), isLoggedIn: loggedIn(json),
            hasError: json["error"] != nil)
    }

    /// Shorts ads arrive as ordinary entries, marked `adClientParams.isAd` or `videoType: REEL_VIDEO_TYPE_AD`;
    /// either marker alone is enough (TVHTML5 capture of 2026-11-12 in #189).
    static func isAd(_ endpoint: [String: Any]) -> Bool {
        let adParams = endpoint["adClientParams"] as? [String: Any]
        return adParams?["isAd"] as? Bool == true || endpoint["videoType"] as? String == "REEL_VIDEO_TYPE_AD"
    }

    static func video(fromReelWatchEndpoint endpoint: [String: Any]) -> Video? {
        guard let id = endpoint["videoId"] as? String, !id.isEmpty, !isAd(endpoint) else { return nil }
        let thumbnail = bestThumbnailURL(endpoint["thumbnail"])
        var video = Video(
            id: id, title: "", channelTitle: "", thumbnailURL: thumbnail, isShort: true,
            hasPortraitThumbnail: thumbnail != nil)
        if thumbnail == nil { video.thumbnailURL = video.highQualityThumbnailURL }
        return video
    }

    /// The TV shape is a top-level `continuation`; the WEB shape `continuationEndpoint.continuationCommand.token`.
    static func continuationToken(_ json: [String: Any]) -> String? {
        if let token = json["continuation"] as? String, !token.isEmpty { return token }
        let endpoint = json["continuationEndpoint"] as? [String: Any]
        let command = endpoint?["continuationCommand"] as? [String: Any]
        guard let token = command?["token"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// Elements of another type (a `null`) are skipped one by one on both levels, so they never hide `logged_in`.
    static func loggedIn(_ json: [String: Any]) -> Bool? {
        let context = json["responseContext"] as? [String: Any]
        for case let service as [String: Any] in context?["serviceTrackingParams"] as? [Any] ?? [] {
            for case let param as [String: Any] in service["params"] as? [Any] ?? []
            where param["key"] as? String == "logged_in" {
                return param["value"] as? String == "1"
            }
        }
        return nil
    }

    /// The overlay of a TVHTML5 `reel/reel_item_watch` (shape from #189): `overlay.reelPlayerOverlayRenderer`'s header
    /// gives the title and channel name, its browse endpoint (else the subscribe button) the channel ID. Nil without
    /// the overlay.
    public static func metadata(from json: [String: Any]) -> Metadata? {
        guard let overlay = (json["overlay"] as? [String: Any])?["reelPlayerOverlayRenderer"] as? [String: Any]
        else { return nil }
        let headers = overlay["reelPlayerHeaderSupportedRenderers"] as? [String: Any]
        let header = headers?["reelPlayerHeaderRenderer"] as? [String: Any] ?? [:]
        let browse = (header["channelNavigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
        let subscribeRoot = overlay["subscribeButtonRenderer"] as? [String: Any]
        let subscribe = subscribeRoot?["subscribeButtonRenderer"] as? [String: Any]
        let channelId = [browse?["browseId"], subscribe?["channelId"]].compactMap { $0 as? String }.first {
            !$0.isEmpty
        }
        return Metadata(
            title: text(header["reelTitleText"]), channelTitle: text(header["channelTitleText"]), channelId: channelId)
    }

    /// Whether `video` lacks the title or channel name the Shorts overlay shows.
    static func needsMetadata(_ video: Video) -> Bool { video.title.isEmpty || video.channelTitle.isEmpty }

    /// `video` with an empty title, channel name or channel ID taken from `metadata`; known values stay.
    static func filling(_ video: Video, with metadata: Metadata) -> Video {
        var filled = video
        if filled.title.isEmpty { filled.title = metadata.title }
        if filled.channelTitle.isEmpty { filled.channelTitle = metadata.channelTitle }
        if filled.channelId?.isEmpty ?? true, let channelId = metadata.channelId { filled.channelId = channelId }
        return filled
    }

    /// A text object's `simpleText`, else its joined `runs`; empty when it has neither.
    private static func text(_ value: Any?) -> String {
        guard let text = value as? [String: Any] else { return "" }
        if let simple = text["simpleText"] as? String { return simple }
        return (text["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
    }

    private static func bestThumbnailURL(_ value: Any?) -> URL? {
        let thumbnails = (value as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let best = thumbnails.max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard var raw = best?["url"] as? String else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }
        return URL(string: raw)
    }
}
