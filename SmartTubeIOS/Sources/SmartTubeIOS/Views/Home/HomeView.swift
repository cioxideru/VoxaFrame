import SmartTubeIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - HomeView
//
// YouTube-style home tab.  A horizontal chip bar at the top lets the user
// switch between every available section:
//   • "Home"  chip  → multi-shelf overview (Subscriptions row,
//                      Recommended row) driven by HomeViewModel.
//   • Any other chip → full-screen video feed for that section driven by a
//                      dedicated BrowseViewModel instance.

public struct HomeView: View {
    @Environment(HomeViewModel.self) private var homeVM
    @State var sectionVM: BrowseViewModel
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLandscapeLayout) private var isLandscapeLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // "Home" is always first; its type is .home.
    @State var selectedSection: BrowseSection = BrowseSection.allSections[0]
    @State private var selectedVideo: Video?
    @State var selectedPlaylist: Video?
    @State private var shortsPresentation: ShortsPresentation?
    @State private var channelDestination: ChannelDestination?
    /// #62: nil = show every subscribed channel's videos. Session-only (not persisted
    /// to AppSettings) — reset when the Subscriptions videoGroups reload from scratch,
    /// same lifetime as a search filter rather than a durable preference.
    @State var subscriptionsChannelFilter: String?
    @State private var showSignIn = false
    /// Where the Home feed's Shorts rows sit; reset whenever the feed is replaced.
    @State private var homeLayout = HomeFeedLayout()
    @State private var sectionLayout = HomeFeedLayout()
    @State private var homeFeedHeight: CGFloat = 0
    /// Width of the content area; the video grids drop columns rather than go below `VFMargin.cardMinWidth`.
    @State private var feedWidth: CGFloat = 0
    @State var queueVideosCount: Int = 0
    // Auto-retry tracking: record the type-specific video count at the moment a
    // scroll trigger fires so onChange can detect whether the next page helped.
    @State var needsMoreShorts = false
    @State var shortsCountAtTrigger = 0
    @State var needsMoreNonShorts = false
    @State var nonShortsCountAtTrigger = 0
    #if os(tvOS)
    @FocusState private var focusedSection: BrowseSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif
    private var visibleSections: [BrowseSection] {
        let types = store.settings.enabledSections
        var all: [BrowseSection] =
            types.isEmpty
            ? BrowseSection.defaultSections
            : types.compactMap { type in BrowseSection.allSections.first { $0.type == type } }
        // Always keep a "Recommended" chip directly after the "Home" chip so the
        // user can filter to only recommended videos regardless of settings.
        if !all.contains(where: { $0.type == .recommended }),
            let homeIdx = all.firstIndex(where: { $0.type == .home })
        {
            all.insert(BrowseSection(type: .recommended), at: homeIdx + 1)
        }
        if store.settings.hideShorts {
            return all.filter { $0.type != .shorts }
        }
        return all
    }

    public init(api: InnerTubeAPI) {
        _sectionVM = State(initialValue: BrowseViewModel(api: api))
    }

    /// Columns of every video grid on this screen; the Shorts rows are placed by the same count.
    var feedColumns: Int {
        videoGridColumnCount(
            store.settings, landscape: isLandscapeLayout, width: feedWidth, dynamicTypeSize: dynamicTypeSize)
    }

    #if os(iOS)
    private var navigationBarVisibility: Visibility {
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Window controls also occupy the top of compact iPadOS 26 windows.
            if #available(iOS 26.0, *) { return .visible }
            if horizontalSizeClass == .regular { return .visible }
        }
        #endif
        return .hidden
    }
    #endif

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            chipBar
            contentArea
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    feedWidth = $0
                }
                .onChange(of: store.settings.hideWatchedVideos ? store.settings.hideWatchedThreshold : nil) {
                    homeLayout = HomeFeedLayout()
                    sectionLayout = HomeFeedLayout()
                }
                #if !os(iOS)
            .navigationDestination(item: $selectedVideo) { video in
                PlayerView(video: video, api: api)
            }
                #endif
                .navigationDestination(item: $selectedPlaylist) { stub in
                    PlaylistView(playlistId: stub.id, playlistTitle: stub.title, api: api)
                }
                .navigationDestination(item: $channelDestination) { dest in
                    ChannelView(channelId: dest.channelId, api: api)
                }
                #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(iOS)
        // Keep the shared iPad tab/navigation-bar region reserved after returning from a destination.
        .toolbar(navigationBarVisibility, for: .navigationBar)
        .navigationBarTitleDisplayMode(navigationBarVisibility == .visible ? .inline : .automatic)
        // Player cover is centralised in MainTabView; deep-link handled there too.
        .fullScreenCover(item: $shortsPresentation) { target in
            ShortsPlayerView(videos: target.videos, startIndex: target.startIndex, api: api)
        }
        #endif
        .sheet(isPresented: $showSignIn) { SignInView() }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        #if os(iOS)
        // App Intents ("Open Subscriptions in SmartTube"): RootView switches to this tab.
        // A section hidden in Settings still opens, just without a chip.
        .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSection)) { note in
            guard let raw = note.userInfo?["section"] as? String,
                let type = BrowseSection.SectionType(rawValue: raw)
            else { return }
            selectedSection =
                visibleSections.first { $0.type == type }
                ?? BrowseSection(id: type.rawValue, title: type.defaultTitle, type: type)
        }
        #endif
        .onChange(of: homeVM.feedGeneration) { homeLayout = HomeFeedLayout() }
        .onChange(of: sectionVM.loadedAt) {
            if sectionVM.loadedAt == nil { sectionLayout = HomeFeedLayout() }
        }
        .onChange(of: subscriptionsChannelFilter) { sectionLayout = HomeFeedLayout() }
        .onChange(of: visibleSections) { _, newSections in
            if !newSections.contains(selectedSection), let first = newSections.first {
                selectedSection = first
            }
        }
        .onChange(of: store.settings.historyState, initial: true) { _, state in
            sectionVM.updateHistoryEnabled(state == .enabled)
        }
        .task(id: auth.accessToken) {
            sectionVM.updateHistoryEnabled(store.settings.historyState == .enabled)
            // Home has its own feed; load the section model only when its chip is visible.
            await sectionVM.updateAuthToken(auth.accessToken, reloadOnSignIn: selectedSection.type != .home)
        }
        .onAppear {
            if selectedSection.type == .channels && !sectionVM.isLoading {
                sectionVM.loadContent(source: "channelsReturn")
            }
        }
        .task {
            for await note in NotificationCenter.default.notifications(named: .subscriptionsDidChange) {
                guard let channel = note.userInfo?["channel"] as? Channel,
                    let subscribed = note.userInfo?["subscribed"] as? Bool,
                    note.userInfo?["signedIn"] as? Bool == auth.isSignedIn
                else { continue }
                sectionVM.applySubscriptionChange(channel: channel, subscribed: subscribed)
                if auth.isSignedIn { await homeVM.refresh() }
            }
        }
        .task(id: selectedSection) {
            sectionVM.updateHistoryEnabled(store.settings.historyState == .enabled)
            // Reset auto-retry flags when switching sections to prevent stale
            // triggers from a previous section firing on the new section's content.
            needsMoreShorts = false
            needsMoreNonShorts = false
            sectionLayout = HomeFeedLayout()
            // #62: leaving Subscriptions (or a hard refresh landing back on it) drops
            // any channel filter — a stale filter pointing at a channel that no longer
            // has videos in a freshly reloaded feed would otherwise silently show "no
            // videos" with no obvious explanation.
            subscriptionsChannelFilter = nil
            if selectedSection.type == .playlists {
                queueVideosCount = await CurrentQueueStore.shared.videos.count
            } else if selectedSection.type != .home {
                // Safety net: if sectionVM somehow fell out of sync with selectedSection
                // (e.g., the chip action raced with an in-flight cancellation, or an
                // @Observable tracking gap left the view empty), force a reload.
                if sectionVM.currentSection != selectedSection {
                    sectionVM.select(section: selectedSection)
                }
            }
        }
    }

}

