import SmartTubeIOSCore
import SwiftUI
import os

private let focusLog = Logger(subsystem: "com.smarttube", category: "focus")
private let feedLog = Logger(subsystem: "com.smarttube", category: "feed")

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the user selects "Open Channel" from a video's context menu.
    /// userInfo keys: "channelId", "channelTitle"
    static let openChannel = Notification.Name("com.smarttube.openChannel")
    /// Posted when a feature requests navigation to the Search tab (e.g. empty-state CTA).
    static let navigateToSearch = Notification.Name("com.smarttube.navigateToSearch")
    // hideVideoFromFeed and hideChannelFromFeed are defined in SmartTubeIOSCore/FeedFeedbackNotifications.swift
}

extension VerticalAlignment {
    private enum CardTextTop: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    /// Top of a card's text block, where its More button lines up.
    fileprivate static let cardTextTop = VerticalAlignment(CardTextTop.self)
}

// MARK: - VideoCardView
//
// VF/VideoCard: a 16:9 cover with duration, Live or Upcoming tag, watch progress and the Watch Later mark, then title,
// channel and metadata. Grid (default) or compact row. The card is one accessibility element that reads everything
// once and carries the menu as actions; the menu also opens from the context menu, from a More button on iPhone and
// iPad (on hover on the Mac) and from Play/Pause on tvOS.

public struct VideoCardView: View {
    public let video: Video
    public var compact: Bool = false
    /// When set, this is the `playlistId` of the list the user is currently browsing.
    /// Pass `"WL"` when inside the Watch Later playlist so the context menu shows
    /// "Remove from Watch Later" instead of "Save to Watch Later".
    public var currentPlaylistId: String? = nil
    /// Opens the video. tvOS calls it on Select; elsewhere it is the VoiceOver default action and callers keep their
    /// own tap gesture (cards on the Channel and Playlist screens pass none and keep VoiceOver's plain activation).
    public var onSelect: (() -> Void)? = nil

    // Not private where VideoCardView+Menu.swift needs them.
    @Environment(AuthService.self) var authService
    @Environment(SettingsStore.self) var store
    @Environment(\.innerTubeAPI) var api
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(PlayerRouter.self) var playerRouter
    #endif
    @State private var isSavedOffline = false
    @State private var localProgress: Double?
    @State private var isVisibleForPrefetch = false
    @State var watchLaterAlert: DownloadAlertItem?
    @State var showsOfflineDownload = false
    @State var playlistPickerMode: PlaylistPickerSheet.Mode?
    /// Index into `video.thumbnailFallbackURLs`. -1 = use primary `thumbnailURL`.
    @State private var thumbnailFallbackIndex: Int = -1
    #if !os(tvOS) && ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) var downloadService
    #endif
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    @State private var showsActions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #elseif os(macOS)
    @State private var isHovering = false
    #endif

    private var effectiveProgress: Double? {
        localProgress ?? video.watchProgress
    }

    /// #125: falls back to `video.playlistId` when the caller doesn't explicitly pass
    /// `currentPlaylistId` (e.g. the "Watch Later" home tab, which renders through the
    /// generic BrowseView grid that has no per-card playlist context of its own) — lets
    /// Remove/Move-to-Playlist actions work there too, not just from PlaylistView.
    var effectivePlaylistId: String? {
        currentPlaylistId ?? video.playlistId
    }

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    public init(video: Video, compact: Bool = false, currentPlaylistId: String? = nil, onSelect: (() -> Void)? = nil) {
        self.video = video
        self.compact = compact
        self.currentPlaylistId = currentPlaylistId
        self.onSelect = onSelect
    }

    // MARK: - Shared card content (tasks + menus)

    @ViewBuilder private var layout: some View {
        if compact {
            compactLayout
        } else {
            gridLayout
        }
    }

    /// The card as one accessibility element: what it shows, read once, with the menu commands as actions.
    private var summary: some View {
        layout
            // #153: without an explicit content shape, the gaps between cover and text are untappable — very
            // noticeable with a precise pointer on macOS. Callers attach their tap gesture to the whole card.
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityActions { menuItems }
            .modifier(DefaultAccessibilityAction(action: onSelect))
    }

