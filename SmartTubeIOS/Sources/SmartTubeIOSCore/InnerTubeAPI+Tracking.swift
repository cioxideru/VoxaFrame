import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

extension InnerTubeAPI {
    // MARK: - Playback Tracking (Watch History)

    /// Generates a Client Playback Nonce (CPN) — a random 16-character base64url string.
    /// YouTube uses this to attribute a view to an account and record it in watch history.
    /// Must be generated once per playback session and used in every tracking ping.
    public static func generateCPN() -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        let chars = Array(alphabet)
        return String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    /// Fires `videostatsPlaybackUrl` to record the video start in the user's YouTube watch history.
    /// Must be called once when AVPlayerItem becomes `readyToPlay`.
    /// Mirrors Android's `TrackingApi.createWatchRecord` in MediaServiceCore.
    /// - Parameters:
    ///   - videoId: The YouTube video ID being watched.
    ///   - cpn: The Client Playback Nonce for this session (see `generateCPN()`).
    ///   - trackingURLs: Tracking URLs from the player response; the `ei`/`vm`/`of` session
    ///     params are extracted from them. Without those params the ping cannot be credited.
    ///   - lengthSeconds: Total video duration in seconds (`len`).
    ///   - startPosition: Playhead position (seconds) the watch record starts at (`cmt`).
    ///   - final: Marks the video as fully watched (`final=1`).
    public func reportPlaybackStarted(
        videoId: String,
        cpn: String,
        trackingURLs: PlaybackTrackingURLs?,
        lengthSeconds: TimeInterval,
        startPosition: TimeInterval,
        final: Bool = false
    ) async {
        guard let session = Self.trackingSession(from: trackingURLs) else {
            tubeLog.notice(
                "reportPlaybackStarted skipped — no ei/vm/of for \(videoId, privacy: .public) (ping would not be credited)"
            )
            return
        }
        var params: [String: String] = [
            "docid": videoId,
            "len": Self.formatSeconds(lengthSeconds),
            "cmt": Self.formatSeconds(startPosition),
            "cpn": cpn,
        ]
        if final { params["final"] = "1" }
        await pingStatsEndpoint("playback", session: session, params: params)
        tubeLog.notice(
            "reportPlaybackStarted: videoId=\(videoId, privacy: .public) cpn=\(cpn.prefix(4), privacy: .public)… cmt=\(Int(startPosition))s final=\(final, privacy: .public)"
        )
    }

    /// Fires `videostatsWatchtimeUrl` to record a watched interval in the user's YouTube watch history.
    /// Must be preceded by `reportPlaybackStarted` — YouTube ignores standalone watchtime pings.
    /// Mirrors Android's `TrackingApi.updateWatchTime` in MediaServiceCore.
    /// - Parameters:
    ///   - videoId: The YouTube video ID being watched.
    ///   - cpn: The same Client Playback Nonce used in `reportPlaybackStarted`.
    ///   - trackingURLs: Tracking URLs from the player response (source of `ei`/`vm`/`of`).
    ///   - lengthSeconds: Total video duration in seconds (`len`).
    ///   - segmentStart: Playhead position (seconds) when the current play segment began (`st`).
    ///   - segmentEnd: Playhead position (seconds) when the current play segment ended (`et`/`cmt`).
    ///   - final: Marks the video as fully watched (`final=1`).
    public func reportWatchtime(  // Preserve the public API. swiftlint:disable:this function_parameter_count
        videoId: String,
        cpn: String,
        trackingURLs: PlaybackTrackingURLs?,
        lengthSeconds: TimeInterval,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        final: Bool = false
    ) async {
        guard let session = Self.trackingSession(from: trackingURLs) else {
            tubeLog.notice(
                "reportWatchtime skipped — no ei/vm/of for \(videoId, privacy: .public) (ping would not be credited)")
            return
        }
        var params: [String: String] = [
            "docid": videoId,
            "len": Self.formatSeconds(lengthSeconds),
            "st": Self.formatSeconds(segmentStart),
            "et": Self.formatSeconds(segmentEnd),
            "cmt": Self.formatSeconds(segmentEnd),
            "cpn": cpn,
        ]
        if final { params["final"] = "1" }
        await pingStatsEndpoint("watchtime", session: session, params: params)
        tubeLog.notice(
            "reportWatchtime: videoId=\(videoId, privacy: .public) st=\(Int(segmentStart))s et=\(Int(segmentEnd))s final=\(final, privacy: .public)"
        )
    }

