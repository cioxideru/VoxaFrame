import Foundation
import Network
import os

private let cacheLog = Logger(subsystem: appSubsystem, category: "PreloadCache")

// MARK: - VideoPreloadCache
//
// An in-memory, actor-isolated cache for all per-video API responses that
// PlaybackViewModel needs before playback can start.
//
// Design goals:
//  - Zero-contention reads/writes via actor isolation (no locks needed)
//  - TTL-based expiry per data type (stream URLs expire earliest, ~5.5 h)
//  - LRU eviction: keeps at most `maxVideoEntries` videos worth of data
//  - Active prefetch tasks are tracked so duplicates are skipped and
//    tasks can be cancelled when the user navigates away
//
// Usage:
//  1. Call `prefetch(videoId:...)` from a VideoCardView `.task` modifier
//     as cards become visible.
//  2. In PlaybackViewModel.loadAsync(), call `consume(videoId:)` first —
//     if the cache holds fresh data you avoid all network calls.
//  3. After a live fetch, store results with `store(...)`.

// MARK: - PrefetchPriority

/// Priority tiers for the prefetch queue.
/// Higher raw values are dispatched first.
public enum PrefetchPriority: Int, Comparable, CaseIterable, Sendable {
    case speculative = 0  // neighbour prefetch — likely next video
    case visible = 1  // VideoCardView onAppear
    case immediate = 2  // reserved for near-play scenarios
    case userFocused = 3  // reserved for user-initiated loads

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - PrefetchRequest

private struct PrefetchRequest: Sendable {
    let videoId: String
    let sponsorCategories: Set<SponsorSegment.Category>
    let authToken: String?
    let priority: PrefetchPriority
    let enqueuedAt: Date
}

public actor VideoPreloadCache {

    // MARK: - Singleton

    public static let shared = VideoPreloadCache()

    // MARK: - Owned service instances
    //
    // The cache owns lightweight service instances so callers (e.g. VideoCardView)
    // only need to supply `videoId`, `isAuthenticated`, and `sponsorCategories` —
    // no service references need to flow through the view hierarchy.
    // Auth token is kept in sync via `setAuthToken(_:)`.
    // Services are injected via init so tests can substitute pre-configured instances.

    private let api: InnerTubeAPI
    private let sponsorBlock: SponsorBlockService
    private let deArrow: DeArrowService
    private let wkHLSNow: @Sendable () -> Date

    // MARK: - TTL constants

    /// CDN stream URLs expire after ~6 h; use 5 h 30 m to be safe.
    public static let playerInfoTTL: TimeInterval = 5.5 * 3600
    /// Tracking URLs are account-bound; token lifetime is typically 1 h.
    public static let trackingTTL: TimeInterval = 3600
    /// Related-video list can change; 20-min window covers typical session length.
    public static let nextInfoTTL: TimeInterval = 20 * 60
    /// End cards and SponsorBlock/DeArrow data are stable for hours.
    public static let endCardsTTL: TimeInterval = 4 * 3600
    public static let sponsorTTL: TimeInterval = 2 * 3600
    public static let deArrowTTL: TimeInterval = 4 * 3600

    // MARK: - LRU cap

    /// Maximum number of distinct video IDs kept in memory.
    static let maxVideoEntries = 30
    static let wkHLSTTL: TimeInterval = 4 * 3_600

    // MARK: - Cache entry

    struct CacheEntry<T: Sendable>: Sendable {
        let value: T
        let storedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(storedAt) > ttl }
    }

    // MARK: - Sub-caches (keyed by videoId)

    private var playerInfoCache: [String: CacheEntry<PlayerInfo>] = [:]
    private var trackingCache: [String: CacheEntry<PlaybackTrackingURLs?>] = [:]
    private var nextInfoCache: [String: CacheEntry<NextInfo>] = [:]
    private var endCardsCache: [String: CacheEntry<[EndCard]>] = [:]
    private var sponsorCache: [String: CacheEntry<[SponsorSegment]>] = [:]
    private var deArrowCache: [String: CacheEntry<DeArrowService.BrandingInfo>] = [:]
    /// URL, token and extraction origin share one lifetime, including token-first writes.
    private struct WKHLSCacheEntry {
        var url: URL?
        var poToken: String?
        var isPreWarm = false
        var storedAt: Date
    }
    private var wkHLSCache: [String: WKHLSCacheEntry] = [:]

