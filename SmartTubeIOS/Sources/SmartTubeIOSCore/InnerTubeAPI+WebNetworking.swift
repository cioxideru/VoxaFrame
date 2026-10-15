import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

extension InnerTubeAPI {
    /// WEB_CREATOR (YouTube Studio) player request.
    /// Per yt-dlp documentation, this client is exempt from rqh=1 CDN enforcement —
    /// adaptive stream URLs returned do NOT require a pot= proof-of-origin token.
    /// Uses nameID=62 so YouTube identifies the request as the Studio creator client.
    ///
    /// Endpoint: www.youtube.com (same as MWEB/WebSafari — WEB_CREATOR is a web client).
    /// Auth: SAPISIDHASH when available (computed from the SAPISID cookie obtained via
    ///   the OAuthLogin/MergeSession flow after TV device sign-in).
    ///   • googleapis.com + Bearer → HTTP 400 INVALID_ARGUMENT (WEB_CREATOR not supported there)
    ///   • www.youtube.com + Bearer → HTTP 400 (expects SAPISID, not OAuth2 Bearer)
    ///   • www.youtube.com + SAPISIDHASH → 200 with rqh=0 adaptive streams ✓
    ///   • www.youtube.com + no auth → 200 + LOGIN_REQUIRED (no streamingData)
    func postWebCreator(body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        // Chrome desktop UA — WEB_CREATOR is identified as a studio/web client.
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36,gzip(gfe)",
            forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.WebCreator.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.WebCreator.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        // SAPISIDHASH auth: `Authorization: SAPISIDHASH {timestamp}_{sha1("{ts} {SAPISID} {origin}")}`
        // This is the yt-dlp web-client auth scheme — the only scheme www.youtube.com accepts
        // for web client nameIDs. Falls through to unauthenticated (LOGIN_REQUIRED) when absent.
        if let sid = sapisid {
            request.setValue(InnerTubeAPI.sapisidhash(sapisid: sid), forHTTPHeaderField: "Authorization")
            request.setValue("1", forHTTPHeaderField: "X-Origin")
        } else if let token = authToken {
            // Fallback: Bearer token + X-Goog-AuthUser header — the auth scheme yt-dlp uses
            // when it has an OAuth token but no browser-cookie SAPISID.
            // www.youtube.com accepts Bearer on web clients when X-Goog-AuthUser is present.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }
        let authStatus: String
        if sapisid != nil {
            authStatus = "SAPISIDHASH"
        } else if authToken != nil {
            authStatus = "Bearer+AuthUser"
        } else {
            authStatus = "unauthenticated"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice(
            "POST /player [WebCreator] videoId=\(videoId, privacy: .public) auth=\(authStatus, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var errSummary = ""
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let err = jsonResponse["error"] as? [String: Any]
            {
                let code = err["code"] ?? ""
                let msg = (err["message"] as? String ?? "").prefix(120)
                let status = err["status"] ?? ""
                errSummary = "code=\(code) status=\(status) msg=\(msg)"
            } else {
                errSummary = String(data: data.prefix(120), encoding: .utf8) ?? "(non-utf8)"
            }
            tubeLog.error(
                "❌ HTTP \(statusCode, privacy: .public) for /player [WebCreator] err=\(errSummary, privacy: .public)")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [WebCreator]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [WebCreator]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player [WebCreator] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// WEB_EMBEDDED_PLAYER (nameID=56) player request on www.youtube.com.
    /// Replaced the deprecated TVHTML5_SIMPLY_EMBEDDED_PLAYER (nameID=85) which YouTube
    /// blocked in 2026. Uses client headers matching nameID=56 / version from InnerTubeClients.
    func postTVEmbedded(body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        // WEB_EMBEDDED_PLAYER is a web client — use a browser UA so YouTube treats the
        // request as a legitimate iframe embed and returns hlsManifestUrl in streamingData.
        request.setValue(InnerTubeClients.Web.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            InnerTubeClients.TVEmbedded.nameID,
            forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(
            InnerTubeClients.TVEmbedded.version,
            forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player [TVEmbedded] videoId=\(videoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player [TVEmbedded]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [TVEmbedded]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [TVEmbedded]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player [TVEmbedded] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// MWEB (m.youtube.com, iPad Safari, nameID=2) player request on www.youtube.com.
    /// Uses the mobile web client which per yt-dlp does not require a PO Token for HLS
    /// (`required=False`) and has no embed restriction — returns `hlsManifestUrl` for a
    /// wider set of videos than WEB_EMBEDDED_PLAYER.
    func postMWEB(body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.MWEB.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.MWEB.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.MWEB.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        // Note: www.youtube.com uses cookie-based auth, not Bearer tokens.
        // Sending Authorization: Bearer causes HTTP 400. Auth is omitted here.
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player [MWEB] videoId=\(videoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player [MWEB]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [MWEB]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [MWEB]: \(String(describing: error["message"] ?? error), privacy: .public)")
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice("✅ /player [MWEB] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// WEB client with macOS Safari UA — mirrors yt-dlp's `web_safari` client (nameID=1).
    /// Unlike the Chrome-UA WEB client, this returns `hlsManifestUrl` for non-embeddable
    /// videos. Uses the same www.youtube.com endpoint as postMWEB; no Bearer auth
    /// (cookie-based auth in yt-dlp, but HLS manifest works without auth for VOD).
    func postWebSafari(
        body: [String: Any], visitorIdOverride: String? = nil, allowBearerFallback: Bool = false
    ) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.WebSafari.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.WebSafari.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.WebSafari.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        // fix9: SAPISID auth for postWebSafari.
        // When SAPISID is available (recovered from WKWebView propagated cookies), use
        // SAPISIDHASH auth so YouTube treats the request as authenticated — returning rqh=0
        // adaptive stream URLs that the CDN serves without pot= enforcement.
        // Without auth, YouTube returns rqh=1 URLs that require pot= and still 403 on the
        // CDN probe when match=false (webVD ≠ apiVD). With SAPISID, Path A wins reliably.
        // Bearer is opt-in: for playback, www.youtube.com is documented throughout this file as
        // rejecting the TV device-code Bearer token with HTTP 400, and PR #129 removed an
        // unconditional Bearer fallback here while fixing playback. Only the tracking-URL fetch
        // opts in, where a 400 just means no account-bound URLs rather than broken playback.
        let authStatus: String
        if let sid = sapisid {
            request.setValue(InnerTubeAPI.sapisidhash(sapisid: sid), forHTTPHeaderField: "Authorization")
            request.setValue("1", forHTTPHeaderField: "X-Origin")
            authStatus = "SAPISIDHASH"
        } else if allowBearerFallback, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
            authStatus = "Bearer"
        } else {
            authStatus = "unauthenticated"
        }
        // Use the override visitor ID (from WKWebView guide call) when provided, so the
        // X-Goog-Visitor-Id header matches the context.client.visitorData in the body and
        // the minted BotGuard pot= token identifier — required for CDN URL validation.
        let effectiveVD = visitorIdOverride ?? visitorData
        if let vd = effectiveVD {
            request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice(
            "POST /player [WebSafari] videoId=\(videoId, privacy: .public) auth=\(authStatus, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player [WebSafari]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [WebSafari]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [WebSafari]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player [WebSafari] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// WEB client (nameID=1) on www.youtube.com authenticated with Bearer + X-Goog-AuthUser:0.
    /// Mirrors yt-dlp's `web` OAuth client pattern — for signed-in users YouTube returns
    /// adaptive stream URLs without `rqh=1`, so no PO token is needed.
    /// Throws `APIError.notAuthenticated` when no `authToken` is present.
    func postWebAuthenticated(body: [String: Any]) async throws -> [String: Any] {
        guard let token = authToken else { throw APIError.notAuthenticated }
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.Web.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.Web.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.Web.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        // yt-dlp web OAuth pattern: Bearer + X-Goog-AuthUser:0 for www.youtube.com endpoints.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        if let vd = visitorData {
            request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player [WebAuth] videoId=\(videoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var errSummary = ""
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let err = jsonResponse["error"] as? [String: Any]
            {
                let code = err["code"] ?? ""
                let msg = (err["message"] as? String ?? "").prefix(120)
                let status = err["status"] ?? ""
                errSummary = "code=\(code) status=\(status) msg=\(msg)"
            } else {
                errSummary = String(data: data.prefix(120), encoding: .utf8) ?? "(non-utf8)"
            }
            tubeLog.error(
                "❌ HTTP \(statusCode, privacy: .public) for /player [WebAuth] err=\(errSummary, privacy: .public)")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [WebAuth]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [WebAuth]: \(String(describing: error["message"] ?? error), privacy: .public)")
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player [WebAuth] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

}
