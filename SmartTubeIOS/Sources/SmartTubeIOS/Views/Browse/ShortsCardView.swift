import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsCardView
//
// VF/ShortsCard, shelf variant: a 9:16 cover with the duration, then title (two lines) and channel.
// Callers set the width; the height follows the cover and the text. One accessibility element that opens the Short
// and carries the Shorts menu (its own reduced set) as actions. Used inside ShortsRowSection.

struct ShortsCardView: View {
    let video: Video
    let onTap: () -> Void

    @Environment(AuthService.self) private var authService
    @Environment(SettingsStore.self) private var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif
    @State private var watchLaterAlert: DownloadAlertItem?
    @State private var confirmsNotInterested = false
    @State private var confirmsDontRecommendChannel = false
    #if !os(tvOS) && ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) private var downloadService
    #endif

    /// Primary thumbnail URL: portrait oardefault.jpg when the API provided one
    /// (reelItemRenderer), landscape thumbnailURL otherwise.
    /// YouTube returns HTTP 200 with a blank black image for oardefault.jpg when
    /// no portrait thumbnail exists, so we skip it for non-reelItemRenderer Shorts.
    private var primaryURL: URL? {
        video.hasPortraitThumbnail ? video.portraitThumbnailURL : video.thumbnailURL
    }

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.s8) {
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay(ThumbnailFillView(primaryURL: primaryURL, fallbackURLs: video.thumbnailFallbackURLs))
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    let duration = video.formattedDuration
                    if !duration.isEmpty {
                        MediaBadge { Text(duration) }
                    }
                }
            VStack(alignment: .leading, spacing: VFSpace.s4 / 2) {
                // Two reserved lines keep a row even; at accessibility sizes the text wraps in full instead.
                let title = Text(video.title).font(.footnote.weight(.semibold))
                if isLargeText {
                    title.fixedSize(horizontal: false, vertical: true)
                } else {
                    title.lineLimit(2, reservesSpace: true)
                }
                if !video.channelTitle.isEmpty {
                    Text(video.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isLargeText ? nil : 1)
                }
                // The duration badge stops growing at xxxLarge, so accessibility sizes repeat it as text.
                if isLargeText, !video.formattedDuration.isEmpty {
                    Text(video.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                [video.title, video.channelTitle, video.accessibilityDuration ?? ""].filter { !$0.isEmpty }
                    .joined(separator: ", "))
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .accessibilityActions { menuItems(nested: false) }
        .contextMenu { menuItems() }
        .feedbackAlert(item: $watchLaterAlert)
        .alert(Text("Not Interested", bundle: .module), isPresented: $confirmsNotInterested) {
            Button(role: .destructive) {
                sendFeedback(token: video.notInterestedToken, iconType: "NOT_INTERESTED")
            } label: {
                Text("Not Interested", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.videoFeedbackConfirm)
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.videoFeedbackCancel)
        } message: {
            Text(video.title)
        }
        .alert(Text("Don't Recommend Channel", bundle: .module), isPresented: $confirmsDontRecommendChannel) {
            Button(role: .destructive) {
                if let channelId = video.channelId, !channelId.isEmpty { dontRecommendChannel(channelId) }
            } label: {
                Text("Don't Recommend Channel", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.videoFeedbackConfirm)
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.videoFeedbackCancel)
        } message: {
            Text(video.channelTitle)
        }
    }

    // MARK: - Menu

    /// The Shorts set: no Offline watch, playlists or Incognito (functional brief §6).
    @ViewBuilder private func menuItems(nested: Bool = true) -> some View {
        Section {
            #if !os(tvOS)
            if let shareURL = video.shareURL {
                ShareLink(item: shareURL) { menuLabel("Share", AppSymbol.share) }
            }
            #endif
            if let channelId = video.channelId, !channelId.isEmpty {
                Button {
                    NotificationCenter.default.post(
                        name: .openChannel,
                        object: nil,
                        userInfo: ["channelId": channelId, "channelTitle": video.channelTitle]
                    )
                } label: {
                    menuLabel("Open Channel", AppSymbol.personRectangle)
                }
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
                Button(action: saveToWatchLater) { menuLabel("Save to Watch Later", AppSymbol.watchLater) }
            }
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
                Button(role: .destructive) {
                    confirmsNotInterested = true
                } label: {
                    menuLabel("Not Interested", AppSymbol.notInterested)
                }
                .accessibilityIdentifier(AccessibilityID.videoNotInterested)
                Button(role: .destructive) {
                    sendFeedback(token: video.dontLikeToken, iconType: "DISLIKE")
                } label: {
                    menuLabel("Don't Like This Video", AppSymbol.thumbsDown)
                }
                if let channelId = video.channelId, !channelId.isEmpty {
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
        let playingIndex: Int? = nil
        #endif
        Task { await CurrentQueueStore.shared.playNext(video, playingIndex: playingIndex) }
    }

    private func saveToWatchLater() {
        Task {
            do {
                try await api.addToWatchLater(videoId: video.id)
                watchLaterAlert = DownloadAlertItem(
                    title: String(localized: "Saved to Watch Later", bundle: .module),
                    message: String(
                        localized: "\"\(video.title)\" was added to your Watch Later playlist.",
                        bundle: .module)
                )
            } catch {
                watchLaterAlert = DownloadAlertItem(
                    title: String(localized: "Could Not Save", bundle: .module),
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Not Interested and Don't Like This Video: the menu token when the feed sent one, else the icon type.
    private func sendFeedback(token: String?, iconType: String) {
        Task {
            if let token {
                try? await api.sendFeedback(token: token)
            } else {
                try? await api.sendFeedbackForVideo(videoId: video.id, iconType: iconType)
            }
            NotificationCenter.default.post(name: .hideVideoFromFeed, object: nil, userInfo: ["videoId": video.id])
        }
    }

    private func dontRecommendChannel(_ channelId: String) {
        Task {
            if let token = video.hideChannelToken {
                try? await api.sendFeedback(token: token)
            } else {
                try? await api.sendFeedbackForVideo(videoId: video.id, iconType: "BLOCK_CHANNEL")
            }
            store.settings.blockedChannels[channelId] = video.channelTitle
            NotificationCenter.default.post(name: .hideChannelFromFeed, object: nil, userInfo: ["channelId": channelId])
        }
    }
}