    // MARK: - Access order (LRU)

    /// Ordered from oldest to newest access.
    private var accessOrder: [String] = []

    // MARK: - Active prefetch tasks

    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var activeRequests: [String: PrefetchRequest] = [:]
    private var workerIDs: [String: UUID] = [:]
    private var demandTask: Task<Void, Never>?
    private var isYieldingToPlayback = false

    // MARK: - In-flight coalescing
    //
    // Ensures concurrent live-load and prefetch calls for the same video ID
    // share a single network request rather than duplicating it.

    private var inFlightPlayerFetches: [String: Task<PlayerInfo?, Never>] = [:]

    // MARK: - Priority queue + worker pool
    //
    // Replaces the old activePrefetchCount + silent-drop guard (FM-1).
    // Enqueues requests sorted by priority; drains the queue with a worker pool.
    // Phase K (task #30) will make the cap network-aware.

    private var prefetchQueue: [PrefetchRequest] = []
    internal static let maxQueueDepth = 20  // internal for tests + Phase K
    internal static let maxWorkersWiFi = 5  // internal for Phase K override
    internal static let maxWorkersCellular = 2  // internal for Phase K override
    private(set) var activeWorkerCount = 0

    // MARK: - Disk cache (Phase J)

    private let disk = VideoDiskCache()

    // MARK: - Network-aware throttling (Phase K)

    nonisolated private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath? = nil

