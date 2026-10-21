#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - MainSidebarView  (macOS)
//
// Native window shell: source-list sidebar with the sections and the Queue (A1, under Library),
// and the selected item's content. Settings is the separate ⌘, window (MacSettingsScene), not a sidebar row.
// The player is pushed into the content stack and owns its inspector (PlayerView+Inspector.swift).
// Three separate states: the selected section (`selection`), the selected item (each section's
// own navigation state) and the active video (a pushed `PlayerView`, e.g. `browseVM.deepLinkedVideo`).

struct MainSidebarView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @State private var searchVM = SearchViewModel()
    /// The selected row's `ShellItem.id`, restored with the window.
    @SceneStorage("sidebarSelection") private var selectionID = ShellItem.section(.home).id
    /// A channel page opened from a card or link, pushed on the detail stack.
    @State private var channelPush: ChannelDestination?
    @State private var windowState = MacWindowState()
    @State private var libraryQueueRequested = false

    var body: some View {
        @Bindable var browseVM = browseVM
        @Bindable var windowState = windowState
        NavigationSplitView(columnVisibility: $windowState.sidebarVisibility) {
            // A click on empty space sets nil: the sidebar always keeps a selection.
            List(selection: Binding<ShellItem?>(get: { selection }, set: { if let item = $0 { selection = item } })) {
                ForEach(sidebarItems) { sidebarRow($0) }
            }
            .navigationTitle("VoxaFrame")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if auth.isSignedIn { accountRow }
            }
        } detail: {
            NavigationStack {
                selection.destination(api: api)
                    // smarttube:// links and the UI-test queue open the player in the content area, like a
                    // card click. Back pops it; it never closes the window. A new link while one is open
                    // replaces that player (`.id`), so its own view model loads the new video.
                    .navigationDestination(item: $browseVM.deepLinkedVideo) { video in
                        PlayerView(video: video, api: api).id(video)
                    }
                    .navigationDestination(item: $channelPush) { dest in
                        ChannelView(channelId: dest.channelId, api: api)
                    }
            }
        }
        .focusedSceneValue(
            \.macSidebarNavigation, MacSidebarNavigation(items: sidebarItems, select: { selection = $0 })
        )
        .environment(searchVM)
        .environment(windowState)
        .frame(minWidth: VFMacWindow.minimumSize.width, minHeight: VFMacWindow.minimumSize.height)
        .background { MacWindowAttachment(state: windowState) }
        // The Queue row goes away when the setting is turned off: keep the user on the queue, as Library › Queue.
        .onChange(of: store.settings.showQueueTab) { _, shown in
            guard !shown, selectionID == ShellItem.queue.id else { return }
            libraryQueueRequested = true
            selection = .section(.library)
        }
        .environment(\.libraryQueueRequest, $libraryQueueRequested)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
            selection = .section(.search)
        }
        .onChange(of: selectionID) { channelPush = nil }
        // Cards and smarttube://channel links push the channel on the detail stack only.
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let id = note.userInfo?["channelId"] as? String, !id.isEmpty, channelPush?.channelId != id
            else { return }
            channelPush = ChannelDestination(channelId: id)
        }
        // App Intents and `smarttube://search` links.
        .onReceive(NotificationCenter.default.publisher(for: .smartTubeOpenSearch)) { note in
            guard let query = note.userInfo?["query"] as? String else { return }
            // Pop a channel pushed over Search so the results show.
            channelPush = nil
            selection = .section(.search)
            searchVM.query = query
            searchVM.search()
        }
        // App Intents and `smarttube://section/…` links: HomeView picks the chip (legacy `recommended` is Home).
        .task {
            for await _ in NotificationCenter.default.notifications(named: .smartTubeOpenSection) {
                selection = .section(.home)
            }
        }
    }

    /// Sidebar order; also the ⌘1… order of the View menu's section commands.
    private var sidebarItems: [ShellItem] {
        AppSection.allCases.filter { $0 != .settings }.flatMap { section -> [ShellItem] in
            section == .library && store.settings.showQueueTab ? [.section(section), .queue] : [.section(section)]
        }
    }

    /// The restored row, or Home when it is no longer in the sidebar.
    private var selection: ShellItem {
        get {
            ShellItem(id: selectionID).flatMap { sidebarItems.contains($0) ? $0 : nil } ?? .section(.home)
        }
        nonmutating set { selectionID = newValue.id }
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
