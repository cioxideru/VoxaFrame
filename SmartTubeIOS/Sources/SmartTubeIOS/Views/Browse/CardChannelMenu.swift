import SmartTubeIOSCore
import SwiftUI

// MARK: - Card channel menu
//
// The channel control of the video and Shorts card menus, like the channel row of the player's More menu: Go to
// Channel and the subscription state with Subscribe / Unsubscribe. Menus allow only native items, so iOS and the Mac
// show one compact ControlGroup row ("Go to Channel" | "Subscribe" or "Subscribed", the second button only once the
// state is known); the tvOS dialogs and the VoiceOver actions get plain buttons with explicit titles. The state
// comes from `SubscribedChannelsCache`, loaded when a menu opens. Unsubscribe asks first through `cardChannelSubscription(channel:pending:)` on the card.

/// An Unsubscribe confirmation, bound to the channel and the account context it was opened for.
struct PendingUnsubscribe {
    let channel: Channel
    let context: SubscriptionContext
}

extension Channel {
    /// The channel of a card's video, with the avatar URL when the session already knows it.
    @MainActor static func ofCard(_ video: Video) -> Channel? {
        guard let id = video.channelId, !id.isEmpty else { return nil }
        return Channel(id: id, title: video.channelTitle, thumbnailURL: ChannelAvatarCache.urls[id] ?? nil)
    }
}

extension AuthService {
    var subscriptionContext: SubscriptionContext {
        SubscriptionContext(signedIn: isSignedIn, session: sessionGeneration)
    }
}

struct CardChannelMenuItems: View {
    let channel: Channel
    /// `true` in context and More menus (the compact row); `false` in the tvOS dialog and the VoiceOver actions.
    let compact: Bool
    @Binding var pendingUnsubscribe: PendingUnsubscribe?

    @Environment(AuthService.self) private var authService
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.showToast) private var showToast
    private let cache = SubscribedChannelsCache.shared

    private var context: SubscriptionContext { authService.subscriptionContext }
    private var isSubscribed: Bool? { cache.isSubscribed(channel.id, in: context) }

    var body: some View {
        #if os(tvOS)
        explicitItems
        #else
        if compact {
            ControlGroup {
                goToChannelButton(Text("Go to Channel", bundle: .module))
                compactSubscriptionButton
            }
            .onAppear(perform: load)
        } else {
            explicitItems
        }
        #endif
    }

    private func goToChannelButton(_ title: Text) -> some View {
        Button(action: openChannel) {
            Label {
                title
            } icon: {
                Image(systemName: AppSymbol.personRectangle)
            }
        }
        .accessibilityIdentifier(AccessibilityID.videoMenuGoToChannel)
    }

    /// "Subscribed" (asks before unsubscribing) or "Subscribe"; nothing while the state is unknown, so the row never
    /// implies a state it does not know.
    @ViewBuilder private var compactSubscriptionButton: some View {
        switch isSubscribed {
        case true?:
            Button {
                pendingUnsubscribe = PendingUnsubscribe(channel: channel, context: context)
            } label: {
                Label {
                    Text("Subscribed", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.subscribed)
                }
            }
            .accessibilityHint(Text("Asks before unsubscribing.", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.videoMenuUnsubscribe)
            .disabled(cache.isChanging(channel.id))
        case false?:
            Button(action: subscribe) {
                Label {
                    Text("Subscribe", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.subscribe)
                }
            }
            .accessibilityIdentifier(AccessibilityID.videoMenuSubscribe)
            .disabled(cache.isChanging(channel.id))
        case nil:
            EmptyView()
        }
    }

    /// Titles that say what happens; the subscription command appears once its state is known.
    @ViewBuilder private var explicitItems: some View {
        goToChannelButton(Text("Go to Channel", bundle: .module))
            .onAppear(perform: load)
        switch isSubscribed {
        case true?:
            Button {
                pendingUnsubscribe = PendingUnsubscribe(channel: channel, context: context)
            } label: {
                Label {
                    Text("Unsubscribe from \(channel.title)", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.personCircleMinus)
                }
            }
            .accessibilityIdentifier(AccessibilityID.videoMenuUnsubscribe)
            .disabled(cache.isChanging(channel.id))
        case false?:
            Button(action: subscribe) {
                Label {
                    Text("Subscribe to \(channel.title)", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.subscribe)
                }
            }
            .accessibilityIdentifier(AccessibilityID.videoMenuSubscribe)
            .disabled(cache.isChanging(channel.id))
        case nil:
            EmptyView()
        }
    }

    private func load() {
        let context = context
        Task { await cache.load(context, api: api) }
    }

    private func openChannel() {
        NotificationCenter.default.post(
            name: .openChannel,
            object: nil,
            userInfo: ["channelId": channel.id, "channelTitle": channel.title]
        )
    }

    private func subscribe() {
        let context = context
        let channel = channel
        Task {
            do {
                // `false`: the state went stale or another change is running; say so rather than do nothing.
                let changed = try await cache.setSubscribed(true, channel: channel, in: context, api: api)
                showToast(
                    changed
                        ? String(localized: "Subscribed to \(channel.title)", bundle: .module)
                        : cardSubscriptionFailedText)
            } catch {
                showToast(cardSubscriptionFailedText)
            }
        }
    }
}

