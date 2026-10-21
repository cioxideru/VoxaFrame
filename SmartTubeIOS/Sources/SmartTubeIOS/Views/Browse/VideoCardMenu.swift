import SmartTubeIOSCore
import SwiftUI

// MARK: - Video card menu
//
// One set of card commands for every video tile, regular and Shorts: the context menu, the More button, the VoiceOver
// actions and the tvOS Play/Pause dialog all show `VideoCardMenuItems`; `videoCardMenu(video:playlistId:title:state:)`
// adds the confirmations, sheets and alerts those commands open. Order follows the design (P-Menus): share and channel,
// playback and lists, feedback.

/// What the card menu has open: the confirmations (Not Interested, Don't Like, Don't Recommend Channel, Unsubscribe),
/// sheets, the error alert and the tvOS command dialog.
@MainActor @Observable final class VideoCardMenuState {
    var confirmsNotInterested = false
    var confirmsDontLike = false
    var confirmsDontRecommendChannel = false
    var showsOfflineDownload = false
    var playlistPickerMode: PlaylistPickerSheet.Mode?
    var pendingUnsubscribe: PendingUnsubscribe?
    var alert: DownloadAlertItem?
    var showsActions = false
}

/// Every card command. `playlistId` is the playlist the card is listed in (`"WL"` for Watch Later), if any.
struct VideoCardMenuItems: View {
    let video: Video
    let playlistId: String?
    /// `true` in context and More menus; `false` in the tvOS dialog and the VoiceOver actions.
    var nested = true
    @Bindable var state: VideoCardMenuState

