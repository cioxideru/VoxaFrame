import SmartTubeIOSCore
import SwiftUI

extension HomeView {
    var feedContent: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let isShorts = selectedSection.type == .shorts
        let applyHideShorts = hideShorts && selectedSection.type != .history
        // #121: History is the one place watched videos are the point — never filtered.
        let applyHideWatched = store.settings.hideWatchedVideos && selectedSection.type != .history
        let hideWatchedThreshold = store.settings.hideWatchedThreshold
        // #62: channel filter only applies to (and is only shown for) Subscriptions —
        // it wouldn't make sense for a single-source list like a specific Channel page,
        // and Home mixes recommendations that don't necessarily come from a subscription.
        let isSubscriptions = selectedSection.type == .subscriptions
        let channelFilter = isSubscriptions ? subscriptionsChannelFilter : nil

        // Pinned shorts row: shown above the scrollable content for all chips
        // except the Shorts chip itself (which shows a full vertical list instead).
        // For Recommended, use the separately-fetched recommendedShortsVideos so
        // there is no double-counting with the grid below.
        // For all other chips, extract any shorts that appear in the video groups.
        let pinnedShorts: [Video]
        if isShorts || applyHideShorts {
            pinnedShorts = []
        } else if selectedSection.type == .recommended {
            pinnedShorts = sectionVM.recommendedShortsVideos.filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
        } else {
            pinnedShorts = sectionVM.videoGroups.flatMap(\.videos).filter(\.isShort).filter {
                !hideLiveShorts || !($0.isLive && $0.isShort)
            }
        }

