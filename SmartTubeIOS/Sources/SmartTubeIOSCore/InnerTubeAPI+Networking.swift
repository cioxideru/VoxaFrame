import CryptoKit
import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

/// Random `[A-Za-z0-9_-]` string for InnerTube `cpn` / `t` request nonces.
func randomInnerTubeNonce(length: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    return String((0..<length).map { _ in alphabet[Int.random(in: alphabet.indices)] })
}

/// Extracts the visitor identifier embedded in a YouTube watch page.
/// YouTube currently emits either the uppercase ytcfg key or lower-camel JSON key.
func extractYouTubeVisitorData(from html: String) -> String? {
    let patterns = [
        #"\"VISITOR_DATA\"\s*:\s*\"([^\"]+)\""#,
        #"\"visitorData\"\s*:\s*\"([^\"]+)\""#,
    ]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)
            ),
            let range = Range(match.range(at: 1), in: html)
        else { continue }
        let encodedValue = String(html[range])
        let quotedJSON = Data("\"\(encodedValue)\"".utf8)
        let value =
            (try? JSONDecoder().decode(String.self, from: quotedJSON))
            ?? encodedValue.replacingOccurrences(of: #"\u003d"#, with: "=")
        if !value.isEmpty { return value }
    }
    return nil
}

// MARK: - Networking

extension InnerTubeAPI {

    // MARK: - visionOS visitor session

    /// Returns visitorData issued to the visionOS client itself via `/visitor_id`
    /// (NewPipe: "we must always pass a valid visitorData to get valid player
    /// responses"). Cached for the app session; nil on failure so the player request
    /// still goes out.
    func visionOSVisitorDataIfNeeded() async -> String? {
        if let cached = visionOSVisitorData { return cached }
        guard let url = URL(string: "https://youtubei.googleapis.com/youtubei/v1/visitor_id?prettyPrint=false"),
            let json = try? await postVisionOSRequest(url: url, body: ["context": visionOSClientContext]),
            let vd = (json["responseContext"] as? [String: Any])?["visitorData"] as? String
        else {
            tubeLog.notice("VisionOS visitor_id request failed — sending player request without visitorData")
            return nil
        }
        visionOSVisitorData = vd
        return vd
    }

    // MARK: - signatureTimestamp fetch

