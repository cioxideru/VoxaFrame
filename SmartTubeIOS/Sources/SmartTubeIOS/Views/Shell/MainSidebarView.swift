#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - MainSidebarView  (macOS)
//
// Native window shell: source-list sidebar with the five sections and the Queue (A1, under Library),
// and the selected item's content.
// The player is pushed into the content stack and owns its inspector (PlayerView+Inspector.swift).
// Three separate states: the selected section (`selection`), the selected item (each section's
// own navigation state) and the active video (a pushed `PlayerView`, e.g. `browseVM.deepLinkedVideo`).

/// Below this window width the player inspector moves under the video and the sidebar collapses.
private let narrowWindowWidth: CGFloat = 1000

struct MainSidebarView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    @State private var searchVM = SearchViewModel()
    @State private var selection: ShellItem? = .section(.home)
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var isNarrowWindow = false

    var body: some View {
        @Bindable var browseVM = browseVM
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(AppSection.allCases) { section in
                    sidebarRow(.section(section))
                    if section == .library { sidebarRow(.queue) }
                }
            }
            .navigationTitle("VoxaFrame")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if auth.isSignedIn { accountRow }
            }
        } detail: {
            NavigationStack {
                (selection ?? .section(.home)).destination(api: api)
                    // smarttube:// links and the UI-test queue open the player in the content area, like a
                    // card click. Back pops it; it never closes the window. A new link while one is open
                    // replaces that player (`.id`), so its own view model loads the new video.
                    .navigationDestination(item: $browseVM.deepLinkedVideo) { video in
                        PlayerView(video: video, api: api).id(video)
                    }
            }
        }
        .environment(searchVM)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
            selection = .section(.search)
        }
        .environment(\.isNarrowWindow, isNarrowWindow)
        .onGeometryChange(for: Bool.self) {
            $0.size.width < narrowWindowWidth
        } action: {
            isNarrowWindow = $0
        }
        // Only on crossing the width, so View > Show Sidebar still works in a narrow window.
        .onChange(of: isNarrowWindow) { _, narrow in
            columnVisibility = narrow ? .detailOnly : .automatic
        }
    }

    private func sidebarRow(_ item: ShellItem) -> some View {
        Label {
            item.title
        } icon: {
            Image(systemName: item.icon)
        }
        .tag(item)
    }

    private var accountRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: VFSpace.s8) {
                AsyncImage(url: auth.accountAvatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: AppSymbol.personCircle)
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)
                Text(auth.accountName ?? String(localized: "Account", bundle: .module))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: VFTarget.pointer)
            .padding(.horizontal, VFSpace.s12)
            .padding(.vertical, VFSpace.s8)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Narrow window

private struct IsNarrowWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` while the Mac window is narrower than 1000 pt; set by `MainSidebarView`.
    var isNarrowWindow: Bool {
        get { self[IsNarrowWindowKey.self] }
        set { self[IsNarrowWindowKey.self] = newValue }
    }
}
#endif
