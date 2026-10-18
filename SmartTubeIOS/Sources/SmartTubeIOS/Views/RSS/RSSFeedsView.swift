import SmartTubeIOSCore
import SwiftUI

// MARK: - RSSFeedsView

/// Shows videos from all active user-added RSS feed subscriptions.
/// Mimics the queue/playlist layout (compact card list, newest-first).

struct RSSFeedsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var vm = RSSFeedsViewModel()
    @State private var showAddFeed = false
    @State private var showManageFeeds = false

    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #else
    @State private var selectedVideo: Video?
    #endif
    @Environment(\.innerTubeAPI) private var api

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Inline header: the segment's own actions, under the Library segmented control.
            HStack(spacing: VFSpace.s4) {
                Text("RSS Feeds", bundle: .module)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showManageFeeds = true
                } label: {
                    Image(systemName: AppSymbol.rssManage)
                        .frame(minWidth: VFTarget.touch, minHeight: VFTarget.touch)
                }
                .accessibilityLabel(Text("Manage RSS Feeds", bundle: .module))
                .accessibilityIdentifier("rss.manageFeedsButton")
                Button {
                    showAddFeed = true
                } label: {
                    Image(systemName: AppSymbol.add)
                        .frame(minWidth: VFTarget.touch, minHeight: VFTarget.touch)
                }
                .accessibilityLabel(Text("Add RSS Feed", bundle: .module))
                .accessibilityIdentifier("rss.addFeedButton")
            }
            .padding(.leading, VFSpace.s16)
            .padding(.trailing, VFSpace.s8)
            #endif

            Group {
                if vm.isLoading && vm.videos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.videos.isEmpty {
                    emptyState
                } else {
                    videoList
                }
            }
        }
        .sheet(isPresented: $showAddFeed, onDismiss: { vm.load() }) {
            AddRSSFeedView()
        }
        .sheet(isPresented: $showManageFeeds, onDismiss: { vm.load() }) {
            ManageRSSFeedsView()
        }
        #if !os(iOS)
        // tvOS and macOS push the player in the Library stack, like a card click elsewhere.
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .task {
            vm.load()
        }
        .refreshable {
            vm.load()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No RSS Feeds", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.rssFeed)
            }
        } description: {
            Text("Add a YouTube channel RSS feed to see videos here.", bundle: .module)
        } actions: {
            Button {
                showAddFeed = true
            } label: {
                Label {
                    Text("Add RSS Feed", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.add)
                }
            }
            .buttonStyle(.vfProminent)
            .accessibilityIdentifier("rss.emptyAddFeedButton")
        }
    }

    // MARK: - Video List

    private var videoList: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let displayVideos = vm.videos
            .filter { !hideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
        return ScrollView {
            VideoGridSection(
                videos: displayVideos,
                onSelect: { video in
                    #if os(iOS)
                    playerRouter.open(video: video, api: api)
                    #else
                    selectedVideo = video
                    #endif
                }
            )
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }
}