private var cardSubscriptionFailedText: String {
    String(localized: "Couldn't update the subscription. Try again.", bundle: .module)
}

// MARK: - Card modifier

extension View {
    /// The Unsubscribe confirmation for a card's channel menu. With VoiceOver on, it also loads the subscription state
    /// (once for all cards) so the card's actions can offer Subscribe or Unsubscribe without opening a menu.
    func cardChannelSubscription(channel: Channel?, pending: Binding<PendingUnsubscribe?>) -> some View {
        modifier(CardChannelSubscriptionModifier(channel: channel, pending: pending))
    }
}

private struct CardChannelSubscriptionModifier: ViewModifier {
    let channel: Channel?
    @Binding var pending: PendingUnsubscribe?

    @Environment(AuthService.self) private var authService
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.showToast) private var showToast
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .task(id: voiceOverEnabled && channel != nil ? authService.subscriptionContext : nil) {
                guard voiceOverEnabled, channel != nil else { return }
                await SubscribedChannelsCache.shared.load(authService.subscriptionContext, api: api)
            }
            .confirmationDialog(
                Text("Unsubscribe?", bundle: .module),
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible, presenting: pending
            ) { pending in
                Button(role: .destructive) {
                    unsubscribe(pending)
                } label: {
                    Text("Unsubscribe", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.subscriptionConfirm)
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.subscriptionCancel)
            } message: { pending in
                if pending.context.signedIn {
                    Text("\(pending.channel.title) will leave Subscriptions in your Google account.", bundle: .module)
                } else {
                    Text(
                        "\(pending.channel.title) will be removed from the subscriptions on this device.",
                        bundle: .module)
                }
            }
            // A sign-in or sign-out while the confirmation is open makes it stale.
            .onChange(of: authService.subscriptionContext) { pending = nil }
    }

    private func unsubscribe(_ pending: PendingUnsubscribe) {
        // A confirmed Unsubscribe that cannot act (account changed, state stale) says so instead of doing nothing.
        guard pending.context == authService.subscriptionContext else {
            showToast(cardSubscriptionFailedText)
            return
        }
        Task {
            do {
                let changed = try await SubscribedChannelsCache.shared.setSubscribed(
                    false, channel: pending.channel, in: pending.context, api: api)
                showToast(
                    changed
                        ? String(localized: "Unsubscribed from \(pending.channel.title)", bundle: .module)
                        : cardSubscriptionFailedText)
            } catch {
                showToast(cardSubscriptionFailedText)
            }
        }
    }
}