    /// Fetches account-bound playback tracking URLs (PLAN-0046).
    ///
    /// The stats server credits a ping to the account only when its `ei`/`vm`/`of` come from an authenticated player
    /// response. Like Android (MediaServiceCore `VideoInfoService.getAuthVideoInfo` with `AppClient.TV_DOWNGRADED`),
    /// a TV client posts `/player` to www.youtube.com with the device-code Bearer token and no API key. The WEB client
    /// rejects the Bearer token with HTTP 400 (iPad log, 2026-11-09), so it is tried only with a SAPISID cookie.
    /// `cpn` is the tracker's playback nonce, which Android also sends in the player request.
    public func fetchAuthenticatedTrackingURLs(videoId: String, cpn: String? = nil) async -> PlaybackTrackingURLs? {
        if authToken != nil {
            let body = buildTVTrackingBody(
                videoId: videoId, cpn: cpn, sts: await fetchSignatureTimestampIfNeeded())
            if let urls = await tvTrackingAttempt(body: body, videoId: videoId) { return urls }
        }
        guard sapisid != nil else { return nil }
        do {
            let body = await buildTrackingURLsBody(videoId: videoId, client: webSafariClientContext)
            let data = try await postWebSafari(body: body)
            return Self.accountTrackingURLs(in: data, source: "web", videoId: videoId)
        } catch {
            tubeLog.error(
                "fetchAuthenticatedTrackingURLs [web] failed for \(videoId, privacy: .public): \(error, privacy: .public)"
            )
            return nil
        }
    }

    /// The TV `/player` request; logs what YouTube answered so a missing `playbackTracking` can be explained.
    private func tvTrackingAttempt(body: [String: Any], videoId: String) async -> PlaybackTrackingURLs? {
        let source = "tv-downgraded"
        do {
            let data = try await postTV(
                endpoint: "player", body: body,
                youTubeHostIdentity: (InnerTubeClients.TVDowngraded.version, InnerTubeClients.TVDowngraded.userAgent))
            let playability = data["playabilityStatus"] as? [String: Any]
            let status = playability?["status"] as? String ?? "none"
            let reason = (playability?["reason"] as? String).map { String($0.prefix(80)) } ?? ""
            let streaming = data["streamingData"] != nil
            let tracking = data["playbackTracking"] != nil
            tubeLog.notice(
                "tracking [\(source, privacy: .public)] \(videoId, privacy: .public): status=\(status, privacy: .public) reason='\(reason, privacy: .public)' streaming=\(streaming, privacy: .public) playbackTracking=\(tracking, privacy: .public)"
            )
            return Self.accountTrackingURLs(in: data, source: source, videoId: videoId)
        } catch {
            tubeLog.error(
                "tracking [\(source, privacy: .public)] failed for \(videoId, privacy: .public): \(error, privacy: .public)"
            )
            return nil
        }
    }

    /// The TV `/player` body Android sends (MediaServiceCore `QueryBuilder`): the client with screen, User-Agent,
    /// region and visitor data, safety mode, the playback nonce and the TV playback capabilities.
    private func buildTVTrackingBody(videoId: String, cpn: String?, sts: Int?) -> [String: Any] {
        var client = (tvClientContext["client"] as? [String: Any]) ?? [:]
        client["clientVersion"] = InnerTubeClients.TVDowngraded.version
        client["clientScreen"] = "WATCH"
        client["userAgent"] = InnerTubeClients.TVDowngraded.userAgent
        client["utcOffsetMinutes"] = TimeZone.current.secondsFromGMT() / 60
        if let vd = visitorData { client["visitorData"] = vd }
        var content: [String: Any] = [
            "html5Preference": "HTML5_PREF_WANTS", "lactMilliseconds": 60_000, "isInlinePlaybackNoAd": true,
        ]
        if let sts { content["signatureTimestamp"] = sts }

        var body = makeBody(client: ["client": client, "user": ["lockedSafetyMode": false]])
        body["videoId"] = videoId
        body["racyCheckOk"] = true
        body["contentCheckOk"] = true
        if let cpn { body["cpn"] = cpn }
        body["playbackContext"] = [
            "contentPlaybackContext": content,
            "devicePlaybackCapabilities": ["supportsVp9Encoding": true, "supportXhr": false],
        ]
        return body
    }

