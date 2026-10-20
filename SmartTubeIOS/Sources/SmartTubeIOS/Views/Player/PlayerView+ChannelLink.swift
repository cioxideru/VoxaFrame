#if !os(tvOS)
import SmartTubeIOSCore
import SwiftUI

extension PlayerView {
    var playingChannelId: String? {
        let cid = vm.channelVideo?.channelId
        return (cid?.isEmpty ?? true) ? nil : cid
    }

    /// Opens the playing video's channel page.
    /// iOS: leaves the full-screen player like Back does (mini-player when enabled, else stop); the shell then
    /// pushes `ChannelView` on the selected tab. macOS: the player is pushed in the detail stack, so the
    /// channel goes on top of it (the player pauses, as before).
    func openPlayingChannel() {
        guard let cid = playingChannelId else { return }
        showMoreMenu = false
        showDescriptionSheet = false
        #if os(iOS)
        playerState.openChannel(cid, miniPlayerEnabled: store.settings.miniPlayerEnabled)
        #else
        channelDestination = ChannelDestination(channelId: cid)
        #endif
    }

    private var openChannelHint: Text {
        #if os(iOS)
        if store.settings.miniPlayerEnabled {
            return Text("Opens the channel page. The video keeps playing in the mini-player.", bundle: .module)
        }
        return Text("Opens the channel page and stops the video.", bundle: .module)
        #else
        return Text("Opens the channel page. The video keeps playing.", bundle: .module)
        #endif
    }

    /// "Open Channel" row of the More menu with the channel avatar; hidden for videos without a channel.
    @ViewBuilder var moreMenuChannelRow: some View {
        if let cid = playingChannelId {
            let row = Button(action: openPlayingChannel) {
                HStack(spacing: VFSpace.s12) {
                    PlayerMoreChannelAvatar(channelId: cid, api: vm.api)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Open Channel", bundle: .module)
                        if let name = vm.channelVideo?.channelTitle, !name.isEmpty {
                            Text(name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: AppSymbol.chevronForward)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: VFTarget.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityHint(openChannelHint)
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuOpenChannel)
            #if os(iOS)
            row.padding(.horizontal, VFSpace.s12)
            #else
            row.padding(.horizontal)
            Divider()
            #endif
        }
    }
}

extension PlaybackViewModel {
    /// The video playing now, with channel metadata from the matching player info. It is `nil` while another
    /// video loads, so the channel of an earlier video is never offered. URL, widget and share launches open a
    /// video without a channel until its player info arrives.
    var channelVideo: Video? {
        guard var current = currentVideo else { return nil }
        guard let info = playerInfo?.video, info.id == current.id else { return current }
        if current.channelId?.isEmpty ?? true { current.channelId = info.channelId }
        if current.channelTitle.isEmpty { current.channelTitle = info.channelTitle }
        return current
    }
}

/// Avatar URLs by channel id, kept for the session (including channels without one), so reopening the More
/// menu does not repeat the request.
@MainActor private enum ChannelAvatarCache {
    static var urls: [String: URL?] = [:]
}

/// Channel avatar loaded via `fetchChannelThumbnailURL`; falls back to the person symbol.
private struct PlayerMoreChannelAvatar: View {
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
#endif