    init(
        api: InnerTubeAPI = InnerTubeAPI(),
        sponsorBlock: SponsorBlockService = SponsorBlockService(),
        deArrow: DeArrowService = DeArrowService(),
        wkHLSNow: @escaping @Sendable () -> Date = Date.init,
        monitorNetwork: Bool = true
    ) {
        self.api = api
        self.sponsorBlock = sponsorBlock
        self.deArrow = deArrow
        self.wkHLSNow = wkHLSNow
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.updatePath(path) }
        }
        if monitorNetwork { pathMonitor.start(queue: .global(qos: .background)) }
    }

    deinit {
        demandTask?.cancel()
        pathMonitor.cancel()
    }

    // MARK: - Public: auth token

    /// Forward the current auth token so prefetch requests can make authenticated calls.
    /// Call this from PlaybackViewModel.updateAuthToken and at app launch.
    public func setAuthToken(_ token: String?) async {
        cacheLog.notice("[auth] setAuthToken: \(token != nil ? "present" : "nil", privacy: .public)")
        await api.setAuthToken(token)
    }

    /// Forward the SAPISID cookie so prefetch WEB_CREATOR requests use SAPISIDHASH auth.
    public func setSAPISID(_ value: String?) async {
        await api.setSAPISID(value)
    }

    // MARK: - Public: prefetch

    /// Enqueues a background prefetch for all data types for `videoId`.
    /// Requests are sorted by `priority`; the queue is bounded at `maxQueueDepth`
    /// and evicts the lowest-priority item on overflow (enqueue-not-drop pattern).
    /// Pass the actual `authToken` value (not just a Bool) so the cache can
    /// sync it to its internal API before the tracking URL fetch fires —
    /// eliminating a race where prefetch starts before `setAuthToken` runs.
    public func prefetch(
        videoId: String,
        sponsorCategories: Set<SponsorSegment.Category>,
        authToken: String?,
        priority: PrefetchPriority = .visible
    ) {
        // Global kill-switch: DebugFlags.cachingDisabled covers both the hardcoded flag
        // and the --uitesting-disable-prefetch launch argument.
        if DebugFlags.cachingDisabled { return }
        // Playlist IDs are not video IDs — skip them to avoid wasted /player calls.
        let isPlaylistId = videoId == "WL" || videoId == "LL" || videoId.hasPrefix("PL")
        if isPlaylistId { return }
        // Skip if still fresh
        if let entry = playerInfoCache[videoId], !entry.isExpired { return }
        // Skip if already in-flight
        if prefetchTasks[videoId] != nil { return }
        // If already queued, upgrade priority if higher and re-sort
        if let idx = prefetchQueue.firstIndex(where: { $0.videoId == videoId }) {
            if priority > prefetchQueue[idx].priority {
                prefetchQueue[idx] = PrefetchRequest(
                    videoId: videoId,
                    sponsorCategories: sponsorCategories,
                    authToken: authToken,
                    priority: priority,
                    enqueuedAt: prefetchQueue[idx].enqueuedAt
                )
                prefetchQueue.sort { $0.priority > $1.priority }
            }
            return
        }
        // Overflow: evict the lowest-priority queued item before inserting
        if prefetchQueue.count >= Self.maxQueueDepth {
            prefetchQueue.removeLast()
        }
        // Insert maintaining descending-priority sort
        let request = PrefetchRequest(
            videoId: videoId,
            sponsorCategories: sponsorCategories,
            authToken: authToken,
            priority: priority,
            enqueuedAt: .init()
        )
        let insertIdx = prefetchQueue.firstIndex(where: { $0.priority < priority }) ?? prefetchQueue.endIndex
        prefetchQueue.insert(request, at: insertIdx)
        let qDepth = prefetchQueue.count
        let wCount = activeWorkerCount
        cacheLog.notice(
            "[prefetch] ENQUEUE \(videoId, privacy: .public) priority=\(priority.rawValue, privacy: .public) queueDepth=\(qDepth, privacy: .public) workers=\(wCount, privacy: .public)"
        )
        drainQueue()
    }

    /// Cancels any in-flight prefetch for `videoId` and removes it from the queue.
    public func cancelPrefetch(for videoId: String) {
        prefetchQueue.removeAll { $0.videoId == videoId }
        prefetchTasks[videoId]?.cancel()
        prefetchTasks.removeValue(forKey: videoId)
        activeRequests.removeValue(forKey: videoId)
        workerIDs.removeValue(forKey: videoId)
    }

    // MARK: - Private: worker pool drain

    /// Updates the tracked network path and re-evaluates the worker pool.
    private func updatePath(_ path: NWPath) {
        currentPath = path
        drainQueue()
    }

    /// Maximum concurrent prefetch workers for the current network path.
    /// Returns 0 when offline — new prefetches are paused but in-flight tasks continue.
    var networkCap: Int {  // internal for tests
        guard let path = currentPath, path.status == .satisfied else {
            // No path yet or path unsatisfied — allow WiFi workers until first update.
            return currentPath == nil ? Self.maxWorkersWiFi : 0
        }
        if path.isConstrained || path.isExpensive {
            return Self.maxWorkersCellular
        }
        return Self.maxWorkersWiFi
    }

    /// Data types allowed for prefetch on the current network path.
    /// Cellular/expensive paths skip large cosmetic fetches (endCards, deArrow).
    var allowedPrefetchDataTypes: Set<String> {  // internal for tests
        guard let path = currentPath, path.status == .satisfied else {
            return currentPath == nil
                ? ["playerInfo", "nextInfo", "sponsorSegments", "endCards", "deArrowBranding"] : []
        }
        if path.isConstrained || path.isExpensive {
            return ["playerInfo", "nextInfo", "sponsorSegments"]
        }
        return ["playerInfo", "nextInfo", "sponsorSegments", "endCards", "deArrowBranding"]
    }

    // MARK: - Public: in-flight coalescing

    /// Returns a shared Task that resolves to the player info for `videoId`.
    /// If a fetch is already in-flight (from a concurrent prefetch or live load),
    /// the existing Task is returned — no duplicate network request is made.
    public func getOrFetchPlayerInfo(videoId: String) -> Task<PlayerInfo?, Never> {
        if let existing = inFlightPlayerFetches[videoId] {
            cacheLog.notice("[coalesce] returning existing in-flight task for \(videoId, privacy: .public)")
            return existing
        }
        if let cached = fresh(playerInfoCache[videoId]) { return Task { cached } }
        cacheLog.notice("[coalesce] creating new in-flight task for \(videoId, privacy: .public)")
        let task = Task<PlayerInfo?, Never>(priority: .userInitiated) {
            let result = try? await self.api.fetchPlayerInfoVisionOS(videoId: videoId)
            self.inFlightPlayerFetches.removeValue(forKey: videoId)
            defer { self.drainQueue() }
            guard !Task.isCancelled, let result, result.hlsURL != nil else { return nil }
            // Publish the stream before optional metadata finishes, so the next Short can start.
            self.store(playerInfo: result, for: videoId)
            return result
        }
        inFlightPlayerFetches[videoId] = task
        return task
    }

    /// Returns the in-flight player fetch task for `videoId`, or `nil` if none is running.
    /// Used by `loadAsync` to coalesce with a concurrent prefetch without losing error context.
    public func inFlightPlayerFetch(videoId: String) -> Task<PlayerInfo?, Never>? {
        inFlightPlayerFetches[videoId]
    }

    // MARK: - Public: consume (cache-first read)

    /// Returns whatever fresh cached data exists for `videoId`, or `nil` fields
    /// for data that is missing or expired. Callers fetch only the missing pieces.
    /// SWR-eligible types (nextInfo, endCards, sponsorSegments, deArrowBranding) are
    /// returned even when stale, with the type added to `staleFields` — so callers can
    /// use the value immediately and revalidate in the background.
    public func consume(videoId: String) -> CachedVideoData {
        if DebugFlags.cachingDisabled {
            cacheLog.notice("[consume] caching disabled — returning empty for \(videoId, privacy: .public)")
            return CachedVideoData(
                playerInfo: nil, trackingURLs: nil, nextInfo: nil,
                endCards: nil, sponsorSegments: nil, deArrowBranding: nil,
                staleFields: [])
        }
        touch(videoId)
        // Disk warm-up (Phase J): populate in-memory cache from disk on cold path.
        // Disk-loaded entries use storedAt: .distantPast so SWR treats them as stale
        // and schedules background revalidation via Phase 2.
        if nextInfoCache[videoId] == nil,
            let fromDisk = disk.load(NextInfo.self, videoId: videoId, dataType: "nextInfo")
        {
            nextInfoCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.nextInfoTTL)
        }
        if endCardsCache[videoId] == nil,
            let fromDisk = disk.load([EndCard].self, videoId: videoId, dataType: "endCards")
        {
            endCardsCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.endCardsTTL)
        }
        if sponsorCache[videoId] == nil,
            let fromDisk = disk.load([SponsorSegment].self, videoId: videoId, dataType: "sponsorSegments")
        {
            sponsorCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.sponsorTTL)
        }
        if deArrowCache[videoId] == nil,
            let fromDisk = disk.load(DeArrowService.BrandingInfo.self, videoId: videoId, dataType: "deArrowBranding")
        {
            deArrowCache[videoId] = CacheEntry(value: fromDisk, storedAt: .distantPast, ttl: Self.deArrowTTL)
        }
        var staleFields = Set<CachedVideoData.DataType>()
        let data = CachedVideoData(
            playerInfo: fresh(playerInfoCache[videoId]),
            trackingURLs: trackingCache[videoId].flatMap { $0.isExpired ? nil : $0.value },
            nextInfo: staleOrFresh(nextInfoCache[videoId], dataType: .nextInfo, into: &staleFields),
            endCards: staleOrFresh(endCardsCache[videoId], dataType: .endCards, into: &staleFields),
            sponsorSegments: staleOrFresh(sponsorCache[videoId], dataType: .sponsorSegments, into: &staleFields),
            deArrowBranding: staleOrFresh(deArrowCache[videoId], dataType: .deArrowBranding, into: &staleFields),
            staleFields: staleFields
        )
        cacheLog.notice(
            "[consume] \(videoId, privacy: .public) — player=\(data.playerInfo != nil, privacy: .public) tracking=\(data.trackingURLs != nil, privacy: .public) next=\(data.nextInfo != nil, privacy: .public) endCards=\(data.endCards != nil, privacy: .public) sponsor=\(data.sponsorSegments != nil, privacy: .public) deArrow=\(data.deArrowBranding != nil, privacy: .public) stale=\(staleFields.count, privacy: .public) complete=\(data.isComplete, privacy: .public)"
        )
        return data
    }

    // MARK: - Public: store (write after live fetch)

    public func store(playerInfo: PlayerInfo, for videoId: String) {
        cacheLog.notice(
            "[store] playerInfo \(videoId, privacy: .public) formats=\(playerInfo.formats.count, privacy: .public) hls=\(playerInfo.hlsURL != nil, privacy: .public) adaptive=\(playerInfo.bestAdaptiveVideoURL != nil, privacy: .public)"
        )
        playerInfoCache[videoId] = CacheEntry(value: playerInfo, storedAt: .init(), ttl: Self.playerInfoTTL)
        touch(videoId)
    }

    public func store(trackingURLs: PlaybackTrackingURLs?, for videoId: String) {
        cacheLog.debug(
            "[store] trackingURLs \(videoId, privacy: .public) present=\(trackingURLs != nil, privacy: .public)")
        trackingCache[videoId] = CacheEntry(value: trackingURLs, storedAt: .init(), ttl: Self.trackingTTL)
        touch(videoId)
    }

    public func store(nextInfo: NextInfo, for videoId: String) {
        cacheLog.debug(
            "[store] nextInfo \(videoId, privacy: .public) related=\(nextInfo.relatedVideos.count, privacy: .public) chapters=\(nextInfo.chapters.count, privacy: .public)"
        )
        nextInfoCache[videoId] = CacheEntry(value: nextInfo, storedAt: .init(), ttl: Self.nextInfoTTL)
        disk.store(nextInfo, videoId: videoId, dataType: "nextInfo")
        touch(videoId)
    }

    public func store(endCards: [EndCard], for videoId: String) {
        cacheLog.debug("[store] endCards \(videoId, privacy: .public) count=\(endCards.count, privacy: .public)")
        endCardsCache[videoId] = CacheEntry(value: endCards, storedAt: .init(), ttl: Self.endCardsTTL)
        disk.store(endCards, videoId: videoId, dataType: "endCards")
        touch(videoId)
    }

    public func store(sponsorSegments: [SponsorSegment], for videoId: String) {
        cacheLog.debug(
            "[store] sponsorSegments \(videoId, privacy: .public) count=\(sponsorSegments.count, privacy: .public)")
        sponsorCache[videoId] = CacheEntry(value: sponsorSegments, storedAt: .init(), ttl: Self.sponsorTTL)
        disk.store(sponsorSegments, videoId: videoId, dataType: "sponsorSegments")
        touch(videoId)
    }

    public func store(deArrowBranding: DeArrowService.BrandingInfo, for videoId: String) {
        cacheLog.debug(
            "[store] deArrowBranding \(videoId, privacy: .public) hasTitle=\(deArrowBranding.title != nil, privacy: .public)"
        )
        deArrowCache[videoId] = CacheEntry(value: deArrowBranding, storedAt: .init(), ttl: Self.deArrowTTL)
        disk.store(deArrowBranding, videoId: videoId, dataType: "deArrowBranding")
        touch(videoId)
    }

    /// Stores the WKWebView-extracted HLS master manifest URL for a video.
    /// TTL matches the `expire=` lifetime of signed manifest URLs (~6h) with a 2h safety margin.
    /// Survives consume() reads for replay, subject to the shared LRU limit.
    /// - Parameter isPreWarm: Pass `true` when called from background `preWarm()` extraction,
    ///   `false` when called from a live race playback path (tryWebViewHLS / Path B win).
    ///   Phase -1a consults this flag to skip the HEAD probe for preWarm + pot=nil entries.
    public func store(wkHLSManifestURL url: URL, for videoId: String, isPreWarm: Bool = false) {
        cacheLog.notice(
            "[store] wkHLS \(videoId) origin=\(isPreWarm ? "preWarm" : "liveRace") url=\(url.absoluteString.prefix(80))"
        )
        var entry = freshWKHLS(for: videoId) ?? WKHLSCacheEntry(storedAt: wkHLSNow())
        entry.url = url
        entry.isPreWarm = isPreWarm
        entry.storedAt = wkHLSNow()
        wkHLSCache[videoId] = entry
        touch(videoId)
    }

    /// Returns `true` when the cached wkHLS URL was stored by a background preWarm extraction.
    /// Returns `false` for live-race extracted URLs or when no URL is cached.
    public func cachedWKHLSIsPreWarm(for videoId: String) -> Bool {
        freshWKHLS(for: videoId)?.isPreWarm ?? false
    }

    /// Returns the cached WKWebView HLS master manifest URL if still within TTL, else nil.
    public func cachedWKHLSURL(for videoId: String) -> URL? {
        if DebugFlags.cachingDisabled { return nil }
        return freshWKHLS(for: videoId)?.url
    }

    /// Returns true if the cached WKWebView HLS URL was stored within the last `seconds` seconds.
    /// Phase -1a uses this to skip the HEAD probe for recently-extracted URLs — the URL is
    /// guaranteed fresh (CDN session active) and the probe round-trip (~0.22s) is wasted work.
    /// Default threshold: 10s (covers the double-preWarm window before the heartbeat fires).
    public func isWKHLSURLFresh(for videoId: String, within seconds: TimeInterval = 10) -> Bool {
        guard let entry = freshWKHLS(for: videoId), entry.url != nil else { return false }
        return wkHLSNow().timeIntervalSince(entry.storedAt) < seconds
    }

    /// Stores the BotGuard pot= token that accompanied the WKWebView HLS URL extraction.
    /// The token shares the URL lifetime; updating it does not extend URL freshness.
    /// Token-only entries have the same TTL and LRU bound. This is the stable storage point for Phase -1a:
    /// unlike `YouTubeWebViewHLSExtractor.extractedPoToken`, this entry survives the
    /// nil-reset that happens at the start of every new `extractHLSURL` call.
    public func store(wkHLSPoToken token: String, for videoId: String) {
        var entry = freshWKHLS(for: videoId) ?? WKHLSCacheEntry(storedAt: wkHLSNow())
        entry.poToken = token
        wkHLSCache[videoId] = entry
        touch(videoId)
    }

    /// Returns the cached pot= token for a video, or nil if none was stored.
    public func cachedPoToken(for videoId: String) -> String? {
        if DebugFlags.cachingDisabled { return nil }
        return freshWKHLS(for: videoId)?.poToken
    }

    // MARK: - Public: auth invalidation

    /// Call on sign-out: tracking URLs and like-status in nextInfo are account-bound.
    public func evictAuthSensitiveData() {
        cacheLog.notice(
            "[evict] auth sign-out — clearing trackingCache (\(self.trackingCache.count, privacy: .public) entries) + nextInfoCache (\(self.nextInfoCache.count, privacy: .public) entries)"
        )
        trackingCache.removeAll()
        nextInfoCache.removeAll()
        // BUG-013 fix: also purge disk so nextInfo (likeStatus) cannot be read back after sign-out.
        disk.removeAll()
    }

    /// Call after a token refresh: tracking URLs bound to the old token are stale.
    public func evictTrackingURLs() {
        cacheLog.notice(
            "[evict] token refresh — clearing trackingCache (\(self.trackingCache.count, privacy: .public) entries)")
        trackingCache.removeAll()
    }

    /// Call when a 403 is received for a cached player-info URL.
    /// The cached URL is IP-bound and is now stale; evicting forces a fresh fetch on next load.
    public func invalidatePlayerInfo(for videoId: String) {
        guard playerInfoCache[videoId] != nil else { return }
        cacheLog.notice("[evict] 403 — invalidating playerInfoCache for \(videoId, privacy: .public)")
        playerInfoCache.removeValue(forKey: videoId)
    }

    /// Call when the cached WKWebView HLS URL returns 403 (expired signed URL).
    /// Evicting forces a fresh WKWebView extraction on the next load of this video.
    /// Also clears the associated pot= token so Phase -1a won't use an orphaned token.
    public func invalidateWKHLSURL(for videoId: String) {
        cacheLog.notice("[evict] 403 — invalidating wkHLSCache for \(videoId, privacy: .public)")
        wkHLSCache.removeValue(forKey: videoId)
    }

    // MARK: - Private: prefetch implementation

    private func runPrefetch(
        videoId: String,
        sponsorCategories: Set<SponsorSegment.Category>,
        authToken: String?
    ) async {
        guard !Task.isCancelled else { return }
        let startedAt = Date()
        let allowed = allowedPrefetchDataTypes
        cacheLog.notice(
            "[prefetch] START \(videoId, privacy: .public) allowed=\(allowed.sorted().joined(separator: ","), privacy: .public)"
        )

        // Route through getOrFetchPlayerInfo so a concurrent live-load for the
        // same video reuses this in-flight task instead of issuing a second request.
        let playerFetchTask = getOrFetchPlayerInfo(videoId: videoId)
        // Gate optional fetches on the current network path (Phase K).
        async let nextResult = allowed.contains("nextInfo") ? (try? await api.fetchNextInfo(videoId: videoId)) : nil
        async let endCardsResult = allowed.contains("endCards") ? (try? await api.fetchEndCards(videoId: videoId)) : nil
        async let sponsorResult = await sponsorBlock.fetchSegments(videoId: videoId, categories: sponsorCategories)
        async let deArrowResult =
            allowed.contains("deArrowBranding") ? await deArrow.fetchBranding(videoId: videoId) : nil

        // Pass the caller-supplied token directly — no dependency on api.authToken being set —
        // eliminating the actor-timing race that caused tracking=false on browse-phase prefetch.
        // This runs concurrently with the 5 child tasks above (all are in flight by this point).
        //
        // Reuse tracking URLs from the prefetched player response.

        let (next, cards, sponsor, dearrow) =
            await (nextResult, endCardsResult, sponsorResult, deArrowResult)
        guard !Task.isCancelled else { return }
        let player = await playerFetchTask.value

        guard !Task.isCancelled else { return }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))

        if let player { store(playerInfo: player, for: videoId) }
        let tracking: PlaybackTrackingURLs? = player?.trackingURLs
        store(trackingURLs: tracking, for: videoId)
        if let next { store(nextInfo: next, for: videoId) }
        if let cards { store(endCards: cards, for: videoId) }
        store(sponsorSegments: sponsor, for: videoId)
        if let dearrow { store(deArrowBranding: dearrow, for: videoId) }

        cacheLog.notice(
            "[prefetch] DONE \(videoId, privacy: .public) elapsed=\(elapsed, privacy: .public) playerInfo=\(player != nil, privacy: .public) tracking=\(tracking != nil, privacy: .public) next=\(next != nil, privacy: .public) endCards=\(cards != nil, privacy: .public) sponsor=\(sponsor.count, privacy: .public) deArrow=\(dearrow != nil, privacy: .public)"
        )
    }

    // MARK: - Private: LRU helpers

    private func touch(_ videoId: String) {
        accessOrder.removeAll { $0 == videoId }
        accessOrder.append(videoId)
        if accessOrder.count > Self.maxVideoEntries {
            let evict = accessOrder.removeFirst()
            cacheLog.notice(
                "[lru] EVICT \(evict, privacy: .public) — cache full (\(Self.maxVideoEntries, privacy: .public) entries)"
            )
            playerInfoCache.removeValue(forKey: evict)
            trackingCache.removeValue(forKey: evict)
            nextInfoCache.removeValue(forKey: evict)
            endCardsCache.removeValue(forKey: evict)
            sponsorCache.removeValue(forKey: evict)
            deArrowCache.removeValue(forKey: evict)
            wkHLSCache.removeValue(forKey: evict)
            cancelPrefetch(for: evict)
        }
    }

    private func freshWKHLS(for videoId: String) -> WKHLSCacheEntry? {
        guard let entry = wkHLSCache[videoId] else { return nil }
        guard wkHLSNow().timeIntervalSince(entry.storedAt) <= Self.wkHLSTTL else {
            wkHLSCache.removeValue(forKey: videoId)
            return nil
        }
        touch(videoId)
        return entry
    }

    private func fresh<T: Sendable>(_ entry: CacheEntry<T>?) -> T? {
        guard let entry, !entry.isExpired else { return nil }
        return entry.value
    }

    /// Returns the cached value regardless of expiry, adding `dataType` to `staleFields`
    /// if the entry is expired. Returns `nil` only when no entry exists at all.
    private func staleOrFresh<T: Sendable>(
        _ entry: CacheEntry<T>?,
        dataType: CachedVideoData.DataType,
        into staleFields: inout Set<CachedVideoData.DataType>
    ) -> T? {
        guard let entry else { return nil }
        if entry.isExpired { staleFields.insert(dataType) }
        return entry.value
    }
}

