import Foundation

// MARK: - LocalSubscriptionFeedService
//
// Builds a subscription feed from locally followed channels, with no authentication.
// Mirrors FreeTube's SubscriptionsVideos fetch strategy:
//   Primary:  YouTube public Atom/RSS feed (no auth, returns last ~15 videos per channel)
//   Fallback: InnerTube fetchChannelVideos (no auth, richer metadata, more rate-limit risk)
//
// Implemented as a Sendable struct — all mutable state lives in the actor dependencies
// (LocalSubscriptionStore, LocalSubscriptionFeedCache) that are passed as parameters.

public struct LocalSubscriptionFeedService: Sendable {

    // MARK: - Singleton

    public static let shared = LocalSubscriptionFeedService()

    // MARK: - Dependencies

    let session: URLSession
    static let maxConcurrentChannels = 4
    private typealias ChannelResult = (channelId: String, feed: RSSParseResult)

    // MARK: - Init

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Fetches new videos for all locally followed channels.
    /// Returns videos sorted newest-first, deduplicated by videoId.
    /// Updates channel name / thumbnail metadata as a side effect.
    ///
    /// - Parameters:
    ///   - store: Where followed channels are persisted. Defaults to `.shared`.
    ///   - cache: Per-channel TTL cache. Defaults to `.shared`.
    ///   - api: InnerTube API instance used as RSS fallback (no auth required for channel videos).
    public func fetchFeed(
        store: LocalSubscriptionStore = .shared,
        cache: LocalSubscriptionFeedCache = .shared,
        api: any InnerTubeAPIProtocol
    ) async -> [Video] {
        let channels = await store.allChannels()
        guard !channels.isEmpty, !Task.isCancelled else { return [] }

        // Force RSS-only when following many channels to avoid InnerTube rate limiting.
        // Matches FreeTube's 125-channel threshold.
        let forceRSS = channels.count >= 125

        var allVideos: [Video] = []
        var metadataUpdates: [(channelId: String, name: String)] = []

        await withTaskGroup(of: ChannelResult?.self) { group in
            var remaining = channels.makeIterator()
            for _ in 0..<Self.maxConcurrentChannels {
                guard !Task.isCancelled, let channel = remaining.next() else { break }
                group.addTask { await fetchChannel(channel, forceRSS: forceRSS, cache: cache, api: api) }
            }
            for await result in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let result {
                    allVideos.append(contentsOf: result.feed.videos)
                    if let name = result.feed.channelName {
                        metadataUpdates.append((result.channelId, name))
                    }
                }
                if let channel = remaining.next() {
                    group.addTask { await fetchChannel(channel, forceRSS: forceRSS, cache: cache, api: api) }
                }
            }
        }

        // Persist any updated channel names / thumbnails from RSS
        for update in metadataUpdates {
            guard !Task.isCancelled else { return [] }
            await store.updateMetadata(
                channelId: update.channelId,
                title: update.name,
                thumbnailURL: nil
            )
        }

        // Deduplicate by videoId — preserve the RSS/InnerTube arrival order rather
        // than sorting by date so both the pinned shorts row and the regular video
        // grid show videos in the same order as they were fetched from each channel.
        var seen = Set<String>()
        guard !Task.isCancelled else { return [] }
        return
            allVideos
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - Per-channel fetch (nonisolated — no actor state accessed)

    private func fetchChannel(
        _ channel: LocalChannel, forceRSS: Bool, cache: LocalSubscriptionFeedCache, api: any InnerTubeAPIProtocol
    ) async -> ChannelResult? {
        guard !Task.isCancelled else { return nil }
        if let cached = await cache.videos(for: channel.id) {
            return (channel.id, RSSParseResult(channelName: nil, videos: cached))
        }
        guard !Task.isCancelled,
            let result = await Self.fetchChannelVideos(
                channel: channel, forceRSS: forceRSS, api: api, session: session),
            !Task.isCancelled
        else { return nil }
        await cache.store(videos: result.videos, for: channel.id)
        return (channel.id, result)
    }

    /// RSS primary → InnerTube fallback.
    /// Returns a successful feed, including a valid empty one; nil means failure or cancellation.
    private static func fetchChannelVideos(
        channel: LocalChannel,
        forceRSS: Bool,
        api: any InnerTubeAPIProtocol,
        session: URLSession
    ) async -> RSSParseResult? {
        // Try RSS first (no rate limiting, no auth)
        if let result = await fetchViaRSS(channel: channel, session: session) {
            return result
        }

        // RSS failed — fall back to InnerTube channel videos (no auth required)
        if !Task.isCancelled, !forceRSS, let videos = await fetchViaInnerTube(channel: channel, api: api) {
            return RSSParseResult(channelName: nil, videos: videos)
        }

        return nil
    }

    // MARK: - RSS fetch

    private static func fetchViaRSS(channel: LocalChannel, session: URLSession) async -> RSSParseResult? {
        // Fetch uploads and Shorts playlist feeds concurrently.
        // Shorts RSS is best-effort: if unavailable the enrichment step is skipped.
        async let uploadsPrimary = fetchRSS(
            url: YouTubeRSS.feedURL(for: channel.id),
            channelId: channel.id,
            session: session)
        async let shortsFetch = fetchRSS(
            url: YouTubeRSS.shortsFeedURL(for: channel.id),
            channelId: channel.id,
            session: session)

        // Await both concurrent fetches before any serial work.
        let primaryResult = await uploadsPrimary
        let shortsFetchResult = await shortsFetch
        guard !Task.isCancelled else { return nil }

        // Resolve uploads: primary first, then fallback if needed.
        let uploads: RSSParseResult
        if let result = primaryResult {
            uploads = result
        } else if let fallback = await fetchRSS(
            url: YouTubeRSS.fallbackFeedURL(for: channel.id),
            channelId: channel.id,
            session: session)
        {
            uploads = fallback
        } else {
            return nil
        }

        let shortIds = Set(shortsFetchResult?.videos.map(\.id) ?? [])
        guard !shortIds.isEmpty else { return uploads }

        let enriched = uploads.videos.map { v -> Video in
            guard shortIds.contains(v.id) else { return v }
            var copy = v
            copy.isShort = true
            return copy
        }
        return RSSParseResult(channelName: uploads.channelName, videos: enriched)
    }

    private static func fetchRSS(url: URL, channelId: String, session: URLSession) async -> RSSParseResult? {
        guard !Task.isCancelled else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return nil }
            let result = parseYouTubeRSS(data, channelId: channelId)
            return result.isValidFeed && !Task.isCancelled ? result : nil
        } catch {
            return nil
        }
    }

    // MARK: - InnerTube fallback

    private static func fetchViaInnerTube(channel: LocalChannel, api: any InnerTubeAPIProtocol) async -> [Video]? {
        guard !Task.isCancelled else { return nil }
        do {
            let group = try await api.fetchChannelVideos(channelId: channel.id, continuationToken: nil)
            return Task.isCancelled ? nil : group.videos
        } catch {
            return nil
        }
    }
}
