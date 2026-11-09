import Foundation
import os

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Social interaction endpoints (like/dislike, next, comments)

extension InnerTubeAPI {

    // MARK: - Like / Dislike

    /// Sends a like for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.LIKE`.
    public func like(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        try Self.checkRatingResponse(try await postTV(endpoint: "like/like", body: body))
    }

    /// Sends a dislike for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.DISLIKE`.
    public func dislike(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        try Self.checkRatingResponse(try await postTV(endpoint: "like/dislike", body: body))
    }

    /// Removes any existing like or dislike for the given video (requires authentication).
    /// Mirrors Android's `LikeDislikePresenter` → `PostVideoAction.REMOVE_LIKE`.
    public func removeLike(videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["target"] = ["videoId": videoId]
        try Self.checkRatingResponse(try await postTV(endpoint: "like/removelike", body: body))
    }

    /// A rating that YouTube answered with an error did not apply; callers roll back or keep the card.
    private static func checkRatingResponse(_ response: [String: Any]) throws {
        if let error = response["error"] as? [String: Any] {
            throw APIError.unavailable(error["message"] as? String ?? "Could not rate this video.")
        }
    }

    /// Adds a video to the authenticated user's Watch Later playlist (id "WL").
    /// Uses the TVHTML5 client's `browse_edit_playlist` endpoint with ACTION_ADD_VIDEO,
    /// mirroring the Android SmartTube `PlaylistPresenter` → `ACTION_ADD_VIDEO` flow.
    /// Requires authentication.
    ///
    /// Returns the new entry's `setVideoId` when the response carries one
    /// (`playlistEditResults[].playlistEditVideoAddedResultData.setVideoId`), so a video shown
    /// in the Watch Later list before YouTube's index catches up can still be removed (#157).
    @discardableResult
    public func addToWatchLater(videoId: String) async throws -> String? {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = "WL"
        body["actions"] = [["addedVideoId": videoId, "action": "ACTION_ADD_VIDEO"]]
        let response = try await postTV(endpoint: "browse/edit_playlist", body: body)
        let setVideoId = Self.findPlaylistEntryToken(in: response)
        tubeLog.notice(
            "addToWatchLater videoId=\(videoId, privacy: .public) setVideoId=\(setVideoId ?? "nil", privacy: .public)")
        return setVideoId
    }

