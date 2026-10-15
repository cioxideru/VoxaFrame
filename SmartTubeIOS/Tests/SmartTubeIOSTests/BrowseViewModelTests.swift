import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - BrowseViewModelTests

@Suite("BrowseViewModel")
@MainActor
struct BrowseViewModelTests {

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

    @Test("Home load hands its videos to onHomeLoaded (#353 widget)")
    func homeLoadNotifiesWidgetHook() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_0000001"), makeVideo("vid_0000002")])]
        let section = BrowseSection(id: "home", title: "Home", type: .home)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        var received: [String]?
        vm.onHomeLoaded = { received = $0.map(\.id) }
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { received != nil })
        #expect(received == ["vid_0000001", "vid_0000002"])
    }

    @Test("signed-out Home gives onHomeLoaded nothing, not the popular-search fallback (#353)")
    func signedOutHomeGivesWidgetNothing() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = []
        mock.searchResult = VideoGroup(title: "Search", videos: [makeVideo("popular_001")])
        let section = BrowseSection(id: "home", title: "Home", type: .home)
        let vm = BrowseViewModel(api: mock, initialSection: section)
        var received: [String]?
        vm.onHomeLoaded = { received = $0.map(\.id) }
        vm.loadContent(for: section, refresh: true, source: "test")
        await waitForTasks(until: { received != nil })
        #expect(vm.isAuthRequired)
        #expect(received == [])
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
        await waitForTasks()

        // Local path never gates on auth — empty means "no follows yet", not "sign in"
        #expect(!vm.isAuthRequired)
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
        await waitForTasks()

        // videoGroups must be [] (not [VideoGroup(videos: [])]) so the Home
        // Shorts chip's empty state ("Nothing here yet") can render — a
        // 1-element array with no videos is indistinguishable from "has content"
        // to sectionFeed's videoGroups.isEmpty check.
        #expect(vm.videoGroups.isEmpty)
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
        await waitForTasks()  // updateAuthToken reloads the section; measure only the load below
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
        await waitForTasks()  // updateAuthToken reloads the section; measure only the load below
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
        await waitForTasks()

        #expect(vm.isAuthRequired)
        #expect(!mock.calls.contains { $0.method == "fetchPlaylistVideos" })
    }
}
