import Foundation

extension BrowseViewModel {

    func fetchShortsGroup(continuationToken: String? = nil) async throws -> VideoGroup {
        var token = continuationToken
        var seenTokens = Set<String>()
        var seenVideos = Set(continuationToken == nil ? [] : videoGroups.flatMap(\.videos).map(\.id))
        var group = VideoGroup(title: "Shorts", videos: [])
        for _ in 0..<InnerTubeClients.maxShortsPagesPerRequest {
            try Task.checkCancellation()
            if let token { seenTokens.insert(token) }
            if let token {
                group = try await api.fetchShortsMore(continuationToken: token)
            } else {
                group = try await api.fetchShorts()
            }
            group.videos = group.videos.filter { seenVideos.insert($0.id).inserted }
            if let next = group.nextPageToken, seenTokens.contains(next) {
                group.nextPageToken = nil
            }
            guard group.videos.isEmpty, let next = group.nextPageToken else { break }
            token = next
        }
        return group
    }

    func fetchHomeSection() async throws {
        let rows = try await api.fetchHomeRows()
        if !Task.isCancelled {
            if rows.flatMap({ $0.videos }).isEmpty {
                isAuthRequired = true
                let popular = try await api.search(query: "popular")
                var deduped = popular
                deduped.videos = deduplicated(popular.videos)
                videoGroups = [deduped]
            } else {
                isAuthRequired = false
                // Dedup within each row — YouTube can return the same video ID
                // in multiple shelves of the initial home response.
                var seen = Set<String>()
                let dedupedRows = rows.map { row -> VideoGroup in
                    var copy = row
                    copy.videos = row.videos.filter { seen.insert($0.id).inserted }
                    return copy
                }.filter { !$0.videos.isEmpty }
                videoGroups = dedupedRows
            }
        }
    }

    func fetchNextHomePage(token: String) async throws {
        let newRows = try await retryWithBackoff(label: "BrowseVM[Home]") {
            try await api.fetchHomeRows(continuationToken: token)
        }
        guard !Task.isCancelled else { return }
        // Continuation responses can repeat videos both within and across shelves.
        var seen = Set(videoGroups.flatMap(\.videos).map(\.id))
        let filteredRows = newRows.map { row -> VideoGroup in
            var copy = row
            copy.videos = row.videos.filter { seen.insert($0.id).inserted }
            return copy
        }.filter { !$0.videos.isEmpty }
        videoGroups.append(contentsOf: filteredRows)
    }

