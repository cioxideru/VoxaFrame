import SmartTubeIOSCore
import SwiftUI

// MARK: - ChannelListView
//
// Displays the list of channels the authenticated user subscribes to.
// Shown when the "Channels" chip is selected in the Home chip bar.
// Mirrors the Android ChannelsBrowseFragment channel row layout.

struct ChannelListView: View {
    let channels: [Channel]
    let changingIDs: Set<String>
    let onSelect: (Channel) -> Void
    let onUnsubscribe: (Channel) async -> Void
    let onRefresh: () async -> Void
    @State private var pendingRemoval: Channel?
    @State private var confirmUnsubscribe = false
    #if os(tvOS)
    @FocusState private var focusedChannelId: String?
    #endif

    var body: some View {
        #if os(tvOS)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(channels) { channel in
                    row(channel)
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .focusSection()
        .confirmationDialog("Unsubscribe?", isPresented: $confirmUnsubscribe, titleVisibility: .visible) {
            confirmationButtons
        } message: {
            Text(pendingRemoval?.title ?? "")
        }
        #else
        List(channels) { channel in
            row(channel)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        requestRemoval(channel)
                    } label: {
                        Label("Unsubscribe", systemImage: AppSymbol.personCircleMinus)
                    }
                    .tint(.red)
                    .disabled(changingIDs.contains(channel.id))
                }
        }
        .listStyle(.plain)
        .refreshable { await onRefresh() }
        .accessibilityIdentifier(AccessibilityID.subscriptionList)
        .confirmationDialog("Unsubscribe?", isPresented: $confirmUnsubscribe, titleVisibility: .visible) {
            confirmationButtons
        } message: {
            Text(pendingRemoval?.title ?? "")
        }
        #endif
    }

    private func row(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelect(channel)
            } label: {
                ChannelListRow(channel: channel)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(changingIDs.contains(channel.id))
            .accessibilityIdentifier(AccessibilityID.subscriptionRow(channel.id))
            #if os(tvOS)
            .focused($focusedChannelId, equals: channel.id)
            #endif
            Button {
                requestRemoval(channel)
            } label: {
                Label("Unsubscribe", systemImage: AppSymbol.personCircleMinus)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(changingIDs.contains(channel.id))
            .accessibilityLabel(Text("Unsubscribe from \(channel.title)"))
            .accessibilityIdentifier(AccessibilityID.subscriptionRemove(channel.id))
        }
    }

    private func requestRemoval(_ channel: Channel) {
        pendingRemoval = channel
        confirmUnsubscribe = true
    }

    @ViewBuilder
    private var confirmationButtons: some View {
        Button("Unsubscribe", role: .destructive) {
            if let channel = pendingRemoval { Task { await onUnsubscribe(channel) } }
        }
        .accessibilityIdentifier(AccessibilityID.subscriptionConfirm)
        Button("Cancel", role: .cancel) { pendingRemoval = nil }
            .accessibilityIdentifier(AccessibilityID.subscriptionCancel)
    }
}

// MARK: - ChannelListRow

private struct ChannelListRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title.isEmpty ? "Unknown channel" : channel.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let count = channel.subscriberCount {
                    Text(count)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: AppSymbol.chevronRight)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = channel.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: 48, height: 48)
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: AppSymbol.personCircle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}
