import Foundation
import Observation
import Synchronization
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
@Suite("SubscribedChannelsCache")
struct SubscribedChannelsCacheTests {
    private let account = SubscriptionContext(signedIn: true, session: 1)
    private let channel = Channel(id: "UCcard", title: "Card Channel")

    private func freshStore() -> LocalSubscriptionStore {
        LocalSubscriptionStore(suiteName: "test-\(UUID().uuidString)")
    }

    private func fetchCount(_ api: MockInnerTubeAPI) -> Int {
        api.calls.filter { $0.method == "fetchSubscribedChannels" }.count
    }

    @Test func loadsOnceForAllCardsUntilItExpires() async {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        var now = Date(timeIntervalSince1970: 0)
        let sut = SubscribedChannelsCache(now: { now })

        #expect(sut.isSubscribed("UCcard", in: account) == nil)
        await sut.load(account, api: api, localStore: freshStore())
        await sut.load(account, api: api, localStore: freshStore())
        #expect(sut.isSubscribed("UCcard", in: account) == true)
        #expect(sut.isSubscribed("UCother", in: account) == false)
        #expect(fetchCount(api) == 1)

        now += SubscribedChannelsCache.maxAge
        await sut.load(account, api: api, localStore: freshStore())
        #expect(fetchCount(api) == 2)
    }

    @Test func anotherSessionReadsAsUnknownUntilLoaded() async {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        let sut = SubscribedChannelsCache()
        await sut.load(account, api: api, localStore: freshStore())

        let nextAccount = SubscriptionContext(signedIn: true, session: 2)
        #expect(sut.isSubscribed("UCcard", in: nextAccount) == nil)
        api.channelsResult = []
        await sut.load(nextAccount, api: api, localStore: freshStore())
        #expect(sut.isSubscribed("UCcard", in: nextAccount) == false)
        #expect(sut.isSubscribed("UCcard", in: account) == nil)
    }

    @Test func unsubscribeActsOnceAndOnlyInItsContext() async throws {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        let sut = SubscribedChannelsCache()
        await sut.load(account, api: api, localStore: freshStore())

        // A confirmation opened under another account does nothing.
        let stale = SubscriptionContext(signedIn: true, session: 0)
        #expect(try await !sut.setSubscribed(false, channel: channel, in: stale, api: api))
        #expect(!api.calls.contains { $0.method == "setSubscribed" })

        #expect(try await sut.setSubscribed(false, channel: channel, in: account, api: api))
        #expect(sut.isSubscribed("UCcard", in: account) == false)
        #expect(api.calls.contains(.init(method: "setSubscribed", args: ["UCcard", "false"])))

        // Already unsubscribed: a repeated confirmation is a no-op.
        #expect(try await !sut.setSubscribed(false, channel: channel, in: account, api: api))
        #expect(api.calls.filter { $0.method == "setSubscribed" }.count == 1)
    }

    @Test func guestSubscribesOnThisDevice() async throws {
        let api = MockInnerTubeAPI()
        let store = freshStore()
        let guest = SubscriptionContext(signedIn: false, session: 0)
        let sut = SubscribedChannelsCache()
        await sut.load(guest, api: api, localStore: store)
        #expect(sut.isSubscribed("UCcard", in: guest) == false)

        #expect(try await sut.setSubscribed(true, channel: channel, in: guest, api: api, localStore: store))
        #expect(sut.isSubscribed("UCcard", in: guest) == true)
        #expect(await store.isFollowing("UCcard"))
        #expect(fetchCount(api) == 0)
    }

    @Test func failedLookupStaysUnknownAndBlocksChanges() async throws {
        let api = MockInnerTubeAPI()
        api.errorToThrow = URLError(.notConnectedToInternet)
        let sut = SubscribedChannelsCache()
        await sut.load(account, api: api, localStore: freshStore())
        #expect(sut.isSubscribed("UCcard", in: account) == nil)
        #expect(try await !sut.setSubscribed(true, channel: channel, in: account, api: api))
    }

    @Test func ownChangesApplyOnlyToTheirContextAndOthersDropTheList() async {
        let api = MockInnerTubeAPI()
        let sut = SubscribedChannelsCache()
        await sut.load(account, api: api, localStore: freshStore())

        sut.apply(channelId: "UCcard", subscribed: true, in: SubscriptionContext(signedIn: true, session: 0))
        #expect(sut.isSubscribed("UCcard", in: account) == false)
        sut.apply(channelId: "UCcard", subscribed: true, in: account)
        #expect(sut.isSubscribed("UCcard", in: account) == true)

        // A change from the channel page or the player has no session: the list is dropped and reloaded.
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        sut.receive(.init(channelId: "UCother", subscribed: true, signedIn: true))
        #expect(sut.isSubscribed("UCcard", in: account) == nil)
        await sut.load(account, api: api, localStore: freshStore())
        #expect(sut.isSubscribed("UCcard", in: account) == true)
        #expect(fetchCount(api) == 2)
    }

