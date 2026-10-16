import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let tubeLog = Logger(subsystem: appSubsystem, category: "InnerTube")

// MARK: - Browse endpoints

extension InnerTubeAPI {

    // MARK: - Visitor data helper

    /// Extracts `responseContext.visitorData` from a browse response and stores it.
    /// The stored token is included in subsequent home-feed requests so YouTube can
    /// tailor recommendations to this specific device/session.
    func updateVisitorData(from response: [String: Any]) {
        guard let ctx = response["responseContext"] as? [String: Any],
            let vd = ctx["visitorData"] as? String, !vd.isEmpty
        else { return }
        visitorData = vd
    }

    // MARK: - Home

    /// Fetches the home feed.
    /// When authenticated, uses TVHTML5 on youtubei.googleapis.com for a personalised feed.
    /// When unauthenticated, uses the WEB client on www.youtube.com for the default feed.
    public func fetchHome(continuationToken: String? = nil) async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isMixedFeedEnabled {
            return HomePaginationUITestFixture.regularPage(subscriptions: false, continuationToken: continuationToken)
        }
        #endif
        let isAuth = authToken != nil
        var body = makeBody(
            client: isAuth ? tvClientContext : webClientContext,
            continuationToken: continuationToken,
            includeVisitorData: true)
        if continuationToken == nil {
            body["browseId"] = "FEwhat_to_watch"
        }
        let data =
            isAuth
            ? try await postTV(endpoint: "browse", body: body)
            : try await post(endpoint: "browse", body: body)
        updateVisitorData(from: data)
        return try parseVideoGroup(from: data, title: BrowseSection.SectionType.home.defaultTitle)
    }

    /// Fetches the home feed as multiple named shelves (TYPE_ROW in Android).
    /// Returns one VideoGroup per shelf; each has layout == .row.
    /// Falls back to a single flat VideoGroup if no shelves are found.
    public func fetchHomeRows(continuationToken: String? = nil) async throws -> [VideoGroup] {
        #if DEBUG
        if HomePaginationUITestFixture.isEnabled {
            return [HomePaginationUITestFixture.regularPage(subscriptions: false, continuationToken: continuationToken)]
        }
        #endif
        let isAuth = authToken != nil
        var body = makeBody(
            client: isAuth ? tvClientContext : webClientContext,
            continuationToken: continuationToken,
            includeVisitorData: true)
        if continuationToken == nil {
            body["browseId"] = "FEwhat_to_watch"
        }
        let data =
            isAuth
            ? try await postTV(endpoint: "browse", body: body)
            : try await post(endpoint: "browse", body: body)
        updateVisitorData(from: data)
        let rows = parseVideoGroupRows(from: data)
        tubeLog.notice("fetchHomeRows → \(rows.count, privacy: .public) shelves")
        let rowShortsDetail = rows.map { row -> String in
            let s = row.videos.filter { $0.isShort }.count
            return "'\(row.title ?? "?")': \(s)/\(row.videos.count) shorts"
        }.joined(separator: ", ")
        tubeLog.notice("fetchHomeRows shelf detail: [\(rowShortsDetail, privacy: .public)]")
        return rows
    }

    // MARK: - Subscriptions

    /// Fetches subscriptions feed (requires auth).
    /// Uses TVHTML5 client on youtubei.googleapis.com — the only endpoint that accepts
    /// the OAuth token issued by the TV device-code flow.
    public func fetchSubscriptions(continuationToken: String? = nil) async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isEnabled {
            return HomePaginationUITestFixture.regularPage(subscriptions: true, continuationToken: continuationToken)
        }
        #endif
        var body = makeBody(client: tvClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["browseId"] = "FEsubscriptions"
        }
        let data = try await postTV(endpoint: "browse", body: body)
        let group = try parseVideoGroup(from: data, title: "Subscriptions")
        // Preserve the API's arrival order — YouTube returns tiles in the order
        // it considers most relevant. Sorting by date re-inserts new pages'
        // videos between existing ones instead of appending them.
        return group
    }

    /// Fetches the list of channels the authenticated user subscribes to (requires auth).
    ///
    /// Strategy:
    ///  1. `/guide` endpoint with TV client + auth — returns the TV sidebar guide which
    ///     includes every subscribed channel with avatar thumbnail URLs via guideEntryRenderer.
    ///  2. If that yields no channels, fall back to parsing unique channels from the
    ///     TVHTML5 video-tile subscription feed (channel IDs + names, no avatars).
    public func fetchSubscribedChannels() async throws -> [Channel] {
        // Primary: TV guide sidebar — includes subscribed channels with avatar thumbnails
        let guideBody = makeBody(client: tvClientContext)
        let guideData = try await postTV(endpoint: "guide", body: guideBody)
        let guideKeys = Array(guideData.keys.sorted().prefix(8))
        tubeLog.notice("fetchSubscribedChannels guide top-level keys: \(guideKeys, privacy: .public)")
        let guideChannels = parseGuideChannels(from: guideData)
        tubeLog.notice("fetchSubscribedChannels guide → \(guideChannels.count, privacy: .public) channels")
        if !guideChannels.isEmpty { return guideChannels }

        // Fallback: TV subscription video-tile feed — extract unique channels (no avatars)
        tubeLog.notice("fetchSubscribedChannels: guide returned 0 — falling back to video tile parse")
        var tvBody = makeBody(client: tvClientContext)
        tvBody["browseId"] = "FEsubscriptions"
        let tvData = try await postTV(endpoint: "browse", body: tvBody)
        return parseSubscribedChannels(from: tvData)
    }

    /// Fetches watch history (requires auth).
    public func fetchHistory(continuationToken: String? = nil) async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isMixedFeedEnabled {
            return VideoGroup(
                title: "History",
                videos: [Video(id: "history-fixture", title: "History fixture", channelTitle: "Fixture")])
        }
        #endif
        var body = makeBody(client: tvClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["browseId"] = "FEhistory"
        }
        let data = try await postTV(endpoint: "browse", body: body)
        return try parseVideoGroup(from: data, title: "History")
    }

    // MARK: - Search

    public func search(
        query: String,
        continuationToken: String? = nil,
        filter: SearchFilter = .default
    ) async throws -> VideoGroup {
        var body = makeBody(client: webClientContext, continuationToken: continuationToken)
        if continuationToken == nil {
            body["query"] = query
            if let params = filter.encodedParams() {
                body["params"] = params
            }
        }
        let data = try await post(endpoint: "search", body: body)
        return try parseVideoGroup(from: data, title: "Search: \(query)")
    }

    public func fetchSearchSuggestions(query: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search")
        else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "youtube"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "callback", value: ""),
        ]
        guard let url = components.url else { return [] }
        tubeLog.debug("[Suggestions] Fetching URL: \(url)")
        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        tubeLog.debug("[Suggestions] HTTP status: \(statusCode), bytes: \(data.count)")
        // Response format: [query, [[suggestion, 0, []], ...], ...]
        guard let raw = String(data: data, encoding: .utf8) else {
            tubeLog.error("[Suggestions] Failed to decode response as UTF-8")
            return []
        }
        tubeLog.debug("[Suggestions] Raw prefix: \(raw.prefix(120))")
        // Extract the outermost JSON array — works regardless of callback wrapper name
        guard let arrayStart = raw.firstIndex(of: "["),
            let arrayEnd = raw.lastIndex(of: "]")
        else {
            tubeLog.error("[Suggestions] Could not find JSON array bounds")
            return []
        }
        let jsonString = String(raw[arrayStart...arrayEnd])
        tubeLog.debug("[Suggestions] JSON prefix after strip: \(jsonString.prefix(120))")
        guard let jsonData = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [Any]
        else {
            tubeLog.error("[Suggestions] JSON parse failed")
            return []
        }
        guard let suggestions = json[safe: 1] as? [[Any]] else {
            tubeLog.error("[Suggestions] Unexpected JSON shape: \(String(describing: json.prefix(2)))")
            return []
        }
        let results = suggestions.compactMap { $0[safe: 0] as? String }
        tubeLog.debug("[Suggestions] Parsed \(results.count) suggestions: \(String(describing: results.prefix(5)))")
        return results
    }

    // MARK: - Shorts

    private static let shortsSubscriptionsPrefix = "subs:"
    private static let shortsSearchPrefix = "srch:"

    public func fetchShorts() async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isEnabled {
            return HomePaginationUITestFixture.shortsPage(continuationToken: nil)
        }
        #endif
        if authToken != nil {
            // TV OAuth exposes account Shorts through subscriptions, not the retired FEshorts browse.
            return try await fetchAccountShorts(continuationToken: nil)
        }
        return try await fetchAnonymousShorts(continuationToken: nil)
    }

    public func fetchShortsMore(continuationToken: String) async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isEnabled {
            return HomePaginationUITestFixture.shortsPage(continuationToken: continuationToken)
        }
        #endif
        if continuationToken.hasPrefix(Self.shortsSubscriptionsPrefix) {
            guard authToken != nil else { throw APIError.notAuthenticated }
            return try await fetchAccountShorts(
                continuationToken: String(continuationToken.dropFirst(Self.shortsSubscriptionsPrefix.count)))
        }
        guard authToken == nil, continuationToken.hasPrefix(Self.shortsSearchPrefix) else {
            // Continuations are session-local: never reinterpret an account token as anonymous search.
            throw APIError.unavailable("Reload Shorts after changing accounts.")
        }
        return try await fetchAnonymousShorts(
            continuationToken: String(continuationToken.dropFirst(Self.shortsSearchPrefix.count)))
    }

    private func fetchAccountShorts(continuationToken: String?) async throws -> VideoGroup {
        let group = try await fetchSubscriptions(continuationToken: continuationToken)
        return VideoGroup(
            title: "Shorts", videos: group.videos.filter(\.isShort),
            nextPageToken: group.nextPageToken.map { Self.shortsSubscriptionsPrefix + $0 })
    }

    private func fetchAnonymousShorts(continuationToken: String?) async throws -> VideoGroup {
        let group = try await search(
            query: "#shorts", continuationToken: continuationToken, filter: SearchFilter(duration: .short))
        var shorts = group.videos.filter { $0.isShort || ($0.duration.map { $0 <= 180 } ?? false) }
        for index in shorts.indices { shorts[index].isShort = true }
        return VideoGroup(
            title: "Shorts", videos: shorts,
            nextPageToken: group.nextPageToken.map { Self.shortsSearchPrefix + $0 })
    }

    // MARK: - Category sections

    public func fetchMusic() async throws -> VideoGroup {
        do {
            // FEmusic_home is the TVHTML5 browse ID for the music category page.
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEmusic_home"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: "Music")
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchMusic browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "music")
    }

    public func fetchGaming() async throws -> VideoGroup {
        do {
            // FEgaming requires TVHTML5 context on www.youtube.com (not googleapis.com).
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEgaming"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: "Gaming")
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchGaming browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "gaming")
    }

    public func fetchNews() async throws -> VideoGroup {
        // FEnews is not a valid InnerTube browse ID — use search directly.
        return try await search(query: "news today")
    }

    public func fetchLive() async throws -> VideoGroup {
        do {
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FElive_home"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: "Live")
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchLive browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "live stream")
    }

    public func fetchSports() async throws -> VideoGroup {
        do {
            // FEsportsau is the known TVHTML5 browse ID for the sports category.
            var body = makeBody(client: tvClientContext)
            body["browseId"] = "FEsportsau"
            let data = try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: "Sports")
            if !group.videos.isEmpty { return group }
        } catch {
            tubeLog.notice("fetchSports browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: "sports")
    }
}
