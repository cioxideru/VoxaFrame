import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

extension InnerTubeAPI {
    // MARK: – WEB playlistVideoRenderer parser (BUG-012 fix)
    // Playlist video items use shortBylineText/shortViewCountText instead of
    // ownerText/viewCountText which parseVideoRenderer expects.
    func parsePlaylistVideoRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }
        // #63: drop members-only videos here too — this renderer serves the same
        // Home/Subscriptions/History feeds parseTileRenderer does (see this function's
        // own BUG-012 doc comment above), just for videos that arrive in the WEB-shaped
        // renderer instead of the TV tile shape. Without this, a members-only video could
        // still leak through whichever of the two shapes YouTube happened to use for it.
        if isMembersOnlyVideo(
            overlays: renderer["thumbnailOverlays"] as? [[String: Any]], badges: renderer["badges"] as? [[String: Any]]
        ) {
            tubeLog.notice("parsePlaylistVideoRenderer: dropping members-only video id=\(videoId, privacy: .public)")
            return nil
        }
        // The playlist-entry token needed to remove this exact item via ACTION_REMOVE_VIDEO
        // (see InnerTubeAPI+Social.swift's removeFromWatchLater — #122).
        let setVideoId = renderer["setVideoId"] as? String
        let title = (renderer["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""

        // channelTitle: shortBylineText preferred; ownerText as fallback
        let channelTitle =
            (renderer["shortBylineText"] as? [String: Any]).flatMap { extractText($0) }
            ?? (renderer["ownerText"] as? [String: Any]).flatMap { extractText($0) }
            ?? ""

        // channelId: from shortBylineText or ownerText runs[0].navigationEndpoint.browseEndpoint.browseId
        let channelId: String? = {
            let sourceKey = renderer["shortBylineText"] != nil ? "shortBylineText" : "ownerText"
            guard let runs = (renderer[sourceKey] as? [String: Any])?["runs"] as? [[String: Any]],
                let first = runs.first,
                let nav = first["navigationEndpoint"] as? [String: Any],
                let browse = nav["browseEndpoint"] as? [String: Any]
            else { return nil }
            return browse["browseId"] as? String
        }()

        let thumbnails = (renderer["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

        let lengthText = (renderer["lengthText"] as? [String: Any]).flatMap { extractText($0) }
        let duration = lengthText.flatMap { parseDuration($0) }

        // viewCount: shortViewCountText preferred; viewCountText as fallback; direct int last
        let viewCountText =
            (renderer["shortViewCountText"] as? [String: Any]).flatMap { extractText($0) }
            ?? (renderer["viewCountText"] as? [String: Any]).flatMap { extractText($0) }
        let viewCount = viewCountText.flatMap { extractNumber($0) } ?? renderer["viewCount"] as? Int

        let watchProgress: Double? = (renderer["thumbnailOverlays"] as? [[String: Any]])?
            .compactMap {
                ($0["thumbnailOverlayResumePlaybackRenderer"] as? [String: Any])
                    .flatMap { $0["percentDurationWatched"] as? Double }
            }
            .first.map { $0 / 100.0 }

        // isShort: apply same 4 signals as parseVideoRenderer (BUG-019 fix).
        // playlistVideoRenderer items appear in Home, Subscriptions, and History feeds
        // and previously had isShort hard-coded to false, bypassing all hideShorts filtering.
        let isShort = isPlaylistShort(renderer, duration: duration, thumbnails: thumbnails)
        if isShort {
            tubeLog.debug(
                "playlistVideoRenderer isShort=true id=\(videoId, privacy: .public) duration=\(Int(duration ?? -1))")
        }

        let publishedTimeText: String? = (renderer["publishedTimeText"] as? [String: Any]).flatMap { extractText($0) }
        let publishedAt: Date? = publishedTimeText.flatMap { parseRelativeDate($0) }
        let publishedTimePreview = publishedTimeText ?? "nil"
        tubeLog.notice(
            "playlistVideoRenderer id=\(videoId, privacy: .public) publishedTimeText='\(publishedTimePreview, privacy: .public)'"
        )

        return Video(
            id: videoId,
            title: title,
            channelTitle: channelTitle,
            channelId: channelId,
            thumbnailURL: thumbURL,
            duration: duration,
            viewCount: viewCount,
            publishedAt: publishedAt,
            publishedTimeText: publishedTimeText,
            isLive: false,
            isShort: isShort,
            watchProgress: watchProgress,
            setVideoId: setVideoId,
            badges: []
        )
    }

    private func isPlaylistShort(
        _ renderer: [String: Any], duration: TimeInterval?, thumbnails: [[String: Any]]?
    ) -> Bool {
        // Primary: reelWatchEndpoint in navigationEndpoint
        if let nav = renderer["navigationEndpoint"] as? [String: Any], nav["reelWatchEndpoint"] != nil {
            if duration.map({ $0 <= 180 }) ?? true { return true }
        }
        // Secondary: thumbnailOverlayTimeStatusRenderer.style == "SHORTS"
        let hasShortOverlay =
            (renderer["thumbnailOverlays"] as? [[String: Any]])?.contains {
                ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
            } ?? false
        if hasShortOverlay && (duration.map { $0 <= 180 } ?? true) { return true }
        // Tertiary: ustreamerConfig == "GgIIBQ=="
        let watchEndpoint = (renderer["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]
        if watchEndpoint?["ustreamerConfig"] as? String == "GgIIBQ=="
            && (duration.map { $0 <= 180 } ?? true)
        {
            return true
        }
        // Quaternary: vertical thumbnail (height > width), guarded by duration
        let isVerticalThumbnail =
            thumbnails?.contains {
                let width = ($0["width"] as? Int) ?? 0
                let height = ($0["height"] as? Int) ?? 0
                return height > width && width > 0
            } ?? false
        return isVerticalThumbnail && (duration.map { $0 <= 180 } ?? true)
    }

}
