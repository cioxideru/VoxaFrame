import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

extension InnerTubeAPI {
    // MARK: – TVHTML5 tileRenderer parser (Android TileItem methodology)
    // Mirrors: TileItem.getVideoId(), getTitle(), getThumbnails(), getBadgeText(), getChannelId()
    func parseTileRenderer(_ tile: [String: Any]) -> Video? {
        // Only parse video tiles — require the content type to be explicitly set.
        // Tiles with nil or non-video contentType (e.g. ads with customData/onFirstVisibleCommand)
        // are silently dropped. Android: TILE_CONTENT_TYPE_VIDEO
        // Also accept TILE_CONTENT_TYPE_REEL: FEshorts TVHTML5 response uses this type for
        // Short videos. Silently dropping all REEL tiles is why the Shorts row shows 0 results
        // from the dedicated FEshorts browse (only subs tiles, which are TILE_CONTENT_TYPE_VIDEO,
        // survive). Log unrecognised types so future renderer changes can be diagnosed.
        let contentType = tile["contentType"] as? String
        switch contentType {
        case "TILE_CONTENT_TYPE_VIDEO", "TILE_CONTENT_TYPE_REEL":
            break  // accepted
        default:
            if let ct = contentType {
                tubeLog.notice("parseTileRenderer: dropping tile contentType=\(ct, privacy: .public)")
            }
            return nil
        }

        // Newer TVHTML5 history/subs responses sometimes nest it under innertubeCommand, or use
        // navigationEndpoint instead of onSelectCommand — try all three paths so regular history
        // videos are not silently dropped (leaving only reelItemRenderer Shorts visible).
        let onSelectCommand = tile["onSelectCommand"] as? [String: Any]
        let navigationEndpoint = tile["navigationEndpoint"] as? [String: Any]
        // videoId resolution order (most to least common in TVHTML5 history/subs responses):
        // 1. onSelectCommand.watchEndpoint.videoId              — classic path
        // 2. onSelectCommand.reelWatchEndpoint.videoId          — Shorts in TV subs/history feed
        // 3. onSelectCommand.innertubeCommand.watchEndpoint.videoId — newer TV variant
        // 4. onSelectCommand.innertubeCommand.reelWatchEndpoint.videoId — nested Shorts variant
        // 5. navigationEndpoint.watchEndpoint.videoId           — another TV variant
        // 6. navigationEndpoint.reelWatchEndpoint.videoId       — nav-level Shorts variant
        // 7. tile.contentId                                     — confirmed by live log: TVHTML5
        //    history tiles with commandExecutorCommand store the id directly here
        let reelWatchEndpoint = tileReelEndpoint(
            onSelectCommand: onSelectCommand, navigationEndpoint: navigationEndpoint)
        let watchEndpoint = tileWatchEndpoint(onSelectCommand: onSelectCommand, navigationEndpoint: navigationEndpoint)
        guard
            let videoId = reelWatchEndpoint?["videoId"] as? String
                ?? watchEndpoint?["videoId"] as? String
                ?? (tile["contentId"] as? String)
        else {
            return nil
        }

        // #157: the playlist-entry token InnerTube uses to identify *this occurrence* of the
        // video within a playlist (distinct from the video ID itself — a playlist can hold the
        // same video more than once). WEB's playlistVideoRenderer exposes it as a top-level
        // `setVideoId` (see parsePlaylistVideoRenderer below); the TV client's tileRenderer only
        // has it nested inside the watch endpoint as `playlistSetVideoId`. Without this, removal
        // from an authenticated playlist fetch (e.g. the Home page's Watch Later section, which
        // goes through the TV client) always fails with "Missing playlist entry information",
        // since VideoCardView's remove action requires `Video.setVideoId`.
        // The exact location in TV responses is unverified against live data, so after the
        // watch endpoint, fall back to a bounded search of the whole tile — e.g. a "Remove
        // from Watch later" menu item's playlistEditEndpoint action carries `setVideoId`.
        let setVideoId =
            watchEndpoint?["playlistSetVideoId"] as? String
            ?? reelWatchEndpoint?["playlistSetVideoId"] as? String
            ?? Self.findPlaylistEntryToken(in: tile)

        // title: metadata.tileMetadataRenderer.title — Android: TileItem.getTitle()
        let tileMetadata = (tile["metadata"] as? [String: Any])?["tileMetadataRenderer"] as? [String: Any]
        let title = (tileMetadata?["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""

        // channelTitle: first line of tileMetadataRenderer.lines[0].lineRenderer.items[0].lineItemRenderer.text
        // Android TileItem.getUserName() = null, but we attempt best-effort extraction from lines
        let channelTitle = tileChannelTitle(tileMetadata)

        // channelId: watchEndpoint.channelId (primary) or onSelectCommand.browseEndpoint.browseId (secondary)
        // Fallback: extract @handle from onLongPressCommand.showMenuCommand.subtitle.simpleText
        // TV client subtitle format: "ChannelName • @handle" — YouTube browse API accepts @handle as browseId.
        let channelId = tileChannelID(tile, watchEndpoint: watchEndpoint, onSelectCommand: onSelectCommand)

        // thumbnail: header.tileHeaderRenderer.thumbnail.thumbnails — Android: TileItem.getThumbnails()
        let tileHeader = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any]
        let thumbnails = (tileHeader?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

        // duration: header.tileHeaderRenderer.thumbnailOverlays[].thumbnailOverlayTimeStatusRenderer.text
        // Android: TileItem.getBadgeText()
        let overlays = tileHeader?["thumbnailOverlays"] as? [[String: Any]]
        let lengthText = overlays?.compactMap {
            ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any]).flatMap {
                ($0["text"] as? [String: Any]).flatMap { extractText($0) }
            }
        }.first
        let duration = lengthText.flatMap { parseDuration($0) }

        // percentWatched: thumbnailOverlays[].thumbnailOverlayResumePlaybackRenderer.percentDurationWatched
        // (same path as WEB, used for watch-again resume)
        let watchProgress: Double? = overlays?.compactMap {
            ($0["thumbnailOverlayResumePlaybackRenderer"] as? [String: Any])
                .flatMap { $0["percentDurationWatched"] as? Double }
        }.first.map { $0 / 100.0 }

        // isLive: thumbnailOverlay style == "LIVE" — Android: TileItem.isLive()
        let isLive =
            overlays?.contains {
                ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "LIVE"
            } ?? false

        // isShorts: style == "TILE_STYLE_YTLR_SHORTS" — Android: TileItem.isShorts()
        // Secondary signals (in priority order):
        //  • reelWatchEndpoint present on onSelectCommand/navigationEndpoint — definitive for Shorts
        //    tiles that carry neither TILE_STYLE_YTLR_SHORTS nor the overlay SHORTS style.
        //  • thumbnailOverlayTimeStatusRenderer.style == "SHORTS" — older TV subs feed fallback.
        //  • ustreamerConfig == "GgIIBQ==" — encodes proto(field3{field1:5}); value 5 is YouTube's
        //    CONTENT_TYPE_SHORTS hint embedded in the watchEndpoint. Observed on Shorts tiles that
        //    carry none of the other signals (TILE_STYLE_YTLR_DEFAULT, watchEndpoint not reel,
        //    landscape thumbnail). Regular videos carry value 1 ("GgIIAQ==") or omit the field.
        //  • Portrait thumbnail (height > width) — Shorts have 9:16 thumbnails; news/sports clips
        //    are always landscape 16:9, so this signal has zero false-positive risk for those.
        let shortMetadata = TileShortMetadata(overlays: overlays, thumbnails: thumbnails, duration: duration)
        let isShort = tileShortStatus(
            tile, metadata: shortMetadata, watchEndpoint: watchEndpoint, reelWatchEndpoint: reelWatchEndpoint,
            videoId: videoId)

        // publishedAt: best-effort from tileMetadata lines (second line may contain "2 years ago")
        var publishedTimeText: String?
        var isUpcoming: Bool = false
        let publishedAt = tilePublishedDate(
            tileMetadata, videoId: videoId, publishedTimeText: &publishedTimeText, isUpcoming: &isUpcoming)

        // Members-only: drop tiles for membership-gated content before they enter the feed.
        // YouTube surfaces these in home/subs/history but they are unplayable without a channel
        // membership. Three detection signals are checked in priority order:
        //  1. thumbnailOverlayMembershipBadgeRenderer present in tileHeader.thumbnailOverlays
        //  2. metadataBadgeRenderer with MEMBERS_ONLY icon or "member" label in tileMetadata.badges
        //  3. "Members only" text in any secondary tileMetadata line item (locale-aware fallback)
        // Signal 3 is a text fallback for locales that translate the badge label.
        let isMembersOnly = isMembersOnlyTile(tileMetadata, overlays: overlays)
        if isMembersOnly {
            tubeLog.notice("parseTileRenderer: dropping members-only tile id=\(videoId, privacy: .public)")
            return nil
        }

        return Video(
            id: videoId,
            title: title,
            channelTitle: channelTitle,
            channelId: channelId,
            thumbnailURL: thumbURL,
            duration: duration,
            viewCount: tileViewCount(tileMetadata),
            publishedAt: publishedAt,
            publishedTimeText: publishedTimeText,
            isLive: isLive,
            isUpcoming: isUpcoming,
            isShort: isShort,
            watchProgress: watchProgress,
            setVideoId: setVideoId,
            badges: []
        )
    }

