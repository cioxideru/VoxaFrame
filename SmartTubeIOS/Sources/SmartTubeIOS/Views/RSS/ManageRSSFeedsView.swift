import SmartTubeIOSCore
import SwiftUI

// MARK: - ManageRSSFeedsView

/// Sheet showing the list of saved RSS feeds with toggle-active and swipe-to-delete.

struct ManageRSSFeedsView: View {
    @State private var feeds: [RSSFeedInfo] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if feeds.isEmpty {
                    ContentUnavailableView(
                        "No RSS Feeds",
                        systemImage: AppSymbol.rssFeed,
                        description: Text("Add a feed from the RSS Feeds screen.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(feeds) { feed in
                                feedRow(feed)
                            }
                            .onDelete(perform: deleteFeeds)
                        } footer: {
                            Text(
                                "Turning a feed off keeps it in this list. Deleting removes it from this device.",
                                bundle: .module)
                        }
                    }
                }
            }
            .navigationTitle("Manage RSS Feeds")
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await reloadFeeds()
            }
        }
    }

    private func feedRow(_ feed: RSSFeedInfo) -> some View {
        // The feed name is the toggle's label, so VoiceOver reads which feed it switches.
        Toggle(
            isOn: Binding(
                get: { feed.isActive },
                set: { newValue in
                    Task {
                        await RSSFeedStore.shared.setActive(feed.id, newValue)
                        await reloadFeeds()
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: VFSpace.s4 / 2) {
                Text(verbatim: feed.title)  // verbatim: feed name
                    .font(.body)
                Group {
                    if feed.isActive {
                        Text(verbatim: feed.feedURL.absoluteString)  // verbatim: feed address
                    } else {
                        Text("Off · stays in this list", bundle: .module)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .padding(.vertical, VFSpace.s4 / 2)
    }

    private func deleteFeeds(at offsets: IndexSet) {
        let toDelete = offsets.map { feeds[$0] }
        Task {
            for feed in toDelete {
                await RSSFeedStore.shared.removeFeed(id: feed.id)
            }
            await reloadFeeds()
        }
    }

    @MainActor
    private func reloadFeeds() async {
        feeds = await RSSFeedStore.shared.allFeeds()
        isLoading = false
    }
}
