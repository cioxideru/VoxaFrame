import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - BrowseViewModelTests

@Suite("BrowseViewModel")
@MainActor
struct BrowseViewModelTests {

    @Test("Initial foreground waits for sign-in instead of starting an anonymous Home load")
    func initialForegroundDoesNotLoadBeforeAuthentication() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(videos: [makeVideo("vid_0000001")])]
        let vm = BrowseViewModel(api: mock)

        vm.refreshIfStale()
        #expect(!vm.isLoading)
        #expect(mock.calls.isEmpty)
        await vm.updateAuthToken("first-token")

        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(mock.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
    }

    @Test("Signed-out startup does not fetch a Home feed")
    func signedOutStartupClearsWidgetWithoutFetching() async {
        let mock = MockInnerTubeAPI()
        let vm = BrowseViewModel(api: mock)

        await vm.updateAuthToken(nil)
        vm.refreshIfStale()

        #expect(!vm.isLoading)
        #expect(mock.calls == [.init(method: "setAuthToken", args: ["nil"])])
    }

    @Test("Foreground refresh does not restart a load queued in the same event")
    func foregroundRefreshKeepsQueuedLoad() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(videos: [makeVideo("vid_0000001")])]
        let vm = BrowseViewModel(api: mock)
        vm.loadContent(source: "test")
        #expect(vm.isLoading)

        vm.refreshIfStale()

        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(mock.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
    }

    @Test("Replacing a queued feed load cancels it before it makes a request")
    func replacedQueuedLoadDoesNotFetch() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(videos: [makeVideo("vid_0000001")])]
        let vm = BrowseViewModel(api: mock)
        vm.loadContent(source: "test")
        vm.loadContent(refresh: true, source: "test.replacement")

        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(mock.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
    }

    @Test(
        "Refreshing credentials keeps the current feed and pagination",
        arguments: [BrowseSection.SectionType.home, .subscriptions]
    )
    func tokenRefreshKeepsLoadedFeed(section: BrowseSection.SectionType) async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [
            VideoGroup(title: "Home", videos: [makeVideo("vid_0000001")], nextPageToken: "next-page")
        ]
        mock.subscriptionsResult = mock.homeRowsResult[0]
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: section))
        await vm.updateAuthToken("first-token")
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        let loadedAt = vm.loadedAt
        let contentRequests = mock.calls.filter { $0.method != "setAuthToken" }

        await vm.updateAuthToken("refreshed-token")

        #expect(vm.loadedAt == loadedAt)
        #expect(vm.videoGroups.first?.videos.first?.id == "vid_0000001")
        #expect(vm.videoGroups.first?.nextPageToken == "next-page")
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(mock.calls.filter { $0.method != "setAuthToken" } == contentRequests)
        #expect(mock.calls.last { $0.method == "setAuthToken" }?.args == ["refreshed-token"])
    }

    @Test("A hidden section can authenticate without replacing its feed")
    func hiddenSectionDefersSignInReload() async {
        let mock = MockInnerTubeAPI()
        let vm = BrowseViewModel(api: mock)
        vm.videoGroups = [VideoGroup(videos: [makeVideo("cached_0001")])]

        await vm.updateAuthToken("first-token", reloadOnSignIn: false)

        #expect(vm.videoGroups.first?.videos.first?.id == "cached_0001")
        #expect(mock.calls == [.init(method: "setAuthToken", args: ["first-token"])])
        mock.subscriptionsResult = VideoGroup(videos: [makeVideo("subs_000001")])
        vm.select(section: BrowseSection(type: .subscriptions))
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(vm.videoGroups.first?.videos.first?.id == "subs_000001")
        #expect(mock.calls.filter { $0.method == "fetchSubscriptions" }.count == 1)
        #expect(!mock.calls.contains { $0.method == "fetchHomeRows" })
    }

    @Test("Deferring sign-in loading still clears account-only content on sign-out")
    func deferredSignInStillHandlesSignOut() async {
        let mock = MockInnerTubeAPI()
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: .channels))
        await vm.updateAuthToken("first-token", reloadOnSignIn: false)
        vm.subscribedChannels = [Channel(id: "account-channel", title: "Account Channel")]

        await vm.updateAuthToken(nil, reloadOnSignIn: false)

        #expect(vm.subscribedChannels.isEmpty)
        #expect(!vm.hasAuthToken)
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })
        #expect(!mock.calls.contains { $0.method == "fetchSubscribedChannels" })
    }

    @Test("loadContent for .subscriptions calls fetchSubscriptions and populates videoGroups")
    func loadSubscriptionsPopulatesGroups() async {
        let mock = MockInnerTubeAPI()
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [makeVideo("subvid_AAAA")])

        let section = BrowseSection(id: "subscriptions", title: "Subscriptions", type: .subscriptions)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        await vm.updateAuthToken("fake-token")  // authenticated path
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { !vm.videoGroups.isEmpty })

        #expect(mock.calls.contains { $0.method == "fetchSubscriptions" })
        #expect(!vm.videoGroups.isEmpty)
        #expect(vm.videoGroups[0].videos[0].id == "subvid_AAAA")
    }

    @Test("Disabled history is empty before authentication and selection, and can be enabled again")
    func disabledHistoryBeforeLoading() async throws {
        let mock = MockInnerTubeAPI()
        mock.historyResult = VideoGroup(title: "History", videos: [makeVideo("remote-history")])
        let local = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "history-\(UUID().uuidString)")))
        local.record(makeVideo("local-history"))
        let vm = BrowseViewModel(api: mock, localHistory: local)
        vm.updateHistoryEnabled(false)
        await vm.updateAuthToken("token", reloadOnSignIn: false)
        vm.select(section: BrowseSection(type: .history))
        await waitForTasks { !vm.isLoading }
        #expect(vm.videoGroups.isEmpty)
        #expect(!mock.calls.contains { $0.method == "fetchHistory" })

        vm.updateHistoryEnabled(true)
        await waitForTasks { !vm.isLoading }
        #expect(vm.videoGroups.flatMap(\.videos).map(\.id) == ["local-history", "remote-history"])
        vm.updateHistoryEnabled(false)
        #expect(vm.videoGroups.isEmpty)
        await waitForTasks { !vm.isLoading }
        #expect(mock.calls.filter { $0.method == "fetchHistory" }.count == 1)
    }

    @Test(
        "Disabling History cancels an initial load or continuation and ignores its late result",
        arguments: [false, true])
    func disableInFlightHistory(pagination: Bool) async throws {
        let mock = MockInnerTubeAPI()
        let local = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "history-\(UUID().uuidString)")))
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: .history), localHistory: local)
        let first = makeVideo("first")
        if pagination {
            mock.historyResult = VideoGroup(title: "History", videos: [first], nextPageToken: "next")
            vm.loadContent(refresh: true)
            await waitForTasks { !vm.isLoading }
        }
        var response: CheckedContinuation<VideoGroup, Never>?
        var returnedCancelled = false
        mock.historyHandler = { _ in
            let result = await withCheckedContinuation { response = $0 }
            returnedCancelled = Task.isCancelled
            return result
        }
        if pagination { vm.loadMoreIfNeeded(lastVideo: first) } else { vm.loadContent(refresh: true) }
        await waitForTasks { response != nil }
        vm.updateHistoryEnabled(false)
        #expect(vm.videoGroups.isEmpty)
        let count = mock.calls.filter { $0.method == "fetchHistory" }.count
        response?.resume(returning: VideoGroup(title: "Late", videos: [makeVideo("late")]))
        await waitForTasks { returnedCancelled && !vm.isLoading }
        #expect(vm.videoGroups.isEmpty)
        #expect(mock.calls.filter { $0.method == "fetchHistory" }.count == count)
    }

    @Test("loadContent for .history calls fetchHistory")
    func loadHistoryCallsFetch() async throws {
        let mock = MockInnerTubeAPI()
        mock.historyResult = VideoGroup(title: "History", videos: [makeVideo("histvid_AAAA")])

        let section = BrowseSection(id: "history", title: "History", type: .history)
        // Own empty local-history store: the shared one persists entries recorded by other
        // player tests across runs, and local entries are shown first (#150).
        let emptyLocal = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "hist-\(UUID().uuidString)")))
        let vm = BrowseViewModel(api: mock, initialSection: section, localHistory: emptyLocal)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.videoGroups.first?.videos.first != nil })

        #expect(mock.calls.contains { $0.method == "fetchHistory" })
        #expect(vm.videoGroups.first?.videos.first?.id == "histvid_AAAA")
    }

    @Test("loadContent for .history shows local history first, then account history without duplicates (#150)")
    func loadHistoryMergesLocalFirst() async throws {
        let mock = MockInnerTubeAPI()
        mock.historyResult = VideoGroup(
            title: "History", videos: [makeVideo("histvid_AAAA"), makeVideo("histvid_BBBB")])
        let local = LocalWatchHistoryStore(defaults: try #require(UserDefaults(suiteName: "hist-\(UUID().uuidString)")))
        local.record(makeVideo("histvid_BBBB"))  // also in account history → must not duplicate
        local.record(makeVideo("localonly_CCCC"))

        let section = BrowseSection(id: "history", title: "History", type: .history)
        let vm = BrowseViewModel(api: mock, initialSection: section, localHistory: local)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.videoGroups.first?.videos.count == 3 })

        #expect(vm.videoGroups.first?.videos.map(\.id) == ["localonly_CCCC", "histvid_BBBB", "histvid_AAAA"])
    }

    @Test("loadContent for .history shows local history even when the account fetch yields nothing (#150)")
    func loadHistoryLocalOnlyWhenRemoteEmpty() async throws {
        let mock = MockInnerTubeAPI()
        let local = LocalWatchHistoryStore(defaults: try #require(UserDefaults(suiteName: "hist-\(UUID().uuidString)")))
        local.record(makeVideo("localonly_CCCC"))

        let section = BrowseSection(id: "history", title: "History", type: .history)
        let vm = BrowseViewModel(api: mock, initialSection: section, localHistory: local)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.videoGroups.first?.videos.first != nil })

        #expect(vm.videoGroups.first?.videos.map(\.id) == ["localonly_CCCC"])
        #expect(!vm.isAuthRequired)
    }

    @Test("Empty subscriptions (local path) does not set isAuthRequired")
    func emptyLocalSubscriptionsDoNotSetAuthRequired() async {
        let mock = MockInnerTubeAPI()
        // No auth token → takes local path; local follows are empty

        let section = BrowseSection(id: "subscriptions", title: "Subscriptions", type: .subscriptions)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })

        // Local path never gates on auth — empty means "no follows yet", not "sign in"
        #expect(!vm.isAuthRequired)
    }

    @Test("Signed-in Recommended uses account Shorts without a duplicate subscription fetch")
    func recommendedAccountShorts() async {
        let api = MockInnerTubeAPI()
        var homeShort = makeVideo("home-short")
        homeShort.isShort = true
        var subscriptionShort = makeVideo("subscription-short")
        subscriptionShort.isShort = true
        api.homeResult = VideoGroup(videos: [homeShort])
        api.subscriptionsResult = VideoGroup(videos: [subscriptionShort, homeShort])
        api.shortsResult = VideoGroup(videos: [makeVideo("global-search")])
        let vm = BrowseViewModel(api: api)
        await vm.updateAuthToken("account", reloadOnSignIn: false)
        vm.select(section: BrowseSection(id: "recommended", title: "Recommended", type: .recommended))
        await waitForTasks { !vm.isLoading }
        #expect(vm.recommendedShortsVideos.map(\.id) == ["home-short", "subscription-short"])
        #expect(api.calls.filter { $0.method == "fetchSubscriptions" }.count == 1)
        #expect(!api.calls.contains { $0.method == "fetchShorts" })
    }

    @Test("loadContent for .shorts calls fetchShorts")
    func loadShortsCallsFetch() async {
        let mock = MockInnerTubeAPI()
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [makeVideo("shortvid_AAAA")])

        let section = BrowseSection(id: "shorts", title: "Shorts", type: .shorts)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { mock.calls.contains { $0.method == "fetchShorts" } })

        #expect(mock.calls.contains { $0.method == "fetchShorts" })
    }

    @Test("loadContent for .shorts with zero results normalizes videoGroups to empty")
    func loadShortsWithEmptyResultClearsVideoGroups() async {
        let mock = MockInnerTubeAPI()
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [])

        let section = BrowseSection(id: "shorts", title: "Shorts", type: .shorts)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })

        // videoGroups must be [] (not [VideoGroup(videos: [])]) so the Home
        // Shorts chip's empty state ("Nothing here yet") can render — a
        // 1-element array with no videos is indistinguishable from "has content"
        // to sectionFeed's videoGroups.isEmpty check.
        #expect(vm.videoGroups.isEmpty)
    }

    @Test("Sparse account Shorts retain a continuation after each bounded request")
    func sparseShortsCanResumeAfterEmptyInitialPages() async {
        let mock = MockInnerTubeAPI()
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "page-1")
        mock.shortsMoreHandler = { token in
            let page = Int(token.dropFirst("page-".count)) ?? 0
            return VideoGroup(
                title: "Shorts", videos: page == 4 ? [makeVideo("account-short")] : [],
                nextPageToken: "page-\(page + 1)")
        }
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: .shorts))
        vm.loadContent(refresh: true)
        await waitForTasks { vm.loadedAt != nil && !vm.isLoading }
        #expect(vm.videoGroups.flatMap(\.videos).isEmpty)
        #expect(vm.videoGroups.last?.nextPageToken == "page-3")
        #expect(vm.hasMoreShorts)
        #expect(mock.calls.filter { $0.method == "fetchShortsMore" }.count == 2)

        vm.loadMoreShorts()
        vm.loadMoreShorts()
        await waitForTasks { !vm.isLoadingMore }
        #expect(vm.videoGroups.flatMap(\.videos).map(\.id) == ["account-short"])
        #expect(
            mock.calls.filter { $0.method == "fetchShortsMore" }.map(\.args) == [
                ["page-1"], ["page-2"], ["page-3"], ["page-4"],
            ])
    }

    @Test("Repeated Shorts continuation stops without an endless request loop")
    func cyclicShortsContinuationStops() async {
        let mock = MockInnerTubeAPI()
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "same-page")
        mock.shortsMoreResult = mock.shortsResult
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: .shorts))
        vm.loadContent(refresh: true)
        await waitForTasks { vm.loadedAt != nil && !vm.isLoading }
        #expect(vm.videoGroups.isEmpty)
        #expect(!vm.hasMoreShorts)
        #expect(mock.calls.filter { $0.method == "fetchShortsMore" }.count == 1)
    }

    @Test("Error on non-auth section sets error property")
    func errorOnFetchSetsErrorProperty() async {
        struct TestError: Error {}
        let mock = MockInnerTubeAPI()
        mock.errorToThrow = TestError()

        let section = BrowseSection(id: "shorts", title: "Shorts", type: .shorts)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.error != nil })

        #expect(vm.error != nil)
    }

    @Test("isLoading is false after fetch completes")
    func isLoadingFalseAfterFetch() async {
        let mock = MockInnerTubeAPI()
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [makeVideo("vid_AAAAAAA")])

        let section = BrowseSection(id: "subscriptions", title: "Subscriptions", type: .subscriptions)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        // isLoading is false both before the fetch starts and after it ends, so
        // it can't be the polling condition on its own — and requiring a
        // recorded mock call doesn't work either, since unauthenticated
        // .subscriptions takes a local-store path that never calls the mock API
        // at all (see "Empty subscriptions (local path)" above). loadedAt is set
        // inside fetchSection's withThrowingTaskGroup body (BrowseViewModel.swift:475),
        // which can fire before the outer function (and its `defer { isLoading = false }`)
        // actually returns if other group children are still running — so require
        // both signals together rather than relying on loadedAt alone.
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })

        #expect(!vm.isLoading)
    }

    @Test("loadContent for .watchLater (signed in) calls fetchPlaylistVideos(WL) and stamps playlistId")
    func loadWatchLaterPopulatesGroupsAndStampsPlaylistId() async {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Watch Later", videos: [makeVideo("wlvid_AAAA")])

        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        await vm.updateAuthToken("fake-token")
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { !vm.videoGroups.isEmpty })

        #expect(mock.calls.contains { $0.method == "fetchPlaylistVideos" && $0.args.first == "WL" })
        #expect(vm.videoGroups.first?.videos.first?.id == "wlvid_AAAA")
        #expect(
            vm.videoGroups.first?.videos.first?.playlistId == "WL",
            "videos must be stamped with playlistId=WL so VideoCardView's Remove/Move-to-Playlist actions work from this tab"
        )
    }

    @Test("Watch Later: adds and removes made in the app update the open list at once (#157)")
    func watchLaterListFollowsAppChanges() async throws {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Watch Later", videos: [makeVideo("wlvid_AAAA")])
        let membership = WatchLaterMembershipStore(
            defaults: try #require(UserDefaults(suiteName: "wl-\(UUID().uuidString)")))
        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section, watchLaterMembership: membership)
        await vm.updateAuthToken("fake-token")
        await waitForTasks(until: { vm.videoGroups.first?.videos.first?.id == "wlvid_AAAA" })

        membership.markSaved(makeVideo("newsave_BBBB"), setVideoId: "SETVID_B")
        await waitForTasks(until: { vm.videoGroups.first?.videos.count == 2 })
        #expect(vm.videoGroups.first?.videos.map(\.id) == ["newsave_BBBB", "wlvid_AAAA"])
        #expect(vm.videoGroups.first?.videos.first?.setVideoId == "SETVID_B")

        membership.markRemoved("wlvid_AAAA")
        await waitForTasks(until: { vm.videoGroups.first?.videos.count == 1 })
        #expect(vm.videoGroups.first?.videos.map(\.id) == ["newsave_BBBB"])
    }

    @Test("Watch Later: a recent save YouTube hasn't indexed yet is shown on top after loading (#157)")
    func watchLaterLoadShowsUnindexedSave() async throws {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Watch Later", videos: [makeVideo("wlvid_AAAA")])
        let membership = WatchLaterMembershipStore(
            defaults: try #require(UserDefaults(suiteName: "wl-\(UUID().uuidString)")))
        membership.markSaved(makeVideo("justsaved_CCCC"), setVideoId: "SETVID_C")
        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section, watchLaterMembership: membership)
        await vm.updateAuthToken("fake-token")
        await waitForTasks(timeout: 5, until: { vm.videoGroups.first?.videos.count == 2 })
        #expect(vm.videoGroups.first?.videos.map(\.id) == ["justsaved_CCCC", "wlvid_AAAA"])
        #expect(vm.videoGroups.first?.videos.first?.playlistId == "WL")
    }

    @Test("Watch Later: an old saved video missing from page 1 does not trigger a retry (#157)")
    func watchLaterOldSaveDoesNotRetry() async throws {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Watch Later", videos: [makeVideo("wlvid_AAAA")])
        let membership = WatchLaterMembershipStore(
            defaults: try #require(UserDefaults(suiteName: "wl-\(UUID().uuidString)")))
        membership.markSaved("oldsave_ZZZZ", at: Date(timeIntervalSinceNow: -3600))

        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section, watchLaterMembership: membership)
        await vm.updateAuthToken("fake-token")
        // updateAuthToken reloads the section; measure only the load below.
        await waitForTasks(timeout: 5, until: { vm.loadedAt != nil && !vm.isLoading })
        mock.calls.removeAll()
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { mock.calls.contains { $0.method == "fetchPlaylistVideos" } })
        await waitForTasks(until: { !vm.isLoading })

        #expect(mock.calls.filter { $0.method == "fetchPlaylistVideos" }.count == 1)
    }

    @Test("Watch Later: a just-saved video missing from the response triggers one re-fetch (#157)")
    func watchLaterRecentSaveRetriesOnce() async throws {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Watch Later", videos: [makeVideo("wlvid_AAAA")])
        let membership = WatchLaterMembershipStore(
            defaults: try #require(UserDefaults(suiteName: "wl-\(UUID().uuidString)")))
        membership.markSaved("justsaved_YYYY")

        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section, watchLaterMembership: membership)
        await vm.updateAuthToken("fake-token")
        // updateAuthToken reloads the section; measure only the load below.
        await waitForTasks(timeout: 5, until: { vm.loadedAt != nil && !vm.isLoading })
        mock.calls.removeAll()
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(timeout: 5, until: { mock.calls.filter { $0.method == "fetchPlaylistVideos" }.count == 2 })

        #expect(mock.calls.filter { $0.method == "fetchPlaylistVideos" }.count == 2)
    }

    @Test("loadContent for .watchLater (signed out) requires auth without calling the API")
    func loadWatchLaterSignedOutRequiresAuth() async {
        let mock = MockInnerTubeAPI()
        // No auth token set.

        let section = BrowseSection(id: "watchLater", title: "Watch Later", type: .watchLater)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { vm.loadedAt != nil && !vm.isLoading })

        #expect(vm.isAuthRequired)
        #expect(!mock.calls.contains { $0.method == "fetchPlaylistVideos" })
    }
}
