import Foundation
import SmartTubeIOSCore

// MARK: - Player channel subscription
//
// Used by the player's channel row (More menu). The same sources as the channel page (`SearchViewModel`):
// the account's TV subscriptions when signed in, otherwise the subscriptions saved on this device.

@MainActor
@Observable
final class PlayerChannelSubscription {
    /// `nil` until the state of the current channel is known, and after a failed lookup.
    private(set) var isSubscribed: Bool?
    private(set) var isLoading = false
    private(set) var isChanging = false
    var error: Error?

    @ObservationIgnored private var channelId: String?
    @ObservationIgnored private var signedIn = false
    @ObservationIgnored private let api: any InnerTubeAPIProtocol
    @ObservationIgnored private let localStore: LocalSubscriptionStore

    init(api: any InnerTubeAPIProtocol, localStore: LocalSubscriptionStore = .shared) {
        self.api = api
        self.localStore = localStore
    }

    // ponytail: the signed-in lookup fetches the whole subscription list each time the menu opens;
    // share a session cache with the channel page if that request shows up in profiles.
    func load(channelId: String, signedIn: Bool) async {
        self.channelId = channelId
        self.signedIn = signedIn
        isSubscribed = nil
        isLoading = true
        defer { if self.channelId == channelId { isLoading = false } }
        do {
            let subscribed =
                signedIn
                ? try await api.fetchSubscribedChannels().contains { $0.id == channelId }
                : await localStore.isFollowing(channelId)
            guard !Task.isCancelled, self.channelId == channelId, self.signedIn == signedIn else { return }
            isSubscribed = subscribed
        } catch {
            playerMenuLog.error("[channelRow] subscription lookup failed: \(ViewModelLogger.errorSummary(error))")
        }
    }

    /// Acts only when `channel` and `signedIn` are still the loaded context, so a confirmation opened for an
    /// earlier video's channel (autoplay moved on, or the account changed) never changes the current one.
    func setSubscribed(_ subscribed: Bool, channel: Channel, signedIn: Bool) async {
        guard channel.id == channelId, signedIn == self.signedIn, isSubscribed != nil, !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        do {
            try await api.changeSubscription(
                channel: channel, subscribed: subscribed, signedIn: signedIn, localStore: localStore)
            // The player may have moved on to another channel meanwhile.
            if channelId == channel.id && self.signedIn == signedIn { isSubscribed = subscribed }
        } catch {
            self.error = error
        }
    }
}