    /// Depth-limited search for a playlist-entry token (`playlistSetVideoId` or `setVideoId`)
    /// anywhere in a renderer dictionary. Both keys only ever identify a playlist entry, so the
    /// first string value found is the entry this renderer represents.
    static func findPlaylistEntryToken(in value: Any, depth: Int = 0) -> String? {
        guard depth < 12 else { return nil }
        if let dict = value as? [String: Any] {
            for key in ["playlistSetVideoId", "setVideoId"] {
                if let token = dict[key] as? String, !token.isEmpty { return token }
            }
            for child in dict.values {
                if let token = findPlaylistEntryToken(in: child, depth: depth + 1) { return token }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let token = findPlaylistEntryToken(in: child, depth: depth + 1) { return token }
            }
        }
        return nil
    }

    // MARK: – WEB lockupViewModel parser (Android LockupItem methodology)
    // Mirrors: LockupItem.getVideoId(), getTitle(), getThumbnails() in CommonHelper.kt
    func parseLockupViewModel(_ lockup: [String: Any]) -> Video? {
        // videoId: rendererContext.commandContext.onTap.innertubeCommand.{watchEndpoint|reelWatchEndpoint}.videoId
        // Shorts use reelWatchEndpoint; regular videos use watchEndpoint.
        guard let rendererContext = lockup["rendererContext"] as? [String: Any],
            let commandContext = rendererContext["commandContext"] as? [String: Any],
            let onTap = commandContext["onTap"] as? [String: Any],
            let innertubeCommand = onTap["innertubeCommand"] as? [String: Any]
        else { return nil }

        let reelEndpoint = innertubeCommand["reelWatchEndpoint"] as? [String: Any]
        let watchEndpoint = innertubeCommand["watchEndpoint"] as? [String: Any]
        guard
            let videoId = reelEndpoint?["videoId"] as? String
                ?? watchEndpoint?["videoId"] as? String
        else { return nil }

        // title: metadata.lockupMetadataViewModel.title
        // The field may be a TextViewModel ({"content": "…"}) in newer API responses,
        // or a legacy runs/simpleText dict handled by extractText.
        let lockupMeta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        let title: String = {
            guard let titleDict = lockupMeta?["title"] as? [String: Any] else { return "" }
            return titleDict["content"] as? String ?? extractText(titleDict) ?? ""
        }()

        // channelTitle + channelId: metadata.lockupMetadataViewModel.metadata.contentMetadataViewModel.metadataRows
        // The first row typically contains the channel name with a browseEndpoint for the channel.
        let metaContentVM = (lockupMeta?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any]
        let metaRows = metaContentVM?["metadataRows"] as? [[String: Any]] ?? []

        // Row 0 is the channel name, unless it is the only row and holds the stats instead
        // ("2.8M views • 1 day ago" on channel pages and single-creator playlists).
        let firstRowIsChannel: Bool = {
            guard metaRows.count == 1, let parts = metaRows[0]["metadataParts"] as? [[String: Any]] else {
                return true
            }
            return !parts.contains { part in
                guard let text = part["text"] as? [String: Any],
                    let str = text["content"] as? String ?? extractText(text)
                else { return false }
                return str.contains("view") || str.contains("watching") || parseRelativeDate(str) != nil
            }
        }()
        let statsRows = firstRowIsChannel ? Array(metaRows.dropFirst()) : metaRows

        let channelTitle: String = {
            guard firstRowIsChannel, let firstRow = metaRows.first,
                let parts = firstRow["metadataParts"] as? [[String: Any]],
                let firstPart = parts.first,
                let text = firstPart["text"] as? [String: Any]
            else { return "" }
            return text["content"] as? String ?? extractText(text) ?? ""
        }()

        // channelId: watchEndpoint.channelId (primary) or reelWatchEndpoint.channelId or
        // lockupMetadataViewModel.metadata.contentMetadataViewModel.metadataRows[].metadataParts[]
        //   .text.commandRuns[].onTap.innertubeCommand.browseEndpoint.browseId (fallback)
        let channelId: String? =
            (watchEndpoint?["channelId"] as? String)
            ?? (reelEndpoint?["channelId"] as? String)
            ?? lockupChannelID(metaRows)

        // thumbnail: contentImage.thumbnailViewModel.image.thumbnails
        let thumbVM = (lockup["contentImage"] as? [String: Any])?["thumbnailViewModel"] as? [String: Any]
        let thumbnails = (thumbVM?["image"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

        // isShort: only one signal currently (reelWatchEndpoint) — unlike parseVideoRenderer's
        // four signals. GitHub #41 ("Hide Shorts" still leaking through in Home/Subscriptions,
        // confirmed on 4.7) is suspected to be Shorts arriving here via a regular watchEndpoint
        // instead of reelWatchEndpoint, the same gap task #201/BUG-014 fixed for
        // parseVideoRenderer — but parseVideoRenderer's extra signals (overlay style,
        // ustreamerConfig, vertical thumbnail) all need a duration guard to avoid
        // misclassifying landscape videos with portrait thumbnails (task #201), and
        // lockupViewModel never exposes a parsed duration. Rather than ship an unguarded
        // (and therefore riskier) heuristic without a live sample to verify against, log
        // the cases that fall through so the next real occurrence gives a concrete renderer
        // shape to fix precisely.
        let isShort = reelEndpoint != nil
        if isShort {
            tubeLog.debug("lockupViewModel isShort=true id=\(videoId, privacy: .public) signal=reelWatchEndpoint")
        } else {
            // Only log the suspicious case (portrait thumbnail but not flagged as a
            // Short) rather than every regular video — keeps this from flooding the
            // log while still catching #41's likely failure mode.
            let isVerticalThumbnail =
                thumbnails?.contains {
                    let width = ($0["width"] as? Int) ?? 0
                    let height = ($0["height"] as? Int) ?? 0
                    return height > width && width > 0
                } ?? false
            if isVerticalThumbnail {
                tubeLog.notice(
                    "lockupViewModel isShort=false but has portrait thumbnail (#41 diagnostic) id=\(videoId, privacy: .public) thumbDims=\(thumbnails?.map { "\($0["width"] ?? 0)x\($0["height"] ?? 0)" }.joined(separator: ",") ?? "nil", privacy: .public)"
                )
            }
        }

        let publishedAt = lockupPublishedDate(statsRows)

        return Video(
            id: videoId, title: title, channelTitle: channelTitle, channelId: channelId,
            thumbnailURL: thumbURL, duration: nil,
            viewCount: lockupViewCount(statsRows),
            publishedAt: publishedAt,
            isLive: false, isShort: isShort, badges: []
        )
    }

    private func tileReelEndpoint(onSelectCommand: [String: Any]?, navigationEndpoint: [String: Any]?) -> [String: Any]?
    {
        if let ep = onSelectCommand?["reelWatchEndpoint"] as? [String: Any] { return ep }
        if let inner = onSelectCommand?["innertubeCommand"] as? [String: Any],
            let ep = inner["reelWatchEndpoint"] as? [String: Any]
        {
            return ep
        }
        if let ep = navigationEndpoint?["reelWatchEndpoint"] as? [String: Any] { return ep }
        if let inner = navigationEndpoint?["innertubeCommand"] as? [String: Any],
            let ep = inner["reelWatchEndpoint"] as? [String: Any]
        {
            return ep
        }
        return nil
    }

    private func tileWatchEndpoint(
        onSelectCommand: [String: Any]?, navigationEndpoint: [String: Any]?
    ) -> [String: Any]? {
        if let ep = onSelectCommand?["watchEndpoint"] as? [String: Any] { return ep }
        if let inner = onSelectCommand?["innertubeCommand"] as? [String: Any],
            let ep = inner["watchEndpoint"] as? [String: Any]
        {
            return ep
        }
        if let ep = navigationEndpoint?["watchEndpoint"] as? [String: Any] { return ep }
        return nil
    }

    private func tileChannelTitle(_ tileMetadata: [String: Any]?) -> String {
        guard let lines = tileMetadata?["lines"] as? [[String: Any]],
            let firstLine = lines.first,
            let lineRenderer = firstLine["lineRenderer"] as? [String: Any],
            let items = lineRenderer["items"] as? [[String: Any]],
            let firstItem = items.first,
            let lineItemRenderer = firstItem["lineItemRenderer"] as? [String: Any],
            let text = lineItemRenderer["text"] as? [String: Any]
        else { return "" }
        return extractText(text) ?? ""
    }

    private func tilePublishedDate(
        _ tileMetadata: [String: Any]?, videoId: String, publishedTimeText: inout String?, isUpcoming: inout Bool
    ) -> Date? {
        guard let lines = tileMetadata?["lines"] as? [[String: Any]], lines.count > 1 else { return nil }
        for line in lines.dropFirst() {
            guard let items = (line["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let text = (item["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any],
                    let str = extractText(text)
                else { continue }
                if let date = parseRelativeDate(str) {
                    publishedTimeText = str
                    tubeLog.notice(
                        "tileRenderer id=\(videoId, privacy: .public) publishedTimeText='\(str, privacy: .public)'")
                    return date
                }
                // Upcoming/scheduled: "Scheduled for 5/27/26, 4:00 PM"
                if let date = parseScheduledDate(str) {
                    publishedTimeText = str
                    isUpcoming = true
                    return date
                }
            }
        }
        tubeLog.notice(
            "tileRenderer id=\(videoId, privacy: .public) publishedTimeText=nil (no date in tileMetadata)")
        return nil
    }

    private func isMembersOnlyTile(_ tileMetadata: [String: Any]?, overlays: [[String: Any]]?) -> Bool {
        if isMembersOnlyVideo(overlays: overlays, badges: tileMetadata?["badges"] as? [[String: Any]]) {
            return true
        }
        // Signal 3: secondary metadata line text (badge text shown next to channel name/date)
        if let lines = tileMetadata?["lines"] as? [[String: Any]], lines.count > 1 {
            for line in lines.dropFirst() {
                guard let items = (line["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] else {
                    continue
                }
                for item in items {
                    guard let text = (item["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any],
                        let str = extractText(text)
                    else { continue }
                    if str.lowercased().contains("members only") { return true }
                }
            }
        }
        return false
    }

    private func lockupPublishedDate(_ statsRows: [[String: Any]]) -> Date? {
        for row in statsRows {
            guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
            for part in parts {
                guard let text = part["text"] as? [String: Any],
                    let str = text["content"] as? String ?? extractText(text)
                else { continue }
                if let date = parseRelativeDate(str) { return date }
            }
        }
        return nil
    }

    private func lockupChannelID(_ metaRows: [[String: Any]]) -> String? {
        for row in metaRows {
            guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
            for part in parts {
                guard let text = part["text"] as? [String: Any],
                    let commandRuns = text["commandRuns"] as? [[String: Any]]
                else { continue }
                for run in commandRuns {
                    guard let cmd = (run["onTap"] as? [String: Any])?["innertubeCommand"] as? [String: Any],
                        let browseId = (cmd["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                        browseId.hasPrefix("UC")
                    else { continue }
                    return browseId
                }
            }
        }
        return nil
    }

    private func lockupViewCount(_ statsRows: [[String: Any]]) -> Int? {
        // BUG-011 fix: extract viewCount from contentMetadataViewModel metadataRows.
        // Row index 1 (second row) often contains "N views" or compact count.
        for row in statsRows {
            guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
            for part in parts {
                guard let text = part["text"] as? [String: Any],
                    let str = text["content"] as? String ?? extractText(text)
                else { continue }
                if let count = extractNumber(str) { return count }
            }
        }
        return nil
    }

    private func tileChannelID(
        _ tile: [String: Any], watchEndpoint: [String: Any]?, onSelectCommand: [String: Any]?
    ) -> String? {
        if let id = watchEndpoint?["channelId"] as? String { return id }
        if let id = (onSelectCommand?["browseEndpoint"] as? [String: Any])?["browseId"] as? String { return id }
        guard let showMenu = (tile["onLongPressCommand"] as? [String: Any])?["showMenuCommand"] as? [String: Any],
            let subtitleText = (showMenu["subtitle"] as? [String: Any])?["simpleText"] as? String,
            let atIndex = subtitleText.firstIndex(of: "@")
        else { return nil }
        let handle = subtitleText[atIndex...]
            .components(separatedBy: .whitespacesAndNewlines)
            .first
            .map { String($0) }
        return handle
    }

    private struct TileShortMetadata {
        let overlays: [[String: Any]]?
        let thumbnails: [[String: Any]]?
        let duration: TimeInterval?
    }

    private func tileShortStatus(
        _ tile: [String: Any], metadata: TileShortMetadata, watchEndpoint: [String: Any]?,
        reelWatchEndpoint: [String: Any]?, videoId: String
    ) -> Bool {
        let overlays = metadata.overlays
        let thumbnails = metadata.thumbnails
        let duration = metadata.duration
        let isVerticalThumbnail =
            thumbnails?.contains {
                let width = ($0["width"] as? Int) ?? 0
                let height = ($0["height"] as? Int) ?? 0
                return height > width && width > 0
            } ?? false

        let ustreamerConfig = watchEndpoint?["ustreamerConfig"] as? String
        // GgIIBQ== encodes CONTENT_TYPE_SHORTS, but YouTube also attaches it to long-form
        // videos that appear in Shorts-adjacent shelves (subscription Shorts shelf, history,
        // home recommendations). Guard with a 180 s ceiling — the maximum YouTube Shorts
        // length — so only genuine Shorts are matched. When duration is unknown (nil),
        // default to trusting the signal.
        let isUstreamerShorts = ustreamerConfig == "GgIIBQ==" && (duration.map { $0 <= 180 } ?? true)

        let isShort =
            (tile["style"] as? String) == "TILE_STYLE_YTLR_SHORTS"
            || reelWatchEndpoint != nil
            || overlays?.contains {
                ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
            } ?? false
            || isUstreamerShorts
            || (isVerticalThumbnail && (duration.map { $0 <= 180 } ?? true))

        if isUstreamerShorts {
            tubeLog.debug(
                "tileRenderer isShort=true id=\(videoId, privacy: .public) signal=ustreamerConfig(\(ustreamerConfig ?? "", privacy: .public))"
            )
        }

        // Diagnostic: log every TV-feed tile's Short signals so Console shows exactly
        // which signals are (or aren't) present, even for non-Short tiles.
        let overlayStyle =
            overlays?.compactMap {
                ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String
            }.first ?? "nil"
        let durationStr = duration.map { Int($0).description } ?? "nil"
        tubeLog.debug(
            "tileRenderer id=\(videoId, privacy: .public) tileStyle=\(tile["style"] as? String ?? "nil", privacy: .public) reelEp=\(reelWatchEndpoint != nil, privacy: .public) overlayStyle=\(overlayStyle, privacy: .public) dur=\(durationStr, privacy: .public) vertThumb=\(isVerticalThumbnail, privacy: .public) ustreamerShorts=\(isUstreamerShorts, privacy: .public) → isShort=\(isShort, privacy: .public)"
        )

        return isShort
    }

    private func tileViewCount(_ tileMetadata: [String: Any]?) -> Int? {
        // BUG-011 fix: extract viewCount from tileMetadata lines instead of hardcoding nil.
        // The second line (index 1) typically contains "N views" or compact "1.2K views".
        guard let lines = tileMetadata?["lines"] as? [[String: Any]] else { return nil }
        for line in lines.dropFirst() {
            guard let items = (line["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let text = (item["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any],
                    let str = extractText(text)
                else { continue }
                if let count = extractNumber(str) { return count }
            }
        }
        return nil
    }

}