extension HomeView {

    // MARK: - Chip bar

    private var chipBar: some View {
        #if os(tvOS)
        HStack(spacing: VFSpace.s12) {
            ForEach(visibleSections) { section in
                chipButton(section: section)
            }
        }
        .padding(.vertical, VFSpace.s12)
        .focusSection()
        .defaultFocus($focusedSection, selectedSection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.homeChipBar)
        #else
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VFSpace.s8) {
                    ForEach(visibleSections) { section in
                        chipButton(section: section).id(section.id)
                    }
                }
                .padding(.horizontal, videoGridMargin)
                .padding(.vertical, VFSpace.s4)
            }
            // Keep the selected chip in view when the section changes by swipe (#159) or
            // App Intent, not by tapping the chip.
            .onChange(of: selectedSection) { _, section in
                withAnimation { proxy.scrollTo(section.id, anchor: .center) }
            }
        }
        .accessibilityIdentifier(AccessibilityID.homeChipBar)
        #endif
    }

    private func chipButton(section: BrowseSection) -> some View {
        let isSelected = selectedSection == section
        let action = {
            let isNewSection = selectedSection != section
            if isNewSection {
                select(section)
            } else if section.type != .home, sectionVM.videoGroups.isEmpty && !sectionVM.isLoading {
                // Same chip re-tapped on an empty section — retry the load.
                // This handles failed fetches or cases where an observation gap
                // left the view showing an empty state despite data being available.
                sectionVM.reload(section: section)
            }
        }
        #if os(tvOS)
        // The chip draws focus itself: filled while focused or selected, and only focus adds the ring and the lift
        // (Reduce Motion keeps the ring and drops the lift), so focused and selected stay distinguishable.
        let isFocused = focusedSection == section
        let isFilled = isSelected || isFocused
        return Button(action: action) {
            // The label style is set on the text only and the fill is a concrete colour: a hierarchical `.primary` fill
            // would resolve against the label style and match the text.
            Text(section.title)
                .font(.headline)
                .foregroundStyle(isFilled ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                .padding(.horizontal, VFSpace.s24)
                .padding(.vertical, VFSpace.s12)
                .background(isFilled ? Color.primary : VFColor.surface, in: Capsule())
                .overlay {
                    if isFocused {
                        Capsule().strokeBorder(Color.primary, lineWidth: 3).padding(-VFSpace.s4 - 3)
                    }
                }
                .focusEffectDisabled()
        }
        .buttonStyle(.borderless)
        .scaleEffect(isFocused && !reduceMotion ? 1.12 : 1.0)
        .vfAnimation(VFMotion.fast, value: focusedSection)
        .vfAnimation(VFMotion.fast, value: selectedSection)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(section.title)
        .accessibilityIdentifier(AccessibilityID.homeSectionChip(section.title))
        .focused($focusedSection, equals: section)
        #else
        return SectionChip(title: section.title, isSelected: isSelected, action: action)
            .accessibilityIdentifier(AccessibilityID.homeSectionChip(section.title))
        #endif
    }

    private func select(_ section: BrowseSection) {
        sectionVM.updateHistoryEnabled(store.settings.historyState == .enabled)
        selectedSection = section
        if section.type != .home { sectionVM.select(section: section) }
    }

    #if os(iOS)
    // MARK: - Swipe between sections (#159)

    /// A clearly sideways swipe over the feed moves to the next / previous chip. Attached
    /// only to the vertical feeds, not the horizontal Shorts row, whose own scrolling would
    /// otherwise also change the section.
    var sectionSwipe: some ViewModifier {
        HomeSectionSwipe { dx in
            let sections = visibleSections
            guard let index = sections.firstIndex(of: selectedSection) else { return }
            let next = index + (dx < 0 ? 1 : -1)
            guard sections.indices.contains(next) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { select(sections[next]) }
        }
    }
    #endif

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if selectedSection.type == .home {
            if auth.isSignedIn {
                homeShelves
            } else {
                homeSignedOutPrompt
            }
        } else if selectedSection.type == .channels {
            channelListFeed
        } else {
            sectionFeed
                .accessibilityIdentifier("home.sectionContainer")
        }
    }

    @ViewBuilder
    private var channelListFeed: some View {
        if sectionVM.isLoading && sectionVM.subscribedChannels.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                if let error = sectionVM.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { sectionVM.loadContent() }
                        .accessibilityIdentifier(AccessibilityID.subscriptionRetry)
                }
                if sectionVM.subscribedChannels.isEmpty && sectionVM.error == nil {
                    feedEmptyState
                } else if !sectionVM.subscribedChannels.isEmpty {
                    ChannelListView(
                        channels: sectionVM.subscribedChannels,
                        changingIDs: sectionVM.changingSubscriptionIDs,
                        onSelect: { channel in
                            channelDestination = ChannelDestination(channelId: channel.id)
                        },
                        onUnsubscribe: { channel in
                            await sectionVM.unsubscribe(from: channel, signedIn: auth.isSignedIn)
                        },
                        onRefresh: { await sectionVM.refreshChannels() })
                }
            }
        }
    }

    private var homeSignedOutPrompt: some View {
        fullArea(
            ContentUnavailableView {
                Label {
                    Text("Sign in to see your feed", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.personCircleQuestion)
                }
            } description: {
                Text(
                    "Sign in with a code from your phone or computer. You don't enter your password in VoxaFrame.",
                    bundle: .module)
            } actions: {
                Button {
                    showSignIn = true
                } label: {
                    Text("Sign In", bundle: .module)
                }
                .buttonStyle(.vfProminent)
                // The guest path stays one step away.
                Button {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                } label: {
                    Text("Open search", bundle: .module)
                }
            })
    }

    /// A state that fills the content area; on iPhone and iPad a sideways swipe over it still changes the section.
    @ViewBuilder
    private func fullArea(_ content: some View) -> some View {
        let area = content.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        #if os(iOS)
        area.modifier(sectionSwipe)
        #else
        area
        #endif
    }

    // MARK: - Home shelves  (unified interleaved feed)

    /// One vertical feed: ten Shorts, six rows of videos, another Shorts row, and so on
    /// (`HomeFeedLayout`). Each Shorts row scrolls horizontally on its own.
    private var homeShelves: some View {
        Group {
            if homeVM.isLoadingAny && homeVM.mergedVideos.isEmpty {
                HomeLoadingView(columns: feedColumns)
            } else if homeVM.mergedVideos.isEmpty && homeVM.homeShortsVideos.isEmpty {
                fullArea(
                    ContentUnavailableView {
                        Label {
                            Text("Nothing here yet", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.tvPlay)
                        }
                    } actions: {
                        Button {
                            Task { await homeVM.refresh() }
                        } label: {
                            Text("Refresh", bundle: .module)
                        }
                        .buttonStyle(.vfProminent)
                    })
            } else {
                let shortsVideos =
                    store.settings.hideShorts
                    ? []
                    : homeVM.homeShortsVideos.filter {
                        !store.settings.shouldHideWatched($0, in: .home)
                    }
                let regularVideos = homeVM.homeRegularVideos.filter {
                    !store.settings.shouldHideWatched($0, in: .home)
                }
                let segments = homeLayout.segments(shorts: shortsVideos, videos: regularVideos, columns: feedColumns)
                let stack = LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(segments) {
                        homeFeedSegment($0, in: segments, shorts: shortsVideos, videos: regularVideos)
                    }
                    if store.settings.hideWatchedVideos, homeVM.sections.contains(where: { $0.nextPageToken != nil }) {
                        Button("More") { homeVM.loadMoreMerged() }
                            .buttonStyle(.bordered)
                            .disabled(homeVM.sections.contains { $0.isLoading || $0.isLoadingMore })
                            .accessibilityIdentifier(AccessibilityID.homeFilteredLoadMoreButton)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VFSpace.s12)
                    }
                    if homeVM.sections.contains(where: \.isLoadingMore) {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
                // At least the viewport tall, so the space below a short feed takes the chip swipe.
                .frame(minHeight: homeFeedHeight, alignment: .top)
                let feed = ScrollView {
                    #if os(iOS)
                    // The gaps between segments take the chip swipe too. Shorts rows sit in front
                    // of this background, so dragging one still scrolls the row.
                    stack.background {
                        Color.clear.contentShape(Rectangle()).modifier(sectionSwipe)
                    }
                    #else
                    stack
                    #endif
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    homeFeedHeight = $0
                }
                .refreshable { await homeVM.refresh() }
                .onChange(of: homeVM.loadedAt) { requestHomeShorts(through: homeLayout.laidOutThrough + 3) }
                #if os(tvOS)
                feed.focusSection()
                #else
                feed
                #endif
            }
        }
    }

    @ViewBuilder
    private func homeFeedSegment(
        _ segment: HomeFeedSegment<Video>, in segments: [HomeFeedSegment<Video>], shorts: [Video], videos: [Video]
    ) -> some View {
        switch segment.kind {
        case .shorts:
            VStack(alignment: .leading, spacing: 0) {
                ShortsShelfHeader()
                ShortsRowSection(
                    videos: segment.items,
                    onSelect: { selectVideo($0, from: shorts) },
                    accessibilityID: AccessibilityID.homeShortsRow(segment.index)
                )
            }
        case .videos:
            let isLastBlock = segment.id == segments.last { $0.kind == .videos }?.id
            let block = VideoGridSection(
                videos: segment.items,
                onSelect: { selectVideo($0, from: videos) },
                loadMore: isLastBlock ? { homeVM.loadMoreMerged() } : nil,
                eager: true,
                columns: feedColumns
            )
            .feedBlockGroup(AccessibilityID.feedVideoBlock(.home, segment.index))
            .contentShape(Rectangle())
            .onAppear {
                homeLayout.markLaidOut(block: segment.index, in: segments)
                requestHomeShorts(through: segment.index + 2)
            }
            // On the video blocks, not the Shorts rows: dragging a Shorts row sideways scrolls
            // the row instead of switching the section.
            #if os(iOS)
            block.modifier(sectionSwipe)
            #else
            block
            #endif
        }
    }

    /// Asks for enough Shorts to put a row in front of every block through `block` that can
    /// still take one.
    private func requestHomeShorts(through block: Int) {
        guard !store.settings.hideShorts else { return }
        homeVM.loadShorts(atLeast: homeLayout.shortsWanted(through: block))
    }

    // MARK: - Section feed  (non-Home chips)

    func interleavedSectionFeed(shorts: [Video], videos: [Video], loadMore: @escaping () -> Void) -> some View {
        let segments = sectionLayout.segments(shorts: shorts, videos: videos, columns: feedColumns)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .shorts:
                    VStack(alignment: .leading, spacing: 0) {
                        ShortsShelfHeader()
                        ShortsRowSection(
                            videos: segment.items,
                            onSelect: { selectVideo($0, from: shorts) },
                            accessibilityID: AccessibilityID.sectionShortsRow(selectedSection.type, segment.index),
                            loadMore: videos.isEmpty ? loadMore : nil)
                    }
                case .videos:
                    VideoGridSection(
                        videos: segment.items,
                        onSelect: { selectVideo($0, from: videos) },
                        loadMore: segment.index == segments.last(where: { $0.kind == .videos })?.index
                            ? loadMore : nil,
                        eager: true,
                        columns: feedColumns
                    )
                    .feedBlockGroup(AccessibilityID.feedVideoBlock(selectedSection.type, segment.index))
                    .onAppear { sectionLayout.markLaidOut(block: segment.index, in: segments) }
                    #if os(iOS)
                    .modifier(sectionSwipe)
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    var sectionFeed: some View {
        if sectionVM.isLoading && sectionVM.videoGroups.allSatisfy({ $0.videos.isEmpty }) {
            HomeLoadingView(columns: feedColumns)
        } else if sectionVM.videoGroups.allSatisfy({ $0.videos.isEmpty }) && !sectionVM.isLoading {
            feedEmptyState
        } else {
            feedContent
        }
    }

    /// Why a section is empty, with the one action that helps. The reasons are today's (A9 is not implemented);
    /// a load error now shows its own state with a retry instead of "Nothing here yet".
    @ViewBuilder
    private var feedEmptyState: some View {
        if sectionVM.isAuthRequired && !auth.isSignedIn {
            fullArea(
                ContentUnavailableView {
                    Label {
                        Text("Sign in to see this section", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.personCircleWarning)
                    }
                } description: {
                    Text("Your Google account is required.", bundle: .module)
                } actions: {
                    Button {
                        showSignIn = true
                    } label: {
                        Text("Sign In", bundle: .module)
                    }
                    .buttonStyle(.vfProminent)
                })
        } else if !auth.isSignedIn && (selectedSection.type == .subscriptions || selectedSection.type == .channels) {
            fullArea(
                ContentUnavailableView {
                    Label {
                        Text("Follow channels to see their latest videos here", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.followChannels)
                    }
                } description: {
                    Text("Search for a channel and tap Subscribe.", bundle: .module)
                } actions: {
                    Button {
                        NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                    } label: {
                        Text("Search", bundle: .module)
                    }
                    .buttonStyle(.vfProminent)
                })
        } else if let error = sectionVM.error {
            fullArea(
                ContentUnavailableView {
                    Label {
                        Text("Couldn't load this section", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.warning)
                    }
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button {
                        sectionVM.loadContent(refresh: true)
                    } label: {
                        Text("Try Again", bundle: .module)
                    }
                    .buttonStyle(.vfProminent)
                })
        } else {
            fullArea(
                ContentUnavailableView {
                    Label {
                        Text("Nothing here yet", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.tvPlay)
                    }
                } actions: {
                    if sectionVM.hasMoreShorts {
                        Button {
                            sectionVM.loadMoreShorts()
                        } label: {
                            Text("More", bundle: .module)
                        }
                        .buttonStyle(.vfProminent)
                        .disabled(sectionVM.isLoadingMore)
                        .accessibilityIdentifier(AccessibilityID.shortsLoadMoreButton)
                    } else {
                        Button {
                            sectionVM.loadContent(refresh: true)
                        } label: {
                            Text("Refresh", bundle: .module)
                        }
                        .buttonStyle(.vfProminent)
                    }
                })
        }
    }

    // MARK: - Video selection

    func selectVideo(_ video: Video, from groupVideos: [Video]) {
        if video.playlistId == video.id {
            selectedPlaylist = video
        } else if video.isShort {
            #if os(iOS)
            let shorts = groupVideos.filter { $0.isShort }
            let idx = shorts.firstIndex(where: { $0.id == video.id }) ?? 0
            shortsPresentation = ShortsPresentation(videos: shorts, startIndex: idx)
            #else
            selectedVideo = video
            #endif
        } else {
            #if os(iOS)
            playerRouter.open(video: video, api: api)
            #else
            selectedVideo = video
            #endif
        }
    }
}
