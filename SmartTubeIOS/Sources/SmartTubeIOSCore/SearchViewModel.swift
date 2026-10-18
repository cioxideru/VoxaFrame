import Foundation
import Observation
import os

private let searchLog = Logger(subsystem: appSubsystem, category: "Search")

// MARK: - SearchViewModel
//
// Mirrors the Android `SearchPresenter`.

@MainActor
@Observable
public final class SearchViewModel {

    /// What the results area shows; "no results" and "failed" are separate screens (A5).
    public enum Phase: Equatable, Sendable {
        /// Nothing submitted yet, or the query was cleared: recent searches and topics.
        case idle
        /// The first page of the submitted query is loading.
        case loading
        /// At least one result; a failed next page keeps them on screen.
        case results
        /// The request succeeded with no matches.
        case noResults
        /// The first page failed; `retry()` repeats it.
        case failed
    }

    public var query: String = ""
    public var filter: SearchFilter = .default
    public private(set) var results: [Video] = []
    public private(set) var suggestions: [String] = []
    public private(set) var history: [SearchHistoryEntry] = []
    public private(set) var isLoading: Bool = false
    /// The last request's failure; cleared when a request starts.
    public private(set) var error: Error?
    /// The query of the last submitted search. The field text may change after it.
    public private(set) var submittedQuery: String?
    /// The filters of the last submitted search, repeated by `retry()`.
    private var submittedFilter: SearchFilter = .default

    public var phase: Phase {
        if !results.isEmpty { return .results }
        if isLoading { return .loading }
        if error != nil { return .failed }
        return submittedQuery == nil ? .idle : .noResults
    }

    private let api: any InnerTubeAPIProtocol
    private let historyStore: SearchHistoryStore
    private var nextPageToken: String?
    private var searchTask: Task<Void, Never>?
    /// Owner of the search state: bumped by every first page, next page and clear.
    private var requestGeneration = 0
    private var suggestTask: Task<Void, Never>?
    private var hideObserverTasks: [Task<Void, Never>] = []

    private static let recommendedTerms: [String] = [
        "trending videos", "music 2025", "cooking recipes", "travel vlog",
        "programming tutorial", "workout", "movie trailer", "lofi hip hop",
        "documentary", "gaming highlights",
    ]

    /// History entries that match the current query (case-insensitive). Returns
    /// the full history when the query is empty.
    public var filteredHistory: [SearchHistoryEntry] {
        guard !query.isEmpty else { return history }
        return history.filter { $0.query.localizedCaseInsensitiveContains(query) }
    }

    public init(api: any InnerTubeAPIProtocol = InnerTubeAPI(), historyStore: SearchHistoryStore = .shared) {
        self.api = api
        self.historyStore = historyStore
        suggestions = Self.recommendedTerms
        Task { await loadHistory() }
        observeFeedHideNotifications()
    }

    /// Call from `.task(id: query)` in the view to debounce live suggestions.
    /// When `q` is empty, restores the recommended terms immediately.
    public func updateSuggestions(for q: String) async {
        searchLog.debug("[Suggestions] updateSuggestions called, q='\(q)'")
        if q.isEmpty {
            searchLog.debug("[Suggestions] Empty query — restoring recommendedTerms")
            suggestions = Self.recommendedTerms
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else {
            searchLog.debug("[Suggestions] Task cancelled before fetch")
            return
        }
        fetchSuggestions(for: q)
    }

    public func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        start(query: trimmed, filter: filter)
        Task { await recordSearch(trimmed) }
    }

    /// Repeats the failed request with the same query and filters: the next page while results are
    /// on screen, otherwise the first page.
    public func retry() {
        guard error != nil, let submittedQuery else { return }
        if results.isEmpty {
            start(query: submittedQuery, filter: submittedFilter)
        } else {
            loadMore()
        }
    }

    /// Back to the idle screen, e.g. when the search field is cleared.
    public func clearResults() {
        invalidateRequest()
        results = []
        nextPageToken = nil
        error = nil
        isLoading = false
        submittedQuery = nil
    }

    private func start(query: String, filter: SearchFilter) {
        let request = invalidateRequest()
        submittedQuery = query
        submittedFilter = filter
        results = []
        nextPageToken = nil
        error = nil
        isLoading = true
        searchTask = Task { await performSearch(request, query: query, continuationToken: nil, filter: filter) }
    }

    /// Cancels the request in flight and returns the number that owns the state from now on.
    @discardableResult
    private func invalidateRequest() -> Int {
        searchTask?.cancel()
        requestGeneration += 1
        return requestGeneration
    }

    // MARK: - History management

    /// Loads history from the store into the published `history` property.
    public func loadHistory() async {
        history = await historyStore.all
    }

    /// Saves `query` to history and refreshes the in-memory list.
    private func recordSearch(_ query: String) async {
        await historyStore.add(query)
        history = await historyStore.all
    }

    /// Removes a single entry from history.
    public func removeHistoryEntry(_ query: String) {
        Task {
            await historyStore.remove(query)
            history = await historyStore.all
        }
    }

    /// Clears all history entries.
    public func clearHistory() {
        Task {
            await historyStore.clear()
            history = await historyStore.all
        }
    }

    /// Apply a new filter and re-run the submitted search (or the field text) immediately.
    public func applyFilter(_ newFilter: SearchFilter) {
        filter = newFilter
        let target = submittedQuery ?? query.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        start(query: target, filter: newFilter)
    }

    public func loadMore() {
        guard let token = nextPageToken, let submittedQuery, !isLoading else { return }
        let request = invalidateRequest()
        error = nil  // a new page request replaces the previous page's failure
        isLoading = true
        let filter = submittedFilter
        searchTask = Task {
            await performSearch(request, query: submittedQuery, continuationToken: token, filter: filter)
        }
    }

