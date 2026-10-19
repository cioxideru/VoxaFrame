import SwiftUI

#if os(iOS)
import OSLog
import SmartTubeIOSCore

private let rootLog = Logger(subsystem: appSubsystem, category: "RootView")

// MARK: - MainTabView  (iOS / iPadOS)

// Where the selected tab's content sits, read from inside the tab: the bottom safe-area inset
// (tab bar + home indicator, which UITabBarController bakes into the tab's safe area) and the
// content column in global coordinates (narrower than the window while the iPad sidebar is docked).
// The mini-player overlay uses both, so it never hard-codes a tab-bar height or a sidebar width.
// A tab reports nothing until the tab container has laid it out (all insets still zero for a frame
// or two on its first appearance), so the mini player does not drop onto the tab bar meanwhile.
private struct TabContentFrame: Equatable {
    var bottomInset: CGFloat = 0
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
}

private struct TabContentFrameKey: PreferenceKey {
    static let defaultValue: TabContentFrame? = nil
    static func reduce(value: inout TabContentFrame?, nextValue: () -> TabContentFrame?) {
        value = value ?? nextValue()
    }
}

// `Tab` API with `.sidebarAdaptable` (sidebar in a wide iPad window, tabs in a narrow one);
// Search is the search-role tab on iOS 26+.
// The mini player stays one overlay on every version. A PLAN-0027 spike of `.tabViewBottomAccessory`
// (iOS 26.5) showed SwiftUI recreating the accessory content on every tab switch, the new copy appearing
// before the old one left, so the shared player layer was re-parented each time; the accessory also has a
// fixed height that clips Dynamic Type and no opaque fallback for Disable Liquid Glass.
struct MainTabView: View {
    /// iPhone and iPad order: Search last, where iOS 26 draws the search-role tab.
    /// `AppSection.allCases` stays the tvOS and macOS order.
    private static let tabOrder: [AppSection] = [.home, .library, .offline, .settings, .search]

