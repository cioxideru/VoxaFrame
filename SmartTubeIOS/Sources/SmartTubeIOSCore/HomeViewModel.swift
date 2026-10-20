import Foundation
import Observation
import os

private let homeLog = ViewModelLogger(category: "Home")

// MARK: - HomeViewModel
//
// Home shows only YouTube's own recommendations (the TV home feed). The subscriptions
// shelf is still loaded, but only as a source of account Shorts for the Shorts rows;
// its regular videos never enter the Home feed (the Subscriptions chip shows them).

@MainActor
@Observable
public final class HomeViewModel {

    // MARK: - Section state

    public struct SectionState: Identifiable {
        public let section: BrowseSection
        public var videos: [Video] = []
        public var isLoading: Bool = true
        public var isLoadingMore: Bool = false
        public var hasFailed: Bool = false
        public var nextPageToken: String? = nil
        public var id: String { section.id }
    }

    // MARK: - State

    public private(set) var sections: [SectionState]
    /// Extra discovery Shorts for signed-out browsing. Account Shorts reuse the loaded shelves.
    public private(set) var shortsVideos: [Video] = []
    /// Continuation for the signed-out discovery source.
    private var shortsNextPageToken: String? = nil
    private var isLoadingMoreShorts: Bool = false
    private var requestedShortsCount = 0
    /// Shorts paging started by `loadShorts(atLeast:)`. Cancelled on the next `load()`.
    private var shortsPreloadTask: Task<Void, Never>? = nil
    public private(set) var isRefreshing: Bool = false
    /// Publishes the current Home result, including an empty result when the session clears.
    @ObservationIgnored public var onHomeLoaded: (@MainActor ([Video]) -> Void)?
    private var sessionID = 0
    private var authRevision = 0
    private var isUpdatingAuth = false
    /// Timestamp of the last successful load. Used for staleness checks.
    public private(set) var loadedAt: Date? = nil
    /// The recommendations feed shown on Home. Replaced once a load completes and
    /// appended to during pagination without ever reordering existing items.
    public private(set) var mergedVideos: [Video] = []
    /// Bumped whenever `mergedVideos` is replaced rather than appended to, so the view can
    /// reset layout state tied to positions in the old feed.
    public private(set) var feedGeneration = 0

    // MARK: - Shelf definitions (in display order)

    public static let shelfSections: [BrowseSection] = [
        BrowseSection(id: BrowseSection.SectionType.home.rawValue, title: "Recommended", type: .home),
        BrowseSection(
            id: BrowseSection.SectionType.subscriptions.rawValue, title: "Subscriptions", type: .subscriptions),
    ]

    /// `true` while either shelf is still on its initial load (no videos yet).
    /// Used by the view to show a spinner.
    public var isLoadingAny: Bool {
        sections.contains { $0.isLoading }
    }

    /// The recommendations shelf, which alone feeds `mergedVideos` and its pagination.
    public var recommendations: SectionState? { sections.first { $0.section.type == .home } }

    /// Rebuilds `mergedVideos` from the recommendations shelf once a load completes, so
    /// mid-load arrivals never rearrange rendered cards. Pagination appends instead.
    private func rebuildMergedVideos() {
        feedGeneration += 1
        let recs = recommendations?.videos ?? []
        var seen = Set<String>()
        // Duplicate IDs would make SwiftUI's ForEach render blank cells.
        mergedVideos = recs.filter { seen.insert($0.id).inserted }
        if mergedVideos.count != recs.count {
            homeLog.notice(
                "rebuildMergedVideos: dedup removed \(recs.count - mergedVideos.count) duplicate(s) (raw=\(recs.count))"
            )
        }
    }

    /// Non-Short videos from the recommendations feed.
    /// Used by `homeShelves` to populate the main grid (Shorts are shown separately).
    public var homeRegularVideos: [Video] { mergedVideos.filter { !$0.isShort } }

    /// Account recommendations and subscriptions take precedence over signed-out discovery.
    public var homeShortsVideos: [Video] {
        let homeShorts = sections.first { $0.section.type == .home }?.videos.filter(\.isShort) ?? []
        let subsShorts = sections.first { $0.section.type == .subscriptions }?.videos.filter(\.isShort) ?? []
        var seen = Set<String>()
        return (homeShorts + subsShorts + shortsVideos).filter { seen.insert($0.id).inserted }
    }