    func fetchRecommendedSection() async throws {
        // UI-testing injection: bypass the network fetch when
        // `--uitesting-inject-recommended-ids=<id1,id2,...>` is present.
        // Allows Recommended chip tests to run on unauthenticated parallel
        // simulator clones without auth or visitor-session dependency.
        if let arg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-recommended-ids=")
        }) {
            let raw = String(arg.dropFirst("--uitesting-inject-recommended-ids=".count))
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            guard !ids.isEmpty, !Task.isCancelled else { return }
            let videos = ids.map { Video(id: $0, title: $0, channelTitle: "Test Channel") }
            isAuthRequired = false
            recommendedUsesSearchFallback = false
            videoGroups = [VideoGroup(title: "Recommended", videos: videos)]
            return
        }
        let group = try await api.fetchHome()
        // Reuse subscriptions for account Shorts; global discovery belongs to signed-out browsing.
        async let shortsFetch: VideoGroup? = hasAuthToken ? nil : try? api.fetchShorts()
        async let subsFetch: VideoGroup? = try? api.fetchSubscriptions()
        let (shortsGroup, subsGroup) = await (shortsFetch, subsFetch)
        if !Task.isCancelled {
            let subsShorts = (subsGroup?.videos ?? []).filter(\.isShort)
            let homeShorts = group.videos.filter(\.isShort)
            var seen = Set<String>()
            recommendedShortsVideos = (homeShorts + subsShorts + (shortsGroup?.videos ?? []))
                .filter { seen.insert($0.id).inserted }
            if group.videos.isEmpty {
                isAuthRequired = true
                recommendedUsesSearchFallback = true
                let popular = try await api.search(query: "popular")
                browseLog.notice(
                    "Recommended: home feed empty, using search fallback (nextToken=\(popular.nextPageToken != nil))"
                )
                var deduped = popular
                deduped.videos = deduplicated(popular.videos)
                videoGroups = [deduped]
            } else {
                isAuthRequired = false
                recommendedUsesSearchFallback = false
                var deduped = group
                deduped.videos = deduplicated(group.videos)
                videoGroups = [deduped]
            }
        }
    }

    func fetchSubscriptionsSection() async throws {
        #if DEBUG
        if HomePaginationUITestFixture.isMixedFeedEnabled {
            videoGroups = [try await api.fetchSubscriptions()]
            isAuthRequired = false
            return
        }
        #endif
        if hasAuthToken {
            let group = try await api.fetchSubscriptions()
            if !Task.isCancelled {
                isAuthRequired = false
                var deduped = group
                deduped.videos = deduplicated(group.videos)
                    .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                videoGroups = deduped.videos.isEmpty ? [] : [deduped]
            }
        } else {
            let videos = await LocalSubscriptionFeedService.shared.fetchFeed(api: api)
            if !Task.isCancelled {
                isAuthRequired = false
                let deduped = deduplicated(videos)
                    .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                videoGroups = deduped.isEmpty ? [] : [VideoGroup(title: "Subscriptions", videos: deduped)]
            }
        }
    }

    func fetchHistorySection() async throws {
        // #150: YouTube doesn't reliably credit watches to the account for device-code
        // sign-in, so the app keeps its own on-device history and shows it first, followed by whatever the account
        // history returns (best-effort — signed-out/failed fetches just yield local).
        let local = localHistory.videos
        let remote: VideoGroup? = try? await api.fetchHistory()
        if !Task.isCancelled {
            let localIds = Set(local.map(\.id))
            var group = remote ?? VideoGroup(title: "History", videos: [])
            group.videos = local + group.videos.filter { !localIds.contains($0.id) }
            isAuthRequired = group.videos.isEmpty
            videoGroups = group.videos.isEmpty ? [] : [group]
        }
    }

    func fetchPlaylistsSection() async throws {
        let playlists = try await api.fetchUserPlaylists()
        if !Task.isCancelled {
            isAuthRequired = playlists.isEmpty
            // Convert PlaylistInfo list into a VideoGroup of placeholder videos
            let videos = playlists.map { pl -> Video in
                Video(
                    id: pl.id, title: pl.title, channelTitle: pl.videoCount.map { "\($0) videos" } ?? "",
                    thumbnailURL: pl.thumbnailURL, playlistId: pl.id)
            }
            videoGroups = videos.isEmpty ? [] : [VideoGroup(title: "Playlists", videos: videos)]
        }
    }

    func fetchChannelsSection() async throws {
        if hasAuthToken {
            let channels = try await api.fetchSubscribedChannels()
            browseLog.notice("channels fetch complete: \(channels.count) channels, isCancelled=\(Task.isCancelled)")
            if !Task.isCancelled {
                isAuthRequired = false
                subscribedChannels = channels
                videoGroups = []
                let chCount = subscribedChannels.count
                let authReq = isAuthRequired
                browseLog.notice("channels state set: subscribedChannels=\(chCount) isAuthRequired=\(authReq)")
                // Fill avatars only for channel tabs that omit their thumbnail.
                if !channels.isEmpty {
                    enrichTask?.cancel()
                    enrichTask = Task { await self.enrichChannelAvatars() }
                }
            }
        } else {
            let localChannels = await LocalSubscriptionStore.shared.allChannelsSortedBySubscriptionDate()
            browseLog.notice(
                "channels (local): \(localChannels.count) followed channels sorted by subscription date, isCancelled=\(Task.isCancelled)"
            )
            if !Task.isCancelled {
                isAuthRequired = false
                subscribedChannels = localChannels.map { $0.toChannel() }
                videoGroups = []
            }
        }
    }

    func fetchWatchLaterSection() async throws {
        // #125: direct "Watch Later" home tab, easier access than Library > Playlists >
        // Watch Later. Stamps playlistId = "WL" on each video (parsePlaylistVideoRenderer
        // doesn't set it) so VideoCardView's Remove/Move-to-Playlist actions work here too
        // (VideoCardView falls back to video.playlistId when its explicit currentPlaylistId
        // parameter isn't passed — this section renders through the generic BrowseView
        // grid, which doesn't thread section context per-card).
        if !hasAuthToken {
            if !Task.isCancelled {
                isAuthRequired = true
                videoGroups = []
            }
        } else {
            var group = try await api.fetchPlaylistVideos(playlistId: "WL", continuationToken: nil)
            // #157: a video just added via this app can be momentarily missing here —
            // YouTube's own playlist index doesn't always reflect an add immediately, so even
            // an explicit pull-to-refresh right after saving can race it. One short delayed
            // re-fetch covers that window. Only *recent* saves count: the persisted membership
            // set is never pruned and only this first page is compared, so using it would add
            // a delay + second fetch to every load for anyone with an old or deep entry.
            let justSaved = watchLaterMembership.recentlySaved(within: 120)
            let fetchedIds = Set(group.videos.map(\.id))
            if !justSaved.isEmpty, !justSaved.isSubset(of: fetchedIds), !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !Task.isCancelled {
                    group = try await api.fetchPlaylistVideos(playlistId: "WL", continuationToken: nil)
                }
            }
            if !Task.isCancelled {
                isAuthRequired = false
                var stamped = group
                stamped.videos = group.videos.map { video -> Video in
                    var video = video
                    video.playlistId = "WL"
                    return video
                }
                // Saves YouTube still hasn't indexed after the retry are shown on top from
                // what this app saved, so they don't seem lost until a later refresh.
                let present = Set(stamped.videos.map(\.id))
                let missing = watchLaterMembership.recentlySavedVideos(within: 15 * 60)
                    .filter { !present.contains($0.id) }
                stamped.videos.insert(contentsOf: missing, at: 0)
                videoGroups = stamped.videos.isEmpty ? [] : [stamped]
            }
        }
    }
}
