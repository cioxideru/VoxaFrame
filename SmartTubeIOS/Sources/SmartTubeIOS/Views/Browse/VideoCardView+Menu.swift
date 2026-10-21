import SmartTubeIOSCore
import SwiftUI

// MARK: - VideoCardView menu
//
// The card's commands in one place: the context menu, the More button, the VoiceOver actions and the tvOS Play/Pause
// dialog all show `menuItems`. Order follows the design (P-Menus): share and channel, playback and lists, feedback.

extension VideoCardView {
    /// Every card command, used by the context menu, the More button, VoiceOver actions and the tvOS dialog.
    @ViewBuilder func menuItems(nested: Bool = true) -> some View {
        Section {
            #if !os(tvOS)
            if let shareURL = video.shareURL {
                ShareLink(item: shareURL) { menuLabel("Share", AppSymbol.share) }
            }
            #endif
            if hasChannel {
                Button(action: openChannel) { menuLabel("Open Channel", AppSymbol.personRectangle) }
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
                if effectivePlaylistId != "WL" {
                    Button(action: saveToWatchLater) { menuLabel("Save to Watch Later", AppSymbol.watchLater) }
                }
                if effectivePlaylistId != nil {
                    Button {
                        playlistPickerMode = .move
                    } label: {
                        menuLabel("Move to Playlist", AppSymbol.moveToPlaylist)
                    }
                }
            }
            OfflineWatchButton(video: video) { showsOfflineDownload = true }
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
                if effectivePlaylistId == "WL" {
                    Button(role: .destructive, action: removeFromWatchLater) {
                        menuLabel("Remove from Watch Later", AppSymbol.removeFromWatchLater)
                    }
                }
                Button(role: .destructive) {
                    confirmsNotInterested = true
                } label: {
                    menuLabel("Not Interested", AppSymbol.notInterested)
                }
                .accessibilityIdentifier(AccessibilityID.videoNotInterested)
                if hasChannel {
                    Button(role: .destructive) {
                        confirmsDontRecommendChannel = true
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
                playlistPickerMode = .copy
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

    func menuLabel(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label {
            Text(title, bundle: .module)
        } icon: {
            Image(systemName: symbol)
        }
    }

    var hasChannel: Bool { video.channelId?.isEmpty == false }

    func openChannel() {
        guard let channelId = video.channelId, !channelId.isEmpty else { return }
        NotificationCenter.default.post(
            name: .openChannel,
            object: nil,
            userInfo: ["channelId": channelId, "channelTitle": video.channelTitle]
        )
    }

    /// Right after the queue item the app player is playing, or first when it plays nothing from the queue.
    func playNext() {
        #if os(iOS)
        let playingIndex = playerRouter.playingQueueIndex
        #else
        // The macOS and tvOS players live in the pushed player screen and stop when it closes, so nothing from the
        // queue plays while a card is on screen.
        let playingIndex: Int? = nil
        #endif
        Task { await CurrentQueueStore.shared.playNext(video, playingIndex: playingIndex) }
    }

    func saveToWatchLater() {
        Task {
            do {
                let setVideoId = try await api.addToWatchLater(videoId: video.id)
                WatchLaterMembershipStore.shared.markSaved(video, setVideoId: setVideoId)
                showToast(String(localized: "Saved to Watch Later", bundle: .module))
            } catch {
                watchLaterAlert = DownloadAlertItem(
                    title: String(localized: "Could Not Save", bundle: .module),
                    message: error.localizedDescription
                )
            }
        }
    }

    func removeFromWatchLater() {
        // Removal is keyed by setVideoId (the playlist-entry token), not the video ID — see
        // InnerTubeAPI+Social.swift's removeFromWatchLater (#122). It's only populated when this card came from
        // browsing the WL playlist itself, which is the only place this button is shown. A video saved this session
        // may be listed before YouTube indexed it, without its own token; use the one returned when it was saved.
        guard let setVideoId = video.setVideoId ?? WatchLaterMembershipStore.shared.setVideoId(for: video.id) else {
            watchLaterAlert = DownloadAlertItem(
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
                watchLaterAlert = DownloadAlertItem(
                    title: String(localized: "Could Not Remove", bundle: .module),
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Hides the card only once YouTube accepted the feedback; a failure keeps it and says so.
    func notInterested() {
        Task {
            do {
                if let token = video.notInterestedToken {
                    try await api.sendFeedback(token: token)
                } else {
                    try await api.sendFeedbackForVideo(videoId: video.id, iconType: "NOT_INTERESTED")
                }
                NotificationCenter.default.post(name: .hideVideoFromFeed, object: nil, userInfo: ["videoId": video.id])
            } catch {
                showToast(Self.feedbackFailedText)
            }
        }
    }

    func dontRecommendChannel() {
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
                showToast(Self.feedbackFailedText)
            }
        }
    }

    /// Shared with the Shorts card.
    static var feedbackFailedText: String {
        String(localized: "Couldn't send feedback. Try again.", bundle: .module)
    }

    func handlePlaylistPickerResult(_ result: Result<PlaylistInfo, Error>) {
        switch result {
        case .success(let playlist):
            showToast(String(localized: "Added to \(playlist.title)", bundle: .module))
        case .failure(let error):
            watchLaterAlert = DownloadAlertItem(
                title: String(localized: "Could Not Update Playlist", bundle: .module),
                message: error.localizedDescription
            )
        }
    }
}
