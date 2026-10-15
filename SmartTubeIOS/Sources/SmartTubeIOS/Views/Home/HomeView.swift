import SmartTubeIOSCore
import SwiftUI

// MARK: - HomeView
//
// YouTube-style home tab.  A horizontal chip bar at the top lets the user
// switch between every available section:
//   • "Home"  chip  → multi-shelf overview (Subscriptions row,
//                      Recommended row) driven by HomeViewModel.
//   • Any other chip → full-screen video feed for that section driven by a
//                      dedicated BrowseViewModel instance.

public struct HomeView: View {
    @State private var homeVM: HomeViewModel
    @State var sectionVM: BrowseViewModel
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) var store
    @Environment(\.innerTubeAPI) private var api
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
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
    @State var queueVideosCount: Int = 0
    // Auto-retry tracking: record the type-specific video count at the moment a
    // scroll trigger fires so onChange can detect whether the next page helped.
    @State var needsMoreShorts = false
    #if os(macOS)
    /// Tracks the video ID for which the TOS player hit a fatal embed error so
    /// the NavigationDestination can fall through to the standard PlayerView for
    /// that video only. Cleared when a different video is tapped.
    @State private var tosPlayerFallbackVideoId: String? = nil
    #endif
    @State var shortsCountAtTrigger = 0
    @State var needsMoreNonShorts = false
    @State var nonShortsCountAtTrigger = 0
    #if os(tvOS)
    @FocusState private var focusedSection: BrowseSection?
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
        _homeVM = State(initialValue: HomeViewModel(api: api))
        _sectionVM = State(initialValue: BrowseViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            chipBar
            #if !os(tvOS)
            Divider()
            #endif
            contentArea
                #if !os(iOS)
            .navigationDestination(item: $selectedVideo) { video in
                #if os(macOS)
                if store.settings.useTOSPlayerOnMac && tosPlayerFallbackVideoId != video.id {
                    TOSPlayerView(video: video, api: api) {
                        tosPlayerFallbackVideoId = video.id
                    }
                    .environment(store)
                    .onDisappear { tosPlayerFallbackVideoId = nil }
                } else {
                    PlayerView(video: video, api: api)
                }
                #else
                PlayerView(video: video, api: api)
                #endif
            }
                #endif
                .navigationDestination(item: $selectedPlaylist) { stub in
                    PlaylistView(playlistId: stub.id, playlistTitle: stub.title, api: api)
                }
                .navigationDestination(item: $channelDestination) { dest in
                    ChannelView(channelId: dest.channelId)
                }
                #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(iOS)
        // Player cover is centralised in MainTabView; deep-link handled there too.
        .toolbar(.hidden, for: .navigationBar)
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
        .onChange(of: visibleSections) { _, newSections in
            if !newSections.contains(selectedSection), let first = newSections.first {
                selectedSection = first
            }
        }
        .task(id: auth.accessToken) {
            await homeVM.updateAuthToken(auth.accessToken)
            await sectionVM.updateAuthToken(auth.accessToken)
        }
        .task(id: selectedSection) {
            // Reset auto-retry flags when switching sections to prevent stale
            // triggers from a previous section firing on the new section's content.
            needsMoreShorts = false
            needsMoreNonShorts = false
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
        HStack(spacing: 8) {
            ForEach(visibleSections) { section in
                chipButton(section: section)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .focusSection()
        .defaultFocus($focusedSection, selectedSection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.chipBar")
        #else
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleSections) { section in
                        chipButton(section: section).id(section.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            // Keep the selected chip in view when the section changes by swipe (#159) or
            // App Intent, not by tapping the chip.
            .onChange(of: selectedSection) { _, section in
                withAnimation { proxy.scrollTo(section.id, anchor: .center) }
            }
        }
        .accessibilityIdentifier("home.chipBar")
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
        let isFocused = focusedSection == section
        return Button(action: action) {
            Text(section.title)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    (isSelected || isFocused) ? Color.primary : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(
                    (isSelected || isFocused)
                        ? Color(white: colorScheme == .dark ? 0 : 1)
                        : Color.primary
                )
                .focusEffectDisabled()
        }
        .buttonStyle(.borderless)
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: focusedSection)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(section.title)
        .accessibilityIdentifier("chip.\(section.title)")
        .focused($focusedSection, equals: section)
        #else
        return Button(action: action) {
            Text(section.title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.primary : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(
                    isSelected
                        ? Color(white: colorScheme == .dark ? 0 : 1)
                        : Color.primary
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        #endif
    }

    private func select(_ section: BrowseSection) {
        selectedSection = section
        if section.type != .home { sectionVM.select(section: section) }
    }

    #if os(iOS)
    // MARK: - Swipe between sections (#159)

    /// A clearly sideways swipe over the feed moves to the next / previous chip. Attached
    /// only to the vertical feeds, not the horizontal Shorts row, whose own scrolling would
    /// otherwise also change the section.
    var sectionSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
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
                .accessibilityIdentifier("home.sectionContainer")
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
        } else if sectionVM.subscribedChannels.isEmpty && !sectionVM.isLoading {
            feedEmptyState
        } else {
            ChannelListView(channels: sectionVM.subscribedChannels) { channel in
                channelDestination = ChannelDestination(channelId: channel.id)
            }
            #if os(iOS)
            .simultaneousGesture(sectionSwipe)
            #endif
        }
    }

    private var homeSignedOutPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbol.personCircleQuestion)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Sign in to see your feed")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Sign In") { showSignIn = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        #if os(iOS)
        .simultaneousGesture(sectionSwipe)
        #endif
    }

    // MARK: - Home shelves  (unified interleaved feed)

    private var homeShelves: some View {
        Group {
            if homeVM.isLoadingAny && homeVM.mergedVideos.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let hideShorts = store.settings.hideShorts
                let regularVideos = homeVM.homeRegularVideos
                let shortsVideos = hideShorts ? [] : homeVM.homeShortsVideos
                // ShortsRowSection is placed OUTSIDE the ScrollView so it stays
                // pinned at the top while the video grid scrolls beneath it.
                VStack(spacing: 0) {
                    if !shortsVideos.isEmpty {
                        ShortsRowSection(
                            videos: shortsVideos,
                            onSelect: { selectVideo($0, from: shortsVideos) },
                            accessibilityID: "home.shortsRow",
                            loadMore: { homeVM.loadNextShortsPage() }
                        )
                        #if os(tvOS)
                        .focusSection()
                        #endif
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VideoGridSection(
                                videos: regularVideos,
                                onSelect: { selectVideo($0, from: regularVideos) },
                                loadMore: { homeVM.loadMoreMerged() }
                            )
                            let isLoadingMore = homeVM.sections.contains { $0.isLoadingMore }
                            if isLoadingMore {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        }
                    }
                    .refreshable { homeVM.load() }
                    #if os(iOS)
                    .simultaneousGesture(sectionSwipe)
                    #endif
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }

    // MARK: - Section feed  (non-Home chips)

    @ViewBuilder
    var sectionFeed: some View {
        if sectionVM.isLoading && sectionVM.videoGroups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sectionVM.videoGroups.isEmpty && !sectionVM.isLoading {
            feedEmptyState
        } else {
            feedContent
        }
    }

    private var feedEmptyState: some View {
        VStack(spacing: 16) {
            if sectionVM.isAuthRequired && !auth.isSignedIn {
                Image(systemName: AppSymbol.personCircleWarning)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Sign in to see this section")
                    .font(.title3)
                Text("Your Google account is required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Sign In") { showSignIn = true }
                    .buttonStyle(.borderedProminent)
            } else if !auth.isSignedIn && (selectedSection.type == .subscriptions || selectedSection.type == .channels)
            {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Follow channels to see their latest videos here")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text("Search for a channel and tap Follow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Search") {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: AppSymbol.tvPlay)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Nothing here yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Refresh") { sectionVM.loadContent(refresh: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        #if os(iOS)
        .simultaneousGesture(sectionSwipe)
        #endif
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
