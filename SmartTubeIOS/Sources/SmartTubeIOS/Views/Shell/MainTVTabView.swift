#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - MainTVTabView  (tvOS)
// Top-bar TabView is the Apple-recommended navigation pattern for Apple TV.
// Each tab contains a NavigationStack so drill-down is available within each section.
// Focus and the tab bar stay system-owned; each section's screen owns its own margins.

struct MainTVTabView: View {
    @State private var searchVM = SearchViewModel()
    @State private var selectedTab: AppSection = .home
    /// A channel page opened from a card or link, pushed on the selected tab's stack only.
    @State private var channelPushes: [AppSection: ChannelDestination] = [:]
    @Environment(\.innerTubeAPI) private var api

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    section.destination(api: api)
                        .navigationDestination(
                            item: Binding(
                                get: { channelPushes[section] },
                                set: { channelPushes[section] = $0 })
                        ) { dest in
                            ChannelView(channelId: dest.channelId, api: api)
                        }
                }
                .tabItem {
                    Label(section.tabTitle, systemImage: section.icon)
                }
                .tag(section)
            }
        }
        .environment(searchVM)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearch)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let id = note.userInfo?["channelId"] as? String, !id.isEmpty,
                channelPushes[selectedTab]?.channelId != id
            else { return }
            channelPushes[selectedTab] = ChannelDestination(channelId: id)
        }
    }
}
#endif
