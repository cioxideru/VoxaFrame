import Foundation
import Observation
import os

internal let browseLog = ViewModelLogger(category: "Browse")

// MARK: - BrowseError

public enum BrowseError: LocalizedError {
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "The feed took too long to load. Check your connection and try again."
        }
    }
}

// MARK: - BrowseViewModel
//
// Drives the main browse screen.  Mirrors the Android `BrowsePresenter`.

@MainActor
@Observable
public final class BrowseViewModel {

    // MARK: - State

    public private(set) var sections: [BrowseSection] = BrowseSection.defaultSections
    public private(set) var currentSection: BrowseSection = BrowseSection.defaultSections[0]
    public internal(set) var videoGroups: [VideoGroup] = []
    /// Populated when the current section is `.channels`; empty for all other sections.
    public internal(set) var subscribedChannels: [Channel] = []
    public private(set) var changingSubscriptionIDs: Set<String> = []
    public private(set) var isLoading: Bool = false
    /// True while a pagination (loadMore) request is in flight. Distinct from `isLoading`,
    /// which covers the initial/refresh fetch. Keeping these separate prevents the preload
    /// cache work that follows the initial fetch from blocking subsequent loadMore calls.
    public private(set) var isLoadingMore: Bool = false
    public var error: Error?
    /// True when the current section requires authentication and the user is not signed in.
    public internal(set) var isAuthRequired: Bool = false
    /// Timestamp of the last successful content fetch for the current section.
    /// Used to detect stale feeds after the app returns from background.
    public private(set) var loadedAt: Date? = nil
    /// A video to open immediately via deeplink / URL interception.
    /// Cleared by the UI after the player is presented.
    public var deepLinkedVideo: Video?
    // MARK: - Dependencies

    internal let api: any InnerTubeAPIProtocol
    internal let localHistory: LocalWatchHistoryStore
    internal let watchLaterMembership: WatchLaterMembershipStore
    private var fetchTask: Task<Void, Never>?
    /// The last error came from the next page; `retryAfterError()` fetches that page again.
    @ObservationIgnored private var nextPageFailed = false
    internal var enrichTask: Task<Void, Never>?
    /// When `false`, the History section returns empty content rather than fetching from YouTube.
    private var historyEnabled: Bool = true
    /// True when a non-nil auth token has been set via updateAuthToken(_:).
    /// Used to select between the authenticated YouTube endpoints and the local RSS feed path.
    internal var hasAuthToken: Bool = false
    private var hideObserverTasks: [Task<Void, Never>] = []