    /// Same as `fetchAuthenticatedTrackingURLs(videoId:)` for a caller that holds the token before
    /// `setAuthToken` has reached the actor (e.g. a prefetch that starts first).
    public func fetchAuthenticatedTrackingURLs(videoId: String, usingToken token: String) async -> PlaybackTrackingURLs?
    {
        if authToken == nil { authToken = token }
        return await fetchAuthenticatedTrackingURLs(videoId: videoId)
    }

    private static func accountTrackingURLs(
        in data: [String: Any], source: String, videoId: String
    ) -> PlaybackTrackingURLs? {
        guard
            let tracking = data["playbackTracking"] as? [String: Any],
            let pbStr = (tracking["videostatsPlaybackUrl"] as? [String: Any])?["baseUrl"] as? String,
            let wtStr = (tracking["videostatsWatchtimeUrl"] as? [String: Any])?["baseUrl"] as? String,
            let pbURL = URL(string: pbStr),
            let wtURL = URL(string: wtStr)
        else {
            tubeLog.notice(
                "fetchAuthenticatedTrackingURLs [\(source, privacy: .public)]: no playbackTracking for \(videoId, privacy: .public)"
            )
            return nil
        }
        let urls = PlaybackTrackingURLs(playbackURL: pbURL, watchtimeURL: wtURL, isAccountBound: true)
        let hasSession = trackingSession(from: urls) != nil
        tubeLog.notice(
            "fetchAuthenticatedTrackingURLs [\(source, privacy: .public)]: account URLs for \(videoId, privacy: .public) session=\(hasSession, privacy: .public)"
        )
        return urls
    }

    /// The `/player` body for a tracking-URLs-only request: the client with visitor data, `contentPlaybackContext`
    /// (with `signatureTimestamp` when known) and the content checks, as in `fetchPlayerInfoAuthenticated`.
    private func buildTrackingURLsBody(videoId: String, client: [String: Any]) async -> [String: Any] {
        var clientFields = (client["client"] as? [String: Any]) ?? [:]
        if let vd = visitorData { clientFields["visitorData"] = vd }
        let sts = await fetchSignatureTimestampIfNeeded()
        var cpbc: [String: Any] = ["html5Preference": "HTML5_PREF_WANTS"]
        if let sts { cpbc["signatureTimestamp"] = sts }

        var body = makeBody(client: ["client": clientFields])
        body["videoId"] = videoId
        body["racyCheckOk"] = true
        body["contentCheckOk"] = true
        body["playbackContext"] = ["contentPlaybackContext": cpbc]
        return body
    }

    // MARK: - Tracking URL helpers

    /// Account-bound session params YouTube mints into the `playbackTracking` URLs.
    /// Without all three the stats server silently drops the ping (Android bails out too).
    struct TrackingSession: Equatable, Sendable {
        let eventId: String
        let visitorMonitoring: String
        let ofParam: String
        let playlistId: String?
    }

