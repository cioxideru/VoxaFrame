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

struct MainSidebarView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    @State private var searchVM = SearchViewModel()
    @State private var selection: ShellItem? = .section(.home)
    @State private var windowState = MacWindowState()

    var body: some View {
        @Bindable var browseVM = browseVM
        @Bindable var windowState = windowState
        NavigationSplitView(columnVisibility: $windowState.sidebarVisibility) {
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
        .environment(windowState)
        .frame(minWidth: VFMacWindow.minimumSize.width, minHeight: VFMacWindow.minimumSize.height)
        .background { MacWindowAttachment(state: windowState) }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
            selection = .section(.search)
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

#endif
