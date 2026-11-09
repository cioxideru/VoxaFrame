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
            let group = HomePaginationUITestFixture.regularPage(
                subscriptions: false, continuationToken: continuationToken)
            return try parseVideoGroup(from: HomePaginationUITestFixture.browseResponse(for: group), title: group.title)
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
        let injectedIDs = HomePaginationUITestFixture.injectedRecommendationIDs
        if !injectedIDs.isEmpty {
            guard continuationToken == nil else { return [] }
            return [VideoGroup(videos: injectedIDs.map { Video(id: $0, title: $0, channelTitle: "Test Channel") })]
        }
        if HomePaginationUITestFixture.isEnabled {
            let group = HomePaginationUITestFixture.regularPage(
                subscriptions: false, continuationToken: continuationToken)
            return parseVideoGroupRows(from: HomePaginationUITestFixture.browseResponse(for: group))
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
            let group = HomePaginationUITestFixture.regularPage(
                subscriptions: true, continuationToken: continuationToken)
            return try parseVideoGroup(from: HomePaginationUITestFixture.browseResponse(for: group), title: group.title)
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

    /// TV subscriptions navigation owns membership; video authors are not a complete list.
    public func fetchSubscribedChannels() async throws -> [Channel] {
        guard let accountToken = authToken else { throw APIError.notAuthenticated }
        var body = makeBody(client: tvClientContext)
        body["browseId"] = "FEsubscriptions"
        var channels: [Channel] = []
        var seenIDs = Set<String>()
        var seenTokens = Set<String>()
        while true {
            try Task.checkCancellation()
            let response = try await postTV(endpoint: "browse", body: body, explicitBearerToken: accountToken)
            try Task.checkCancellation()
            try checkSubscriptionResponse(response)
            let page = try parseSubscriptionNavigation(response)
            channels += page.channels.filter { seenIDs.insert($0.id).inserted }
            guard let token = page.continuation else { break }
            guard seenTokens.insert(token).inserted else {
                throw APIError.decodingError("Repeated subscriptions continuation.")
            }
            body = makeBody(client: tvClientContext, continuationToken: token)
        }
        return channels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Fetches watch history (requires auth).
    public func fetchHistory(continuationToken: String? = nil) async throws -> VideoGroup {
        #if DEBUG
        if HomePaginationUITestFixture.isMixedFeedEnabled {
            return VideoGroup(
                title: "History",
                videos: [
                    Video(id: "history-fixture", title: "History fixture", channelTitle: "Fixture", watchProgress: 1)
                ])
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

    public func fetchMusic(continuationToken: String? = nil) async throws -> VideoGroup {
        try await fetchCategory(
            browseId: "FEtopics_music", title: "Music", fallbackQuery: "music", continuationToken: continuationToken)
    }

    public func fetchGaming(continuationToken: String? = nil) async throws -> VideoGroup {
        try await fetchCategory(
            browseId: "FEtopics_gaming", title: "Gaming", fallbackQuery: "gaming", continuationToken: continuationToken)
    }

    public func fetchNews(continuationToken: String? = nil) async throws -> VideoGroup {
        try await fetchCategory(
            browseId: "FEtopics_news", title: "News", fallbackQuery: "news today",
            continuationToken: continuationToken)
    }

    public func fetchLive(continuationToken: String? = nil) async throws -> VideoGroup {
        try await fetchCategory(
            browseId: "FEtopics_live", title: "Live", fallbackQuery: "live stream", continuationToken: continuationToken
        )
    }

    public func fetchSports(continuationToken: String? = nil) async throws -> VideoGroup {
        try await fetchCategory(
            browseId: "FEtopics_sports", title: "Sports", fallbackQuery: "sports", continuationToken: continuationToken)
    }

    /// A TV category page (`FEtopics_*`), or a search when the first page is empty or fails (PLAN-0047).
    ///
    /// A signed-in account browses with the TV client and its token on youtubei.googleapis.com, like Home; without
    /// one the request goes to www.youtube.com. The older IDs (`FEmusic_home`, `FEgaming`, `FElive_home`,
    /// `FEsportsau`) answer HTTP 400 on both hosts, with or without the token (iPad log and probes, 2026-11-09).
    /// A continuation that fails ends the section: the token may belong to the search fallback.
    private func fetchCategory(
        browseId: String, title: String, fallbackQuery: String, continuationToken: String?
    ) async throws -> VideoGroup {
        do {
            var body = makeBody(client: tvClientContext, continuationToken: continuationToken)
            if continuationToken == nil { body["browseId"] = browseId }
            let data =
                authToken != nil
                ? try await postTV(endpoint: "browse", body: body)
                : try await postTVCategory(endpoint: "browse", body: body)
            let group = try parseVideoGroup(from: data, title: title)
            if !group.videos.isEmpty || continuationToken != nil { return group }
            tubeLog.notice("\(browseId, privacy: .public) browse returned no videos, falling back to search")
        } catch {
            guard continuationToken == nil else { return VideoGroup(title: title) }
            tubeLog.notice(
                "\(browseId, privacy: .public) browse failed, falling back to search: \(error, privacy: .public)")
        }
        return try await search(query: fallbackQuery)
    }
}
