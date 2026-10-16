import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - MockInnerTubeAPI
//
// Synchronous, controllable stand-in for InnerTubeAPI.
// Set `*Result` properties to control what each fetch returns.
// All calls record themselves in `calls` for assertion.

@MainActor
final class MockInnerTubeAPI: InnerTubeAPIProtocol {

    // MARK: - Call recorder

    struct Call: Equatable {
        let method: String
        let args: [String]
    }
    var calls: [Call] = []

    // MARK: - Configurable return values

    var authTokenHandler: (@MainActor (String?) async -> Void)?
    var homeRowsHandler: (@MainActor (String?) async -> [VideoGroup])?
    var subscriptionsHandler: (@MainActor (String?) async -> VideoGroup)?
    var shortsHandler: (@MainActor () async -> VideoGroup)?
    var shortsMoreAsyncHandler: (@MainActor (String) async throws -> VideoGroup)?
    var homeResult: VideoGroup = VideoGroup(title: "Home", videos: [])
    var homeRowsResult: [VideoGroup] = []
    var subscriptionsResult: VideoGroup = VideoGroup(title: "Subs", videos: [])
    var historyHandler: (@MainActor (String?) async -> VideoGroup)?
    var historyResult: VideoGroup = VideoGroup(title: "History", videos: [])
    var shortsResult: VideoGroup = VideoGroup(title: "Shorts", videos: [])
    var shortsMoreResult: VideoGroup = VideoGroup(title: "Shorts", videos: [])
    /// When set, overrides `shortsMoreResult` and is called for each
    /// `fetchShortsMore` invocation — lets tests vary the response per call
    /// (e.g. to simulate a multi-page continuation sequence).
    var shortsMoreHandler: ((String) -> VideoGroup)? = nil
    var musicResult: VideoGroup = VideoGroup(title: "Music", videos: [])
    var gamingResult: VideoGroup = VideoGroup(title: "Gaming", videos: [])
    var newsResult: VideoGroup = VideoGroup(title: "News", videos: [])
    var liveResult: VideoGroup = VideoGroup(title: "Live", videos: [])
    var sportsResult: VideoGroup = VideoGroup(title: "Sports", videos: [])
    var playlistsResult: [PlaylistInfo] = []
    var channelsResult: [Channel] = []
    var channelThumbnailResult: URL? = nil
    var channelResult: (channel: Channel, videos: VideoGroup) = (
        Channel(id: "ch1", title: "Channel"), VideoGroup(title: "Ch", videos: [])
    )
    var channelVideosResult: VideoGroup = VideoGroup(title: "ChVideos", videos: [])
    var searchResult: VideoGroup = VideoGroup(title: "Search", videos: [])
    var suggestionsResult: [String] = []
    var playlistVideosResult: VideoGroup = VideoGroup(title: "Playlist", videos: [])
    var errorToThrow: Error? = nil

    // MARK: - Protocol conformance

    func setAuthToken(_ token: String?) async {
        calls.append(Call(method: "setAuthToken", args: [token ?? "nil"]))
        await authTokenHandler?(token)
    }

    func setSAPISID(_ value: String?) async {
        calls.append(Call(method: "setSAPISID", args: [value ?? "nil"]))
    }

