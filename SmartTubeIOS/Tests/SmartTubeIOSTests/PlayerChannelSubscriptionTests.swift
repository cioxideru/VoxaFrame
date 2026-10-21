import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
@Suite("PlayerChannelSubscription")
struct PlayerChannelSubscriptionTests {
    private let channel = Channel(id: "UCplayer", title: "Player Channel")

    @Test func signedInStateComesFromAccountAndUnsubscribeReachesIt() async {
        let api = MockInnerTubeAPI()
        api.channelsResult = [Channel(id: "UCplayer", title: "Player Channel", isSubscribed: true)]
        let sut = PlayerChannelSubscription(
            api: api, localStore: LocalSubscriptionStore(suiteName: "test-\(UUID().uuidString)"))

        await sut.load(channelId: "UCplayer", signedIn: true)
        #expect(sut.isSubscribed == true)
        #expect(!sut.isLoading)

        await sut.setSubscribed(false, channel: channel, signedIn: true)
        #expect(sut.isSubscribed == false)
        #expect(api.calls.contains(.init(method: "setSubscribed", args: ["UCplayer", "false"])))
    }

    @Test func guestSubscribesOnThisDevice() async {
        let api = MockInnerTubeAPI()
        let store = LocalSubscriptionStore(suiteName: "test-\(UUID().uuidString)")
        let sut = PlayerChannelSubscription(api: api, localStore: store)

        await sut.load(channelId: "UCplayer", signedIn: false)
        #expect(sut.isSubscribed == false)

        await sut.setSubscribed(true, channel: channel, signedIn: false)
        #expect(sut.isSubscribed == true)
        #expect(await store.isFollowing("UCplayer"))
        #expect(!api.calls.contains { $0.method == "setSubscribed" })
    }

    @Test func failedLookupLeavesStateUnknownAndBlocksChanges() async {
        let api = MockInnerTubeAPI()
        api.errorToThrow = URLError(.notConnectedToInternet)
        let sut = PlayerChannelSubscription(
            api: api, localStore: LocalSubscriptionStore(suiteName: "test-\(UUID().uuidString)"))

        await sut.load(channelId: "UCplayer", signedIn: true)
        #expect(sut.isSubscribed == nil)

        await sut.setSubscribed(true, channel: channel, signedIn: true)
        #expect(!api.calls.contains { $0.method == "setSubscribed" })
    }

    @Test func staleConfirmationDoesNotChangeTheNextChannel() async {
        let api = MockInnerTubeAPI()
        api.channelsResult = [
            Channel(id: "UCplayer", title: "Player Channel", isSubscribed: true),
            Channel(id: "UCnext", title: "Next Channel", isSubscribed: true),
        ]
        let sut = PlayerChannelSubscription(
            api: api, localStore: LocalSubscriptionStore(suiteName: "test-\(UUID().uuidString)"))
        await sut.load(channelId: "UCplayer", signedIn: true)
        let pending = (channel: channel, signedIn: true)

        // Autoplay moves on to another channel while the confirmation for the first one is open.
        await sut.load(channelId: "UCnext", signedIn: true)
        await sut.setSubscribed(false, channel: pending.channel, signedIn: pending.signedIn)
        #expect(sut.isSubscribed == true)
        #expect(!api.calls.contains { $0.method == "setSubscribed" })

        // The same channel under another account context is stale too.
        await sut.load(channelId: "UCplayer", signedIn: false)
        await sut.setSubscribed(false, channel: pending.channel, signedIn: pending.signedIn)
        #expect(!api.calls.contains { $0.method == "setSubscribed" })
    }
}