        let rowGroups: [VideoGroup] = sectionVM.videoGroups.filter { $0.layout == .row }.map { group in
            var copy = group
            var videos = group.videos
            if applyHideShorts { videos = videos.filter { !$0.isShort } }
            if hideLiveShorts { videos = videos.filter { !($0.isLive && $0.isShort) } }
            if hideVideoPremieres { videos = videos.filter { !$0.isUpcoming } }
            if applyHideWatched { videos = videos.filter { !$0.isWatched(threshold: hideWatchedThreshold) } }
            if let channelFilter { videos = videos.filter { $0.channelId == channelFilter } }
            copy.videos = videos
            return copy
        }
        // For non-Shorts chips, exclude shorts from the grid — they appear in the
        // pinned row above. For the Shorts chip itself, keep all videos.
        // VStack (not LazyVStack) is required here. LazyVGrid inside LazyVStack
        // collapses to zero height — grid items become invisible and non-tappable
        // because LazyVStack never provides a measured height to LazyVGrid.
        // Row groups are few (typically ≤15 carousels) so eager rendering is fine.
        let gridVideos = sectionVM.videoGroups.filter { $0.layout != .row }
            .flatMap(\.videos)
            .filter { !applyHideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
            .filter { !applyHideWatched || !$0.isWatched(threshold: hideWatchedThreshold) }
            .filter { channelFilter == nil || $0.channelId == channelFilter }
            .filter { isShorts || !$0.isShort }

        // #62: distinct (channelId, channelTitle) pairs across the currently loaded
        // Subscriptions videos, for the channel-filter menu. Derived client-side from
        // whatever's already loaded — no extra network call — so it only ever offers
        // channels with at least one video in the feed right now, not literally every
        // channel the user follows (a channel with zero recent uploads has nothing to
        // filter to anyway).
        let availableChannels: [(id: String, title: String)] = {
            guard isSubscriptions else { return [] }
            var seen = Set<String>()
            var result: [(id: String, title: String)] = []
            for video in sectionVM.videoGroups.flatMap(\.videos) {
                guard let channelId = video.channelId, seen.insert(channelId).inserted else { continue }
                result.append((id: channelId, title: video.channelTitle))
            }
            return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }()

        // The raw last video of the last group is the canonical pagination trigger for
        // loadMoreIfNeeded — it checks membership in videoGroups.last, so passing a
        // filtered (non-short) video won't match if the last group is all-shorts.
        // Both the shorts row and the grid use this as their loadMore trigger so
        // either reaching the end of the shorts row OR scrolling to the bottom of
        // the main content independently triggers the next page load.
        let paginationTrigger: Video? = sectionVM.videoGroups.last?.videos.last

        return VStack(spacing: 0) {
            // #62: channel filter, Subscriptions only. Hidden entirely when there's
            // nothing to filter between (0 or 1 distinct channels loaded).
            if isSubscriptions, availableChannels.count > 1 {
                HStack {
                    Menu {
                        Button {
                            subscriptionsChannelFilter = nil
                        } label: {
                            if subscriptionsChannelFilter == nil {
                                Label("All Channels", systemImage: AppSymbol.checkmark)
                            } else {
                                Text("All Channels")
                            }
                        }
                        Divider()
                        ForEach(availableChannels, id: \.id) { channel in
                            Button {
                                subscriptionsChannelFilter = channel.id
                            } label: {
                                if subscriptionsChannelFilter == channel.id {
                                    Label(channel.title, systemImage: AppSymbol.checkmark)
                                } else {
                                    Text(channel.title)
                                }
                            }
                        }
                    } label: {
                        Label(
                            availableChannels.first(where: { $0.id == subscriptionsChannelFilter })?.title
                                ?? "All Channels",
                            systemImage: AppSymbol.channelFilter
                        )
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier(AccessibilityID.homeSubscriptionsChannelFilter)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            // Pinned ShortsRowSection — outside the ScrollView so it stays fixed
            // at the top while the video content below scrolls.
            if !pinnedShorts.isEmpty {
                ShortsRowSection(
                    videos: pinnedShorts,
                    onSelect: { selectVideo($0, from: pinnedShorts) },
                    accessibilityID: selectedSection.type == .recommended
                        ? "recommended.shortsRow"
                        : "browse.shortsRow",
                    loadMore: {
                        // Reaching the end of the shorts row means the user wants more
                        // content of ALL types — set both flags so onChange keeps
                        // retrying until both shorts AND non-shorts have grown (or pages
                        // are exhausted). Without setting needsMoreNonShorts here, pages
                        // that arrive with only non-shorts would not re-trigger the loop.
                        let allVideos = sectionVM.videoGroups.flatMap(\.videos)
                        shortsCountAtTrigger = allVideos.filter(\.isShort).count
                        nonShortsCountAtTrigger = allVideos.filter { !$0.isShort }.count
                        needsMoreShorts = true
                        needsMoreNonShorts = true
                        if let last = paginationTrigger {
                            sectionVM.loadMoreIfNeeded(lastVideo: last)
                        }
                    }
                )
                #if os(tvOS)
                .focusSection()
                #endif
            }
            if isShorts {
                // Shorts chip: vertical portrait card list driven by ShortsRowSection's
                // internal ScrollView. frame(maxHeight: .infinity) ensures the internal
                // ScrollView gets the full remaining height rather than sizing to content.
                let shortsVideos = sectionVM.videoGroups.flatMap(\.videos)
                ShortsRowSection(
                    videos: shortsVideos,
                    onSelect: { selectVideo($0, from: shortsVideos) },
                    accessibilityID: "shorts.section",
                    loadMore: {
                        // Set retry flag so onChange keeps fetching pages until the
                        // Shorts chip has more videos — guards in loadMoreIfNeeded
                        // prevent duplicate in-flight requests.
                        shortsCountAtTrigger = sectionVM.videoGroups.flatMap(\.videos).count
                        needsMoreShorts = true
                        if let last = paginationTrigger {
                            sectionVM.loadMoreIfNeeded(lastVideo: last)
                        }
                    },
                    scrollAxis: .vertical
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(tvOS)
                .focusSection()
                #endif
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if selectedSection.type == .playlists, queueVideosCount > 0 {
                            currentQueueRow
                        }
                        ForEach(rowGroups) { group in
                            if let title = group.title, !title.isEmpty {
                                Text(title)
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)
                            }
                            VideoRowSection(videos: group.videos, onSelect: { selectVideo($0, from: group.videos) })
                        }
                        if !gridVideos.isEmpty {
                            VideoGridSection(
                                videos: gridVideos,
                                onSelect: { selectVideo($0, from: gridVideos) },
                                loadMore: {
                                    // Reaching the end of the grid means the user wants
                                    // more content of ALL types — set both flags so
                                    // onChange keeps retrying until both non-shorts AND
                                    // shorts have grown (or pages are exhausted). Without
                                    // setting needsMoreShorts here, pages that contain
                                    // only shorts (no new grid videos) would stall the
                                    // retry — and the pinned shorts row would never grow
                                    // unless the user also manually scrolls it to the end.
                                    let allVideos = sectionVM.videoGroups.flatMap(\.videos)
                                    nonShortsCountAtTrigger = allVideos.filter { !$0.isShort }.count
                                    shortsCountAtTrigger = allVideos.filter(\.isShort).count
                                    needsMoreNonShorts = true
                                    needsMoreShorts = true
                                    if let last = paginationTrigger {
                                        sectionVM.loadMoreIfNeeded(lastVideo: last)
                                    }
                                }
                            )
                        }
                        if sectionVM.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                }
                .accessibilityIdentifier(AccessibilityID.homeSectionFeed)
                .refreshable { sectionVM.loadContent(refresh: true) }
                #if os(iOS)
                .simultaneousGesture(sectionSwipe)
                #endif
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
        .onChange(of: sectionVM.videoGroups.flatMap(\.videos).count) { _, _ in
            // After each page load, check whether the type(s) each trigger was
            // waiting for actually appeared. Compare against the count snapshot
            // recorded when the scroll trigger fired — NOT the last-page slice,
            // which for mergeIntoFirstGroup sections is the entire accumulated
            // list (making "does last page have shorts?" always true after the
            // first short ever arrived).
            //
            // loadMoreIfNeeded's own guards (nextPageToken, isLoadingMore) prevent
            // runaway loops — pagination stops when pages are exhausted or a load
            // is already in flight.
            let isShortsSectionActive = selectedSection.type == .shorts
            let applyHide = store.settings.hideShorts && selectedSection.type != .history
            guard !applyHide,
                let trigger = sectionVM.videoGroups.last?.videos.last
            else { return }

            let allVideos = sectionVM.videoGroups.flatMap(\.videos)
            var shouldTrigger = false

            if isShortsSectionActive {
                // Shorts chip: all videos are shorts — compare total count against snapshot.
                // Keep triggering until the count grows or pages are exhausted.
                if needsMoreShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    if allVideos.count > shortsCountAtTrigger {
                        needsMoreShorts = false  // new shorts arrived — satisfied
                    } else if !hasMorePages {
                        needsMoreShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had nothing new — fetch another
                    }
                }
            } else {
                // Mixed feed: check each type independently.
                if needsMoreShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    let currentShortsCount = allVideos.filter(\.isShort).count
                    if currentShortsCount > shortsCountAtTrigger {
                        needsMoreShorts = false  // pinned row got new shorts — satisfied
                    } else if !hasMorePages {
                        needsMoreShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had no new shorts — fetch another
                    }
                }

                if needsMoreNonShorts {
                    let hasMorePages = sectionVM.videoGroups.last?.nextPageToken != nil
                    let currentNonShortsCount = allVideos.filter { !$0.isShort }.count
                    if currentNonShortsCount > nonShortsCountAtTrigger {
                        needsMoreNonShorts = false  // grid got new regular videos — satisfied
                    } else if !hasMorePages {
                        needsMoreNonShorts = false  // no more pages — stop
                    } else {
                        shouldTrigger = true  // page had no new regulars — fetch another
                    }
                }
            }

            if shouldTrigger {
                sectionVM.loadMoreIfNeeded(lastVideo: trigger)
            }
        }
    }

    @ViewBuilder private var currentQueueRow: some View {
        HStack(spacing: 12) {
            Image(systemName: AppSymbol.queue)
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Queue")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(queueVideosCount) video\(queueVideosCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: AppSymbol.chevronRight)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlaylist = Video(
                id: CurrentQueueStore.playlistID,
                title: "Current Queue",
                channelTitle: ""
            )
        }
        .accessibilityIdentifier(AccessibilityID.homeCurrentQueueRow)
        Divider().padding(.horizontal)
    }

}