    /// Returns the current YouTube player `signatureTimestamp` (STS), fetching and
    /// caching it from YouTube's homepage if not already stored or if the cache has
    /// expired (TTL = 1 hour). The STS is required by the TV authenticated player
    /// request to validate the player JS version — YouTube returns
    /// "The page needs to be reloaded" when it is absent or stale.
    /// Returns `nil` silently on network failure so callers can proceed without it.
    func fetchSignatureTimestampIfNeeded() async -> Int? {
        if let sts = signatureTimestamp,
            let fetchedAt = signatureTimestampFetchedAt,
            Date().timeIntervalSince(fetchedAt) < 3600
        {
            return sts
        }
        guard let url = URL(string: "https://www.youtube.com/") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            // "STS" appears at byte ~606 KB in YouTube's homepage — scan the full page.
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #""STS"\s*:\s*(\d+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                let range = Range(match.range(at: 1), in: html),
                let sts = Int(html[range])
            else {
                tubeLog.error("⚠️ signatureTimestamp: pattern not found in homepage response")
                return nil
            }
            signatureTimestamp = sts
            signatureTimestampFetchedAt = Date()
            tubeLog.notice("Fetched signatureTimestamp (STS): \(sts, privacy: .public)")
            return sts
        } catch {
            tubeLog.error("⚠️ signatureTimestamp fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - Body builders

    func makeBody(
        client: [String: Any], continuationToken: String? = nil, includeVisitorData: Bool = false,
        includePoToken: Bool = false
    ) -> [String: Any] {
        var body: [String: Any] = ["context": client]
        if let token = continuationToken {
            body["continuation"] = token
        }
        if includeVisitorData, let visitor = visitorData {
            body["visitorData"] = visitor
        }
        if includePoToken, let pot = poToken {
            body["serviceIntegrityDimensions"] = ["poToken": pot]
        }
        return body
    }

    // MARK: - Attestation

    /// Fetches a proof-of-origin attestation token via YouTube's att/get endpoint.
    /// Sends the TV client context + Bearer auth + contentBindingContext so YouTube
    /// can confirm the request originates from a legitimate TV session.
    /// The returned `attestationToken` is included as `serviceIntegrityDimensions.poToken`
    /// in subsequent TV auth player requests — YouTube may then return `hlsManifestUrl`
    /// or standard CDN adaptive URLs rather than the SABR-only streaming response.
    /// Returns nil silently on any failure so callers are unaffected.
    func fetchAttestationToken(videoId: String) async -> String? {
        guard let token = authToken else { return nil }
        // Use playerBaseURL (googleapis.com) — www.youtube.com rejects Bearer tokens
        // with 400, same as all other authenticated requests (see postTV).
        guard let url = playerBaseURL.appendingPathComponent("att/get") as URL? else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InnerTubeClients.TV.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.TV.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        var clientFields = (tvClientContext["client"] as? [String: Any]) ?? [:]
        if let vd = visitorData { clientFields["visitorData"] = vd }
        var body: [String: Any] = ["context": ["client": clientFields]]
        body["contentBindingContext"] = ["videoId": videoId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                tubeLog.notice("att/get: statusCode=\(statusCode, privacy: .public) — no JSON")
                return nil
            }
            // Log top-level keys so we can see the real field name if it differs.
            let topKeys = Array(json.keys.prefix(8))
            tubeLog.notice("att/get: HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
            guard let attToken = json["attestationToken"] as? String, !attToken.isEmpty else {
                tubeLog.notice("att/get: no attestationToken in response keys=\(topKeys, privacy: .public)")
                return nil
            }
            tubeLog.notice("att/get: ✅ attestationToken obtained (prefix=\(attToken.prefix(20), privacy: .public)…)")
            return attToken
        } catch {
            tubeLog.notice("att/get: failed — \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Transport

    /// Player requests use the iOS client UA, googleapis.com base, and no auth header.
    func postPlayer(body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: playerBaseURL.appendingPathComponent("player"), resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(iosUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.iOS.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.iOS.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let playerVideoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player (iOS) videoId=\(playerVideoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error("❌ API error in /player: \(String(describing: error["message"] ?? error), privacy: .public)")
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice("✅ /player HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// Authenticated iOS client player request on youtubei.googleapis.com.
    /// Like `postPlayer` but adds a Bearer auth header when an auth token is available.
    /// YouTube may return non-rqh=1 stream URLs and an HLS manifest for authenticated
    /// iOS requests that it withholds from unauthenticated ones (e.g. embed-disabled videos).
    /// Falls back to `postPlayer` (unauthenticated) if no token is stored.
    func postPlayerAuthenticated(body: [String: Any]) async throws -> [String: Any] {
        guard let token = authToken else {
            return try await postPlayer(body: body)
        }
        guard
            let comps = URLComponents(
                url: playerBaseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        // Mirror postTV: Bearer auth on googleapis.com does not require ?key=.
        // (Sending key= with Bearer is harmless but unnecessary; omit it like postTV does.)
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(iosUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.iOS.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.iOS.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let playerVideoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player (iOS, auth) videoId=\(playerVideoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player (iOS, auth)")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player (iOS, auth)")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player (iOS, auth): \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player (iOS, auth) HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// Android VR (Oculus Quest) client player request on www.youtube.com.
    /// Uses the correct client headers (nameID=28) so YouTube identifies the request
    /// as an Oculus VR client. Per yt-dlp research, this client is exempt from rqh=1
    /// PO-token enforcement that affects standard Android and iOS adaptive streams.
    /// yt-dlp sends android_vr to www.youtube.com with the TV API key as a query param
    /// and without an Origin header (Android apps don't send Origin). The previous version
    /// of this function sent Origin: https://www.youtube.com without an API key — YouTube's
    /// Android VR (Oculus Quest, clientName=ANDROID_VR, nameID=28) player request.
    /// Uses the public Android/TV API key and includes X-Goog-Visitor-Id from the
    /// actor's stored visitorData (populated by prior TVAuth/iOS responses). yt-dlp
    /// bypasses bot-detection by downloading the YouTube webpage first to seed visitor
    /// cookies; we approximate this by passing visitorData via the header.
    func postAndroidVR(body: [String: Any]) async throws -> [String: Any] {
        // yt-dlp android_vr uses the TV/Android API key (same value). nosec: published in yt-dlp.
        let vrApiKey = "AIzaSyDCU8mBbAkSfXX4txZFpEpPEBoAOUMCxkU"  // gitleaks:allow
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("player"),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [
            URLQueryItem(name: "key", value: vrApiKey),
            URLQueryItem(name: "prettyPrint", value: "false"),
        ]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // yt-dlp sends Origin: https://www.youtube.com for android_vr (derived from
        // api_hostname in generate_api_headers). This is required — omitting it causes
        // YouTube to return a bot-detection LOGIN_REQUIRED response.
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.AndroidVR.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.AndroidVR.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.AndroidVR.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        // yt-dlp sends X-Goog-Visitor-Id populated from the YouTube webpage download.
        // Without a valid visitor context, YouTube returns a bot-detection response.
        // We use the visitorData captured from previous TVAuth/iOS player responses —
        // it is in the same protobuf format and confirms we have a legitimate YouTube session.
        if let vd = visitorData {
            request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
            tubeLog.notice("POST /player [AndroidVR] using visitorData (len=\(vd.count, privacy: .public))")
        } else {
            tubeLog.notice("POST /player [AndroidVR] — no visitorData available (may bot-detect)")
        }
        // Use the shared session to carry any YouTube cookies set by previous TVAuth/iOS
        // player responses — these help establish a legitimate session context for android_vr.
        // (Previously used an ephemeral session which stripped all session state, causing
        // YouTube to treat this as a raw API call from an unknown client.)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /player [AndroidVR] videoId=\(videoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /player [AndroidVR]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /player [AndroidVR]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /player [AndroidVR]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /player [AndroidVR] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)")
        }
        return json
    }

    /// visionOS player transport mirrored from NewPipeExtractor: youtubei.googleapis.com,
    /// no API key, no Origin, native visionOS UA and `X-Goog-Api-Format-Version: 2`.
    func postVisionOS(body: [String: Any], videoId: String) async throws -> [String: Any] {
        guard var comps = URLComponents(string: "https://youtubei.googleapis.com/youtubei/v1/player") else {
            throw APIError.invalidURL("player")
        }
        comps.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "t", value: randomInnerTubeNonce(length: 12)),
            URLQueryItem(name: "id", value: videoId),
        ]
        guard let url = comps.url else { throw APIError.invalidURL("player") }
        return try await postVisionOSRequest(url: url, body: body)
    }

    func postVisionOSRequest(url: URL, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InnerTubeClients.VisionOS.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else { throw APIError.httpError(statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        return json
    }

    /// Android client player request — used for download URL resolution.
    /// Android client headers use googleapis.com like iOS, but with Android UA/client IDs.
    func postAndroid(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: playerBaseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL(endpoint)
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InnerTubeClients.Android.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(InnerTubeClients.Android.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.Android.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let videoId = body["videoId"] as? String ?? ""
        tubeLog.notice("POST /\(endpoint, privacy: .public) [Android] videoId=\(videoId, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /\(endpoint, privacy: .public) [Android]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /\(endpoint, privacy: .public) [Android]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /\(endpoint, privacy: .public) [Android]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /\(endpoint, privacy: .public) [Android] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)"
            )
        }
        return json
    }

    func post(endpoint: String, body: [String: Any], useAuth: Bool = false) async throws -> [String: Any] {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL(endpoint)
        }
        let resolvedToken = useAuth ? authToken : nil
        if resolvedToken == nil {
            comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }
        guard let url = comps.url else { throw APIError.invalidURL(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.Web.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.Web.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let token = resolvedToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let authLabel = resolvedToken != nil ? "yes" : "no"
        tubeLog.notice("POST /\(endpoint, privacy: .public) [WEB] auth=\(authLabel, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /\(endpoint, privacy: .public)")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /\(endpoint, privacy: .public)")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        let topKeys = Array(json.keys.prefix(6))
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /\(endpoint, privacy: .public): \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            tubeLog.notice(
                "✅ /\(endpoint, privacy: .public) HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)"
            )
        }
        return json
    }

    /// Unauthenticated TVHTML5 browse on www.youtube.com.    /// FE* category browse IDs (FEgaming, FEshorts, FEmusic, …) require the TVHTML5
    /// client format but return 400 on youtubei.googleapis.com without a valid auth token.
    /// Posting to www.youtube.com with TV client headers resolves this.
    func postTVCategory(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: baseURL.appendingPathComponent(endpoint),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL(endpoint)
        }
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = comps.url else { throw APIError.invalidURL(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(InnerTubeClients.TV.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.TV.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        tubeLog.notice("POST /\(endpoint, privacy: .public) [TV-category]")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /\(endpoint, privacy: .public) [TV-category]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /\(endpoint, privacy: .public) [TV-category]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /\(endpoint, privacy: .public) [TV-category]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /\(endpoint, privacy: .public) [TV-category] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)"
            )
        }
        return json
    }

    /// Authenticated InnerTube endpoint — TVHTML5 client on youtubei.googleapis.com.
    /// Required for subscriptions, history, playlists, and personalised home: the OAuth
    /// token issued by the TV device-code flow is matched to this client. The WEB client
    /// on www.youtube.com rejects Bearer tokens (returns 400).
    ///
    /// Android alignment: when Bearer token is present, no ?key= param is sent
    /// (mirrors RetrofitOkHttpHelper — authHeaders non-empty → skip key, apply Bearer headers).
    /// When unauthenticated, the WEB key is used as on all other clients.
    func postTV(
        endpoint: String,
        body: [String: Any],
        useAuth: Bool = true,
        explicitBearerToken: String? = nil
    ) async throws -> [String: Any] {
        guard
            var comps = URLComponents(
                url: playerBaseURL.appendingPathComponent(endpoint),
                resolvingAgainstBaseURL: false)
        else {
            throw APIError.invalidURL(endpoint)
        }
        // Android: no ?key= when Bearer present; WEB key for unauthenticated.
        // `explicitBearerToken` lets callers bypass actor-state and supply a token directly.
        let resolvedToken = explicitBearerToken ?? (useAuth ? authToken : nil)
        let shouldAuthenticate = resolvedToken != nil
        if !shouldAuthenticate {
            comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }
        guard let url = comps.url else { throw APIError.invalidURL(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InnerTubeClients.TV.nameID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(InnerTubeClients.TV.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let token = resolvedToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let authLabel = shouldAuthenticate ? "yes" : "no"
        tubeLog.notice("POST /\(endpoint, privacy: .public) [TV] auth=\(authLabel, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            tubeLog.error("❌ HTTP \(statusCode, privacy: .public) for /\(endpoint, privacy: .public) [TV]")
            throw APIError.httpError(statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            tubeLog.error("❌ Non-dictionary JSON root for /\(endpoint, privacy: .public) [TV]")
            throw APIError.decodingError("Root JSON is not a dictionary")
        }
        if let error = json["error"] as? [String: Any] {
            tubeLog.error(
                "❌ API error in /\(endpoint, privacy: .public) [TV]: \(String(describing: error["message"] ?? error), privacy: .public)"
            )
        } else {
            let topKeys = Array(json.keys.prefix(6))
            tubeLog.notice(
                "✅ /\(endpoint, privacy: .public) [TV] HTTP \(statusCode, privacy: .public) keys: \(topKeys, privacy: .public)"
            )
        }
        return json
    }

}

// MARK: - SAPISIDHASH helper

extension InnerTubeAPI {

    /// Computes the SAPISIDHASH Authorization header value for www.youtube.com web-client requests.
    ///
    /// Format: `SAPISIDHASH {timestamp}_{sha1("{timestamp} {SAPISID} {origin}")}`
    ///
    /// This is the auth scheme used by YouTube's web frontend and mirrored by yt-dlp.
    /// Pass the result directly as the `Authorization` header value.
    static func sapisidhash(
        sapisid: String,
        origin: String = "https://www.youtube.com"
    ) -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let payload = "\(ts) \(sapisid) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(ts)_\(hex)"
    }
}