    /// Extracts `ei`/`vm`/`of`/`plid` from the watchtime tracking URL.
    /// Mirrors Android's `VideoInfo.parseTrackingParams`.
    static func trackingSession(from urls: PlaybackTrackingURLs?) -> TrackingSession? {
        guard let urls,
            let items = URLComponents(url: urls.watchtimeURL, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let ei = value("ei"), let vm = value("vm"), let of = value("of") else { return nil }
        return TrackingSession(eventId: ei, visitorMonitoring: vm, ofParam: of, playlistId: value("plid"))
    }

    static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    /// Builds and fires a YouTube stats ping, always against `www.youtube.com`.
    ///
    /// The `baseUrl` in `playbackTracking` frequently points at `s.youtube.com`, which is
    /// widely blocked and — more importantly — is not the host Android authenticates against.
    /// Android's OkHttp interceptor only attaches the Bearer token and `X-Goog-Visitor-Id`
    /// to URLs prefixed `https://www.youtube.com/api/stats/`, so rebuilding the URL is what
    /// makes the ping account-attributable in the first place.
    private func pingStatsEndpoint(
        _ endpoint: String,
        session: TrackingSession,
        params: [String: String]
    ) async {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.youtube.com"
        comps.path = "/api/stats/\(endpoint)"
        var items = [
            URLQueryItem(name: "ns", value: "yt"),
            URLQueryItem(name: "ver", value: "2"),
        ]
        items += params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        items += [
            URLQueryItem(name: "ei", value: session.eventId),
            URLQueryItem(name: "vm", value: session.visitorMonitoring),
            URLQueryItem(name: "of", value: session.ofParam),
        ]
        if let plid = session.playlistId {
            items.append(URLQueryItem(name: "plid", value: plid))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            tubeLog.error("pingStatsEndpoint: failed to build URL for \(endpoint, privacy: .public)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(iosUserAgent, forHTTPHeaderField: "User-Agent")
        // Use the same web-session authentication as the tracking-URL request.
        // SAPISIDHASH is required for youtube.com stats endpoints to associate the
        // ping with the signed-in account; Bearer is only the fallback when no web
        // cookie is available.
        if let sid = sapisid {
            request.setValue(Self.sapisidhash(sapisid: sid), forHTTPHeaderField: "Authorization")
        } else if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let vd = visitorData {
            request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        await sendTrackingRequest(request, url: url)
    }

    /// Fires the prepared stats request, logging the response body and retrying once
    /// on transient failures. The stats server answers 200 for both credited and
    /// silently-dropped pings, so the body is the only attribution signal available.
    private func sendTrackingRequest(_ request: URLRequest, url: URL) async {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                tubeLog.warning(
                    "trackingPing: HTTP \(http.statusCode) for \(url.absoluteString.prefix(120), privacy: .public)")
            } else {
                let bodyPreview =
                    String(data: data.prefix(200), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ")
                    ?? "(non-utf8 \(data.count) bytes)"
                tubeLog.notice(
                    "trackingPing: ok — body=\(bodyPreview, privacy: .public) for \(url.absoluteString.prefix(120), privacy: .public)"
                )
            }
        } catch is CancellationError {
            // Task was cancelled (user navigated away) — expected, do not retry.
        } catch {
            tubeLog.warning(
                "trackingPing: transient error (\(error.localizedDescription, privacy: .public)) — retrying once")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    tubeLog.error(
                        "trackingPing: retry HTTP \(http.statusCode) for \(url.absoluteString.prefix(120), privacy: .public)"
                    )
                } else {
                    let bodyPreview =
                        String(data: data.prefix(200), encoding: .utf8)?
                        .replacingOccurrences(of: "\n", with: " ")
                        ?? "(non-utf8 \(data.count) bytes)"
                    tubeLog.notice(
                        "trackingPing: retry ok — body=\(bodyPreview, privacy: .public) for \(url.absoluteString.prefix(120), privacy: .public)"
                    )
                }
            } catch {
                tubeLog.error("trackingPing: retry also failed — \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Test helpers (for AuthenticatedTrackingURLsTests)

    static func statsURLForTesting(
        _ endpoint: String, session: TrackingSession, params: [String: String]
    ) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.youtube.com"
        comps.path = "/api/stats/\(endpoint)"
        var items = [
            URLQueryItem(name: "ns", value: "yt"),
            URLQueryItem(name: "ver", value: "2"),
        ]
        items += params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        items += [
            URLQueryItem(name: "ei", value: session.eventId),
            URLQueryItem(name: "vm", value: session.visitorMonitoring),
            URLQueryItem(name: "of", value: session.ofParam),
        ]
        if let plid = session.playlistId {
            items.append(URLQueryItem(name: "plid", value: plid))
        }
        comps.queryItems = items
        return comps.url
    }
}