    func fetchHome(continuationToken: String?) async throws -> VideoGroup {
        calls.append(Call(method: "fetchHome", args: [continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        return homeResult
    }

    func fetchHomeRows(continuationToken: String?) async throws -> [VideoGroup] {
        calls.append(Call(method: "fetchHomeRows", args: [continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        if let homeRowsHandler { return await homeRowsHandler(continuationToken) }
        return homeRowsResult
    }

    func fetchSubscriptions(continuationToken: String?) async throws -> VideoGroup {
        calls.append(Call(method: "fetchSubscriptions", args: [continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        if let subscriptionsHandler { return await subscriptionsHandler(continuationToken) }
        return subscriptionsResult
    }

    func fetchHistory(continuationToken: String?) async throws -> VideoGroup {
        calls.append(Call(method: "fetchHistory", args: [continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        if let historyHandler { return await historyHandler(continuationToken) }
        return historyResult
    }

    func fetchShorts() async throws -> VideoGroup {
        calls.append(Call(method: "fetchShorts", args: []))
        if let error = errorToThrow { throw error }
        if let shortsHandler { return await shortsHandler() }
        return shortsResult
    }

    func fetchShortsMore(continuationToken: String) async throws -> VideoGroup {
        calls.append(Call(method: "fetchShortsMore", args: [continuationToken]))
        if let error = errorToThrow { throw error }
        if let shortsMoreAsyncHandler { return try await shortsMoreAsyncHandler(continuationToken) }
        if let handler = shortsMoreHandler { return handler(continuationToken) }
        return shortsMoreResult
    }

    func fetchMusic() async throws -> VideoGroup {
        calls.append(Call(method: "fetchMusic", args: []))
        if let error = errorToThrow { throw error }
        return musicResult
    }

    func fetchGaming() async throws -> VideoGroup {
        calls.append(Call(method: "fetchGaming", args: []))
        if let error = errorToThrow { throw error }
        return gamingResult
    }

    func fetchNews() async throws -> VideoGroup {
        calls.append(Call(method: "fetchNews", args: []))
        if let error = errorToThrow { throw error }
        return newsResult
    }

    func fetchLive() async throws -> VideoGroup {
        calls.append(Call(method: "fetchLive", args: []))
        if let error = errorToThrow { throw error }
        return liveResult
    }

    func fetchSports() async throws -> VideoGroup {
        calls.append(Call(method: "fetchSports", args: []))
        if let error = errorToThrow { throw error }
        return sportsResult
    }

    func fetchUserPlaylists() async throws -> [PlaylistInfo] {
        calls.append(Call(method: "fetchUserPlaylists", args: []))
        if let error = errorToThrow { throw error }
        return playlistsResult
    }

    func fetchSubscribedChannels() async throws -> [Channel] {
        calls.append(Call(method: "fetchSubscribedChannels", args: []))
        if let error = errorToThrow { throw error }
        return channelsResult
    }

    func fetchChannelThumbnailURL(channelId: String) async throws -> URL? {
        calls.append(Call(method: "fetchChannelThumbnailURL", args: [channelId]))
        return channelThumbnailResult
    }

    func fetchChannel(channelId: String) async throws -> (channel: Channel, videos: VideoGroup) {
        calls.append(Call(method: "fetchChannel", args: [channelId]))
        if let error = errorToThrow { throw error }
        return channelResult
    }

    func fetchChannelVideos(channelId: String, continuationToken: String?) async throws -> VideoGroup {
        calls.append(Call(method: "fetchChannelVideos", args: [channelId, continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        return channelVideosResult
    }

    func search(query: String, continuationToken: String?, filter: SearchFilter) async throws -> VideoGroup {
        calls.append(Call(method: "search", args: [query, continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        return searchResult
    }

    func fetchSearchSuggestions(query: String) async throws -> [String] {
        calls.append(Call(method: "fetchSearchSuggestions", args: [query]))
        if let error = errorToThrow { throw error }
        return suggestionsResult
    }

    func fetchPlaylistVideos(playlistId: String, continuationToken: String?) async throws -> VideoGroup {
        calls.append(Call(method: "fetchPlaylistVideos", args: [playlistId, continuationToken ?? "nil"]))
        if let error = errorToThrow { throw error }
        return playlistVideosResult
    }

    // Keep the async protocol witness signature. swiftlint:disable:next async_without_await
    func addToWatchLater(videoId: String) async throws -> String? {
        calls.append(Call(method: "addToWatchLater", args: [videoId]))
        if let error = errorToThrow { throw error }
        return nil
    }

    // Keep the async protocol witness signature. swiftlint:disable:next async_without_await
    func removeFromWatchLater(setVideoId: String) async throws {
        calls.append(Call(method: "removeFromWatchLater", args: [setVideoId]))
        if let error = errorToThrow { throw error }
    }

    // Keep the async protocol witness signature. swiftlint:disable:next async_without_await
    func addToPlaylist(playlistId: String, videoId: String) async throws {
        calls.append(Call(method: "addToPlaylist", args: [playlistId, videoId]))
        if let error = errorToThrow { throw error }
    }

    // Keep the async protocol witness signature. swiftlint:disable:next async_without_await
    func removeFromPlaylist(playlistId: String, setVideoId: String) async throws {
        calls.append(Call(method: "removeFromPlaylist", args: [playlistId, setVideoId]))
        if let error = errorToThrow { throw error }
    }

    func sendFeedback(token: String) async throws {
        calls.append(Call(method: "sendFeedback", args: [token]))
        if let error = errorToThrow { throw error }
    }

    func sendFeedbackForVideo(videoId: String, iconType: String) async throws {
        calls.append(Call(method: "sendFeedbackForVideo", args: [videoId, iconType]))
        if let error = errorToThrow { throw error }
    }
}

// MARK: - Helpers

/// Polls an explicit completion condition; elapsed time or idle yields do not prove completion.
@MainActor
func waitForTasks(
    timeout: TimeInterval = 2,
    until condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for the expected ViewModel state", sourceLocation: sourceLocation)
            return
        }
        await Task.yield()
    }
}

func makeVideo(_ id: String) -> Video {
    Video(id: id, title: "Video \(id)", channelTitle: "Channel")
}

/// Creates a `SearchViewModel` backed by a uniquely-suited `SearchHistoryStore`
/// instead of `.shared`, so tests don't read/write the same `UserDefaults`
/// search-history entries across the suite.
@MainActor
private func makeSearchViewModel(api: any InnerTubeAPIProtocol) -> SearchViewModel {
    SearchViewModel(api: api, historyStore: SearchHistoryStore(suiteName: "test-\(UUID().uuidString)"))
}

// MARK: - HomeViewModelTests

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {

    @Test("load() calls fetchHomeRows and fetchSubscriptions")
    func loadCallsBothFetches() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_0000001")])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [makeVideo("vid_0000002")])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: {
            let methods = mock.calls.map(\.method)
            return methods.contains("fetchHomeRows") && methods.contains("fetchSubscriptions")
        })

        let methods = mock.calls.map(\.method)
        #expect(methods.contains("fetchHomeRows"))
        #expect(methods.contains("fetchSubscriptions"))
    }

    @Test("After load() completes, isRefreshing is false")
    func loadResetsIsRefreshing() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_0000001")])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        #expect(!vm.isRefreshing)
    }

    @Test("Home section is populated with videos from fetchHomeRows")
    func homeSectionPopulated() async {
        let mock = MockInnerTubeAPI()
        let video = makeVideo("vid_0000001")
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [video])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: {
            vm.sections.first { $0.section.type == .home }?.videos.isEmpty == false
        })

        let homeState = vm.sections.first { $0.section.type == .home }
        #expect(homeState?.videos.isEmpty == false)
    }

    @Test("mergedVideos interleaves rec and sub videos")
    func mergedVideosInterleaves() async {
        let mock = MockInnerTubeAPI()
        let recVideos = (0..<8).map { makeVideo("rec\($0)_AAAAAA") }
        let subVideos = (0..<4).map { makeVideo("sub\($0)_BBBBBB") }
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: recVideos)]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: subVideos)

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        // mergedVideos inserts 1 sub every 4 recs; total should be > 8
        #expect(vm.mergedVideos.count > 8)
        // Subscription videos should appear in merged list
        let ids = Set(vm.mergedVideos.map(\.id))
        #expect(ids.contains("sub0_BBBBBB"))
    }

    @Test("mergedVideos with empty subs returns only recs")
    func mergedVideosEmptySubsReturnsRecs() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_AAAAAAA")])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        let recs = vm.sections.first { $0.section.type == .home }?.videos ?? []
        #expect(vm.mergedVideos == recs)
    }

    @Test("homeRegularVideos excludes Shorts and homeShortsVideos contains only Shorts")
    func homePartitionsShorts() async {
        let mock = MockInnerTubeAPI()
        let regularVideo = makeVideo("reg0_AAAA")
        let shortVideo = Video(id: "srt0_BBBB", title: "A Short", channelTitle: "Channel", isShort: true)
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [regularVideo, shortVideo])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        #expect(vm.homeRegularVideos.allSatisfy { !$0.isShort })
        #expect(vm.homeShortsVideos.allSatisfy { $0.isShort })
        #expect(vm.homeRegularVideos.map(\.id).contains("reg0_AAAA"))
        #expect(vm.homeShortsVideos.map(\.id).contains("srt0_BBBB"))
    }

    @Test("loadMoreShortsIfNeeded auto-fetches next page when shorts < 6")
    func loadMoreShortsAutoFetchWhenBelowThreshold() async {
        let mock = MockInnerTubeAPI()
        // Initial page: 3 shorts with a continuation token
        let initialShorts = (0..<3).map {
            Video(id: "srt\($0)_AAAAA", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        mock.shortsResult = VideoGroup(title: "Shorts", videos: initialShorts, nextPageToken: "tok_page2")
        // Next page: 4 more shorts
        let moreShorts = (10..<14).map {
            Video(id: "srt\($0)_BBBBB", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        mock.shortsMoreResult = VideoGroup(title: "Shorts", videos: moreShorts, nextPageToken: nil)
        mock.homeRowsResult = []
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        // fetchShortsMore must have been called
        #expect(mock.calls.contains(where: { $0.method == "fetchShortsMore" }))
        // shortsVideos should contain both pages (3 initial + 4 more = 7)
        #expect(vm.shortsVideos.count == 7)
    }

    @Test("loadMoreShortsIfNeeded skips auto-fetch when no continuation token")
    func loadMoreShortsSkipsWithNoToken() async {
        let mock = MockInnerTubeAPI()
        // Initial page: 2 shorts, no continuation token
        let initialShorts = (0..<2).map {
            Video(id: "srt\($0)_DDDDD", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        mock.shortsResult = VideoGroup(title: "Shorts", videos: initialShorts, nextPageToken: nil)
        mock.homeRowsResult = []
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        // fetchShortsMore must NOT have been called
        #expect(!mock.calls.contains(where: { $0.method == "fetchShortsMore" }))
        #expect(vm.shortsVideos.count == 2)
    }

    @Test("loadMoreShortsIfNeeded deduplicates videos from next page")
    func loadMoreShortsDeduplicates() async {
        let mock = MockInnerTubeAPI()
        let initialShorts = (0..<3).map {
            Video(id: "srt\($0)_EEEEE", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        // Next page contains 2 new + 1 duplicate from first page
        let moreShorts = [
            Video(id: "srt0_EEEEE", title: "Dup", channelTitle: "Ch", isShort: true),
            Video(id: "srt10_FFFFF", title: "New1", channelTitle: "Ch", isShort: true),
            Video(id: "srt11_FFFFF", title: "New2", channelTitle: "Ch", isShort: true),
        ]
        mock.shortsResult = VideoGroup(title: "Shorts", videos: initialShorts, nextPageToken: "tok_dup")
        mock.shortsMoreResult = VideoGroup(title: "Shorts", videos: moreShorts, nextPageToken: nil)
        mock.homeRowsResult = []
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { vm.shortsVideos.count >= 5 })

        // 3 initial + 2 new (duplicate filtered out) = 5
        #expect(vm.shortsVideos.count == 5)
        let ids = Set(vm.shortsVideos.map(\.id))
        #expect(!ids.contains("srt0_EEEEE") == false)  // original kept
        #expect(ids.contains("srt10_FFFFF"))
        #expect(ids.contains("srt11_FFFFF"))
    }

    @Test("loadShorts(atLeast:) loops fetching pages until homeShortsVideos reaches the target")
    func loadShortsLoopsUntilTarget() async {
        let mock = MockInnerTubeAPI()
        let initialShorts = (0..<3).map {
            Video(id: "srt\($0)_AAAAA", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        mock.shortsResult = VideoGroup(title: "Shorts", videos: initialShorts, nextPageToken: "tok_0")
        mock.homeRowsResult = []
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        // Each call returns 5 fresh shorts plus a continuation token, so the
        // loop must run several iterations to cross the 40-item target.
        var callCount = 0
        mock.shortsMoreHandler = { _ in
            callCount += 1
            let page = (0..<5).map { i in
                Video(
                    id: "more\(callCount)_\(i)_GGGGG", title: "More \(callCount)-\(i)", channelTitle: "Ch",
                    isShort: true)
            }
            return VideoGroup(title: "Shorts", videos: page, nextPageToken: "tok_\(callCount)")
        }

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })
        vm.loadShorts(atLeast: 40)
        await waitForTasks(until: { vm.homeShortsVideos.count >= 40 })

        // 3 initial + repeated pages of 5 must reach the 40-item target.
        #expect(vm.homeShortsVideos.count >= 40)
        // Reaching 40 from 3 (+5/page) requires looping across multiple pages,
        // not just the single page loadMoreShortsIfNeeded fetches for its
        // own (lower) threshold.
        let shortsMoreCallCount = mock.calls.filter { $0.method == "fetchShortsMore" }.count
        #expect(shortsMoreCallCount >= 7)
    }

    @Test("loadShorts(atLeast:) stops immediately when no continuation tokens remain")
    func loadShortsStopsWithNoTokens() async {
        let mock = MockInnerTubeAPI()
        let initialShorts = (0..<2).map {
            Video(id: "srt\($0)_HHHHH", title: "Short \($0)", channelTitle: "Ch", isShort: true)
        }
        // No continuation token from the initial fetch, and no subs section
        // continuation either — both sources are exhausted from the start.
        mock.shortsResult = VideoGroup(title: "Shorts", videos: initialShorts, nextPageToken: nil)
        mock.homeRowsResult = []
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing && vm.homeShortsVideos == initialShorts })
        vm.loadShorts(atLeast: 40)

        // Below the 40-item target, but with no tokens left it must not call
        // fetchShortsMore at all.
        #expect(vm.homeShortsVideos.count == 2)
        #expect(!mock.calls.contains(where: { $0.method == "fetchShortsMore" }))
    }

    @Test("refresh() keeps the current feed on screen until the new one arrives")
    func refreshKeepsContent() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_0000001")])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [makeVideo("vid_0000002")])

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })
        let generation = vm.feedGeneration

        let refresh = Task { await vm.refresh() }
        var sawEmptyFeed = false
        await waitForTasks(until: {
            sawEmptyFeed = sawEmptyFeed || vm.mergedVideos.isEmpty
            return vm.feedGeneration > generation && !vm.isRefreshing
        })
        await refresh.value
        #expect(!sawEmptyFeed)

        #expect(!vm.isRefreshing)
        #expect(vm.feedGeneration > generation)
        #expect(Set(vm.mergedVideos.map(\.id)) == ["vid_0000001", "vid_0000002"])
    }

    @Test("A subscriptions page fetched for Shorts also adds its regular videos to the feed")
    func shortsSubsPageFeedsRegularVideos() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Rec", videos: [makeVideo("vid_0000001")])]
        mock.subscriptionsResult = VideoGroup(
            title: "Subs", videos: [makeVideo("vid_0000002")], nextPageToken: "subs_tok")

        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        vm.load()
        await waitForTasks(until: { !vm.isRefreshing })

        // Duplicate IDs within the page and against both initial shelves must stay unique.
        mock.subscriptionsResult = VideoGroup(
            title: "Subs",
            videos: [
                makeVideo("vid_0000003"),
                makeVideo("vid_0000003"),
                makeVideo("vid_0000001"),
                makeVideo("vid_0000002"),
                Video(id: "srt_0000004", title: "Short", channelTitle: "Ch", isShort: true),
            ])
        vm.loadShorts(atLeast: 10)
        await waitForTasks(until: { vm.homeShortsVideos.contains { $0.id == "srt_0000004" } })

        #expect(vm.homeRegularVideos.map(\.id) == ["vid_0000001", "vid_0000002", "vid_0000003"])
        let subscriptionIDs = vm.sections.first { $0.section.type == .subscriptions }?.videos.map(\.id) ?? []
        #expect(subscriptionIDs == ["vid_0000002", "vid_0000003", "vid_0000001", "srt_0000004"])
        #expect(Set(vm.mergedVideos.map(\.id)).count == vm.mergedVideos.count)
    }
}

// MARK: - SearchViewModelTests

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {

    @Test("search() with non-empty query populates results")
    func searchPopulatesResults() async {
        let mock = MockInnerTubeAPI()
        mock.searchResult = VideoGroup(title: "Results", videos: [makeVideo("result_AAAAA")])

        let vm = makeSearchViewModel(api: mock)
        vm.query = "swift programming"
        vm.search()
        await waitForTasks(until: { !vm.isLoading && mock.calls.contains { $0.method == "search" } })

        #expect(!vm.results.isEmpty)
        #expect(vm.results[0].id == "result_AAAAA")
    }

    @Test("search() with whitespace-only query is a no-op")
    func searchWithWhitespaceOnlyIsNoOp() {
        let mock = MockInnerTubeAPI()
        mock.searchResult = VideoGroup(title: "Results", videos: [makeVideo("result_AAAAA")])

        let vm = makeSearchViewModel(api: mock)
        vm.query = "   "
        vm.search()

        #expect(vm.results.isEmpty)
        #expect(!mock.calls.contains { $0.method == "search" })
    }

    @Test("loadMore() with nextPageToken appends results")
    func loadMoreAppendsResults() async {
        let mock = MockInnerTubeAPI()
        let page1 = VideoGroup(title: "R", videos: [makeVideo("p1_0000001")], nextPageToken: "token123")
        let page2 = VideoGroup(title: "R", videos: [makeVideo("p2_0000002")])
        mock.searchResult = page1

        let vm = makeSearchViewModel(api: mock)
        vm.query = "test"
        vm.search()
        await waitForTasks(until: { !vm.isLoading && mock.calls.contains { $0.method == "search" } })

        // Now set up page 2 and trigger loadMore
        mock.searchResult = page2
        vm.loadMore()
        await waitForTasks(until: { !vm.isLoading && vm.results.count == 2 })

        #expect(vm.results.count == 2)
        let ids = vm.results.map(\.id)
        #expect(ids.contains("p1_0000001"))
        #expect(ids.contains("p2_0000002"))
    }

    @Test("isLoading is false after search completes")
    func isLoadingFalseAfterSearch() async {
        let mock = MockInnerTubeAPI()
        mock.searchResult = VideoGroup(title: "R", videos: [])

        let vm = makeSearchViewModel(api: mock)
        vm.query = "query"
        vm.search()
        await waitForTasks(until: { !vm.isLoading && mock.calls.contains { $0.method == "search" } })

        #expect(!vm.isLoading)
    }

    @Test("applyFilter reruns search with new filter")
    func applyFilterReruns() async {
        let mock = MockInnerTubeAPI()
        mock.searchResult = VideoGroup(title: "R", videos: [makeVideo("vid_AAAAAAA")])

        let vm = makeSearchViewModel(api: mock)
        vm.query = "swift"
        vm.search()
        await waitForTasks(until: { !vm.isLoading && mock.calls.contains { $0.method == "search" } })

        let beforeCount = mock.calls.filter { $0.method == "search" }.count
        var filter = SearchFilter()
        filter.sortOrder = .viewCount
        vm.applyFilter(filter)
        await waitForTasks(until: {
            !vm.isLoading && mock.calls.filter { $0.method == "search" }.count > beforeCount
        })

        let afterCount = mock.calls.filter { $0.method == "search" }.count
        #expect(afterCount > beforeCount)
    }
}

// MARK: - PlaylistViewModelTests

@Suite("PlaylistViewModel")
@MainActor
struct PlaylistViewModelTests {

    @Test("load() fetches playlist videos and populates videos array")
    func loadPopulatesVideos() async {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(
            title: "PL",
            videos: [
                makeVideo("plvid_AAAAA"),
                makeVideo("plvid_BBBBB"),
            ])

        let vm = PlaylistViewModel(api: mock)
        vm.load(playlistId: "PLtest1234567")
        await waitForTasks(until: { vm.videos.count == 2 })

        #expect(vm.videos.count == 2)
        #expect(mock.calls.contains { $0.method == "fetchPlaylistVideos" })
    }

    @Test("load() tags each video with playlistId")
    func loadTagsVideosWithPlaylistId() async {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "PL", videos: [makeVideo("vid_AAAAAAA")])

        let vm = PlaylistViewModel(api: mock)
        vm.load(playlistId: "PLtest1234567")
        await waitForTasks(until: { vm.videos.first != nil })

        #expect(vm.videos.first?.playlistId == "PLtest1234567")
    }

    @Test("load(refresh: true) clears videos and reloads")
    func loadRefreshClearsAndReloads() async {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "PL", videos: [makeVideo("vid_AAAAAAA")])

        let vm = PlaylistViewModel(api: mock)
        vm.load(playlistId: "PLtest1234567")
        await waitForTasks(until: { !vm.isLoading && vm.videos.count == 1 })

        // Refresh — should clear and re-fetch
        mock.playlistVideosResult = VideoGroup(title: "PL", videos: [makeVideo("vid_BBBBBBB")])
        vm.load(playlistId: "PLtest1234567", refresh: true)
        await waitForTasks(until: { !vm.isLoading && vm.videos.first?.id == "vid_BBBBBBB" })

        #expect(vm.videos.count == 1)
        #expect(vm.videos[0].id == "vid_BBBBBBB")
    }

    @Test("loadMoreIfNeeded appends next page when on last video")
    func loadMoreAppendsNextPage() async {
        let mock = MockInnerTubeAPI()
        let page1Video = makeVideo("page1_AAAAA")
        mock.playlistVideosResult = VideoGroup(
            title: "PL", videos: [page1Video], nextPageToken: "token_page2"
        )

        let vm = PlaylistViewModel(api: mock)
        vm.load(playlistId: "PLtest1234567")
        await waitForTasks(until: { !vm.isLoading && vm.videos.count == 1 })

        // Set up page 2
        mock.playlistVideosResult = VideoGroup(title: "PL", videos: [makeVideo("page2_BBBBB")])
        vm.loadMoreIfNeeded(lastVideo: page1Video)
        await waitForTasks(until: { !vm.isLoading && vm.videos.count == 2 })

        #expect(vm.videos.count == 2)
    }

    @Test("isLoading is false after fetch completes")
    func isLoadingFalseAfterFetch() async {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "PL", videos: [])

        let vm = PlaylistViewModel(api: mock)
        vm.load(playlistId: "PLtest1234567")
        await waitForTasks(until: { !vm.isLoading && !mock.calls.isEmpty })

        #expect(!vm.isLoading)
    }
}
