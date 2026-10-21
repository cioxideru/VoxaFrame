import SmartTubeIOSCore
import SwiftUI

// MARK: - LibraryView
//
// Subscriptions, watch history, playlists, the play queue and RSS feeds. A guest sees subscriptions on this
// device, on-device history (A4) and the queue (A1); only account playlists ask to sign in.
// Mirrors the Android launcher activities for Subscriptions, Playlists, History and Channels.

public struct LibraryView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @Environment(\.libraryQueueRequest) private var queueRequest
    @State private var selectedSection: LibrarySection = .subscriptions
    @State private var selectedVideo: Video?
    @State private var selectedPlaylist: Video?
    @State private var channelDestination: ChannelDestination?
    @State private var showsSignIn = false
    @State private var scrollStore = ScrollOffsetStore()
    @State private var savedScrollOffset: CGFloat? = nil
    @State private var restoreOffset: CGFloat? = nil
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif
    #if os(tvOS)
    @FocusState private var focusedSection: LibrarySection?
    #endif

    enum LibrarySection: String, CaseIterable, Identifiable {
        // Raw values are the UI-test identifiers (`library.picker.<raw>`, `library.chip.<raw>`); `title` is shown.
        case subscriptions = "Subs"
        case history = "History"
        case playlists = "Playlists"
        case queue = "Queue"
        case rss = "RSS Feeds"
        case downloads = "Downloads"

        #if os(tvOS) || !ENABLE_DOWNLOADS
        // Downloads saves to Photos library — not supported on tvOS, and compiled out of
        // App Store builds (guideline 5.2.3). Exclude the chip by hiding it from allCases.
        static var allCases: [LibrarySection] {
            [.subscriptions, .history, .playlists, .queue, .rss]
        }
        #endif

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .subscriptions: "Subs"
            case .history: "History"
            case .playlists: "Playlists"
            case .queue: "Queue"
            case .rss: "RSS"
            case .downloads: "Downloads"
            }
        }

        /// The browse feed behind the segment; `nil` for segments with their own source. The queue reads
        /// `CurrentQueueStore` directly, so it never waits for, or fails with, the playlists request (A1).
        var browseSection: BrowseSection? {
            let type: BrowseSection.SectionType
            switch self {
            case .subscriptions: type = .subscriptions
            case .history: type = .history
            case .playlists: type = .playlists
            case .queue, .rss, .downloads: return nil
            }
            return BrowseSection(id: id, title: rawValue, type: type)
        }

        /// Only account playlists need Google. History shows on-device history to a guest (A4).
        var requiresSignIn: Bool { self == .playlists }
    }

    public init() {}

    public var body: some View {
        Group {
            libraryContent
        }
        #if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle(Text("Library", bundle: .module))
        #endif
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
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
        // A sheet, not a push: SignInView owns a NavigationStack and must not nest in this one.
        .sheet(isPresented: $showsSignIn) {
            SignInView()
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch selectedSection {
                case .rss:
                    RSSFeedsView()
                case .downloads:
                    downloadsContent
                case .queue:
                    QueueView(api: api)
                default:
                    feedContent
                }
            }
        }
        .onChange(of: selectedSection) { _, section in
            if let feed = section.browseSection { browseVM.select(section: feed) }
        }
        // `initial`: the shell may ask before this tab was ever built. The request is consumed here, so a
        // rebuilt Library does not replay it; screens pushed above Library go, so the queue is what shows.
        .onChange(of: queueRequest.wrappedValue, initial: true) { _, pending in
            guard pending else { return }
            queueRequest.wrappedValue = false
            selectedPlaylist = nil
            channelDestination = nil
            selectedVideo = nil
            selectedSection = .queue
        }
        #if os(tvOS)
        // tvOS: player is opened via navigationDestination(item: $selectedVideo).
        // Save offset when selectedVideo is set; restore when it clears.
        .onChange(of: selectedVideo) { old, new in
            if old == nil, new != nil {
                savedScrollOffset = scrollStore.scrollView?.contentOffset.y ?? 0
            } else if old != nil, new == nil, let saved = savedScrollOffset {
                restoreOffset = saved
                savedScrollOffset = nil
            }
        }
        #endif
        .onDisappear {
            // Snapshot scroll position whenever the Library view leaves the screen
            // (player opening, tab switch, navigation push). At onDisappear time the
            // UIScrollView is still in memory and contentOffset is accurate.
            #if os(iOS) || os(tvOS)
            if let offset = scrollStore.scrollView?.contentOffset.y, offset > 0 {
                savedScrollOffset = offset
            }
            #endif
        }
        .onAppear {
            guard let feed = selectedSection.browseSection else { return }
            browseVM.select(section: feed)
            // Restore scroll position when returning from the player, another tab,
            // or any navigation that caused onDisappear to fire.
            #if os(iOS) || os(tvOS)
            if let saved = savedScrollOffset {
                restoreOffset = saved
                savedScrollOffset = nil
            }
            #endif
        }
    }

    // MARK: - Section picker

    @ViewBuilder
    private var sectionPicker: some View {
        #if os(tvOS)
        HStack(spacing: VFSpace.s8) {
            ForEach(LibrarySection.allCases) { sec in
                let isSelected = selectedSection == sec
                Button {
                    guard selectedSection != sec else { return }
                    selectedSection = sec
                } label: {
                    // Selection is the action pair (contrast-checked in both appearances); focus is the
                    // system's lift and highlight on the borderless button, not drawn here.
                    Text(sec.title, bundle: .module)
                        .font(.headline)
                        .padding(.horizontal, VFSpace.s24)
                        .padding(.vertical, VFSpace.s12)
                        .background(isSelected ? VFColor.action : VFColor.surface, in: Capsule())
                        .foregroundStyle(isSelected ? VFColor.onAction : Color.primary)
                }
                .buttonStyle(.borderless)
                .vfAnimation(VFMotion.fast, value: selectedSection)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier(AccessibilityID.libraryChip(sec.rawValue))
                .focused($focusedSection, equals: sec)
            }
        }
        .padding(.horizontal, VFMargin.tvHorizontal)
        .padding(.vertical, VFSpace.s12)
        .focusSection()
        .defaultFocus($focusedSection, selectedSection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.libraryChipBar)
        #else
        Picker(selection: $selectedSection) {
            ForEach(LibrarySection.allCases) { sec in
                Text(sec.title, bundle: .module).tag(sec)
                    .accessibilityIdentifier(AccessibilityID.libraryPicker(sec.rawValue))
            }
        } label: {
            Text("Library Section", bundle: .module)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier(AccessibilityID.librarySectionPicker)
        .padding(.horizontal, VFSpace.s16)
        .padding(.vertical, VFSpace.s8)
        #endif
    }

    // MARK: - Browse feed segments

    @ViewBuilder
    private var feedContent: some View {
        let allVideos = browseVM.videoGroups.flatMap(\.videos)
        if !auth.isSignedIn && selectedSection.requiresSignIn {
            segmentSignInPrompt
        } else if browseVM.isLoading && allVideos.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if allVideos.isEmpty {
            emptyLibraryView
        } else {
            // Hide Shorts never applies to History.
            let applyHideShorts = store.settings.hideShorts && selectedSection != .history
            let videos = allVideos.filter { !applyHideShorts || !$0.isShort }
            ScrollView {
                // KVO reader — always present; writes to ScrollOffsetStore
                // without triggering SwiftUI re-renders on every scroll tick.
                #if os(iOS) || os(tvOS)
                ScrollOffsetReader(store: scrollStore)
                    .frame(width: 0, height: 0)
                #endif

                if selectedSection == .history, !auth.isSignedIn {
                    Text("On this device. Sign in to add your YouTube history.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VFSpace.s16)
                        .padding(.bottom, VFSpace.s8)
                        .accessibilityIdentifier(AccessibilityID.libraryGuestHistoryNote)
                }
                VideoGridSection(
                    videos: videos,
                    onSelect: { video in
                        if video.playlistId == video.id {
                            selectedPlaylist = video
                        } else {
                            #if os(iOS)
                            playerRouter.open(video: video, api: api)
                            #else
                            selectedVideo = video
                            #endif
                        }
                    },
                    loadMore: {
                        if let last = videos.last {
                            browseVM.loadMoreIfNeeded(lastVideo: last)
                        }
                    }
                )
                // Offset restorer — always present; no-op when restoreOffset is nil.
                #if os(iOS) || os(tvOS)
                ScrollOffsetRestorer(targetOffset: restoreOffset) {
                    restoreOffset = nil
                }
                .frame(width: 0, height: 0)
                #endif

                if browseVM.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(VFSpace.s16)
                }
            }
            .refreshable {
                if let feed = selectedSection.browseSection {
                    browseVM.loadContent(for: feed, refresh: true)
                }
            }
        }
    }

    @ViewBuilder private var emptyLibraryView: some View {
        switch selectedSection {
        case .subscriptions where !auth.isSignedIn:
            ContentUnavailableView {
                Label {
                    Text("No Subscriptions Yet", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.followChannels)
                }
            } description: {
                Text("Follow channels to see their latest videos here", bundle: .module)
            } actions: {
                Button {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                } label: {
                    Text("Search", bundle: .module)
                }
                .buttonStyle(.vfProminent)
            }
        case .history where store.settings.historyState != .enabled:
            ContentUnavailableView {
                Label {
                    Text("History Is Off", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.clock)
                }
            } description: {
                Text(
                    "Turn on Watch History to list the videos you play. You can turn it off again in Settings.",
                    bundle: .module)
            } actions: {
                Button {
                    store.settings.historyState = .enabled
                } label: {
                    Text("Turn On Watch History", bundle: .module)
                }
                .buttonStyle(.vfProminent)
            }
        case .history:
            ContentUnavailableView {
                Label {
                    Text("No History Yet", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.clock)
                }
            } description: {
                if auth.isSignedIn {
                    Text("Videos you play appear here.", bundle: .module)
                } else {
                    Text(
                        "Videos you play on this device appear here. Sign in to add your YouTube history.",
                        bundle: .module)
                }
            }
        default:
            ContentUnavailableView {
                Label {
                    Text("Nothing here yet", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.stackLayers)
                }
            }
        }
    }

    private var segmentSignInPrompt: some View {
        ContentUnavailableView {
            Label {
                Text(
                    "Sign in to see your \(String(localized: "Playlists", bundle: .module).lowercased())",
                    bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.personCircleQuestion)
            }
        } description: {
            Text(
                "Your YouTube playlists and Watch Later. History and the queue work without signing in.",
                bundle: .module)
        } actions: {
            Button {
                showsSignIn = true
            } label: {
                Text("Sign In", bundle: .module)
            }
            .buttonStyle(.vfProminent)
            .accessibilityIdentifier(AccessibilityID.librarySignInButton)
        }
    }
}

extension EnvironmentValues {
    /// Set by the iPad shell when its sidebar Queue item goes away (compact width); Library shows its Queue
    /// and clears it.
    @Entry var libraryQueueRequest: Binding<Bool> = .constant(false)
}

extension LibraryView {
    @ViewBuilder fileprivate var downloadsContent: some View {
        #if ENABLE_DOWNLOADS
        DownloadsView()
            .environment(DownloadStore.shared)
        #endif
    }
}