    @State private var searchVM = SearchViewModel()
    @State private var selectedTab: ShellItem = .section(.home)
    /// The channel page the player asked for, pushed on `channelPushTab`'s stack (any tab, Settings included).
    @State private var channelPushes: [ShellItem: ChannelDestination] = [:]
    @State private var libraryQueueRequested = false
    @State private var tabContentFrame = TabContentFrame()
    @State private var shellFrame: CGRect = .zero
    /// Global frame of the sidebar header while the iPad sidebar is on screen (docked or floating).
    @State private var sidebarHeaderFrame: CGRect?
    @State private var miniPlayerHeight: CGFloat = 0
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isLandscapeLayout) private var isLandscapeLayout
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @Environment(PlayerStateStore.self) private var playerState
    @Environment(PlayerRouter.self) private var playerRouter
    @Environment(BrowseViewModel.self) private var browseVM

    var body: some View {
        // Read these in body so SwiftUI's @Observable tracker registers the dependency.
        // If only accessed inside the Binding.get closure, changes won't trigger a body re-render
        // and updateUIViewController won't be called, so the cover never dismisses.
        let fullScreenVideo: Video? = playerState.presentation == .fullScreen ? playerState.currentVideo : nil
        // ViewBuilder bodies cannot use `_ =`. swiftlint:disable:next redundant_discardable_let
        let _ = rootLog.notice(
            "[MainTabView] body re-render — presentation=\(String(describing: playerState.presentation)) fullScreenVideo=\(fullScreenVideo?.id ?? "nil")"
        )
        let fullScreenRequestID = playerState.fullScreenRequestID
        let fullScreenBinding = Binding<Video?>(
            get: { playerState.presentation == .fullScreen ? playerState.currentVideo : nil },
            set: { newValue in
                guard newValue == nil else { return }
                playerState.fullScreenCoverDismissed(requestID: fullScreenRequestID)
            }
        )
        tabs
            .onPreferenceChange(TabContentFrameKey.self) { frame in
                if let frame, frame != tabContentFrame { tabContentFrame = frame }
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                shellFrame = $0
            }
            .background(TabBarLiquidGlassConfigurator(disableLiquidGlass: store.settings.disableLiquidGlass))
            .environment(searchVM)
            // A compact width has no Queue tab: keep the user on the queue, as Library › Queue.
            .onChange(of: horizontalSizeClass) { _, sizeClass in
                guard sizeClass != .regular, selectedTab == .queue else { return }
                libraryQueueRequested = true
                selectedTab = .section(.library)
            }
            .environment(\.libraryQueueRequest, $libraryQueueRequested)
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
                selectedTab = .section(.search)
            }
            // "Open Channel" from the player: wait until the full-screen player is gone, then push the page on
            // the selected tab, unless that channel page is already showing.
            .onChange(of: playerState.presentation) { applyPendingChannel() }
            .onChange(of: playerState.pendingChannelId) { applyPendingChannel() }
            // App Intents / Spotlight (see AppEntry.handleOpenURL).
            .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSearch)) { note in
                guard let query = note.userInfo?["query"] as? String else { return }
                selectedTab = .section(.search)
                searchVM.query = query
                searchVM.search()
            }
            // HomeView picks the section itself (it owns the chip selection).
            .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSection)) { _ in
                selectedTab = .section(.home)
            }
            // Render the single visible MiniPlayerView above the tab bar, beside the iPad sidebar rather
            // than over it. The transparent passthrough spacer below it is the tab-bar height + home
            // indicator (e.g. 83 pt on Face ID iPhones), so tab items stay tappable.
            .overlay(alignment: .bottom) {
                if playerState.presentation == .miniPlayer {
                    VStack(spacing: 0) {
                        MiniPlayerView()
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { miniPlayerHeight = $0 }
                        Color.clear
                            .frame(height: tabContentFrame.bottomInset)
                            .allowsHitTesting(false)
                    }
                    .padding(.leading, columnInsets.leading)
                    .padding(.trailing, columnInsets.trailing)
                    // The spacer already contains the home indicator; without this the bar
                    // floated that much (34 pt on Face ID iPhones) above the tab bar.
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .vfAnimation(value: playerState.presentation)
                    .vfAnimation(value: columnInsets.leading)
                }
            }
            .landscapePlayerCover(item: fullScreenBinding, dismissStore: playerState) { video in
                PlayerView(video: video, api: api)
            }
            .onChange(of: browseVM.deepLinkedVideo) { _, video in
                guard let video else { return }
                playerRouter.open(video: video, api: api)
                browseVM.deepLinkedVideo = nil
            }
            // UI-testing only: invisible button that re-opens the deeplink video in the
            // same session after stop() so testSecondOpenAfterStopPlays can verify the fix.
            // Uses the same browseVM.deepLinkedVideo path as the production deeplink, so
            // the full playerRouter.open() code path is exercised.
            .overlay(alignment: .bottomLeading) {
                let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
                let deeplinkArg = ProcessInfo.processInfo.arguments
                    .first(where: { $0.hasPrefix("--uitesting-deeplink-video=") })
                let deeplinkID: String? =
                    deeplinkArg.map {
                        let id = String($0.dropFirst("--uitesting-deeplink-video=".count))
                        return id.isEmpty ? nil : id
                    } ?? nil
                if isUITesting, let id = deeplinkID,
                    playerState.presentation == .hidden
                {
                    Button {
                        browseVM.deepLinkedVideo = Video(id: id, title: "", channelTitle: "")
                    } label: {
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier(AccessibilityID.uiTestingReopenDeeplinkVideo)
                }
            }
    }

    private func applyPendingChannel() {
        guard let id = playerState.pendingChannelId, playerState.presentation != .fullScreen else { return }
        playerState.pendingChannelId = nil
        guard channelPushes[selectedTab]?.channelId != id else { return }
        channelPushes[selectedTab] = ChannelDestination(channelId: id)
    }

    private var columnInsets: (leading: CGFloat, trailing: CGFloat) {
        MiniPlayerColumn.insets(
            shell: shellFrame,
            contentMinX: tabContentFrame.minX,
            contentMaxX: tabContentFrame.maxX,
            sidebarHeader: sidebarHeaderFrame,
            layoutDirection: layoutDirection
        )
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(Self.tabOrder.prefix(2)) { section in
                sectionTab(section)
            }
            // A1: the Queue under Library in the sidebar of a regular-width window only. A compact width
            // shows `.sidebarOnly` tabs in the tab bar too (a sixth tab pushes Search into More), so there
            // the queue stays in Library › Queue.
            if horizontalSizeClass == .regular {
                Tab(
                    String(localized: "Queue", bundle: .module), systemImage: ShellItem.queue.icon,
                    value: ShellItem.queue
                ) {
                    tabContent(.queue)
                }
                .tabPlacement(.sidebarOnly)
                .accessibilityIdentifier(AccessibilityID.tab(ShellItem.queue.id))
            }
            ForEach(Self.tabOrder.dropFirst(2)) { section in
                sectionTab(section)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Match the initial window shape; the user can still toggle between the sidebar and tabs.
        .defaultAdaptableTabBarPlacement(isLandscapeLayout ? .sidebar : .tabBar)
        // An invisible header that reports where the sidebar is while it is on screen.
        .tabViewSidebarHeader {
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    sidebarHeaderFrame = $0
                }
                .onDisappear { sidebarHeaderFrame = nil }
        }
    }

    private func sectionTab(_ section: AppSection) -> some TabContent<ShellItem> {
        Tab(section.tabTitle, systemImage: section.icon, value: ShellItem.section(section), role: section.tabRole) {
            tabContent(.section(section))
        }
        .accessibilityIdentifier(AccessibilityID.tab(section.rawValue))
    }

    /// One NavigationStack per tab; the tab container never adds another.
    private func tabContent(_ item: ShellItem) -> some View {
        NavigationStack {
            item.destination(api: api)
                .navigationDestination(
                    item: Binding(
                        get: { channelPushes[item] },
                        set: { channelPushes[item] = $0 })
                ) { dest in
                    ChannelView(channelId: dest.channelId, api: api)
                }
        }
        .background {
            // Reserve the mini player's measured height (it grows with Dynamic Type) at the bottom
            // of the root and every pushed screen, without a second MiniPlayerView and so without
            // duplicating the PersistentPlayerHostView layer across tabs.
            NavigationBottomReserve(height: playerState.presentation == .miniPlayer ? miniPlayerHeight : 0)
            // Only the selected tab reports, so an off-screen tab cannot leave a stale frame.
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                let isLaidOut = geo.safeAreaInsets != EdgeInsets()
                Color.clear.preference(
                    key: TabContentFrameKey.self,
                    value: item == selectedTab && isLaidOut
                        ? TabContentFrame(
                            bottomInset: geo.safeAreaInsets.bottom, minX: frame.minX, maxX: frame.maxX)
                        : nil
                )
            }
        }
        .accessibilityIdentifier(AccessibilityID.tab(item.id))
    }
}