// MARK: - Playback demand and queue scheduling

extension VideoPreloadCache {
    public func observePlaybackDemand(_ demand: PlaybackDemandCoordinator) async {
        guard demandTask == nil else { return }
        let changes = await demand.changes()
        guard demandTask == nil else { return }
        demandTask = Task { [weak self] in
            for await yielding in changes {
                guard !Task.isCancelled else { return }
                await self?.setPlaybackYielding(yielding)
            }
        }
    }

    func setPlaybackYielding(_ yielding: Bool) {
        guard isYieldingToPlayback != yielding else { return }
        isYieldingToPlayback = yielding
        if yielding {
            for (videoID, request) in activeRequests {
                // Only optional children are cancelled. The shared stream task survives promotion.
                prefetchTasks[videoID]?.cancel()
                if !prefetchQueue.contains(where: { $0.videoId == videoID }) {
                    prefetchQueue.append(request)
                }
            }
            prefetchQueue.sort {
                $0.priority == $1.priority ? $0.enqueuedAt < $1.enqueuedAt : $0.priority > $1.priority
            }
            prefetchQueue = Array(prefetchQueue.prefix(Self.maxQueueDepth))
        } else {
            drainQueue()
        }
    }

    /// Starts worker tasks up to the current cap until the queue is empty.
    /// Called by `prefetch()` and by each worker on completion.
    func drainQueue(workerCap: Int? = nil) {
        let cap = workerCap ?? networkCap
        guard cap > 0, !isYieldingToPlayback else { return }
        while activeWorkerCount < cap,
            let index = prefetchQueue.firstIndex(where: { request in
                guard prefetchTasks[request.videoId] == nil else { return false }
                // Cancelled workers may leave streams owned by foreground consumers.
                let occupied = Set(inFlightPlayerFetches.keys).union(activeRequests.keys)
                return occupied.contains(request.videoId)
                    || fresh(playerInfoCache[request.videoId]) != nil || occupied.count < cap
            })
        {
            let request = prefetchQueue.remove(at: index)
            activeWorkerCount += 1
            let workerID = UUID()
            workerIDs[request.videoId] = workerID
            activeRequests[request.videoId] = request
            let task = Task(priority: .background) {
                await self.runPrefetch(
                    videoId: request.videoId,
                    sponsorCategories: request.sponsorCategories,
                    authToken: request.authToken
                )
                self.activeWorkerCount = max(0, self.activeWorkerCount - 1)
                if self.workerIDs[request.videoId] == workerID {
                    self.prefetchTasks.removeValue(forKey: request.videoId)
                    self.activeRequests.removeValue(forKey: request.videoId)
                    self.workerIDs.removeValue(forKey: request.videoId)
                }
                self.drainQueue()
            }
            prefetchTasks[request.videoId] = task
        }
    }

}

