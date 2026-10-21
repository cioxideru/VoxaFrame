import Foundation
import SmartTubeIOSCore

private let subscriptionsLog = ViewModelLogger(category: "Subscriptions")

/// The account context a subscription state belongs to: signed in or guest, and which sign-in session.
struct SubscriptionContext: Hashable, Sendable {
    let signedIn: Bool
    let session: Int
}

// MARK: - Subscribed channels cache
//
// The subscription state behind the video and Shorts card menus. Cards never fetch on appear: the first menu that
// opens loads the whole list once (the account's TV subscriptions when signed in, otherwise the subscriptions saved on
// this device) and later menus read it from memory. The state is known only for the account context it was loaded for
// and only for `maxAge`: an expired list reads as unknown and starts one shared reload.
// Changes made through this cache are applied for their own context (and over a reload still in flight). Any other
// `subscriptionsDidChange` (channel page, player) carries no sign-in session, so it drops the list and the next read
// reloads it.

@MainActor
@Observable
final class SubscribedChannelsCache {
    static let shared: SubscribedChannelsCache = {
        let cache = SubscribedChannelsCache()
        cache.observeChanges()
        return cache
    }()

    /// Changes made outside the app (another device) show up after this.
    static let maxAge: TimeInterval = 5 * 60

    private struct Source {
        let api: any InnerTubeAPIProtocol
        let localStore: LocalSubscriptionStore
    }

    /// A change as `subscriptionsDidChange` reports it.
    struct Change: Equatable {
        let channelId: String
        let subscribed: Bool
        let signedIn: Bool
    }

    private var channelIds: Set<String>?
    private var context: SubscriptionContext?
    private var changingIds: Set<String> = []
    /// Bumped whenever a load ends. Reads depend on it, so a reload that returns the same ids (an equal write that
    /// Observation does not report) still moves readers from unknown back to known.
    private var revision = 0
    @ObservationIgnored private var loadedAt: Date?
    /// Set when a change from elsewhere made the list unreliable; the next read reloads it.
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var source: Source?
    /// Changes completed for `context` while its list is loading; applied over the response.
    @ObservationIgnored private var changesWhileLoading: [String: Bool] = [:]
    /// Changes made here whose `subscriptionsDidChange` has not arrived yet (only while observing).
    @ObservationIgnored private var expectedEchoes: [Change] = []
    @ObservationIgnored private var observing = false
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// `nil` while the state for `context` is unknown: not loaded, loading, failed, expired or dropped.
    /// Reading an expired or dropped list starts one shared reload.
    func isSubscribed(_ channelId: String, in context: SubscriptionContext) -> Bool? {
        _ = revision
        guard self.context == context else { return nil }
        guard isFresh, let channelIds else {
            if loadTask == nil, invalidated || loadedAt != nil, let source { start(context, source) }
            return nil
        }
        return channelIds.contains(channelId)
    }

    func isChanging(_ channelId: String) -> Bool { changingIds.contains(channelId) }

    private var isFresh: Bool {
        guard channelIds != nil, !invalidated, let loadedAt else { return false }
        return now().timeIntervalSince(loadedAt) < Self.maxAge
    }

    /// Loads the list unless a current one for `context` is in memory; joins a load already running for it.
    func load(
        _ context: SubscriptionContext, api: any InnerTubeAPIProtocol, localStore: LocalSubscriptionStore = .shared
    ) async {
        let source = Source(api: api, localStore: localStore)
        self.source = source
        if self.context == context {
            if let loadTask {
                await loadTask.value
                return
            }
            if isFresh { return }
        }
        start(context, source)
        await loadTask?.value
    }

    /// Starts a load for `context`, replacing any running one. Observed state changes only inside the task, so a
    /// read during a view update may call this.
    private func start(_ context: SubscriptionContext, _ source: Source) {
        loadGeneration += 1
        let generation = loadGeneration
        let contextChanged = self.context != context
        loadedAt = nil
        invalidated = false
        changesWhileLoading = [:]
        if contextChanged {
            // Reads of another context are unknown at once; nothing of the old context carries over.
            self.context = context
            channelIds = nil
        }
        loadTask = Task {
            let ids: Set<String>?
            do {
                ids =
                    context.signedIn
                    ? Set(try await source.api.fetchSubscribedChannels().map(\.id))
                    : Set(await source.localStore.allChannels().map(\.id))
            } catch {
                subscriptionsLog.error("[cardMenu] subscription lookup failed: \(ViewModelLogger.errorSummary(error))")
                ids = nil
            }
            // Replaced by another load, or dropped by a change from elsewhere.
            guard generation == loadGeneration else { return }
            loadTask = nil
            defer { revision += 1 }
            guard var ids else {
                channelIds = nil
                return
            }
            for (channelId, subscribed) in changesWhileLoading {
                if subscribed {
                    ids.insert(channelId)
                } else {
                    ids.remove(channelId)
                }
            }
            changesWhileLoading = [:]
            loadedAt = now()
            channelIds = ids
        }
    }

    /// Changes the subscription only while its state is known and current for `context` and differs from
    /// `subscribed`, so a confirmation opened under another account, a stale list or a repeated tap never acts.
    /// Returns whether it changed.
    func setSubscribed(
        _ subscribed: Bool, channel: Channel, in context: SubscriptionContext, api: any InnerTubeAPIProtocol,
        localStore: LocalSubscriptionStore = .shared
    ) async throws -> Bool {
        guard isSubscribed(channel.id, in: context) == !subscribed, !changingIds.contains(channel.id) else {
            return false
        }
        let change = Change(channelId: channel.id, subscribed: subscribed, signedIn: context.signedIn)
        // Registered before the request: the notification may arrive before the request returns here.
        if observing { expectedEchoes.append(change) }
        changingIds.insert(channel.id)
        defer { changingIds.remove(channel.id) }
        do {
            try await api.changeSubscription(
                channel: channel, subscribed: subscribed, signedIn: context.signedIn, localStore: localStore)
        } catch {
            if let index = expectedEchoes.firstIndex(of: change) { expectedEchoes.remove(at: index) }
            throw error
        }
        apply(channelId: channel.id, subscribed: subscribed, in: context)
        return true
    }

    /// A change completed for `context`: ignored when the cache moved to another account meanwhile.
    func apply(channelId: String, subscribed: Bool, in context: SubscriptionContext) {
        guard self.context == context else { return }
        if loadTask != nil {
            changesWhileLoading[channelId] = subscribed
        } else if channelIds != nil {
            if subscribed {
                channelIds?.insert(channelId)
            } else {
                channelIds?.remove(channelId)
            }
        }
    }

    /// `subscriptionsDidChange`: the echo of a change made here is already applied; any other change has no session
    /// to match, so the list (and a load in flight) is dropped until the next read or menu reloads it.
    func receive(_ change: Change) {
        if let index = expectedEchoes.firstIndex(of: change) {
            expectedEchoes.remove(at: index)
            return
        }
        guard context != nil else { return }
        loadGeneration += 1
        loadTask = nil
        changesWhileLoading = [:]
        invalidated = true
        channelIds = nil
    }

    private func observeChanges() {
        observing = true
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .subscriptionsDidChange) {
                guard let self,
                    let channel = note.userInfo?["channel"] as? Channel,
                    let subscribed = note.userInfo?["subscribed"] as? Bool,
                    let signedIn = note.userInfo?["signedIn"] as? Bool
                else { continue }
                receive(Change(channelId: channel.id, subscribed: subscribed, signedIn: signedIn))
            }
        }
    }
}
