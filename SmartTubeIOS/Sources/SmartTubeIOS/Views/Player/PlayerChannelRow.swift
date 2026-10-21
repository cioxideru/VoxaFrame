import SmartTubeIOSCore
import SwiftUI

/// One line in the player's More menu: the channel (avatar, name, chevron) opens the channel page, and the trailing
/// control shows and changes the subscription. Unsubscribe asks first, as on the channel page.
struct PlayerChannelRow: View {
    let channelId: String
    let title: String
    let api: InnerTubeAPI
    let isSignedIn: Bool
    let openChannelHint: Text
    let openChannel: () -> Void

    @State private var subscription: PlayerChannelSubscription
    /// The channel and account context the Unsubscribe confirmation was opened for.
    @State private var pendingUnsubscribe: (channel: Channel, signedIn: Bool)?

    init(
        channelId: String, title: String, api: InnerTubeAPI, isSignedIn: Bool, openChannelHint: Text,
        openChannel: @escaping () -> Void
    ) {
        self.channelId = channelId
        self.title = title
        self.api = api
        self.isSignedIn = isSignedIn
        self.openChannelHint = openChannelHint
        self.openChannel = openChannel
        _subscription = State(initialValue: PlayerChannelSubscription(api: api))
    }

    private var rowTarget: CGFloat {
        #if os(tvOS)
        VFTarget.tv
        #else
        VFTarget.touch
        #endif
    }

    private var displayTitle: Text {
        title.isEmpty ? Text("Channel", bundle: .module) : Text(title)
    }

    private var channel: Channel {
        Channel(id: channelId, title: title, thumbnailURL: ChannelAvatarCache.urls[channelId] ?? nil)
    }

    var body: some View {
        HStack(spacing: VFSpace.s8) {
            Button(action: openChannel) {
                HStack(spacing: VFSpace.s12) {
                    PlayerMoreChannelAvatar(channelId: channelId, api: api)
                    displayTitle
                        .lineLimit(1)
                    Image(systemName: AppSymbol.chevronForward)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: rowTarget)
                .contentShape(Rectangle())
            }
            .playerMenuRowButtonStyle()
            .foregroundStyle(.primary)
            .accessibilityLabel(displayTitle)
            .accessibilityValue(statusText)
            .accessibilityHint(openChannelHint)
            .accessibilityActions { subscriptionAction }
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuOpenChannel)

            subscriptionControl
        }
        .task(id: "\(channelId)|\(isSignedIn)") {
            await subscription.load(channelId: channelId, signedIn: isSignedIn)
        }
        .confirmationDialog(
            Text("Unsubscribe?", bundle: .module),
            isPresented: Binding(get: { pendingUnsubscribe != nil }, set: { if !$0 { pendingUnsubscribe = nil } }),
            titleVisibility: .visible, presenting: pendingUnsubscribe
        ) { pending in
            Button(role: .destructive) {
                Task { await subscription.setSubscribed(false, channel: pending.channel, signedIn: pending.signedIn) }
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
            if pending.signedIn {
                Text("\(pending.channel.title) will leave Subscriptions in your Google account.", bundle: .module)
            } else {
                Text("\(pending.channel.title) will be removed from the subscriptions on this device.", bundle: .module)
            }
        }
        // Autoplay or an account change moves the row to another context: the open confirmation no longer applies.
        .onChange(of: "\(channelId)|\(isSignedIn)") { pendingUnsubscribe = nil }
        .alert(
            Text("Error", bundle: .module),
            isPresented: Binding(get: { subscription.error != nil }, set: { if !$0 { subscription.error = nil } }),
            presenting: subscription.error
        ) { _ in
            Button(role: .cancel) {
            } label: {
                Text("OK", bundle: .module)
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var statusText: Text {
        switch subscription.isSubscribed {
        case true?: Text("Subscribed", bundle: .module)
        case false?: Text("Not subscribed", bundle: .module)
        case nil: Text("Subscription status unknown", bundle: .module)
        }
    }

    @ViewBuilder private var subscriptionAction: some View {
        switch subscription.isSubscribed {
        case true?:
            Button {
                pendingUnsubscribe = (channel, isSignedIn)
            } label: {
                Text("Unsubscribe", bundle: .module)
            }
        case false?:
            Button {
                Task { await subscription.setSubscribed(true, channel: channel, signedIn: isSignedIn) }
            } label: {
                Text("Subscribe", bundle: .module)
            }
        case nil:
            EmptyView()
        }
    }

    /// Subscribe is prominent; once subscribed it steps back to a quiet "Subscribed" that offers Unsubscribe.
    /// A spinner stands in while the state loads; nothing is shown when it could not be loaded.
    @ViewBuilder private var subscriptionControl: some View {
        if subscription.isLoading || subscription.isChanging {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: rowTarget, minHeight: rowTarget)
                .accessibilityLabel(Text("Loading subscription", bundle: .module))
        } else if let subscribed = subscription.isSubscribed {
            if subscribed {
                subscribedButton
            } else {
                Button {
                    Task { await subscription.setSubscribed(true, channel: channel, signedIn: isSignedIn) }
                } label: {
                    Text("Subscribe", bundle: .module)
                }
                .buttonStyle(.vfProminent)
                .controlSize(.small)
                .accessibilityHint(
                    isSignedIn
                        ? Text("Subscribes with your Google account.", bundle: .module)
                        : Text("Without signing in, the subscription is saved on this device", bundle: .module)
                )
                .accessibilityIdentifier(AccessibilityID.playerMoreMenuSubscribeButton)
            }
        }
    }

    @ViewBuilder private var subscribedButton: some View {
        let button = Button {
            pendingUnsubscribe = (channel, isSignedIn)
        } label: {
            let label = Label {
                Text("Subscribed", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.subscribed)
            }
            .labelStyle(.titleAndIcon)
            #if os(iOS)
            // A bordered button is shorter than the touch target on iOS; this pill keeps the whole 44 pt.
            label
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, VFSpace.s12)
                .padding(.vertical, VFSpace.s4)
                .background(.fill.tertiary, in: Capsule())
                .frame(minHeight: VFTarget.touch)
                .contentShape(Rectangle())
            #else
            label
            #endif
        }
        .accessibilityHint(Text("Asks before unsubscribing.", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.playerMoreMenuUnsubscribeButton)
        #if os(iOS)
        button.buttonStyle(.plain)
        #else
        button.buttonStyle(.bordered).controlSize(.small)
        #endif
    }
}

/// Avatar URLs by channel id, kept for the session (including channels without one), so reopening the More
/// menu does not repeat the request.
@MainActor enum ChannelAvatarCache {
    static var urls: [String: URL?] = [:]
}

/// Channel avatar loaded via `fetchChannelThumbnailURL`; falls back to the person symbol.
struct PlayerMoreChannelAvatar: View {
    let channelId: String
    let api: InnerTubeAPI
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: AppSymbol.personCircle)
                .resizable()
                .foregroundStyle(.tint)
        }
        .frame(width: VFTarget.pointer, height: VFTarget.pointer)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: channelId) {
            if let cached = ChannelAvatarCache.urls[channelId] {
                url = cached
                return
            }
            url = nil
            // Only a completed lookup is cached (a channel without a thumbnail included); failures retry.
            do {
                let fetched = try await api.fetchChannelThumbnailURL(channelId: channelId)
                guard !Task.isCancelled else { return }
                ChannelAvatarCache.urls[channelId] = .some(fetched)
                url = fetched
            } catch {
                return
            }
        }
    }
}