    // MARK: - Dependencies

    private let api: any InnerTubeAPIProtocol
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var hideObserverTasks: [Task<Void, Never>] = []
    /// Tracks whether a non-nil auth token has been set. Used to distinguish a
    /// sign-in event (nil → non-nil) from a token refresh (non-nil → new non-nil)
    /// so that token refreshes during video playback do not trigger a feed reload.
    private var hasAuthToken: Bool = false

    public init(api: any InnerTubeAPIProtocol = InnerTubeAPI()) {
        self.api = api
        self.sections = Self.shelfSections.map { SectionState(section: $0) }
        observeFeedHideNotifications()
    }

    // MARK: - Feed hide handling

    private func observeFeedHideNotifications() {
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideVideoFromFeed) {
                    guard let self, let videoId = note.userInfo?["videoId"] as? String else { continue }
                    self.removeVideo(id: videoId)
                }
            })
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideChannelFromFeed) {
                    guard let self, let channelId = note.userInfo?["channelId"] as? String else { continue }
                    self.removeChannel(id: channelId)
                }
            })
    }

    public func removeVideo(id: String) {
        for i in sections.indices {
            sections[i].videos.removeAll { $0.id == id }
        }
        mergedVideos.removeAll { $0.id == id }
    }

    public func removeChannel(id: String) {
        for i in sections.indices {
            sections[i].videos.removeAll { $0.channelId == id }
        }
        mergedVideos.removeAll { $0.channelId == id }
    }

    /// Cancels all in-flight and background work (the main load task, the
    /// Shorts paging, and the feed-hide notification observers). Callers
    /// that create short-lived `HomeViewModel` instances — e.g. tests — should
    /// call this when done to avoid orphaned tasks bleeding state into later use.
    public func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        shortsPreloadTask?.cancel()
        hideObserverTasks.forEach { $0.cancel() }
    }

    // MARK: - Public API

    public func load() {
        startLoad(keepingContent: false)
    }

    /// Pull to refresh: reloads while the current feed stays on screen, and returns once the
    /// new feed has replaced it.
    public func refresh() async {
        startLoad(keepingContent: true)
        await loadTask?.value
    }

    private func startLoad(keepingContent: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        shortsPreloadTask?.cancel()
        loadedAt = nil
        shortsNextPageToken = nil
        isLoadingMoreShorts = false
        requestedShortsCount = 0
        isRefreshing = true
        recommendationsStalled = false
        if !keepingContent {
            shortsVideos = []
            mergedVideos = []
            feedGeneration += 1
        }
        for i in sections.indices {
            if !keepingContent { sections[i].videos = [] }
            sections[i].isLoading = true
            sections[i].isLoadingMore = false
            sections[i].hasFailed = false
            sections[i].nextPageToken = nil
        }

        loadTask = Task {
            guard isCurrentLoad(generation) else { return }
            // Signed-in Shorts reuse the account shelves instead of fetching subscriptions twice.
            async let fetchedShortsResult: ([Video], String?) = HomeViewModel.fetchShortsVideos(
                api: self.api, hasAccount: hasAuthToken)

            await withTaskGroup(of: (String, [Video], String?).self) { group in
                for state in sections {
                    let sectionId = state.id
                    let type = state.section.type
                    let api = self.api
                    group.addTask {
                        let (videos, token) = await HomeViewModel.fetchVideos(type: type, api: api)
                        return (sectionId, videos, token)
                    }
                }
                for await (sectionId, videos, token) in group {
                    guard isCurrentLoad(generation) else { break }
                    if let idx = sections.firstIndex(where: { $0.id == sectionId }) {
                        sections[idx].videos = videos
                        sections[idx].nextPageToken = token
                        sections[idx].isLoading = false
                        sections[idx].hasFailed = videos.isEmpty
                        // Show recommendations as soon as they arrive, before the
                        // subscriptions shelf (Shorts only) finishes.
                        if sections[idx].section.type == .home, mergedVideos.isEmpty, !videos.isEmpty {
                            mergedVideos = videos
                        }
                    }
                }
            }
            guard isCurrentLoad(generation) else { return }
            // Both shelves are loaded: one atomic swap to the deduplicated recommendations.
            rebuildMergedVideos()
            let (fetchedShorts, nextToken) = await fetchedShortsResult
            guard isCurrentLoad(generation) else { return }
            shortsVideos = fetchedShorts
            shortsNextPageToken = nextToken
            // Fill the initial threshold (6 iOS / 8 tvOS) quickly.
            // Further pages load as the Home feed's video blocks scroll into view (loadShorts).
            await loadMoreShortsIfNeeded(generation: generation)
            guard isCurrentLoad(generation) else { return }
            isRefreshing = false
            loadedAt = Date()
            onHomeLoaded?(mergedVideos)
            resumeShortsDemand()
            // No regular card means no scroll trigger: continue the recommendations right away.
            if homeRegularVideos.isEmpty { loadMoreMerged() }
            let merged = self.mergedVideos
            let mergedShorts = merged.filter { $0.isShort }.count
            homeLog.notice(
                "load complete: merged=\(merged.count) regular=\(merged.count - mergedShorts) mergedShorts=\(mergedShorts) shortsSection=\(shortsVideos.count)"
            )
        }
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    public func updateAuthToken(_ token: String?, signedIn: Bool? = nil, sessionID: Int = 0) async {
        authRevision += 1
        let revision = authRevision
        isUpdatingAuth = true
        defer {
            if revision == authRevision { isUpdatingAuth = false }
        }
        var authenticated = (signedIn ?? true) && token != nil
        #if DEBUG
        if signedIn == true,
            HomePaginationUITestFixture.isEnabled || !HomePaginationUITestFixture.injectedRecommendationIDs.isEmpty
        {
            authenticated = true
        }
        #endif
        let changedSession = self.sessionID != sessionID
        let needsLoad = authenticated && (!hasAuthToken || changedSession || (loadedAt == nil && !isRefreshing))
        self.sessionID = sessionID
        hasAuthToken = authenticated
        if !authenticated || changedSession {
            loadGeneration += 1
            loadTask?.cancel()
            shortsPreloadTask?.cancel()
            sections = Self.shelfSections.map { SectionState(section: $0, isLoading: false) }
            mergedVideos = []
            recommendationsStalled = false
            shortsVideos = []
            shortsNextPageToken = nil
            requestedShortsCount = 0
            isLoadingMoreShorts = false
            isRefreshing = false
            loadedAt = nil
            feedGeneration += 1
            onHomeLoaded?([])
        }
        await api.setAuthToken(token)
        guard revision == authRevision, !Task.isCancelled else { return }
        if needsLoad && !isRefreshing { load() }
    }

    /// Refreshes both shelves if the last successful load was more than
    /// `threshold` seconds ago (default 15 min). No-op while loading.
    public func refreshIfStale(threshold: TimeInterval = 15 * 60) {
        guard hasAuthToken, !isUpdatingAuth, !isRefreshing else { return }
        let age = loadedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age > threshold else { return }
        let ageDesc = age.isFinite ? "\(Int(age))s" : "never loaded"
        homeLog.notice("refreshIfStale: age=\(ageDesc) — reloading shelves")
        load()
    }

    // MARK: - Pagination

    @discardableResult
    public func loadMore(sectionId: String) -> Task<Void, Never>? {
        guard let idx = sections.firstIndex(where: { $0.id == sectionId }),
            let token = sections[idx].nextPageToken,
            !sections[idx].isLoadingMore,
            !sections[idx].isLoading
        else { return nil }
        sections[idx].isLoadingMore = true
        let type = sections[idx].section.type
        let generation = loadGeneration
        return Task {
            var token = token
            var usedTokens: Set<String> = []
            var addedVideos = false
            var addedRegularVideo = false
            // A recommendations page that adds no new regular video (empty, duplicates, Shorts only) shows no new
            // card to trigger the next page, so continue here, a bounded number of times per request.
            for _ in 0..<Self.maxEmptyPagesPerRequest {
                guard isCurrentLoad(generation) else { return }
                usedTokens.insert(token)
                let (newVideos, fetchedToken) = await HomeViewModel.fetchMoreVideos(type: type, token: token, api: api)
                guard isCurrentLoad(generation), let idx = sections.firstIndex(where: { $0.id == sectionId })
                else { return }
                // A token already sent would repeat the same pages forever.
                let nextToken = fetchedToken.flatMap { usedTokens.contains($0) ? nil : $0 }
                // Use a growing set so IDs that appear multiple times within
                // newVideos itself (same page returning the same video twice)
                // are also caught — not just duplicates against existing videos.
                var seenIds = Set(sections[idx].videos.map(\.id))
                let deduplicated = newVideos.filter { seenIds.insert($0.id).inserted }
                sections[idx].videos.append(contentsOf: deduplicated)
                sections[idx].nextPageToken = nextToken
                // Do NOT sort after appending: reordering existing items shifts the
                // LazyVGrid under the user's scroll offset.
                // Only recommendations join the Home feed; subscription pages feed Shorts.
                guard type == .home else { break }
                let existingMergedIds = Set(mergedVideos.map(\.id))
                let added = deduplicated.filter { !existingMergedIds.contains($0.id) }
                mergedVideos.append(contentsOf: added)
                addedVideos = addedVideos || !added.isEmpty
                addedRegularVideo = added.contains { !$0.isShort }
                guard let nextToken, !addedRegularVideo else { break }
                token = nextToken
            }
            if let idx = sections.firstIndex(where: { $0.id == sectionId }) {
                sections[idx].isLoadingMore = false
                if type == .home {
                    // The scan limit ended with no new card to trigger the next page: the view offers More.
                    recommendationsStalled = !addedRegularVideo && sections[idx].nextPageToken != nil
                }
            }
            // Automatic paging can turn an empty or Shorts-only first page into the real feed.
            if type == .home, addedVideos { onHomeLoaded?(mergedVideos) }
            resumeShortsDemand()
        }
    }

    /// Recommendation pages fetched in a row while each adds no new regular video.
    static let maxEmptyPagesPerRequest = 3

    /// `true` when the last recommendations request reached `maxEmptyPagesPerRequest` without a new regular video
    /// while a continuation remains: no new card appears to trigger the next page, so the view shows More.
    public private(set) var recommendationsStalled = false

    /// Called by the Home feed when the user scrolls near the bottom: continues the
    /// recommendations feed.
    @discardableResult
    public func loadMoreMerged() -> Task<Void, Never>? {
        recommendations.flatMap { loadMore(sectionId: $0.id) }
    }

    /// Pages Shorts (search continuation, then subscriptions) until `homeShortsVideos` holds
    /// `count` items or both sources run out. The Home feed asks for as many as its Shorts rows
    /// need as video blocks scroll into view.
    public func loadShorts(atLeast count: Int) {
        requestedShortsCount = max(requestedShortsCount, count)
        resumeShortsDemand()
    }

    private func resumeShortsDemand() {
        guard !isRefreshing, !isLoadingMoreShorts, homeShortsVideos.count < requestedShortsCount,
            hasShortsSource
        else { return }
        if shortsNextPageToken == nil,
            let subscriptions = sections.first(where: { $0.section.type == .subscriptions }),
            subscriptions.isLoading || subscriptions.isLoadingMore
        {
            return
        }
        isLoadingMoreShorts = true
        let generation = loadGeneration
        shortsPreloadTask = Task { @MainActor [weak self] in
            guard let self, self.isCurrentLoad(generation) else { return }
            await self.fetchShortsPages(generation: generation)
            guard self.isCurrentLoad(generation) else { return }
            self.isLoadingMoreShorts = false
        }
    }

    private var hasShortsSource: Bool {
        shortsNextPageToken != nil || sections.first { $0.section.type == .subscriptions }?.nextPageToken != nil
    }

    private func fetchShortsPages(generation: Int) async {
        var pagesRemaining = InnerTubeClients.maxShortsPagesPerRequest
        while isCurrentLoad(generation), homeShortsVideos.count < requestedShortsCount, hasShortsSource,
            pagesRemaining > 0
        {
            pagesRemaining -= 1
            guard await fetchOneShortsPage(generation: generation) else {
                homeLog.notice("loadShorts: waiting for subscriptions or sources exhausted")
                break
            }
        }
        homeLog.notice("loadShorts: count=\(homeShortsVideos.count) target=\(requestedShortsCount)")
    }

    /// Fetches one increment of Shorts content: an anonymous search-continuation page
    /// if available, falling back to one subscriptions-continuation page if the
    /// search page is exhausted or returned nothing new. Search results land in
    /// `shortsVideos`; subs results land in `sections[subscriptions].videos` — both
    /// are surfaced together via `homeShortsVideos`. Regular subscription videos never
    /// reach the Home feed.
    /// Returns `true` if videos were appended or a continuation advanced.
    private func fetchOneShortsPage(generation: Int) async -> Bool {
        guard isCurrentLoad(generation) else { return false }
        // Phase 1: one search page (srch: token from fetchShorts).
        if let token = shortsNextPageToken {
            homeLog.notice("fetchOneShortsPage search: fetching token=\(String(token.prefix(16)))\u{2026}")
            do {
                let more = try await api.fetchShortsMore(continuationToken: token)
                guard isCurrentLoad(generation) else { return false }
                var seenIDs = Set(shortsVideos.map(\.id))
                let newVideos = more.videos.filter { seenIDs.insert($0.id).inserted }
                shortsVideos.append(contentsOf: newVideos)
                // Stop a non-advancing source, but keep looking through empty advancing pages.
                shortsNextPageToken = newVideos.isEmpty && more.nextPageToken == token ? nil : more.nextPageToken
                homeLog.notice(
                    "fetchOneShortsPage search: added \(newVideos.count) total=\(shortsVideos.count) hasMore=\(more.nextPageToken != nil)"
                )
                if !newVideos.isEmpty || shortsNextPageToken != nil {
                    return true
                }
                // Search page returned 0 new Shorts — fall through to Phase 2
            } catch {
                guard isCurrentLoad(generation) else { return false }
                homeLog.error("fetchOneShortsPage search: failed: \(ViewModelLogger.errorSummary(error))")
                shortsNextPageToken = nil
            }
        }
        // Phase 2: one subs page when search is exhausted or returned nothing new.
        // Skipped while the feed itself is paging subscriptions, so the two never consume the
        // same continuation token.
        if let idx = sections.firstIndex(where: { $0.section.type == .subscriptions }),
            let token = sections[idx].nextPageToken, !sections[idx].isLoadingMore, !sections[idx].isLoading
        {
            homeLog.notice("fetchOneShortsPage subs: fetching token=\(String(token.prefix(16)))\u{2026}")
            sections[idx].isLoadingMore = true
            let more = await Self.fetchMoreVideos(type: .subscriptions, token: token, api: api)
            guard isCurrentLoad(generation) else { return false }
            sections[idx].isLoadingMore = false
            var seenIDs = Set(sections[idx].videos.map(\.id))
            let newVideos = more.0.filter { seenIDs.insert($0.id).inserted }
            sections[idx].videos.append(contentsOf: newVideos)
            sections[idx].nextPageToken = newVideos.isEmpty && more.1 == token ? nil : more.1
            let newShorts = newVideos.filter { $0.isShort }.count
            homeLog.notice(
                "fetchOneShortsPage subs: added \(newVideos.count) (\(newShorts) shorts) hasMore=\(more.1 != nil)")
            return !newVideos.isEmpty || sections[idx].nextPageToken != nil
        }
        return false
    }

    /// Auto-loads an additional Shorts page if the current count falls below
    /// the threshold needed to fill 2 horizontal screens.
    /// iOS: ~3 cards/screen → threshold = 6; tvOS: ~4 cards/screen → threshold = 8.
    private func loadMoreShortsIfNeeded(generation: Int) async {
        guard isCurrentLoad(generation) else { return }
        #if os(tvOS)
        let threshold = 8
        #else
        let threshold = 6
        #endif
        if shortsNextPageToken != nil {
            requestedShortsCount = max(requestedShortsCount, threshold)
        }
        guard !isLoadingMoreShorts else { return }
        isLoadingMoreShorts = true
        defer {
            if isCurrentLoad(generation) { isLoadingMoreShorts = false }
        }
        await fetchShortsPages(generation: generation)
    }

}