    @Test func changeCompletedDuringAReloadIsAppliedOverTheResponse() async throws {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        var now = Date(timeIntervalSince1970: 0)
        let sut = SubscribedChannelsCache(now: { now })
        await sut.load(account, api: api, localStore: freshStore())

        let mutationGate = Gate()
        api.setSubscribedHandler = { _, _ in await mutationGate.pass() }
        let mutation = Task { try await sut.setSubscribed(false, channel: channel, in: account, api: api) }
        await mutationGate.waitForArrival()

        // The list expires and reloads; its response still lists the channel.
        let fetchGate = Gate()
        api.subscribedChannelsHandler = {
            await fetchGate.pass()
            return [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        }
        now += SubscribedChannelsCache.maxAge
        let reload = Task { await sut.load(account, api: api, localStore: freshStore()) }
        await fetchGate.waitForArrival()

        mutationGate.open()
        #expect(try await mutation.value)
        fetchGate.open()
        await reload.value
        #expect(sut.isSubscribed("UCcard", in: account) == false)
    }

    @Test func mutationFinishingAfterAnAccountSwitchLeavesTheNewAccountAlone() async throws {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        let sut = SubscribedChannelsCache()
        await sut.load(account, api: api, localStore: freshStore())

        let mutationGate = Gate()
        api.setSubscribedHandler = { _, _ in await mutationGate.pass() }
        let mutation = Task { try await sut.setSubscribed(false, channel: channel, in: account, api: api) }
        await mutationGate.waitForArrival()

        let nextAccount = SubscriptionContext(signedIn: true, session: 2)
        await sut.load(nextAccount, api: api, localStore: freshStore())
        mutationGate.open()
        #expect(try await mutation.value)
        #expect(sut.isSubscribed("UCcard", in: nextAccount) == true)
    }

    @Test func expiredListReadsAsUnknownBlocksChangesAndReloadsOnce() async throws {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        var now = Date(timeIntervalSince1970: 0)
        let sut = SubscribedChannelsCache(now: { now })
        await sut.load(account, api: api, localStore: freshStore())

        let fetchGate = Gate()
        api.subscribedChannelsHandler = {
            await fetchGate.pass()
            return []
        }
        now += SubscribedChannelsCache.maxAge
        #expect(sut.isSubscribed("UCcard", in: account) == nil)
        #expect(sut.isSubscribed("UCcard", in: account) == nil)
        #expect(try await !sut.setSubscribed(false, channel: channel, in: account, api: api))
        #expect(!api.calls.contains { $0.method == "setSubscribed" })

        await fetchGate.waitForArrival()
        fetchGate.open()
        await sut.load(account, api: api, localStore: freshStore())
        #expect(fetchCount(api) == 2)
        #expect(sut.isSubscribed("UCcard", in: account) == false)
    }

    @Test func reloadWithTheSameIdsStillNotifiesReaders() async {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCcard", title: "Card Channel", isSubscribed: true)]
        var now = Date(timeIntervalSince1970: 0)
        let sut = SubscribedChannelsCache(now: { now })
        await sut.load(account, api: api, localStore: freshStore())

        now += SubscribedChannelsCache.maxAge
        let notified = NotifiedFlag()
        let status = withObservationTracking {
            sut.isSubscribed("UCcard", in: account)
        } onChange: {
            notified.set()
        }
        #expect(status == nil)

        // The reload the read started returns the same list.
        await sut.load(account, api: api, localStore: freshStore())
        #expect(notified.value)
        #expect(sut.isSubscribed("UCcard", in: account) == true)
        #expect(fetchCount(api) == 2)
    }
}

private final class NotifiedFlag: Sendable {
    private let state = Mutex(false)
    var value: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}

/// Holds an async fake call until the test opens it; `waitForArrival` returns once a call is held.
@MainActor
private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let arrivals = AsyncStream<Void>.makeStream()
    private var isOpen = false

    func pass() async {
        arrivals.continuation.yield()
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitForArrival() async {
        var iterator = arrivals.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
