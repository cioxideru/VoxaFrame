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

    /// The More menu's channel row (open the channel, subscribe or unsubscribe); hidden for videos without a channel.
    @ViewBuilder var moreMenuChannelRow: some View {
        if let cid = playingChannelId {
            let row = PlayerChannelRow(
                channelId: cid, title: vm.channelVideo?.channelTitle ?? "", api: vm.api,
                isSignedIn: authService.isSignedIn, openChannelHint: openChannelHint, openChannel: openPlayingChannel)
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