// MARK: - NavigationBottomReserve

/// Adds `height` to the bottom safe area of the sibling NavigationStack's UINavigationController, so the root and
/// every pushed screen inset their scroll content. A SwiftUI `safeAreaInset` on the TabView or on the NavigationStack
/// does not reach the screens inside these UIKit containers (measured on iOS 26.5, PLAN-0027 stage 2a); on the root
/// view it misses pushed screens. The tab's own safe-area reader sits outside the navigation controller, so the
/// measured tab-bar inset does not include this reserve.
private struct NavigationBottomReserve: UIViewRepresentable {
    let height: CGFloat

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.height = height
    }

    final class Probe: UIView {
        /// Set on every SwiftUI update, changed or not, so a lookup that failed is retried by the next one.
        var height: CGFloat = 0 {
            didSet { apply() }
        }
        /// Found once, then reused: a tab keeps its navigation controller for its lifetime.
        private weak var navigation: UINavigationController?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        /// Runs while this tab is on screen; an off-screen tab catches up in `didMoveToWindow`.
        private func apply(retry: Bool = true) {
            guard window != nil else { return }
            if navigation == nil { navigation = nearestNavigationController() }
            guard let navigation else {
                // On a tab's first appearance SwiftUI adds the navigation controller in the same update that moves
                // this probe into the window: look again on the next main-actor turn. Later updates, layouts and
                // window moves keep retrying until it is found.
                if retry { Task { [weak self] in self?.apply(retry: false) } }
                return
            }
            if navigation.additionalSafeAreaInsets.bottom != height {
                navigation.additionalSafeAreaInsets.bottom = height
            }
        }

        /// The tab's NavigationStack: a child of the view controller that hosts this probe. Searching view controller
        /// containment, not the view tree, keeps a tab from catching another tab's stack mid-transition.
        private func nearestNavigationController() -> UINavigationController? {
            let host = sequence(first: self as UIResponder, next: \.next).lazy.compactMap { $0 as? UIViewController }
                .first
            return host.flatMap(Self.navigationController(in:))
        }

        private static func navigationController(in controller: UIViewController) -> UINavigationController? {
            for child in controller.children {
                if let navigation = child as? UINavigationController ?? navigationController(in: child) {
                    return navigation
                }
            }
            return nil
        }
    }
}