extension HomeViewModel {

    // MARK: - Private fetch helpers

    /// Fetches signed-out discovery concurrently with the home/subs task group.
    private static func fetchShortsVideos(api: any InnerTubeAPIProtocol, hasAccount: Bool) async -> ([Video], String?) {
        guard !hasAccount else { return ([], nil) }
        do {
            let group = try await api.fetchShorts()
            let hasToken = group.nextPageToken != nil
            homeLog.notice("fetchShortsVideos → \(group.videos.count) shorts hasToken=\(hasToken)")
            return (group.videos, group.nextPageToken)
        } catch {
            homeLog.error("fetchShortsVideos failed: \(ViewModelLogger.errorSummary(error))")
            return ([], nil)
        }
    }

    /// Non-isolated so child tasks run on the global executor and network
    /// calls can overlap.
    private static func fetchVideos(
        type: BrowseSection.SectionType, api: any InnerTubeAPIProtocol
    ) async -> ([Video], String?) {
        do {
            switch type {
            case .subscriptions:
                let group = try await api.fetchSubscriptions()
                let shortsCount = group.videos.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchVideos subs: total=\(group.videos.count) shorts=\(shortsCount) regular=\(group.videos.count - shortsCount)"
                )
                return (initialShelfVideos(group.videos), group.nextPageToken)
            case .home:
                let rows = try await api.fetchHomeRows()
                let token = rows.last(where: { $0.nextPageToken != nil })?.nextPageToken
                var seen = Set<String>()
                let deduped = rows.flatMap(\.videos).filter { seen.insert($0.id).inserted }
                let fetchedShortsCount = deduped.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchVideos home: total=\(deduped.count) shorts=\(fetchedShortsCount) regular=\(deduped.count - fetchedShortsCount)"
                )
                // An empty account Home stays empty: no generic fallback replaces the recommendations.
                return (initialShelfVideos(deduped), token)
            default:
                return ([], nil)
            }
        } catch {
            homeLog.error("HomeViewModel fetch \(String(describing: type)): \(ViewModelLogger.errorSummary(error))")
            return ([], nil)
        }
    }

    /// Keep Shorts even when YouTube puts their shelf after the initial regular-video limit.
    private static func initialShelfVideos(_ videos: [Video]) -> [Video] {
        var regularCount = 0
        return videos.filter { video in
            if video.isShort { return true }
            regularCount += 1
            return regularCount <= InnerTubeClients.maxVideoResults
        }
    }

    private static func fetchMoreVideos(
        type: BrowseSection.SectionType, token: String, api: any InnerTubeAPIProtocol
    ) async -> ([Video], String?) {
        do {
            switch type {
            case .subscriptions:
                let group = try await retryWithBackoff(label: "HomeVM.subs") {
                    try await api.fetchSubscriptions(continuationToken: token)
                }
                let shortsCount = group.videos.filter { $0.isShort }.count
                homeLog.notice(
                    "fetchMoreVideos subs: total=\(group.videos.count) shorts=\(shortsCount) regular=\(group.videos.count - shortsCount)"
                )
                return (group.videos, group.nextPageToken)
            case .home:
                let rows = try await retryWithBackoff(label: "HomeVM.home") {
                    try await api.fetchHomeRows(continuationToken: token)
                }
                let nextToken = rows.last(where: { $0.nextPageToken != nil })?.nextPageToken
                // Dedup within the page — YouTube can return the same video ID
                // in multiple shelves of the same continuation response.
                var seen = Set<String>()
                let deduped = rows.flatMap(\.videos).filter { seen.insert($0.id).inserted }
                return (deduped, nextToken)
            default:
                return ([], nil)
            }
        } catch {
            homeLog.error("HomeViewModel loadMore \(String(describing: type)): \(ViewModelLogger.errorSummary(error))")
            return ([], nil)
        }
    }
}