    @Environment(AuthService.self) private var authService
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.showToast) private var showToast
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif
    #if !os(tvOS) && ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) private var downloadService
    #endif

    var body: some View {
        Section {
            #if !os(tvOS)
            if let shareURL = video.shareURL {
                ShareLink(item: shareURL) { menuLabel("Share", AppSymbol.share) }
            }
            #endif
            if let channel = Channel.ofCard(video) {
                CardChannelMenuItems(channel: channel, compact: nested, pendingUnsubscribe: $state.pendingUnsubscribe)
            }
        }
        Section {
            if nested {
                Menu {
                    secondaryMenuItems
                } label: {
                    Text(verbatim: "…")  // verbatim: Glyph only; the accessibility label is localized.
                }
                .accessibilityLabel(Text("More", bundle: .module))
                .accessibilityIdentifier(AccessibilityID.videoSecondaryMenu)
            } else {
                secondaryMenuItems
            }
            if authService.isSignedIn {
                if playlistId != "WL" {
                    Button(action: saveToWatchLater) { menuLabel("Save to Watch Later", AppSymbol.watchLater) }
                }
                if playlistId != nil {
                    Button {
                        state.playlistPickerMode = .move
                    } label: {
                        menuLabel("Move to Playlist", AppSymbol.moveToPlaylist)
                    }
                }
            }
            OfflineWatchButton(video: video) { state.showsOfflineDownload = true }
            #if !os(tvOS) && ENABLE_DOWNLOADS
            Button {
                downloadService.download(video: video)
            } label: {
                if downloadService.state.isActive {
                    Label("Downloading…", systemImage: AppSymbol.download)
                } else {
                    Label("Download to Gallery", systemImage: AppSymbol.download)
                }
            }
            .disabled(downloadService.state.isActive)
            #endif
        }
        if authService.isSignedIn {
            Section {
                if playlistId == "WL" {
                    Button(role: .destructive, action: removeFromWatchLater) {
                        menuLabel("Remove from Watch Later", AppSymbol.removeFromWatchLater)
                    }
                }
                Button(role: .destructive) {
                    state.confirmsNotInterested = true
                } label: {
                    menuLabel("Not Interested", AppSymbol.notInterested)
                }
                .accessibilityIdentifier(AccessibilityID.videoNotInterested)
                Button(role: .destructive) {
                    state.confirmsDontLike = true
                } label: {
                    menuLabel("Don't Like This Video", AppSymbol.thumbsDown)
                }
                .accessibilityIdentifier(AccessibilityID.videoDontLike)
                if Channel.ofCard(video) != nil {
                    Button(role: .destructive) {
                        state.confirmsDontRecommendChannel = true
                    } label: {
                        menuLabel("Don't Recommend Channel", AppSymbol.dontRecommendChannel)
                    }
                    .accessibilityIdentifier(AccessibilityID.videoDontRecommendChannel)
                }
            }
        }
    }

    @ViewBuilder private var secondaryMenuItems: some View {
        Button(action: playNext) { menuLabel("Play Next", AppSymbol.playNext) }
        Button {
            Task { await CurrentQueueStore.shared.append(video) }
        } label: {
            menuLabel("Add to Queue", AppSymbol.addToQueue)
        }
        if authService.isSignedIn {
            Button {
                state.playlistPickerMode = .copy
            } label: {
                menuLabel("Copy to Playlist", AppSymbol.copyToPlaylist)
            }
        }
        #if os(iOS)
        Button {
            playerRouter.open(video: video, api: api, incognito: true)
        } label: {
            menuLabel("Play Incognito", AppSymbol.incognito)
        }
        #endif
    }

    private func menuLabel(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label {
            Text(title, bundle: .module)
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// Right after the queue item the app player is playing, or first when it plays nothing from the queue.
    private func playNext() {
        #if os(iOS)
        let playingIndex = playerRouter.playingQueueIndex
        #else
        // The macOS and tvOS players live in the pushed player screen and stop when it closes, so nothing from the
        // queue plays while a card is on screen.
        let playingIndex: Int? = nil
        #endif
        Task { await CurrentQueueStore.shared.playNext(video, playingIndex: playingIndex) }
    }

    private func saveToWatchLater() {
        Task {
            do {
                let setVideoId = try await api.addToWatchLater(videoId: video.id)
                WatchLaterMembershipStore.shared.markSaved(video, setVideoId: setVideoId)
                showToast(String(localized: "Saved to Watch Later", bundle: .module))
            } catch {
                state.alert = DownloadAlertItem(
                    title: String(localized: "Could Not Save", bundle: .module),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func removeFromWatchLater() {
        // Removal is keyed by setVideoId (the playlist-entry token), not the video ID — see
        // InnerTubeAPI+Social.swift's removeFromWatchLater (#122). It's only populated when this card came from
        // browsing the WL playlist itself, which is the only place this button is shown. A video saved this session
        // may be listed before YouTube indexed it, without its own token; use the one returned when it was saved.
        guard let setVideoId = video.setVideoId ?? WatchLaterMembershipStore.shared.setVideoId(for: video.id) else {
            state.alert = DownloadAlertItem(
                title: String(localized: "Could Not Remove", bundle: .module),
                message: String(
                    localized: "Missing playlist entry information for \"\(video.title)\".",
                    bundle: .module)
            )
            return
        }
        Task {
            do {
                try await api.removeFromWatchLater(setVideoId: setVideoId)
                WatchLaterMembershipStore.shared.markRemoved(video.id)
                showToast(String(localized: "Removed from Watch Later", bundle: .module))
            } catch {
                state.alert = DownloadAlertItem(
                    title: String(localized: "Could Not Remove", bundle: .module),
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - More button

extension VerticalAlignment {
    private enum CardTextTop: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    /// Top of a card's text block, where its More button lines up.
    static let cardTextTop = VerticalAlignment(CardTextTop.self)
}

#if !os(tvOS)
/// A card's More button: a separate control (and VoiceOver element) next to the title, outside the card's tap area.
/// Place it with `.overlay(alignment: Alignment(horizontal: .trailing, vertical: .cardTextTop))` and give the text
/// block `.alignmentGuide(.cardTextTop) { $0[.top] }` and a trailing inset of `inset`.
struct VideoCardMoreButton: View {
    let video: Video
    let playlistId: String?
    let title: String
    /// `false` hides it (the Mac shows it only while the pointer is over the card).
    var visible = true
    let state: VideoCardMenuState

    /// Touch target on iPhone and iPad, pointer target on the Mac; the text keeps clear of it.
    static var inset: CGFloat {
        #if os(macOS)
        return VFTarget.pointer
        #else
        return VFTarget.touch
        #endif
    }

    var body: some View {
        Menu {
            VideoCardMenuItems(video: video, playlistId: playlistId, state: state)
        } label: {
            // The glyph stops growing at the largest standard size so it keeps clear of the title; the large
            // content viewer shows it enlarged on a long press.
            Image(systemName: AppSymbol.more)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.secondary)
                .frame(width: Self.inset, height: Self.inset)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel(Text("More: \(title)", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.videoCardMenu(video.id))
        // Centre the glyph on the first line of the title rather than the top of the text.
        .alignmentGuide(.cardTextTop) { $0[.top] + ($0.height - VFTarget.pointer) / 2 }
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(!visible)
    }
}
#endif

// MARK: - Presentation

extension View {
    /// The confirmations, sheets and alert the card menu opens, and on tvOS the Play/Pause command dialog. Attach it
    /// to the card's focusable element so tvOS Play/Pause reaches it.
    func videoCardMenu(video: Video, playlistId: String?, title: String, state: VideoCardMenuState) -> some View {
        modifier(VideoCardMenuPresenter(video: video, playlistId: playlistId, title: title, state: state))
    }
}

private struct VideoCardMenuPresenter: ViewModifier {
    let video: Video
    let playlistId: String?
    let title: String
    @Bindable var state: VideoCardMenuState

    @Environment(AuthService.self) private var authService
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.showToast) private var showToast

    func body(content: Content) -> some View {
        let presented =
            content
            .cardChannelSubscription(channel: Channel.ofCard(video), pending: $state.pendingUnsubscribe)
            .alert(Text("Not Interested", bundle: .module), isPresented: $state.confirmsNotInterested) {
                Button(role: .destructive) {
                    CardFeedback.hideVideo(
                        video, token: video.notInterestedToken, iconType: "NOT_INTERESTED", api: api,
                        showToast: showToast)
                } label: {
                    Text("Not Interested", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.videoFeedbackConfirm)
                cancelButton
            } message: {
                Text(video.title)
            }
            .alert(Text("Don't Like This Video", bundle: .module), isPresented: $state.confirmsDontLike) {
                Button(role: .destructive) {
                    CardFeedback.hideVideo(
                        video, token: video.dontLikeToken, iconType: "DISLIKE", api: api, showToast: showToast)
                } label: {
                    Text("Don't Like This Video", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.videoFeedbackConfirm)
                cancelButton
            } message: {
                Text(video.title)
            }
            .alert(Text("Don't Recommend Channel", bundle: .module), isPresented: $state.confirmsDontRecommendChannel) {
                Button(role: .destructive, action: dontRecommendChannel) {
                    Text("Don't Recommend Channel", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.videoFeedbackConfirm)
                cancelButton
            } message: {
                Text(video.channelTitle)
            }
            .sheet(isPresented: $state.showsOfflineDownload) { OfflineDownloadSheet(video: video) }
            .feedbackAlert(item: $state.alert)
            .sheet(item: $state.playlistPickerMode) { mode in
                PlaylistPickerSheet(
                    mode: mode, video: video, sourcePlaylistId: playlistId, api: api,
                    onFinished: handlePlaylistPickerResult
                )
            }
        #if os(tvOS)
        // Play/Pause opens the same commands as a dialog and never starts the video.
        presented
            .onPlayPauseCommand {
                state.showsActions = true
                // The dialog lists Subscribe or Unsubscribe once the (shared, cached) state is known.
                if Channel.ofCard(video) != nil {
                    let context = authService.subscriptionContext
                    Task { await SubscribedChannelsCache.shared.load(context, api: api) }
                }
            }
            .confirmationDialog(Text(title), isPresented: $state.showsActions, titleVisibility: .visible) {
                VideoCardMenuItems(video: video, playlistId: playlistId, nested: false, state: state)
            }
        #else
        presented
        #endif
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
        } label: {
            Text("Cancel", bundle: .module)
        }
        .accessibilityIdentifier(AccessibilityID.videoFeedbackCancel)
    }

    /// Blocks the channel only once YouTube accepted the feedback; a failure keeps it and says so.
    private func dontRecommendChannel() {
        guard let channelId = video.channelId, !channelId.isEmpty else { return }
        Task {
            do {
                if let token = video.hideChannelToken {
                    try await api.sendFeedback(token: token)
                } else {
                    try await api.sendFeedbackForVideo(videoId: video.id, iconType: "BLOCK_CHANNEL")
                }
                store.settings.blockedChannels[channelId] = video.channelTitle
                NotificationCenter.default.post(
                    name: .hideChannelFromFeed, object: nil, userInfo: ["channelId": channelId])
            } catch {
                showToast(CardFeedback.failedText)
            }
        }
    }

    private func handlePlaylistPickerResult(_ result: Result<PlaylistInfo, Error>) {
        switch result {
        case .success(let playlist):
            showToast(String(localized: "Added to \(playlist.title)", bundle: .module))
        case .failure(let error):
            state.alert = DownloadAlertItem(
                title: String(localized: "Could Not Update Playlist", bundle: .module),
                message: error.localizedDescription
            )
        }
    }
}

@MainActor private enum CardFeedback {
    static var failedText: String {
        String(localized: "Couldn't send feedback. Try again.", bundle: .module)
    }

    /// Not Interested and Don't Like This Video: the menu token when the feed sent one, else the icon type. Hides the
    /// card only once YouTube accepted the feedback; a failure keeps it and says so.
    static func hideVideo(
        _ video: Video, token: String?, iconType: String, api: InnerTubeAPI, showToast: ShowToastAction
    ) {
        Task {
            do {
                if let token {
                    try await api.sendFeedback(token: token)
                } else {
                    try await api.sendFeedbackForVideo(videoId: video.id, iconType: iconType)
                }
                NotificationCenter.default.post(name: .hideVideoFromFeed, object: nil, userInfo: ["videoId": video.id])
            } catch {
                showToast(failedText)
            }
        }
    }
}