    private var cardContent: some View {
        summary
            .background { OfflineSavedObserver(videoID: video.id) { isSavedOffline = $0 } }
            .onScrollVisibilityChange { isVisibleForPrefetch = $0 }
            .task {
                localProgress = await VideoStateStore.shared.state(for: video.id)?.watchedFraction
            }
            .task(id: isVisibleForPrefetch ? video.id : nil) {
                guard isVisibleForPrefetch else { return }
                await VideoPreloadCache.shared.prefetch(
                    videoId: video.id,
                    sponsorCategories: store.settings.activeSponsorCategories,
                    authToken: authService.accessToken,
                    priority: .visible
                )
            }
            .contextMenu {
                menuItems
            } preview: {
                layout
                    .padding(VFSpace.s12)
                    .frame(width: 300)
                    .background(.background)
            }
    }
}

extension VideoCardView {

    // MARK: - Body

    public var body: some View {
        // The card's identity for UI automation, set once for every screen that shows cards.
        cardBody
            .accessibilityIdentifier(AccessibilityID.videoCard(video.id))
            .accessibilityValue(video.isShort ? "short" : "")
    }

    @ViewBuilder private var cardBody: some View {
        #if os(tvOS)
        // Modifier order is critical on tvOS:
        //
        //   cardContent  (contains .contextMenu — handles long press)
        //       .focusable()          — registers view with focus engine (D-pad navigation)
        //       .onTapGesture { }     — fires on Select press (outermost → receives event first)
        //       .focused($isFocused)  — tracks focus state (does not consume events)
        //
        // Why this order works:
        // • .onTapGesture outermost → Select button press fires the action.
        //   (.focusable() outermost broke Select because the focus engine intercepted
        //    the primary-action event before the inner tap gesture could see it.)
        // • .contextMenu innermost, co-located in the same modifier chain as
        //   .onTapGesture → SwiftUI's gesture arbiter can cancel the pending tap
        //   recogniser when it detects a long press, so long press shows the menu
        //   without also playing the video.
        // • .focusable() between contextMenu and onTapGesture keeps the view in the
        //   focus engine so D-pad UP/DOWN can reach it.
        // Play/Pause opens the same commands as a dialog and never starts the video.
        cardContent
            .focusable()
            .onTapGesture { onSelect?() }
            .focused($isFocused)
            .onPlayPauseCommand { showsActions = true }
            .confirmationDialog(Text(displayTitle), isPresented: $showsActions, titleVisibility: .visible) {
                menuItems
            }
            .onAppear { feedLog.info("[feed] id=\(self.video.id) title=\(self.video.title)") }
            .onChange(of: isFocused) { _, newValue in
                focusLog.info("[VideoCard] isFocused=\(newValue) id=\(self.video.id)")
                #if canImport(WebKit)
                if newValue, !video.isShort {
                    let videoId = video.id
                    Task(priority: .background) {
                        await YouTubeWebViewHLSExtractor.preWarm(videoId: videoId)
                    }
                }
                #endif
            }
            // Lift and glow; Reduce Motion keeps the glow and drops the scale.
            .shadow(color: isFocused ? .white.opacity(0.9) : .clear, radius: 18, x: 0, y: 0)
            .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1.0)
            .zIndex(isFocused ? 1 : 0)
            .vfAnimation(VFMotion.fast, value: isFocused)
            .sheet(isPresented: $showsOfflineDownload) { OfflineDownloadSheet(video: video) }
            .feedbackAlert(item: $watchLaterAlert)
            .sheet(item: $playlistPickerMode) { mode in
                PlaylistPickerSheet(
                    mode: mode, video: video, sourcePlaylistId: effectivePlaylistId, api: api,
                    onFinished: handlePlaylistPickerResult
                )
            }
        #else
        let card =
            cardContent
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .cardTextTop)) { moreButton }
            .onAppear { feedLog.info("[feed] id=\(self.video.id) title=\(self.video.title)") }
            .sheet(isPresented: $showsOfflineDownload) { OfflineDownloadSheet(video: video) }
            .feedbackAlert(item: $watchLaterAlert)
            .sheet(item: $playlistPickerMode) { mode in
                PlaylistPickerSheet(
                    mode: mode, video: video, sourcePlaylistId: effectivePlaylistId, api: api,
                    onFinished: handlePlaylistPickerResult
                )
            }
        #if os(macOS)
        card.onHover { isHovering = $0 }
        #else
        // A container for the summary and the More button. The Mac shows More only on hover, hidden from accessibility.
        card.accessibilityElement(children: .contain)
        #endif
        #endif
    }

    // MARK: More button

    #if !os(tvOS)
    /// Touch target on iPhone and iPad, pointer target on the Mac; the text keeps clear of it.
    private var moreTarget: CGFloat {
        #if os(macOS)
        return VFTarget.pointer
        #else
        return VFTarget.touch
        #endif
    }

    /// A separate control (and VoiceOver element) next to the title, outside the card's tap area.
    /// The Mac shows it while the pointer is over the card, next to the context menu.
    private var moreButton: some View {
        Menu {
            menuItems
        } label: {
            // The glyph stops growing at the largest standard size so it keeps clear of the title; the large
            // content viewer shows it enlarged on a long press.
            Image(systemName: AppSymbol.more)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.secondary)
                .frame(width: moreTarget, height: moreTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel(Text("More: \(displayTitle)", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.videoCardMenu(video.id))
        // Centre the glyph on the first line of the title rather than the top of the text.
        .alignmentGuide(.cardTextTop) { $0[.top] + ($0.height - VFTarget.pointer) / 2 }
        .opacity(moreButtonVisible ? 1 : 0)
        .accessibilityHidden(!moreButtonVisible)
    }

    private var moreButtonVisible: Bool {
        #if os(macOS)
        return isHovering
        #else
        return true
        #endif
    }
    #endif

    /// Space the text leaves for the More button.
    private var moreButtonInset: CGFloat {
        #if os(tvOS)
        return 0
        #else
        return moreTarget
        #endif
    }

    // MARK: Grid layout (default)

    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: VFSpace.s8) {
            cover(cornerRadius: VFRadius.card)
            textBlock(reservesTitleSpace: true)
                .padding(.trailing, moreButtonInset)
        }
    }

    // MARK: Compact (list) layout

    #if os(tvOS)
    private static let compactCoverWidth: CGFloat = 296
    #else
    private static let compactCoverWidth: CGFloat = 148
    #endif

    /// Cover beside the text; at accessibility text sizes the cover goes above it at full width.
    private var compactLayout: some View {
        let stack =
            isLargeText
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VFSpace.s12))
        return stack {
            cover(cornerRadius: VFRadius.small)
                .frame(width: isLargeText ? nil : Self.compactCoverWidth)
            textBlock(reservesTitleSpace: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, moreButtonInset)
        }
    }

    // MARK: Text

    /// Title, channel and metadata in semantic styles. At accessibility sizes every line wraps instead of truncating.
    private func textBlock(reservesTitleSpace: Bool) -> some View {
        VStack(alignment: .leading, spacing: VFSpace.s4 / 2) {
            let title = Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                // UI tests compare the exact title, apart from the spoken summary.
                .accessibilityIdentifier(AccessibilityID.videoCardTitle)
            if isLargeText {
                title.fixedSize(horizontal: false, vertical: true)
            } else {
                title.lineLimit(2, reservesSpace: reservesTitleSpace)
            }
            Text(video.channelTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(isLargeText ? nil : 1)
                .onTapGesture(perform: openChannel)
            if let metadata = metadataText {
                metadata
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isLargeText ? nil : 1)
            }
        }
        .alignmentGuide(.cardTextTop) { $0[.top] }
    }

    /// Views and age; the scheduled start for an upcoming video; "DeArrow" when it replaced the title or cover.
    /// At accessibility sizes it starts with the cover badge's text, since the badge stops growing at xxxLarge.
    private var metadataText: Text? {
        var parts: [String] = []
        if isLargeText, let badge = coverBadgeText { parts.append(badge) }
        if video.isUpcoming {
            if let start = video.publishedAt { parts.append(start.formatted(Self.scheduleFormat)) }
        } else {
            parts.append(video.formattedViewCount)
            if !video.isLive, let age = video.publishedAgeLabel() { parts.append(age) }
        }
        let line = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        guard isDeArrowed else { return line.isEmpty ? nil : Text(line) }
        let marker = Text("DeArrow", bundle: .module).fontWeight(.semibold).foregroundStyle(.tint)
        return line.isEmpty ? marker : Text(verbatim: "\(line) · ") + marker  // verbatim: data plus separator
    }

    private static let scheduleFormat = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()

    /// What the cover badge says: LIVE, Upcoming or the duration.
    private var coverBadgeText: String? {
        if video.isLive { return String(localized: "LIVE", bundle: .module) }
        if video.isUpcoming { return String(localized: "Upcoming", bundle: .module) }
        let duration = video.formattedDuration
        return duration.isEmpty ? nil : duration
    }

    /// What VoiceOver reads for the card: duration once, then views, age, Watch Later and progress.
    /// The title always leads (UI tests read it as the label's prefix); empty details are left out.
    private var accessibilitySummary: Text {
        var parts = [video.channelTitle]
        if video.isLive {
            parts.append(String(localized: "LIVE", bundle: .module))
        } else if video.isUpcoming {
            parts.append(String(localized: "Upcoming", bundle: .module))
            if let start = video.publishedAt { parts.append(start.formatted(Self.scheduleFormat)) }
        } else if let duration = video.accessibilityDuration {
            parts.append(duration)
        }
        parts.append(video.formattedViewCount)
        if !video.isLive, !video.isUpcoming, let age = video.publishedAgeLabel() { parts.append(age) }
        if WatchLaterMembershipStore.shared.contains(video.id) {
            parts.append(String(localized: "Saved to Watch Later", bundle: .module))
        }
        if isSavedOffline { parts.append(String(localized: "Saved offline", bundle: .module)) }
        if let progress = effectiveProgress, progress > 0 {
            let percent = progress.formatted(.percent.precision(.fractionLength(0)))
            parts.append(String(localized: "\(percent) watched", bundle: .module))
        }
        return Text(([displayTitle] + parts.filter { !$0.isEmpty }).joined(separator: ", "))
    }

    // MARK: Cover

    private func cover(cornerRadius: CGFloat) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(thumbnailView.clipped())
            .overlay(alignment: .bottom) {
                if let progress = effectiveProgress, progress > 0 {
                    watchProgressBar(progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                let duration = video.formattedDuration
                if !video.isLive, !video.isUpcoming, !duration.isEmpty {
                    MediaBadge { Text(duration) }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if video.isLive {
                    MediaBadge {
                        HStack(spacing: VFSpace.s4) {
                            Image(systemName: AppSymbol.liveDot)
                                .imageScale(.small)
                                .foregroundStyle(.red)
                            Text("LIVE", bundle: .module)
                        }
                    }
                } else if video.isUpcoming {
                    MediaBadge { Text("Upcoming", bundle: .module).textCase(.uppercase) }
                } else if isSavedOffline {
                    MediaBadge { Image(systemName: AppSymbol.offlineSaved) }
                }
            }
            .overlay(alignment: .topTrailing) {
                if WatchLaterMembershipStore.shared.contains(video.id) { watchLaterSavedMark }
            }
    }

    /// Returns the DeArrow thumbnail URL if the feature is enabled and a timestamp is available.
    private var deArrowThumbnailURL: URL? {
        guard store.settings.deArrowEnabled,
            let ts = video.deArrowThumbnailTimestamp
        else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(video.id)/\(Int(ts)).jpg")
    }

    /// The title to show — community de-arrow title when enabled, raw title otherwise.
    private var displayTitle: String {
        if store.settings.deArrowEnabled, let t = video.deArrowTitle { return t }
        return video.title
    }

    private var isDeArrowed: Bool {
        store.settings.deArrowEnabled && (video.deArrowTitle != nil || video.deArrowThumbnailTimestamp != nil)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if video.thumbnailURL == nil, video.id == "WL" || video.id == "LL" {
            systemPlaylistThumbnail
        } else {
            // Walk a fallback chain on each successive failure:
            //   -1 → deArrowThumbnailURL (community thumbnail), else maxresdefault.jpg when
            //        High Resolution is on, else thumbnailURL (API-provided)
            //    (High Resolution only: hq720.jpg, then the standard chain below)
            //    0 → sddefault.jpg  (640×480, available for most videos)
            //    1 → hqdefault.jpg  (480×360, always available)
            //    2 → mqdefault.jpg  (320×180, always available — last resort)
            // High-res URLs are built from `/vi/<id>/`, so they only make sense for real
            // videos: playlist placeholder cards (Playlists section: id == playlistId) would
            // walk the whole chain against a playlist ID and end on a grey placeholder, and
            // Shorts would swap their portrait thumbnail for a landscape one.
            let highRes =
                store.settings.highResThumbnails && video.playlistId != video.id && !video.isShort
            let fallbacks = highRes ? video.highResThumbnailFallbackURLs : video.thumbnailFallbackURLs
            let url: URL? =
                thumbnailFallbackIndex < 0
                ? (deArrowThumbnailURL ?? (highRes ? video.maxResThumbnailURL : video.thumbnailURL) ?? fallbacks.first)
                : (thumbnailFallbackIndex < fallbacks.count ? fallbacks[thumbnailFallbackIndex] : nil)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    let nextIndex = thumbnailFallbackIndex + 1
                    if nextIndex < fallbacks.count {
                        placeholderThumbnail
                            .onAppear { thumbnailFallbackIndex = nextIndex }
                    } else {
                        missingCover
                    }
                default:
                    // Loading draws the empty surface, like the design's skeleton.
                    if url == nil {
                        missingCover
                    } else {
                        placeholderThumbnail
                    }
                }
            }
            .task(id: video.id) {
                // Reset so a reused card slot always tries the primary URL for the new video.
                thumbnailFallbackIndex = -1
                #if canImport(WebKit) && !os(iOS)
                await BotGuardWebViewRunner.shared.prepare()
                if !video.isShort {
                    let videoId = video.id
                    while !Task.isCancelled {
                        await YouTubeWebViewHLSExtractor.preWarm(videoId: videoId)
                        if await VideoPreloadCache.shared.cachedWKHLSURL(for: videoId) != nil { break }
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                    }
                }
                #endif
            }
        }
    }

    private var systemPlaylistThumbnail: some View {
        let icon = video.id == "WL" ? AppSymbol.watchLaterPlaylist : AppSymbol.likedPlaylist
        return ZStack {
            VFColor.surface
            Image(systemName: icon)
                .font(.largeTitle.weight(.light))
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderThumbnail: some View {
        VFColor.surface
    }

    /// No cover at all: the surface with a play symbol, so the card does not look like it is still loading.
    private var missingCover: some View {
        VFColor.surface.overlay {
            Image(systemName: AppSymbol.noCover)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    /// The fill runs on an opaque track in the page background, so it keeps its contrast over any frame: every accent
    /// reaches 4.5:1 on `background` in both themes (DesignTokenTests.accentPairsAreReadable).
    private func watchProgressBar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tint)
                .frame(width: geo.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: VFSpace.s4)
        .background(.background)
    }

    /// #39: shown when this video was saved to Watch Later via this app. See
    /// WatchLaterMembershipStore's doc comment for why this can't reflect Watch
    /// Later state from other clients.
    private var watchLaterSavedMark: some View {
        Image(systemName: AppSymbol.savedToWatchLater)
            .font(.caption.weight(.semibold))
            .foregroundStyle(VFColor.onMedia)
            .padding(VFSpace.s8)
            .background(VFColor.scrim, in: Circle())
            .padding(VFSpace.s8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - MediaBadge

/// Duration, Live and Upcoming labels on a cover: white on the 72 % scrim, whatever the frame behind it.
/// Capped at the largest standard text size so it never hides the cover; at accessibility sizes the cards repeat
/// its text under the title, and VoiceOver reads the card's label.
struct MediaBadge<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(VFColor.onMedia)
            .lineLimit(1)
            .padding(.horizontal, VFSpace.s8)
            .padding(.vertical, VFSpace.s4 / 2)
            .background(VFColor.scrim, in: RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
            .padding(VFSpace.s8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension Video {
    /// Duration as words ("12 minutes, 4 seconds") for VoiceOver; `nil` without a duration.
    var accessibilityDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

/// VoiceOver activation opens the video through `action` when the caller passes one; otherwise it taps the card.
private struct DefaultAccessibilityAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(.default, action)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VideoCardView(
        video: Video(
            id: "dQw4w9WgXcQ",
            title: "Rick Astley – Never Gonna Give You Up",
            channelTitle: "Rick Astley",
            duration: 213,
            viewCount: 1_400_000_000
        )
    )
    .frame(width: 320)
    .padding()
}
#endif