    /// Removes a video from the authenticated user's Watch Later playlist (id \"WL\").
    ///
    /// Unlike `addToWatchLater` (which only needs the video ID), removal is keyed by
    /// `setVideoId` — the playlist-entry token from that video's `playlistVideoRenderer`
    /// (see `parsePlaylistVideoRenderer` in InnerTubeAPI+VideoRenderers.swift). A playlist
    /// can hold the same video more than once, so InnerTube's `ACTION_REMOVE_VIDEO` removes
    /// a specific *entry*, not "any entry with this video ID" — sending the raw video ID
    /// under a `removedVideoId` key (the previous behavior, #122) is not a field this action
    /// recognizes and the removal silently fails.
    /// Requires authentication.
    public func removeFromWatchLater(setVideoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = "WL"
        body["actions"] = [["setVideoId": setVideoId, "action": "ACTION_REMOVE_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice("removeFromWatchLater setVideoId=\(setVideoId, privacy: .public)")
    }

    /// Adds a video to an arbitrary user playlist (#8). Same mechanics as `addToWatchLater`,
    /// generalized to any `playlistId` from `fetchUserPlaylists()`.
    /// Requires authentication.
    public func addToPlaylist(playlistId: String, videoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = playlistId
        body["actions"] = [["addedVideoId": videoId, "action": "ACTION_ADD_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice("addToPlaylist playlistId=\(playlistId, privacy: .public) videoId=\(videoId, privacy: .public)")
    }

    /// Removes a video from an arbitrary user playlist (#8). Same mechanics as
    /// `removeFromWatchLater` — keyed by `setVideoId`, not the raw video ID (see that
    /// function's doc comment for why).
    /// Requires authentication.
    public func removeFromPlaylist(playlistId: String, setVideoId: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["playlistId"] = playlistId
        body["actions"] = [["setVideoId": setVideoId, "action": "ACTION_REMOVE_VIDEO"]]
        _ = try await postTV(endpoint: "browse/edit_playlist", body: body)
        tubeLog.notice(
            "removeFromPlaylist playlistId=\(playlistId, privacy: .public) setVideoId=\(setVideoId, privacy: .public)"
        )
    }

    /// Why a feedback action did not reach YouTube.
    public enum VideoFeedbackError: Error, Equatable {
        /// Neither the card nor its TV menu panel offered a token for the action, so no request was sent.
        case tokenUnavailable
        /// YouTube answered but did not apply the feedback.
        case rejected
    }

    /// Sends a feed feedback signal to YouTube.
    /// "Not interested", "Hide" and "Don't recommend channel" share this endpoint and differ only in their
    /// `feedbackToken`. Requires authentication.
    public func sendFeedback(token: String) async throws {
        var body = makeBody(client: tvClientContext)
        body["feedbackTokens"] = [token]
        let response = try await postTV(endpoint: "feedback", body: body)
        if response["error"] != nil { throw VideoFeedbackError.rejected }
        // `feedbackResponses` is optional; when present, one of them must report the token as processed.
        if let results = response["feedbackResponses"] as? [[String: Any]], !results.isEmpty,
            !results.contains(where: { $0["isProcessed"] as? Bool == true })
        {
            throw VideoFeedbackError.rejected
        }
        tubeLog.notice("sendFeedback accepted")
    }

    /// Sends a card's feedback command (PLAN-0045).
    ///
    /// Not Interested and Don't Recommend Channel use the card's inline token, else the token its TV menu panel
    /// (`get_panel`) offers. Don't Like This Video exists only where a feed sent its `DISLIKE` token; TV menus have
    /// no such item, and the card menu then hides it.
    ///
    /// Throws `VideoFeedbackError.tokenUnavailable` when there was nothing to send: callers must not hide the video
    /// or block the channel.
    public func sendFeedback(_ action: VideoFeedbackAction, for video: Video) async throws {
        try await sendFeedback(token: try await feedbackToken(action, for: video))
    }

    private func feedbackToken(_ action: VideoFeedbackAction, for video: Video) async throws -> String {
        if let token = Self.inlineFeedbackToken(action, of: video) { return token }
        if action != .dontLike, let panel = video.feedbackPanel {
            let tokens = try await fetchFeedbackTokens(panel: panel)
            if let token = action == .notInterested ? tokens.notInterested : tokens.dontRecommendChannel {
                return token
            }
        }
        tubeLog.warning(
            "sendFeedback: no \(String(describing: action), privacy: .public) token for videoId=\(video.id, privacy: .public) panel=\(video.feedbackPanel != nil, privacy: .public)"
        )
        throw VideoFeedbackError.tokenUnavailable
    }

    private static func inlineFeedbackToken(_ action: VideoFeedbackAction, of video: Video) -> String? {
        switch action {
        case .notInterested: video.notInterestedToken
        case .dontLike: video.dontLikeToken
        case .dontRecommendChannel: video.hideChannelToken
        }
    }

    /// Loads a card's TV menu (`get_panel`, TV client) and returns its feedback tokens.
    /// Mirrors Android's `PanelService.getFeedbackTokens` (MediaServiceCore, 2026-09-20).
    func fetchFeedbackTokens(panel: FeedbackPanel) async throws -> TVMenuFeedbackTokens {
        var body = makeBody(client: tvClientContext)
        body["panelId"] = panel.id
        body["params"] = panel.params
        let response = try await postTV(endpoint: "get_panel", body: body)
        if response["error"] != nil { throw VideoFeedbackError.rejected }
        let section = (response["content"] as? [String: Any])?["engagementPanelSectionListRenderer"] as? [String: Any]
        let list = (section?["content"] as? [String: Any])?["listViewModel"] as? [String: Any]
        let tokens = TVMenuFeedbackTokens(menuItems: list?["listItems"] as? [[String: Any]] ?? [])
        let hasVideo = tokens.notInterested != nil
        let hasChannel = tokens.dontRecommendChannel != nil
        tubeLog.notice(
            "get_panel \(panel.id, privacy: .public): notInterested=\(hasVideo, privacy: .public) channel=\(hasChannel, privacy: .public)"
        )
        return tokens
    }

    // MARK: - Next (related videos / SuggestionsController equivalent)

    /// Fetches related/suggested videos and the current like status for a video.
    /// When authenticated, uses TVHTML5 on youtubei.googleapis.com so the Bearer
    /// token is accepted and the response includes the user's current like state.
    /// Without auth, falls back to the WEB client (like status will be .none).
    /// Mirrors Android's SuggestionsController + LikeDislikePresenter.
    public func fetchNextInfo(videoId: String) async throws -> NextInfo {
        let isAuth = authToken != nil
        var tvBody = makeBody(client: isAuth ? tvClientContext : webClientContext)
        tvBody["videoId"] = videoId

        if isAuth {
            // TV client (/next) returns like status + related but omits
            // engagementPanels (where chapters live). Make a second sequential
            // WEB /next call to extract chapters — no auth needed.
            // (async let cannot be used here: [String:Any] is not Sendable in Swift 6.)
            var webBody = makeBody(client: webClientContext)
            webBody["videoId"] = videoId
            let tvData = try await postTV(endpoint: "next", body: tvBody)
            let webData = try await post(endpoint: "next", body: webBody)
            let videos = parseRelatedVideos(from: webData)  // the TV response has no secondaryResults
            let status = parseLikeStatus(from: tvData)
            let chapters = parseChapters(from: webData)
            tubeLog.notice(
                "fetchNextInfo (auth) → related=\(videos.count, privacy: .public) chapters=\(chapters.count, privacy: .public)"
            )
            return NextInfo(relatedVideos: videos, likeStatus: status, chapters: chapters)
        } else {
            let data = try await post(endpoint: "next", body: tvBody)
            let videos = parseRelatedVideos(from: data)
            let chapters = parseChapters(from: data)
            tubeLog.notice(
                "fetchNextInfo (anon) → related=\(videos.count, privacy: .public) chapters=\(chapters.count, privacy: .public)"
            )
            return NextInfo(relatedVideos: videos, likeStatus: .none, chapters: chapters)
        }
    }

    // MARK: - Comments

    /// Fetches the first page of top-level comments for a video.
    /// Uses the WEB client: calls `/next` with the videoId to extract the
    /// comments continuation token from `engagementPanels`, then fetches comments.
    /// Returns an empty array when comments are disabled or the token is absent.
    public func fetchComments(videoId: String) async throws -> [Comment] {
        var body = makeBody(client: webClientContext)
        body["videoId"] = videoId
        let nextData = try await post(endpoint: "next", body: body)
        guard let token = parseCommentsContinuationToken(from: nextData) else {
            tubeLog.notice("fetchComments: no comments token for videoId=\(videoId, privacy: .public)")
            return []
        }
        let commentsBody = makeBody(client: webClientContext, continuationToken: token)
        let commentsData = try await post(endpoint: "next", body: commentsBody)
        let comments = parseComments(from: commentsData)
        tubeLog.notice(
            "fetchComments videoId=\(videoId, privacy: .public) → \(comments.count, privacy: .public) comments")
        return comments
    }

    // MARK: - Private social parsers

    /// Parses the user's current like/dislike state from a `/next` response.
    ///
    /// Handles two layouts:
    /// - WEB client: `videoPrimaryInfoRenderer.likeStatus` → string "LIKE" / "DISLIKE" / "INDIFFERENT"
    /// - TV/WEB client: `segmentedLikeDislikeButtonRenderer.{like,dislike}Button.toggleButtonRenderer.isToggled`
    private func parseLikeStatus(from json: [String: Any]) -> LikeStatus {
        var found: LikeStatus? = nil
        func walk(_ obj: Any, depth: Int = 0) {
            guard found == nil else { return }
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                // Strategy 1: direct likeStatus string (videoPrimaryInfoRenderer on WEB)
                if let statusStr = dict["likeStatus"] as? String {
                    switch statusStr {
                    case "LIKE": found = .like
                    case "DISLIKE": found = .dislike
                    default: found = LikeStatus.none
                    }
                    return
                }
                // Strategy 2: segmentedLikeDislikeButtonRenderer (WEB + TV clients)
                if let seg = dict["segmentedLikeDislikeButtonRenderer"] as? [String: Any] {
                    let liked =
                        (seg["likeButton"] as? [String: Any])
                        .flatMap { $0["toggleButtonRenderer"] as? [String: Any] }
                        .flatMap { $0["isToggled"] as? Bool } ?? false
                    let disliked =
                        (seg["dislikeButton"] as? [String: Any])
                        .flatMap { $0["toggleButtonRenderer"] as? [String: Any] }
                        .flatMap { $0["isToggled"] as? Bool } ?? false
                    found = liked ? .like : disliked ? .dislike : LikeStatus.none
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        tubeLog.notice("parseLikeStatus → \(String(describing: found ?? .none), privacy: .public)")
        return found ?? .none
    }

    /// Parses related / suggested videos from a WEB `/next` response.
    /// Related videos appear in `secondaryResults` as video `lockupViewModel`s (2026-11) or the older
    /// `compactVideoRenderer`s; playlist and mix lockups are skipped (PLAN-0047).
    func parseRelatedVideos(from json: [String: Any]) -> [Video] {
        var videos: [Video] = []
        var rendererKeysFound: Set<String> = []
        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                // Collect any *Renderer keys for diagnostics
                for k in dict.keys where k.hasSuffix("Renderer") { rendererKeysFound.insert(k) }
                if let r = dict["compactVideoRenderer"] as? [String: Any],
                    let v = parseVideoRenderer(r)
                {
                    videos.append(v)
                } else if let lockup = dict["lockupViewModel"] as? [String: Any] {
                    let contentType = lockup["contentType"] as? String ?? "LOCKUP_CONTENT_TYPE_VIDEO"
                    if contentType == "LOCKUP_CONTENT_TYPE_VIDEO", let video = parseLockupViewModel(lockup) {
                        videos.append(video)
                    }
                } else {
                    for value in dict.values { walk(value, depth: depth + 1) }
                }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        tubeLog.notice(
            "[parseRelatedVideos] found=\(videos.count, privacy: .public) rendererKeys=\(rendererKeysFound.sorted().joined(separator: ","), privacy: .public)"
        )
        return Array(videos.prefix(25))
    }

    /// Parses video chapters from a `/next` response.
    /// Chapters live in `engagementPanels[].engagementPanelSectionListRenderer
    ///   .content.macroMarkersListRenderer.contents[].macroMarkersListItemRenderer`.
    /// Each item carries a `title` text object and either
    ///   - `onTap.watchEndpoint.startTimeSeconds` (Int) — preferred, or
    ///   - `timeDescription` text object — fallback (parsed via `parseDuration`).
    private func parseChapters(from json: [String: Any]) -> [Chapter] {
        var chapters: [Chapter] = []
        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                if let renderer = dict["macroMarkersListItemRenderer"] as? [String: Any] {
                    let title = (renderer["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    // startTimeSeconds arrives as Int, Double, or NSNumber depending on
                    // how JSONSerialization bridges the JSON number — handle all three.
                    let startTime: TimeInterval? = {
                        if let watchEndpoint = (renderer["onTap"] as? [String: Any])
                            .flatMap({ $0["watchEndpoint"] as? [String: Any] })
                        {
                            let raw = watchEndpoint["startTimeSeconds"]
                            if let n = raw as? Int { return TimeInterval(n) }
                            if let n = raw as? Double { return n }
                            if let n = raw as? NSNumber { return n.doubleValue }
                            if let s = raw as? String { return TimeInterval(s) }
                        }
                        // Fallback: parse the visible time description (e.g. "1:23")
                        return (renderer["timeDescription"] as? [String: Any])
                            .flatMap { extractText($0) }
                            .flatMap { parseDuration($0) }
                    }()
                    if let t = startTime {
                        chapters.append(Chapter(title: title, startTime: t))
                    }
                    return
                }
                for value in dict.values { walk(value, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        return chapters.sorted { $0.startTime < $1.startTime }
    }

    /// Finds the comments continuation token inside the `engagementPanels` of a
    /// `/next` response — looks for the panel whose `panelIdentifier` or header title
    /// contains "comment".
    private func parseCommentsContinuationToken(from json: [String: Any]) -> String? {
        guard let panels = json["engagementPanels"] as? [[String: Any]] else { return nil }
        for panel in panels {
            guard let pslr = panel["engagementPanelSectionListRenderer"] as? [String: Any] else { continue }
            let panelId = pslr["panelIdentifier"] as? String ?? ""
            let headerTitle: String = {
                let header = pslr["header"] as? [String: Any]
                let thr = header?["engagementPanelTitleHeaderRenderer"] as? [String: Any]
                return (thr?["title"] as? [String: Any]).flatMap { extractText($0) } ?? ""
            }()
            guard panelId.lowercased().contains("comment") || headerTitle.lowercased().contains("comment") else {
                continue
            }
            var found: String? = nil
            func findToken(_ obj: Any, depth: Int = 0) {
                guard found == nil else { return }
                guard depth < 50 else { return }
                if let dict = obj as? [String: Any] {
                    if let contItem = dict["continuationItemRenderer"] as? [String: Any],
                        let endpoint = contItem["continuationEndpoint"] as? [String: Any],
                        let cmd = endpoint["continuationCommand"] as? [String: Any],
                        let t = cmd["token"] as? String
                    {
                        found = t
                        return
                    }
                    for v in dict.values { findToken(v, depth: depth + 1) }
                } else if let arr = obj as? [Any] {
                    for item in arr { findToken(item, depth: depth + 1) }
                }
            }
            findToken(pslr["content"] as Any)
            if let t = found { return t }
        }
        return nil
    }

    /// Parses `commentRenderer` objects from a comments continuation `/next` response.
    private func parseComments(from json: [String: Any]) -> [Comment] {
        var comments: [Comment] = []

        // New entity-based format (YouTube InnerTube v2):
        // frameworkUpdates.entityBatchUpdate.mutations[].payload.commentEntityPayload
        // The comment list in onResponseReceivedEndpoints now holds only `commentViewModel`
        // key-references; the actual data is in entity mutations.
        if let frameworkUpdates = json["frameworkUpdates"] as? [String: Any],
            let entityBatch = frameworkUpdates["entityBatchUpdate"] as? [String: Any],
            let mutations = entityBatch["mutations"] as? [[String: Any]]
        {
            for mutation in mutations {
                guard let payload = mutation["payload"] as? [String: Any],
                    let cep = payload["commentEntityPayload"] as? [String: Any]
                else { continue }
                let properties = cep["properties"] as? [String: Any]
                let author = cep["author"] as? [String: Any]

                let id = properties?["commentId"] as? String ?? UUID().uuidString
                let authorName = author?["displayName"] as? String ?? ""
                let avatarURL = (author?["avatarThumbnailUrl"] as? String).flatMap { URL(string: $0) }
                let text = (properties?["content"] as? [String: Any])?["content"] as? String ?? ""
                let publishedTime = properties?["publishedTime"] as? String ?? ""
                let toolbarState = properties?["toolbarState"] as? [String: Any]
                let likeCount = toolbarState?["likeCountNotliked"] as? String ?? ""
                let isLiked = (toolbarState?["likeState"] as? String) == "LIKE_STATE_LIKED"
                comments.append(
                    Comment(
                        id: id,
                        author: authorName,
                        authorAvatarURL: avatarURL,
                        text: text,
                        likeCount: likeCount,
                        publishedTime: publishedTime,
                        isLiked: isLiked
                    ))
            }
            if !comments.isEmpty {
                tubeLog.notice("parseComments: entity format → \(comments.count, privacy: .public) comments")
                return comments
            }
        }

        // Legacy format: commentRenderer nested in the response tree.
        func walk(_ obj: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let dict = obj as? [String: Any] {
                if let cr = dict["commentRenderer"] as? [String: Any] {
                    let id = cr["commentId"] as? String ?? UUID().uuidString
                    let author = (cr["authorText"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    let avatarURL = ((cr["authorThumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                        .last.flatMap { $0["url"] as? String }.flatMap { URL(string: $0) }
                    let text = (cr["contentText"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    let likeCount = (cr["voteCount"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    let publishedTime = (cr["publishedTimeText"] as? [String: Any]).flatMap { extractText($0) } ?? ""
                    let isLiked = cr["isLiked"] as? Bool ?? false
                    comments.append(
                        Comment(
                            id: id,
                            author: author,
                            authorAvatarURL: avatarURL,
                            text: text,
                            likeCount: likeCount,
                            publishedTime: publishedTime,
                            isLiked: isLiked
                        ))
                    return
                }
                for v in dict.values { walk(v, depth: depth + 1) }
            } else if let arr = obj as? [Any] {
                for item in arr { walk(item, depth: depth + 1) }
            }
        }
        walk(json)
        if !comments.isEmpty {
            tubeLog.notice(
                "parseComments: legacy commentRenderer format → \(comments.count, privacy: .public) comments")
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice("parseComments: 0 comments — top-level keys: \(topKeys, privacy: .public)")
        }
        return comments
    }

    // MARK: - Private: parseVideoRenderer passthrough
    // Social parsers (parseRelatedVideos) call parseVideoRenderer which lives in
    // InnerTubeAPI+VideoRenderers.swift. Because both files declare extensions on the
    // same actor, Swift resolves the call correctly at compile time.
}