// MARK: - CachedVideoData

/// A snapshot of whatever pre-fetched data is available for a video.
/// Fields that are `nil` were not cached or have expired — callers must fetch those live.
/// Fields in `staleFields` have data but are past their TTL — callers can use the stale
/// value immediately and revalidate in the background (stale-while-revalidate pattern).
public struct CachedVideoData: Sendable {

    /// SWR-eligible data types. `playerInfo` and `trackingURLs` are NOT SWR-eligible
    /// (CDN/token-bound — stale stream URLs cause 403; stale tokens cause auth failures).
    public enum DataType: CaseIterable, Sendable {
        case nextInfo, endCards, sponsorSegments, deArrowBranding
    }

    public let playerInfo: PlayerInfo?
    public let trackingURLs: PlaybackTrackingURLs??  // outer nil = not cached, inner nil = cached as "no URLs"
    public let nextInfo: NextInfo?
    public let endCards: [EndCard]?
    public let sponsorSegments: [SponsorSegment]?
    public let deArrowBranding: DeArrowService.BrandingInfo?
    /// Data types that are present but past their TTL. Non-empty means the value was
    /// returned stale and a background revalidation fetch should be scheduled.
    public var staleFields: Set<DataType>

    /// True when every field that is required for instant playback start is fresh.
    public var isComplete: Bool {
        playerInfo != nil && nextInfo != nil && sponsorSegments != nil
    }

    public init(
        playerInfo: PlayerInfo?,
        trackingURLs: PlaybackTrackingURLs??,
        nextInfo: NextInfo?,
        endCards: [EndCard]?,
        sponsorSegments: [SponsorSegment]?,
        deArrowBranding: DeArrowService.BrandingInfo?,
        staleFields: Set<DataType>
    ) {
        self.playerInfo = playerInfo
        self.trackingURLs = trackingURLs
        self.nextInfo = nextInfo
        self.endCards = endCards
        self.sponsorSegments = sponsorSegments
        self.deArrowBranding = deArrowBranding
        self.staleFields = staleFields
    }
}
