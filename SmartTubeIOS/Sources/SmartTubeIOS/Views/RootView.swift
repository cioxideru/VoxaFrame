import SmartTubeIOSCore
import SwiftUI

// MARK: - RootView
//
// Entry point that decides whether to show the main tab UI or the
// sign-in screen.  On macOS it uses a sidebar-based navigation.

public struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    /// Shared download service — observed here so the completion alert is shown
    /// at a stable level unaffected by context menu dismiss animations on cards.
    #if ENABLE_DOWNLOADS
    @Environment(VideoDownloadService.self) private var cardDownloadService
    #endif
    @State private var cardDownloadAlertItem: DownloadAlertItem?
    @State private var isLandscapeLayout = false

    public init() {}

    public var body: some View {
        @Bindable var browseVM = browseVM
        // Explicitly read cardDownloadService.state in body so SwiftUI's
        // @Observable tracking engine registers this view as a subscriber.
        // Without this, onChange(of: cardDownloadService.state) may not fire
        // when the state changes on an environment-injected @Observable object.
        #if ENABLE_DOWNLOADS
        let _ = cardDownloadService.state
        #endif
        Group {
            #if os(tvOS)
            MainTVTabView()
            #elseif os(macOS)
            MainSidebarView()
            #else
            MainTabView()
            #endif
        }
        .environment(\.isLandscapeLayout, isLandscapeLayout)
        .vfGlassScope()
        .toastPresenter()
        .onGeometryChange(for: Bool.self) {
            $0.size.width > $0.size.height
        } action: {
            isLandscapeLayout = $0
        }
        .tint(store.settings.accentColor.color)
        .preferredColorScheme(store.settings.themeName.colorScheme)
        #if !os(tvOS) && ENABLE_DOWNLOADS
        .onChange(of: cardDownloadService.state) { _, newState in
            switch newState {
            case .done:
                cardDownloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Saved to Gallery", bundle: .module),
                    message: String(localized: "Video has been saved to your Photos library.", bundle: .module)
                )
                cardDownloadService.reset()
            case .failed(let reason):
                cardDownloadAlertItem = DownloadAlertItem(
                    title: String(localized: "Download Failed", bundle: .module),
                    message: reason
                )
                cardDownloadService.reset()
            default:
                break
            }
        }
        .alert(
            cardDownloadAlertItem?.title ?? "",
            isPresented: Binding(
                get: { cardDownloadAlertItem != nil },
                set: { if !$0 { cardDownloadAlertItem = nil } }
            ),
            presenting: cardDownloadAlertItem
        ) { _ in
            Button("OK") { cardDownloadAlertItem = nil }
        } message: { item in
            Text(item.message)
        }
        #endif
        .sheet(isPresented: .constant(!auth.isSignedIn && requiresAuth)) {
            // Sign-in prompt is shown as a dismissible sheet so users
            // can still browse without being signed in.
            SignInView()
        }
        #if os(iOS)
        // Deep link is handled by MainTabView.onChange(of: browseVM.deepLinkedVideo)
        // which calls playerRouter.open(video:api:). No landscapePlayerCover needed here.
        #elseif !os(macOS) && !os(tvOS)
        .fullScreenCover(item: $browseVM.deepLinkedVideo) { video in
            PlayerView(video: video, api: api)
                .environment(store)
                .environment(auth)
        }
        #endif
    }

    private var requiresAuth: Bool { false }  // guest browsing is allowed
}

// MARK: - AppSection

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case library = "Library"
    case offline = "Offline videos"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return AppSymbol.home
        case .search: return AppSymbol.search
        case .library: return AppSymbol.library
        case .offline: return AppSymbol.download
        case .settings: return AppSymbol.settings
        }
    }

    @MainActor @ViewBuilder
    func destination(api: InnerTubeAPI) -> some View {
        switch self {
        case .home: HomeView(api: api)
        case .search: SearchView()
        case .library: LibraryView()
        case .offline: OfflineVideosView()
        case .settings: SettingsView()
        }
    }
}