extension AppSection {
    /// Short, localized chrome labels; raw values remain the stable navigation and accessibility identity.
    fileprivate var tabTitle: String {
        switch self {
        case .home: String(localized: "Home", bundle: .module)
        case .library: String(localized: "Library", bundle: .module)
        case .offline: String(localized: "Offline", bundle: .module)
        case .settings: String(localized: "Settings", bundle: .module)
        case .search: String(localized: "Search", bundle: .module)
        }
    }

    /// Search is the system search-role tab on iOS 26+; a regular tab before that.
    fileprivate var tabRole: TabRole? {
        guard self == .search else { return nil }
        if #available(iOS 26, *) { return .search }
        return nil
    }
}
#endif

// MARK: - MiniPlayerColumn

/// Padding that keeps the mini player over the part of the tab content that no iPad sidebar covers.
/// Outside `#if os(iOS)` so the package tests can run it on macOS.
enum MiniPlayerColumn {
    /// Global frames are physical (x grows to the right in both layout directions); the result is logical.
    /// - Parameters:
    ///   - shell: the tab container.
    ///   - contentMinX: left edge of the selected tab's content column; a docked sidebar moves it inwards.
    ///   - contentMaxX: right edge of that column.
    ///   - sidebarHeader: the sidebar header's frame while the sidebar is on screen, docked or floating.
    static func insets(
        shell: CGRect,
        contentMinX: CGFloat,
        contentMaxX: CGFloat,
        sidebarHeader: CGRect?,
        layoutDirection: LayoutDirection
    ) -> (leading: CGFloat, trailing: CGFloat) {
        guard shell.width > 0, contentMaxX > contentMinX else { return (0, 0) }
        var left = max(0, contentMinX - shell.minX)
        var right = max(0, shell.maxX - contentMaxX)
        if let header = sidebarHeader {
            // A floating sidebar covers the column instead of narrowing it and exposes no edge, so its width is
            // estimated as the header plus equal margins on both sides (it errs past the real edge, not short).
            if header.midX < shell.midX {
                left = max(left, (header.maxX - shell.minX) + (header.minX - shell.minX))
            } else {
                right = max(right, (shell.maxX - header.minX) + (shell.maxX - header.maxX))
            }
        }
        return layoutDirection == .rightToLeft ? (right, left) : (left, right)
    }
}
