import Foundation
import os

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Video renderer parsers

extension InnerTubeAPI {

    // MARK: - Testing hooks

    /// Internal accessor so unit tests can exercise the JSON parser without a live network.
    func parseVideoGroupForTesting(_ json: [String: Any], title: String?) throws -> VideoGroup {
        try parseVideoGroup(from: json, title: title)
    }

    /// Internal accessor so unit tests can exercise the multi-shelf home row parser without a live network.
    func parseVideoGroupRowsForTesting(_ json: [String: Any]) -> [VideoGroup] {
        parseVideoGroupRows(from: json)
    }

    // MARK: - Multi-shelf home row parser

    /// Walks the JSON looking for `richShelfRenderer` sections (YouTube home feed).
    /// Each shelf becomes a VideoGroup with layout == .row.
    /// If no shelves are found, falls back to the flat parser.
    func parseVideoGroupRows(from json: [String: Any]) -> [VideoGroup] {
        var rows: [VideoGroup] = []
        var continuationToken: String? = nil

        // Renderer keys that are known ad/promoted slots — skip silently.
        let adRendererKeys: Set<String> = [
            "adSlotRenderer", "adRenderer", "promotedSparklesVideoRenderer",
            "promotedVideoRenderer", "adBreakServiceRenderer",
            "movingThumbnailRenderer",
        ]

        func dumpJSON(_ obj: Any) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                let str = String(data: data, encoding: .utf8)
            else { return "<unserializable>" }
            // Truncate to avoid flooding the log
            return str.count > 2000 ? String(str.prefix(2000)) + "\n...(truncated)" : str
        }

        func walkShelfContents(_ obj: Any, depth: Int = 0) -> [Video] {
            guard depth < 50 else {
                tubeLog.warning("walkShelfContents: depth limit (50) reached — skipping subtree")
                return []
            }
            var videos: [Video] = []
            if let dict = obj as? [String: Any] {
                if let vr = dict["videoRenderer"] as? [String: Any], let v = parseVideoRenderer(vr) {
                    videos.append(v)
                } else if let ri = dict["richItemRenderer"] as? [String: Any],
                    let content = ri["content"] as? [String: Any]
                {
                    if let vr = content["videoRenderer"] as? [String: Any],
                        let v = parseVideoRenderer(vr)
                    {
                        videos.append(v)
                    } else if let reel = content["reelItemRenderer"] as? [String: Any],
                        let v = parseReelItemRenderer(reel)
                    {
                        videos.append(v)
                    } else {
                        let contentKeys = content.keys.sorted()
                        let isAd = contentKeys.contains(where: { adRendererKeys.contains($0) })
                        if isAd {
                            tubeLog.debug(
                                "walkShelfContents: skipping ad richItemRenderer keys=\(contentKeys, privacy: .public)")
                        } else {
                            tubeLog.notice(
                                "walkShelfContents: unrecognised richItemRenderer — add key to adRendererKeys if it is an ad\nkeys=\(contentKeys, privacy: .public)\nJSON=\(dumpJSON(content), privacy: .public)"
                            )
                            for value in content.values { videos += walkShelfContents(value, depth: depth + 1) }
                        }
                    }
                } else {
                    let dictKeys = dict.keys.sorted()
                    let isAd = dictKeys.contains(where: { adRendererKeys.contains($0) })
                    if isAd {
                        tubeLog.debug("walkShelfContents: skipping ad renderer keys=\(dictKeys, privacy: .public)")
                    } else {
                        for value in dict.values { videos += walkShelfContents(value, depth: depth + 1) }
                    }
                }
            } else if let arr = obj as? [Any] {
                for item in arr { videos += walkShelfContents(item, depth: depth + 1) }
            }
            return videos
        }

        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else {
                tubeLog.warning("parseHomeSections: walk depth limit (50) reached — skipping subtree")
                return
            }
            if let dict = obj as? [String: Any] {
                if let shelf = dict["richShelfRenderer"] as? [String: Any] {
                    let title = (shelf["title"] as? [String: Any]).flatMap { extractText($0) }
                    let videos = walkShelfContents(shelf["contents"] as Any)
                    if !videos.isEmpty {
                        rows.append(VideoGroup(title: title, videos: videos, layout: .row))
                    }
                    return
                }
                if let shelf = dict["reelShelfRenderer"] as? [String: Any] {
                    let title = (shelf["title"] as? [String: Any]).flatMap { extractText($0) }
                    let videos = walkShelfContents(shelf["items"] as Any)
                    if !videos.isEmpty {
                        rows.append(VideoGroup(title: title, videos: videos, layout: .row))
                    }
                    return
                }
                if let contItem = dict["continuationItemRenderer"] as? [String: Any],
                    let contEndpoint = contItem["continuationEndpoint"] as? [String: Any],
                    let contCmd = contEndpoint["continuationCommand"] as? [String: Any],
                    let ct = contCmd["token"] as? String
                {
                    continuationToken = ct
                    return
                }
                // Log any richSectionRenderer whose inner content is not a richShelfRenderer
                // (ads and promos often appear as richSectionRenderer wrapping a non-shelf renderer)
                if let section = dict["richSectionRenderer"] as? [String: Any],
                    let content = section["content"] as? [String: Any]
                {
                    let contentKeys = content.keys.sorted()
                    let isAd = contentKeys.contains(where: { adRendererKeys.contains($0) })
                    if isAd {
                        tubeLog.debug(
                            "walk: skipping ad richSectionRenderer content keys=\(contentKeys, privacy: .public)")
                    } else if !contentKeys.contains("richShelfRenderer") {
                        tubeLog.notice(
                            "walk: unrecognised richSectionRenderer — add key to adRendererKeys if it is an ad\nkeys=\(contentKeys, privacy: .public)\nJSON=\(dumpJSON(content), privacy: .public)"
                        )
                        for value in dict.values { walk(value, depth: depth + 1) }
                    } else {
                        for value in dict.values { walk(value, depth: depth + 1) }
                    }
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }

        walk(json)

        if rows.isEmpty {
            // No shelves found — fall back to flat parse
            if let flat = try? parseVideoGroup(from: json, title: BrowseSection.SectionType.home.defaultTitle) {
                return [flat]
            }
        } else if let token = continuationToken {
            // Attach continuation to the last row so BrowseViewModel can paginate
            rows[rows.count - 1].nextPageToken = token
        }

        return rows
    }