    public init(
        api: any InnerTubeAPIProtocol = InnerTubeAPI(), initialSection: BrowseSection? = nil,
        localHistory: LocalWatchHistoryStore = .shared,
        watchLaterMembership: WatchLaterMembershipStore = .shared
    ) {
        self.localHistory = localHistory
        self.watchLaterMembership = watchLaterMembership
        self.api = api
        if let initial = initialSection {
            // Ensure the initial section appears in the picker list.
            if !sections.contains(initial) {
                sections = [initial] + sections
            }
            currentSection = initial
        }
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
                for await note in NotificationCenter.default.notifications(named: .watchLaterDidChange) {
                    guard let self, let videoId = note.userInfo?["videoId"] as? String else { continue }
                    self.applyWatchLaterChange(videoId: videoId, added: note.userInfo?["added"] as? Bool ?? false)
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
        for i in videoGroups.indices {
            videoGroups[i].videos.removeAll { $0.id == id }
        }
    }

    /// Keeps an open Watch Later section in step with adds/removes made in this app, instead
    /// of waiting for a refresh (and YouTube's index) — #157.
    func applyWatchLaterChange(videoId: String, added: Bool) {
        guard currentSection.type == .watchLater else { return }
        if !added {
            removeVideo(id: videoId)
            return
        }
        guard let video = watchLaterMembership.savedVideo(videoId),
            !videoGroups.contains(where: { $0.videos.contains { $0.id == videoId } })
        else { return }
        if videoGroups.isEmpty {
            videoGroups = [VideoGroup(title: BrowseSection.SectionType.watchLater.defaultTitle, videos: [video])]
        } else {
            videoGroups[0].videos.insert(video, at: 0)
        }
    }

    public func removeChannel(id: String) {
        for i in videoGroups.indices {
            videoGroups[i].videos.removeAll { $0.channelId == id }
        }
    }

    // MARK: - Section selection

    public func select(section: BrowseSection) {
        guard section != currentSection else {
            browseLog.notice("select: already on section \(section.title) — ignored")
            return
        }
        let fromTitle = currentSection.title
        browseLog.notice("select: switching to \(section.title) from \(fromTitle)")
        currentSection = section
        loadContent(for: section, refresh: true, source: "select")
    }

    /// Reloads the given section unconditionally, bypassing the same-section guard in `select`.
    /// Use this to retry a failed/empty fetch or to recover from an observation gap.
    public func reload(section: BrowseSection) {
        browseLog.notice("reload: forcing refresh of \(section.title)")
        currentSection = section
        loadContent(for: section, refresh: true, source: "reload")
    }

    public func refreshChannels() async {
        loadContent(refresh: false, source: "refreshChannels")
        await fetchTask?.value
    }

    public func unsubscribe(from channel: Channel, signedIn: Bool) async {
        guard changingSubscriptionIDs.insert(channel.id).inserted else { return }
        defer { changingSubscriptionIDs.remove(channel.id) }
        error = nil
        do {
            try await api.changeSubscription(channel: channel, subscribed: false, signedIn: signedIn)
            if signedIn == hasAuthToken { applySubscriptionChange(channel: channel, subscribed: false) }
        } catch {
            self.error = error
        }
    }

    public func applySubscriptionChange(channel: Channel, subscribed: Bool) {
        guard currentSection.type == .channels || currentSection.type == .subscriptions else { return }
        fetchTask?.cancel()
        enrichTask?.cancel()
        isLoading = false
        isLoadingMore = false
        loadedAt = nil
        if currentSection.type == .channels {
            subscribedChannels.removeAll { $0.id == channel.id }
            if subscribed {
                var updated = channel
                updated.isSubscribed = true
                subscribedChannels.append(updated)
                subscribedChannels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        } else {
            loadContent(refresh: true, source: "subscriptionChanged")
        }
    }

    /// Rebuilds the visible sections list from settings.
    /// Call this when AppSettings.enabledSections changes.
    public func configureSections(_ enabledTypes: [BrowseSection.SectionType]) {
        let allSections = BrowseSection.allSections
        let ordered = enabledTypes.compactMap { type in allSections.first { $0.type == type } }
        sections = ordered.isEmpty ? BrowseSection.defaultSections : ordered
        // If current section is no longer in the list, switch to first
        if !sections.contains(currentSection), let first = sections.first {
            currentSection = first
        }
    }

    // MARK: - Loading

    public func loadContent(for section: BrowseSection? = nil, refresh: Bool = false, source: String = "unknown") {
        error = nil
        nextPageFailed = false
        let target = section ?? currentSection
        let chCount = subscribedChannels.count
        let vCount = videoGroups.flatMap(\.videos).count
        let loading = isLoading
        browseLog.notice(
            "loadContent source=\(source) section=\(target.title) refresh=\(refresh) channels=\(chCount) videos=\(vCount) loading=\(loading)"
        )
        if refresh {
            videoGroups = []
            subscribedChannels = []
            loadedAt = nil
            enrichTask?.cancel()
            enrichTask = nil
        }
        fetchTask?.cancel()
        isLoading = true
        fetchTask = Task { await fetchSection(target) }
    }

    public func loadMoreIfNeeded(lastVideo: Video) {
        // Use `contains` instead of `==` on the raw last video: when "Hide Shorts" is on,
        // the caller's last visible video may not be the raw last video (the raw last video
        // might be a Short that was filtered out). The user has reached the end of filtered
        // content as long as their last visible video appears anywhere in the last raw group.
        guard let lastGroup = videoGroups.last,
            lastGroup.videos.contains(where: { $0.id == lastVideo.id }),
            lastGroup.nextPageToken != nil,
            // Not during a reload: the cards it keeps on screen would page the old feed into the new one.
            !isLoading, !isLoadingMore
        else {
            let hasToken = videoGroups.last?.nextPageToken != nil
            let lastVideoInGroup = videoGroups.last?.videos.contains(where: { $0.id == lastVideo.id }) == true
            browseLog.notice(
                "loadMore skipped: section=\(currentSection.title) isLoading=\(isLoading) isLoadingMore=\(isLoadingMore) hasToken=\(hasToken) lastVideoMatch=\(lastVideoInGroup)"
            )
            return
        }
        browseLog.notice(
            "loadMore triggered: section=\(currentSection.title) currentCount=\(videoGroups.first?.videos.count ?? 0)")
        isLoadingMore = true  // synchronous guard — prevents duplicate pagination tasks before the Task body runs
        fetchTask = Task { await fetchNextPage(for: currentSection) }
    }

    /// Try Again after an error over a loaded feed: fetches the failed next page again, or reloads the section.
    /// Either way the loaded videos stay on screen until new ones arrive.
    public func retryAfterError() {
        guard !isLoading, !isLoadingMore else { return }
        guard nextPageFailed, videoGroups.last?.nextPageToken != nil else {
            loadContent(source: "retryAfterError")
            return
        }
        error = nil
        isLoadingMore = true
        fetchTask = Task { await fetchNextPage(for: currentSection) }
    }

    public var hasMoreShorts: Bool {
        currentSection.type == .shorts && videoGroups.last?.nextPageToken != nil
    }

    /// Empty account pages still have a continuation, even without a last visible card.
    public func loadMoreShorts() {
        guard hasMoreShorts, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        fetchTask = Task { await fetchNextPage(for: currentSection) }
    }

    /// Refreshes the current section's feed if the last successful fetch was more than
    /// `threshold` seconds ago (default 15 min). The first load belongs to sign-in or selection.
    public func refreshIfStale(threshold: TimeInterval = 15 * 60) {
        guard fetchTask != nil, !isLoading else { return }
        let age = loadedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age > threshold else { return }
        let ageDesc = age.isFinite ? "\(Int(age))s" : "never loaded"
        browseLog.notice(
            "refreshIfStale: age=\(ageDesc) > threshold=\(Int(threshold))s — refreshing \(currentSection.title)")
        loadContent(refresh: true, source: "refreshIfStale")
    }

    /// Update whether history is enabled. If currently on the history section, reloads it.
    public func updateHistoryEnabled(_ enabled: Bool) {
        guard historyEnabled != enabled else { return }
        historyEnabled = enabled
        if currentSection.type == .history {
            loadContent(refresh: true, source: "updateHistoryEnabled")
        }
    }

    // MARK: - Auth

    /// Reloads on sign-in, preserving the feed when an existing session refreshes its token.
    /// Sets the token on the API first so that the fetch always runs authenticated.
    public func updateAuthToken(_ token: String?, reloadOnSignIn: Bool = true) async {
        let wasAuthenticated = hasAuthToken
        hasAuthToken = token != nil
        await api.setAuthToken(token)
        if token != nil && !wasAuthenticated && reloadOnSignIn {
            loadContent(refresh: true, source: "updateAuthToken")
        } else if token == nil && wasAuthenticated {
            // Signed out — reload account sections to show local content instead. This also cancels their
            // account requests and drops the account's records (History, playlists) before a guest sees them.
            let authSections: Set<BrowseSection.SectionType> = [
                .subscriptions, .channels, .shorts, .history, .playlists, .watchLater,
            ]
            if authSections.contains(currentSection.type) {
                loadContent(refresh: true, source: "updateAuthToken.signOut")
            }
        }
    }

}

extension BrowseViewModel {

    // MARK: - Private fetching

    private static var fetchTimeoutSeconds: TimeInterval {
        ProcessInfo.processInfo.arguments.contains("--uitesting-extended-fetch-timeout") ? 60 : 20
    }

    private func fetchSection(_ section: BrowseSection) async {
        guard !Task.isCancelled else { return }
        defer { if !Task.isCancelled { isLoading = false } }
        browseLog.notice("Fetching section: \(section.title) (\(String(describing: section.type)))")
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.fetchSectionBody(section) }
                group.addTask {
                    try await Task.sleep(for: .seconds(Self.fetchTimeoutSeconds))
                    throw BrowseError.timeout
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            if !Task.isCancelled {
                let authSections: Set<BrowseSection.SectionType> = [.subscriptions, .history, .playlists, .channels]
                if let apiErr = error as? APIError,
                    case .httpError(let code) = apiErr,
                    (code == 401 || code == 403),
                    authSections.contains(section.type)
                {
                    isAuthRequired = true
                    self.error = error
                    browseLog.notice("Auth required for \(section.title) (HTTP \(code))")
                } else {
                    isAuthRequired = false
                    if case BrowseError.timeout = error {
                        browseLog.error("⏱ \(section.title) timed out after \(Int(Self.fetchTimeoutSeconds))s")
                    } else {
                        browseLog.error("❌ \(section.title) error: \(ViewModelLogger.errorSummary(error))")
                    }
                    self.error = error
                }
            }
        }
    }

    private func fetchSectionBody(_ section: BrowseSection) async throws {
        switch section.type {

        case .home, .recommended:
            try await fetchHomeSection()

        case .subscriptions:
            try await fetchSubscriptionsSection()

        case .history:
            guard historyEnabled else {
                if !Task.isCancelled {
                    videoGroups = []
                    isAuthRequired = false
                }
                return
            }
            try await fetchHistorySection()

        case .playlists:
            try await fetchPlaylistsSection()

        case .channels:
            try await fetchChannelsSection()

        case .shorts:
            let group = try await fetchShortsGroup()
            if !Task.isCancelled {
                videoGroups = group.videos.isEmpty && group.nextPageToken == nil ? [] : [group]
            }

        case .music:
            let group = try await api.fetchMusic()
            if !Task.isCancelled { videoGroups = [group] }

        case .gaming:
            let group = try await api.fetchGaming()
            if !Task.isCancelled { videoGroups = [group] }

        case .news:
            let group = try await api.fetchNews()
            if !Task.isCancelled { videoGroups = [group] }

        case .live:
            let group = try await api.fetchLive()
            if !Task.isCancelled { videoGroups = [group] }

        case .sports:
            let group = try await api.fetchSports()
            if !Task.isCancelled { videoGroups = [group] }

        case .watchLater:
            try await fetchWatchLaterSection()

        case .settings:
            break
        }
        if !Task.isCancelled { loadedAt = Date() }
    }

    private func fetchNextPage(for section: BrowseSection, autoChainDepth: Int = 0) async {
        guard let token = videoGroups.last?.nextPageToken else { return }
        isLoadingMore = true
        // Any new attempt at the page (Try Again or scrolling) replaces the error of the one that failed.
        if nextPageFailed { error = nil }
        nextPageFailed = false
        defer { isLoadingMore = false }
        do {
            if section.type == .home || section.type == .recommended {
                try await fetchNextHomePage(token: token)
                return
            }
            let group = try await retryWithBackoff(label: "BrowseVM[\(section.title)]") {
                try await self.fetchContinuationGroup(for: section.type, token: token)
            }
            guard !Task.isCancelled, let group else { return }
            // Append in server order so existing cards stay in place while scrolling.
            mergeIntoFirstGroup(group)
            // Hidden Shorts do not advance the History sentinel, so keep looking for regular videos.
            if section.type == .history, autoChainDepth < 5,
                group.videos.allSatisfy(\.isShort), group.nextPageToken != nil
            {
                await fetchNextPage(for: section, autoChainDepth: autoChainDepth + 1)
            }
        } catch {
            if !Task.isCancelled {
                browseLog.error("fetchNextPage \(section.title): \(ViewModelLogger.errorSummary(error))")
                self.error = error
                nextPageFailed = true
            }
        }
    }

    private func fetchContinuationGroup(for type: BrowseSection.SectionType, token: String) async throws -> VideoGroup?
    {
        switch type {
        case .subscriptions:
            return try await api.fetchSubscriptions(continuationToken: token)
        case .history:
            return try await api.fetchHistory(continuationToken: token)
        case .shorts:
            return try await fetchShortsGroup(continuationToken: token)
        case .music:
            return try await api.fetchMusic()
        case .gaming:
            return try await api.fetchGaming()
        case .news:
            return try await api.fetchNews()
        case .live:
            return try await api.fetchLive()
        case .sports:
            return try await api.fetchSports()
        default:
            return nil
        }
    }

    /// Appends `group.videos` into `videoGroups[0]` and updates its pagination token.
    /// Falls back to inserting `group` as a new group if none exist yet.
    private func mergeIntoFirstGroup(_ group: VideoGroup) {
        if videoGroups.isEmpty {
            videoGroups.append(group)
        } else {
            // Use a growing set so duplicate IDs within group.videos itself
            // (same video appearing twice in one page) are also caught.
            var seenIds = Set(videoGroups[0].videos.map(\.id))
            let newVideos = group.videos.filter { seenIds.insert($0.id).inserted }
            videoGroups[0].videos.append(contentsOf: newVideos)
            videoGroups[0].nextPageToken = group.nextPageToken
        }
    }

    /// Returns `videos` with duplicate IDs removed, preserving first-occurrence order.
    internal func deduplicated(_ videos: [Video]) -> [Video] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Channel avatar enrichment

    /// Concurrently fetches the avatar thumbnail URL for each subscribed channel and
    /// patches it into `subscribedChannels` as results arrive.
    ///
    /// If a subscription tab omits its avatar, fetch the channel's About tab. Requests are fired
    /// concurrently. The task is cancelled automatically when the user leaves the
    /// Channels section (enrichTask?.cancel() in loadContent).
    internal func enrichChannelAvatars() async {
        let snapshot = subscribedChannels
        guard !snapshot.isEmpty else { return }
        let missing = snapshot.filter { $0.thumbnailURL == nil }
        guard !missing.isEmpty else { return }
        browseLog.notice("enrichChannelAvatars: fetching avatars for \(missing.count) channels")

        let apiRef = api
        await withTaskGroup(of: (String, URL?).self) { group in
            for channel in missing {
                guard !Task.isCancelled else { break }
                let channelId = channel.id
                group.addTask {
                    let url = try? await apiRef.fetchChannelThumbnailURL(channelId: channelId)
                    return (channelId, url)
                }
            }
            for await (channelId, thumbURL) in group {
                guard !Task.isCancelled else { break }
                guard let thumbURL,
                    let idx = self.subscribedChannels.firstIndex(where: { $0.id == channelId })
                else { continue }
                self.subscribedChannels[idx].thumbnailURL = thumbURL
            }
        }

        let finalCount = self.subscribedChannels.filter { $0.thumbnailURL != nil }.count
        let total = self.subscribedChannels.count
        browseLog.notice("enrichChannelAvatars done: \(finalCount)/\(total) have avatars")
    }
}