    /// Writes state only while `request` is still the current one: a search or page started, or the
    /// results cleared, after it was sent makes its response (or failure) obsolete.
    private func performSearch(
        _ request: Int, query: String, continuationToken: String?, filter: SearchFilter
    ) async {
        do {
            let group = try await retryWithBackoff(label: "SearchVM") {
                try await api.search(query: query, continuationToken: continuationToken, filter: filter)
            }
            guard request == requestGeneration else { return }
            if continuationToken == nil {
                results = group.videos
            } else {
                results.append(contentsOf: group.videos)
            }
            nextPageToken = group.nextPageToken
        } catch {
            guard request == requestGeneration else { return }
            searchLog.error("search failed: \(ViewModelLogger.errorSummary(error))")
            self.error = error
        }
        isLoading = false
    }

    private func fetchSuggestions(for query: String) {
        searchLog.debug("[Suggestions] fetchSuggestions spawning task for q='\(query)'")
        suggestTask?.cancel()
        suggestTask = Task {
            do {
                let s = try await api.fetchSearchSuggestions(query: query)
                guard !Task.isCancelled else {
                    searchLog.debug("[Suggestions] Task cancelled after fetch")
                    return
                }
                let result = s.isEmpty ? Self.recommendedTerms : s
                searchLog.debug("[Suggestions] Setting \(result.count) suggestions")
                suggestions = result
            } catch {
                searchLog.error("[Suggestions] fetchSearchSuggestions threw: \(error)")
                if !Task.isCancelled { suggestions = Self.recommendedTerms }
            }
        }
    }

    // MARK: - Feed hide handling

    private func observeFeedHideNotifications() {
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideVideoFromFeed) {
                    guard let self, let videoId = note.userInfo?["videoId"] as? String else { continue }
                    self.results.removeAll { $0.id == videoId }
                }
            })
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideChannelFromFeed) {
                    guard let self, let channelId = note.userInfo?["channelId"] as? String else { continue }
                    self.results.removeAll { $0.channelId == channelId }
                }
            })
    }
}

// MARK: - ChannelViewModel

@MainActor
@Observable
public final class ChannelViewModel {

    public private(set) var channel: Channel?
    public private(set) var videos: [Video] = []
    public private(set) var isLoading: Bool = false
    public var error: Error?
    public private(set) var isSubscriptionLoaded = false
    public private(set) var isChangingSubscription = false

    private let api: any InnerTubeAPIProtocol
    private let localSubscriptions: LocalSubscriptionStore
    private var signedIn = false
    private var loadTask: Task<Void, Never>?
    private var nextPageToken: String?
    private var hideObserverTasks: [Task<Void, Never>] = []

    public init(
        api: any InnerTubeAPIProtocol = InnerTubeAPI(),
        localSubscriptions: LocalSubscriptionStore = .shared
    ) {
        self.api = api
        self.localSubscriptions = localSubscriptions
        observeFeedHideNotifications()
    }

    public func load(channelId: String, signedIn: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { await loadAsync(channelId: channelId, signedIn: signedIn) }
    }

    public func refresh(channelId: String, signedIn: Bool) async {
        load(channelId: channelId, signedIn: signedIn)
        await loadTask?.value
    }

    func loadAsync(channelId: String, signedIn: Bool = false) async {
        self.signedIn = signedIn
        isLoading = true
        isSubscriptionLoaded = false
        error = nil
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let (ch, group) = try await api.fetchChannel(channelId: channelId)
            try Task.checkCancellation()
            channel = ch
            videos = group.videos
            nextPageToken = group.nextPageToken
            let subscribed: Bool
            if signedIn {
                let subscriptions = try await api.fetchSubscribedChannels()
                subscribed = subscriptions.contains { $0.id == ch.id || $0.id == channelId }
            } else {
                subscribed = await localSubscriptions.isFollowing(ch.id)
            }
            try Task.checkCancellation()
            channel?.isSubscribed = subscribed
            isSubscriptionLoaded = true
        } catch {
            if !Task.isCancelled { self.error = error }
        }
    }

    public func setSubscribed(_ subscribed: Bool) async {
        guard let channel, isSubscriptionLoaded, !isChangingSubscription else { return }
        let signedIn = signedIn
        isChangingSubscription = true
        error = nil
        defer { isChangingSubscription = false }
        do {
            try await api.changeSubscription(
                channel: channel, subscribed: subscribed, signedIn: signedIn, localStore: localSubscriptions)
            if self.channel?.id == channel.id && self.signedIn == signedIn {
                // A refresh begun during the mutation may still return the old membership.
                loadTask?.cancel()
                isLoading = false
                isSubscriptionLoaded = true
                self.channel?.isSubscribed = subscribed
            }
        } catch {
            self.error = error
        }
    }

    public func loadMore() {
        guard let id = channel?.id, let token = nextPageToken, !isLoading else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let group = try await retryWithBackoff(label: "ChannelVM") {
                    try await api.fetchChannelVideos(channelId: id, continuationToken: token)
                }
                videos.append(contentsOf: group.videos)
                nextPageToken = group.nextPageToken
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - Feed hide handling

    private func observeFeedHideNotifications() {
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideVideoFromFeed) {
                    guard let self, let videoId = note.userInfo?["videoId"] as? String else { continue }
                    self.videos.removeAll { $0.id == videoId }
                }
            })
        hideObserverTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(named: .hideChannelFromFeed) {
                    guard let self, let channelId = note.userInfo?["channelId"] as? String else { continue }
                    self.videos.removeAll { $0.channelId == channelId }
                }
            })
    }
}