    // MARK: - Flat video group parser

    func parseVideoGroup(from json: [String: Any], title: String?) throws -> VideoGroup {
        var videos: [Video] = []
        var nextPageToken: String? = nil
        // Tracks the approximate watched/published date from section group headers.
        // History (and similar sections) use itemSectionRenderer with a header title
        // like "Today", "Yesterday", "This week" that is the closest available date
        // when the tile metadata lines contain no relative date string.
        var currentSectionDate: Date? = nil
        // Diagnostic counters for unknown/skipped renderers — logged at the end.
        var rendererHits: [String: Int] = [:]
        var rendererMisses: [String: Int] = [:]

        // Walk the renderer tree to find videoRenderers and continuationItemRenderers.
        // Handles WEB (videoRenderer, richItemRenderer, compactVideoRenderer),
        // WEB grid (gridVideoRenderer), and TVHTML5 tileRenderer (subs/history/home on TV client).
        // Matches Android MediaServiceCore ItemWrapper renderer dispatch order.
        func walk(_ obj: Any, depth: Int = 0) {
            // Limit recursion depth to guard against unbounded/cyclic structures, while still
            // covering all known YouTube structures: WEB client reaches depth ~6, TVHTML5
            // home/history reach depth ~8, and the real FEsubscriptions response — which wraps
            // every tileRenderer inside an extra tvSecondaryNavRenderer/tvSecondaryNavSectionRenderer
            // "tabs" layer (one tab per subscribed channel) — needs depth 13 to reach tileRenderer.
            // 16 leaves a little headroom above that.
            guard depth < 16 else {
                tubeLog.warning("parseVideoGroup: walk depth limit (16) reached — skipping subtree")
                return
            }
            if let dict = obj as? [String: Any] {
                // TVHTML5 gridRenderer stores its continuation in
                // gridRenderer.continuations[0].nextContinuationData.continuation.
                // Check this independently of the renderer dispatch below so we still
                // recurse into gridRenderer.items to collect the video tiles.
                if let continuations = dict["continuations"] as? [[String: Any]],
                    let token = continuations.first
                        .flatMap({ $0["nextContinuationData"] as? [String: Any] })
                        .flatMap({ $0["continuation"] as? String })
                {
                    nextPageToken = token
                }

                // TVHTML5 top-level browse response wrapper — jump straight to content.
                // tvBrowseRenderer wraps everything inside a deep nav/surface stack
                // (tvSecondaryNavRenderer → tvSecondaryNavSectionRenderer → tabRenderer →
                //  tvSurfaceContentRenderer → sectionListRenderer) that adds ~15 levels of
                // depth before reaching the first tileRenderer. Pass-through each wrapper
                // so we don't burn depth budget on structural-only nodes.
                if let r = dict["tvBrowseRenderer"] as? [String: Any] {
                    walk(r["content"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["tvSecondaryNavRenderer"] as? [String: Any] {
                    walk(r["sections"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["tvSecondaryNavSectionRenderer"] as? [String: Any] {
                    walk(r["tabs"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["tabRenderer"] as? [String: Any] {
                    walk(r["content"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["tvSurfaceContentRenderer"] as? [String: Any] {
                    walk(r["content"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["sectionListRenderer"] as? [String: Any] {
                    // Check for TV-style continuation token here too.
                    if let continuations = r["continuations"] as? [[String: Any]],
                        let token = continuations.first
                            .flatMap({ $0["nextContinuationData"] as? [String: Any] })
                            .flatMap({ $0["continuation"] as? String })
                    {
                        nextPageToken = token
                    }
                    walk(r["contents"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["shelfRenderer"] as? [String: Any] {
                    // Extract shelf-level continuation if present.
                    if let contToken = (r["continuations"] as? [[String: Any]])?.first
                        .flatMap({ $0["nextContinuationData"] as? [String: Any] })
                        .flatMap({ $0["continuation"] as? String })
                    {
                        nextPageToken = contToken
                    }
                    walk(r["content"] as Any, depth: depth + 1)
                    return
                }
                if let r = dict["horizontalListRenderer"] as? [String: Any] {
                    // Extract continuation from horizontalListRenderer.continuations if present.
                    if let contToken = (r["continuations"] as? [[String: Any]])?.first
                        .flatMap({ $0["nextContinuationData"] as? [String: Any] })
                        .flatMap({ $0["continuation"] as? String })
                    {
                        nextPageToken = contToken
                    }
                    walk(r["items"] as Any, depth: depth + 1)
                    return
                }

                // TVHTML5 History groups tiles under itemSectionRenderer with a date
                // header ("Today", "Yesterday", "This week", …). Capture that header
                // and apply it as a fallback publishedAt for tiles with no explicit date.
                if let sectionRenderer = dict["itemSectionRenderer"] as? [String: Any] {
                    let prevDate = currentSectionDate
                    if let header = sectionRenderer["header"] as? [String: Any] {
                        let headerTitle = extractSectionTitle(from: header)
                        currentSectionDate = headerTitle.flatMap { parseSectionDate($0) }
                        tubeLog.debug(
                            "parseVideoGroup: section '\(headerTitle ?? "nil", privacy: .public)' → date=\(currentSectionDate != nil ? "yes" : "nil", privacy: .public)"
                        )
                    }
                    walk(sectionRenderer["contents"] as Any, depth: depth + 1)
                    currentSectionDate = prevDate
                    return
                }

                if let renderer = dict["tileRenderer"] as? [String: Any] {
                    // TVHTML5 client (subs, history, home) — Android ItemWrapper.tileRenderer
                    if var v = parseTileRenderer(renderer) {
                        if v.publishedAt == nil { v.publishedAt = currentSectionDate }
                        videos.append(v)
                        rendererHits["tileRenderer", default: 0] += 1
                    } else {
                        rendererMisses["tileRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["videoRenderer"] as? [String: Any] {
                    if let v = parseVideoRenderer(renderer) {
                        videos.append(v)
                        rendererHits["videoRenderer", default: 0] += 1
                    } else {
                        rendererMisses["videoRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["gridVideoRenderer"] as? [String: Any] {
                    if let v = parseVideoRenderer(renderer) {
                        videos.append(v)
                        rendererHits["gridVideoRenderer", default: 0] += 1
                    } else {
                        rendererMisses["gridVideoRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["reelItemRenderer"] as? [String: Any] {
                    if let v = parseReelItemRenderer(renderer) {
                        videos.append(v)
                        rendererHits["reelItemRenderer", default: 0] += 1
                    } else {
                        rendererMisses["reelItemRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["richItemRenderer"] as? [String: Any],
                    let content = renderer["content"] as? [String: Any]
                {
                    if let videoRenderer = content["videoRenderer"] as? [String: Any] {
                        if let v = parseVideoRenderer(videoRenderer) {
                            videos.append(v)
                            rendererHits["richItem/videoRenderer", default: 0] += 1
                        } else {
                            rendererMisses["richItem/videoRenderer", default: 0] += 1
                        }
                    } else if let reelRenderer = content["reelItemRenderer"] as? [String: Any] {
                        if let v = parseReelItemRenderer(reelRenderer) {
                            videos.append(v)
                            rendererHits["richItem/reelItemRenderer", default: 0] += 1
                        } else {
                            rendererMisses["richItem/reelItemRenderer", default: 0] += 1
                        }
                    } else if let lockup = content["lockupViewModel"] as? [String: Any] {
                        // WEB home v2: richItemRenderer wraps lockupViewModel
                        if let v = parseLockupViewModel(lockup) {
                            videos.append(v)
                            rendererHits["richItem/lockupViewModel", default: 0] += 1
                        } else {
                            rendererMisses["richItem/lockupViewModel", default: 0] += 1
                        }
                    } else if let contItem = content["continuationItemRenderer"] as? [String: Any],
                        let endpoint = contItem["continuationEndpoint"] as? [String: Any],
                        let command = endpoint["continuationCommand"] as? [String: Any],
                        let token = command["token"] as? String
                    {
                        // Continuation token nested inside richItemRenderer
                        nextPageToken = token
                    } else {
                        // Unknown richItemRenderer content type — log keys once, then recurse
                        let unknownKeys = content.keys.sorted().joined(separator: ",")
                        tubeLog.notice(
                            "parseVideoGroup: unknown richItem content keys: [\(unknownKeys, privacy: .public)]")
                        rendererMisses["richItem/unknown", default: 0] += 1
                        for value in content.values { walk(value, depth: depth + 1) }
                    }
                } else if let renderer = dict["compactVideoRenderer"] as? [String: Any] {
                    if let v = parseVideoRenderer(renderer) {
                        videos.append(v)
                        rendererHits["compactVideoRenderer", default: 0] += 1
                    } else {
                        rendererMisses["compactVideoRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["playlistVideoRenderer"] as? [String: Any] {
                    // WEB browse response for VL<playlistId> — playlist video items
                    // BUG-012 fix: use parsePlaylistVideoRenderer instead of parseVideoRenderer
                    // so shortBylineText/shortViewCountText fields are read correctly.
                    if let v = parsePlaylistVideoRenderer(renderer) {
                        videos.append(v)
                        rendererHits["playlistVideoRenderer", default: 0] += 1
                    } else {
                        rendererMisses["playlistVideoRenderer", default: 0] += 1
                    }
                } else if let renderer = dict["lockupViewModel"] as? [String: Any] {
                    // WEB home v2 (LockupItem in Android) — lockupViewModel
                    if let v = parseLockupViewModel(renderer) {
                        videos.append(v)
                        rendererHits["lockupViewModel", default: 0] += 1
                    } else {
                        rendererMisses["lockupViewModel", default: 0] += 1
                    }
                } else if let renderer = dict["shortsLockupViewModel"] as? [String: Any] {
                    // WEB search results — YouTube returns Shorts in shortsLockupViewModel
                    // inside reelShelfRenderer items instead of videoRenderer (2026-05-28).
                    if let v = parseShortsLockupViewModel(renderer) {
                        videos.append(v)
                        rendererHits["shortsLockupViewModel", default: 0] += 1
                    } else {
                        rendererMisses["shortsLockupViewModel", default: 0] += 1
                    }
                } else if let contItem = dict["continuationItemRenderer"] as? [String: Any],
                    let endpoint = contItem["continuationEndpoint"] as? [String: Any],
                    let command = endpoint["continuationCommand"] as? [String: Any],
                    let token = command["token"] as? String
                {
                    nextPageToken = token
                } else {
                    for value in dict.values { walk(value, depth: depth + 1) }
                }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }

        walk(json)
        let shortsCount = videos.filter { $0.isShort }.count
        let hitsDesc = rendererHits.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(
            separator: " ")
        let missDesc = rendererMisses.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(
            separator: " ")
        tubeLog.notice(
            "parseVideoGroup '\(title ?? "nil", privacy: .public)' → \(videos.count, privacy: .public) videos (\(videos.count - shortsCount, privacy: .public) regular, \(shortsCount, privacy: .public) shorts), nextPage=\(nextPageToken != nil ? "yes" : "no", privacy: .public) | hits: \(hitsDesc.isEmpty ? "none" : hitsDesc, privacy: .public) | misses: \(missDesc.isEmpty ? "none" : missDesc, privacy: .public)"
        )
        return VideoGroup(title: title, videos: videos, nextPageToken: nextPageToken)
    }

    // MARK: - Shared members-only detection (#63, originally #227 for parseTileRenderer only)
    //
    // Two of the three signals task #227 implemented for parseTileRenderer are generic
    // InnerTube renderer shapes (`thumbnailOverlayMembershipBadgeRenderer`,
    // `metadataBadgeRenderer`) shared across renderer types, not TV-tile-specific — shared
    // here so parsePlaylistVideoRenderer (used for the same Home/Subscriptions/History
    // feeds, just for videos that arrive in the WEB-shaped renderer instead) can drop
    // members-only videos too, instead of only tileRenderer-shaped ones. The third signal
    // (secondary tileMetadata line text) is TV-tile-specific layout and stays inline in
    // parseTileRenderer since other renderers don't share that structure.
    func isMembersOnlyVideo(overlays: [[String: Any]]?, badges: [[String: Any]]?) -> Bool {
        if overlays?.contains(where: { $0["thumbnailOverlayMembershipBadgeRenderer"] != nil }) == true {
            return true
        }
        if let badges {
            return badges.contains { badge in
                guard let meta = badge["metadataBadgeRenderer"] as? [String: Any] else { return false }
                let iconType = (meta["icon"] as? [String: Any])?["iconType"] as? String ?? ""
                let label = meta["label"] as? String ?? ""
                return iconType.hasPrefix("MEMBERS") || label.lowercased().contains("member")
            }
        }
        return false
    }

    // MARK: – Shorts reelItemRenderer parser
    private func parseReelItemRenderer(_ r: [String: Any]) -> Video? {
        guard let videoId = r["videoId"] as? String else { return nil }
        let title = (r["headline"] as? [String: Any]).flatMap { extractText($0) } ?? ""
        let thumbnails = (r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

        // channelTitle: ownerText or shortBylineText — for collab videos YouTube
        // renders multiple runs ("Inequality Media and Robert Reich"). Take only the
        // first run that has a navigationEndpoint (the primary/uploading channel) so
        // video cards show the uploader name rather than the full collab string (#118).
        let channelTitle: String = {
            let ownerDict = (r["ownerText"] as? [String: Any]) ?? (r["shortBylineText"] as? [String: Any])
            if let runs = ownerDict?["runs"] as? [[String: Any]],
                let first = runs.first(where: { $0["navigationEndpoint"] != nil }),
                let text = first["text"] as? String
            {
                return text
            }
            return ownerDict.flatMap { extractText($0) } ?? ""
        }()

        // channelId: navigationEndpoint.reelWatchEndpoint.channelId (primary)
        // or ownerText/shortBylineText runs[0].navigationEndpoint.browseEndpoint.browseId (fallback)
        let channelId: String? = {
            if let channelId = (r["navigationEndpoint"] as? [String: Any])
                .flatMap({ ($0["reelWatchEndpoint"] as? [String: Any])?["channelId"] as? String })
            {
                return channelId
            }
            let sourceKey = r["ownerText"] != nil ? "ownerText" : "shortBylineText"
            guard let runs = (r[sourceKey] as? [String: Any])?["runs"] as? [[String: Any]],
                let first = runs.first,
                let nav = first["navigationEndpoint"] as? [String: Any],
                let browse = nav["browseEndpoint"] as? [String: Any]
            else { return nil }
            return browse["browseId"] as? String
        }()

        return Video(
            id: videoId, title: title, channelTitle: channelTitle, channelId: channelId,
            thumbnailURL: thumbURL, duration: nil,
            viewCount: {
                // BUG-011 fix: extract viewCount from viewCountText (runs or simpleText).
                let vcText = (r["viewCountText"] as? [String: Any]).flatMap { extractText($0) }
                return vcText.flatMap { extractNumber($0) }
            }(),
            isLive: false, isShort: true, hasPortraitThumbnail: true, badges: []
        )
    }

    // MARK: – WEB videoRenderer parser
    func parseVideoRenderer(_ r: [String: Any]) -> Video? {
        guard let videoId = r["videoId"] as? String else { return nil }
        let title =
            (r["title"] as? [String: Any]).flatMap { extractText($0) }
            ?? (r["headline"] as? [String: Any]).flatMap { extractText($0) }
            ?? ""
        let channelTitle =
            (r["ownerText"] as? [String: Any]).flatMap { extractText($0) }
            ?? (r["shortBylineText"] as? [String: Any]).flatMap { extractText($0) }
            ?? ""

        // channelId: ownerText (videoRenderer) or shortBylineText (gridVideoRenderer)
        let channelId: String? = {
            let sourceKey = r["ownerText"] != nil ? "ownerText" : "shortBylineText"
            guard let runs = (r[sourceKey] as? [String: Any])?["runs"] as? [[String: Any]],
                let first = runs.first,
                let nav = first["navigationEndpoint"] as? [String: Any],
                let browse = nav["browseEndpoint"] as? [String: Any]
            else { return nil }
            return browse["browseId"] as? String
        }()

        let thumbnails = (r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }

        // duration: lengthText (videoRenderer) or thumbnailOverlays[N].thumbnailOverlayTimeStatusRenderer.text (gridVideoRenderer)
        let lengthText: String? =
            (r["lengthText"] as? [String: Any]).flatMap { extractText($0) }
            ?? (r["thumbnailOverlays"] as? [[String: Any]])?
            .compactMap { ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["text"] as? [String: Any] }
            .first.flatMap { extractText($0) }
        let duration = lengthText.flatMap { parseDuration($0) }

        let viewCountText =
            (r["viewCountText"] as? [String: Any]).flatMap { extractText($0) }
            // BUG-014 fix: fall back to shortViewCountText when viewCountText is absent (some locales/auth configs).
            ?? (r["shortViewCountText"] as? [String: Any]).flatMap { extractText($0) }
        let viewCount =
            viewCountText.flatMap { extractNumber($0) }
            // Further fallback: direct integer field (rare, but present in some compact API responses).
            ?? r["viewCount"] as? Int

        let isLive =
            (r["badges"] as? [[String: Any]])?.contains {
                (($0["metadataBadgeRenderer"] as? [String: Any])?["style"] as? String) == "BADGE_STYLE_TYPE_LIVE_NOW"
            } ?? false

        let isShort: Bool = {
            // Primary signal: reelWatchEndpoint in navigationEndpoint (home, search, most feeds)
            // Guard with duration ≤ 180 s: YouTube occasionally attaches reelWatchEndpoint to
            // regular videos (e.g. because they were also published as a Short). The duration
            // guard prevents those from being misclassified as Shorts. When duration is unknown
            // (nil) we trust the endpoint signal alone — Shorts with no parsed duration are
            // still Shorts.
            if let nav = r["navigationEndpoint"] as? [String: Any], nav["reelWatchEndpoint"] != nil {
                if duration.map({ $0 <= 180 }) ?? true { return true }
            }
            // Secondary signal: thumbnailOverlayTimeStatusRenderer.style == "SHORTS"
            // (subscriptions feed often omits reelWatchEndpoint and uses this style instead).
            // Guard with duration ≤ 180 s: regular videos can appear in Shorts-adjacent shelves
            // with this overlay style, causing false positives. Duration validation prevents
            // misclassification of videos like vkUokV3Xwp8. Mirrors the guard in parseTileRenderer.
            let hasShortOverlay =
                (r["thumbnailOverlays"] as? [[String: Any]])?.contains {
                    ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
                } ?? false
            if hasShortOverlay && (duration.map { $0 <= 180 } ?? true) { return true }
            // Tertiary signal: ustreamerConfig == "GgIIBQ==" — mirrors parseTileRenderer.
            // Catches compactVideoRenderer Short tiles in TV subs/history feeds that omit both
            // reelWatchEndpoint and the overlay style.
            let watchEndpoint = (r["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]
            let ustreamerConfig = watchEndpoint?["ustreamerConfig"] as? String
            if ustreamerConfig == "GgIIBQ==" && (duration.map { $0 <= 180 } ?? true) { return true }
            // Quaternary signal: vertical thumbnail (height > width) — another parseTileRenderer mirror.
            // Guard with duration ≤ 180 s: long-form landscape videos sometimes have portrait
            // thumbnails (movie trailers, talk show clips). Without the guard any such video
            // is misclassified as a Short (task #201).
            let thumbnails = (r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let isVerticalThumbnail =
                thumbnails?.contains {
                    let w = ($0["width"] as? Int) ?? 0
                    let h = ($0["height"] as? Int) ?? 0
                    return h > w && w > 0
                } ?? false
            return isVerticalThumbnail && (duration.map { $0 <= 180 } ?? true)
        }()
        if isShort {
            let signal: String
            if let nav = r["navigationEndpoint"] as? [String: Any], nav["reelWatchEndpoint"] != nil {
                signal = "reelWatchEndpoint"
            } else {
                let hasShortOverlay =
                    (r["thumbnailOverlays"] as? [[String: Any]])?.contains {
                        ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
                    } ?? false
                signal = hasShortOverlay ? "overlayStyle" : "ustreamerConfig/verticalThumb"
            }
            tubeLog.debug(
                "videoRenderer isShort=true id=\(videoId, privacy: .public) signal=\(signal, privacy: .public) duration=\(Int(duration ?? -1))"
            )
        }

        let badges =
            (r["badges"] as? [[String: Any]])?.compactMap {
                ($0["metadataBadgeRenderer"] as? [String: Any])?["label"] as? String
            } ?? []

        let watchProgress: Double? = (r["thumbnailOverlays"] as? [[String: Any]])?
            .compactMap {
                ($0["thumbnailOverlayResumePlaybackRenderer"] as? [String: Any])
                    .flatMap { $0["percentDurationWatched"] as? Double }
            }
            .first.map { $0 / 100.0 }

        // Parse feed feedback tokens keyed by icon type from the video's menuRenderer.
        // All three actions share the /feedback endpoint — only the token differs.
        let feedbackTokens: [String: String] = {
            guard let menu = r["menu"] as? [String: Any],
                let mr = menu["menuRenderer"] as? [String: Any],
                let items = mr["items"] as? [[String: Any]]
            else { return [:] }
            var result: [String: String] = [:]
            for item in items {
                guard let svc = item["menuServiceItemRenderer"] as? [String: Any],
                    let endpoint = svc["serviceEndpoint"] as? [String: Any],
                    let token = (endpoint["feedbackEndpoint"] as? [String: Any])?["feedbackToken"] as? String,
                    let iconType = (svc["icon"] as? [String: Any])?["iconType"] as? String
                else { continue }
                result[iconType] = token
            }
            return result
        }()

        let publishedTimeText: String? = (r["publishedTimeText"] as? [String: Any]).flatMap { extractText($0) }
        let publishedAt: Date? = publishedTimeText.flatMap { parseRelativeDate($0) }
        let _ptv = publishedTimeText ?? "nil"
        tubeLog.notice("videoRenderer id=\(videoId, privacy: .public) publishedTimeText='\(_ptv, privacy: .public)'")

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
            isLive: isLive,
            isShort: isShort,
            watchProgress: watchProgress,
            badges: badges,
            notInterestedToken: feedbackTokens["NOT_INTERESTED"],
            dontLikeToken: feedbackTokens["DISLIKE"],
            hideChannelToken: feedbackTokens["BLOCK_CHANNEL"]
        )
    }

    // MARK: - WEB shortsLockupViewModel parser
    // Used by WEB search responses for #shorts queries (and shelf results in general).
    // YouTube returns Shorts in a reelShelfRenderer → items[] → shortsLockupViewModel
    // structure instead of videoRenderer. The videoId, title, thumbnail, and view
    // count are all available without a secondary network request.
    //
    // Field mapping verified against live API response (2026-05-28):
    //   videoId:   onTap.innertubeCommand.reelWatchEndpoint.videoId
    //   title:     overlayMetadata.primaryText.content
    //   viewCount: overlayMetadata.secondaryText.content  (e.g. "3.3K views")
    //   thumbnail: onTap.innertubeCommand.reelWatchEndpoint.thumbnail.thumbnails[-1].url
    //              or thumbnailViewModel.image.sources[-1].url as fallback
    private func parseShortsLockupViewModel(_ r: [String: Any]) -> Video? {
        // videoId — from reelWatchEndpoint inside onTap.innertubeCommand
        guard let onTap = r["onTap"] as? [String: Any],
            let command = onTap["innertubeCommand"] as? [String: Any],
            let reelEp = command["reelWatchEndpoint"] as? [String: Any],
            let videoId = reelEp["videoId"] as? String,
            !videoId.isEmpty
        else { return nil }

        // title — overlayMetadata.primaryText.content
        let title: String = {
            guard let overlay = r["overlayMetadata"] as? [String: Any],
                let primary = overlay["primaryText"] as? [String: Any],
                let content = primary["content"] as? String
            else { return "" }
            return content
        }()

        // viewCount — overlayMetadata.secondaryText.content ("3.3K views", "829K views", etc.)
        let viewCount: Int? = {
            guard let overlay = r["overlayMetadata"] as? [String: Any],
                let secondary = overlay["secondaryText"] as? [String: Any],
                let content = secondary["content"] as? String
            else { return nil }
            return extractNumber(content)
        }()

        // thumbnail — reelWatchEndpoint.thumbnail.thumbnails[-1] preferred; thumbnailViewModel fallback
        let thumbURL: URL? = {
            if let thumbDict = reelEp["thumbnail"] as? [String: Any],
                let thumbs = thumbDict["thumbnails"] as? [[String: Any]],
                let urlStr = thumbs.last?["url"] as? String
            {
                return URL(string: urlStr)
            }
            // Fallback: thumbnailViewModel.image.sources[-1].url
            if let tvm = r["thumbnailViewModel"] as? [String: Any],
                let image = tvm["image"] as? [String: Any],
                let sources = image["sources"] as? [[String: Any]],
                let urlStr = sources.last?["url"] as? String
            {
                return URL(string: urlStr)
            }
            return nil
        }()

        tubeLog.debug(
            "shortsLockupViewModel id=\(videoId, privacy: .public) title=\(title.prefix(40), privacy: .public)")

        return Video(
            id: videoId,
            title: title,
            channelTitle: "",
            channelId: nil,
            thumbnailURL: thumbURL,
            duration: nil,  // not provided; isShort=true is the signal
            viewCount: viewCount,
            publishedAt: nil,
            publishedTimeText: nil,
            isLive: false,
            isShort: true,
            watchProgress: nil,
            badges: []
        )
    }
}
