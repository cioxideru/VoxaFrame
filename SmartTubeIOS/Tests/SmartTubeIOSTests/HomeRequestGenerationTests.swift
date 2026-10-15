import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Deliberately ignores cancellation so tests can release obsolete network results.
@MainActor
private final class HomeResponseGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?
    private(set) var started = false

    func value() async -> Value {
        started = true
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: Value) {
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Suite("Home request generations")
@MainActor
struct HomeRequestGenerationTests {
    @Test("An obsolete full load cannot finish a replacement refresh", arguments: [false, true])
    func obsoleteFullLoad(shortsPending: Bool) async {
        let mock = MockInnerTubeAPI()
        let oldHome = HomeResponseGate<[VideoGroup]>()
        let oldShorts = HomeResponseGate<VideoGroup>()
        let freshHome = HomeResponseGate<[VideoGroup]>()
        let freshShorts = HomeResponseGate<VideoGroup>()
        let initialHome = [VideoGroup(title: "Old", videos: [makeVideo("old")])]
        let initialShorts = VideoGroup(title: "Old", videos: [short("old-short")])
        mock.homeRowsHandler = { _ in await oldHome.value() }
        mock.shortsHandler = { await oldShorts.value() }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        let oldLoad = Task { await vm.refresh() }
        await waitForTasks { oldHome.started && oldShorts.started }
        if shortsPending {
            oldHome.resolve(initialHome)
            await waitForTasks { !vm.isLoadingAny }
        }

        mock.homeRowsHandler = { _ in await freshHome.value() }
        mock.shortsHandler = { await freshShorts.value() }
        let replacement = Task { await vm.refresh() }
        await waitForTasks { freshHome.started && freshShorts.started }
        let generation = vm.feedGeneration
        let feed = vm.mergedVideos
        oldHome.resolve(initialHome)
        oldShorts.resolve(initialShorts)
        await oldLoad.value

        #expect(vm.isRefreshing)
        #expect(vm.loadedAt == nil)
        #expect(vm.feedGeneration == generation)
        #expect(vm.mergedVideos == feed)
        #expect(vm.shortsVideos.isEmpty)

        freshHome.resolve([VideoGroup(title: "Fresh", videos: [makeVideo("fresh")])])
        freshShorts.resolve(VideoGroup(title: "Fresh", videos: [short("fresh-short")]))
        await replacement.value
        #expect(vm.mergedVideos.map(\.id) == ["fresh"])
        #expect(vm.shortsVideos.map(\.id) == ["fresh-short"])
        #expect(!vm.isRefreshing)
    }

    @Test("An old section page cannot replace fresh data, tokens or loading flags", arguments: [false, true])
    func obsoleteSectionPage(subscriptions: Bool) async throws {
        let mock = MockInnerTubeAPI()
        let oldPage = HomeResponseGate<VideoGroup>()
        let freshPage = HomeResponseGate<VideoGroup>()
        let old = VideoGroup(title: "Old", videos: [makeVideo("old")], nextPageToken: "old-token")
        let fresh = VideoGroup(title: "Fresh", videos: [makeVideo("fresh")], nextPageToken: "fresh-token")
        mock.homeRowsResult = [old]
        mock.subscriptionsResult = old
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        await vm.refresh()
        let sectionID =
            subscriptions ? BrowseSection.SectionType.subscriptions.rawValue : BrowseSection.SectionType.home.rawValue
        mock.homeRowsHandler = { token in token == nil ? [fresh] : [await oldPage.value()] }
        mock.subscriptionsHandler = { token in token == nil ? fresh : await oldPage.value() }
        let oldTask = try #require(vm.loadMore(sectionId: sectionID))
        await waitForTasks { oldPage.started }
        await vm.refresh()
        mock.homeRowsHandler = { _ in [await freshPage.value()] }
        mock.subscriptionsHandler = { _ in await freshPage.value() }
        let freshTask = try #require(vm.loadMore(sectionId: sectionID))
        await waitForTasks { freshPage.started }
        oldPage.resolve(VideoGroup(title: "Stale", videos: [makeVideo("stale")], nextPageToken: "stale-token"))
        await oldTask.value
        #expect(vm.sections.first { $0.id == sectionID }?.isLoadingMore == true)
        #expect(vm.sections.first { $0.id == sectionID }?.nextPageToken == "fresh-token")
        #expect(vm.mergedVideos.map(\.id) == ["fresh"])
        freshPage.resolve(VideoGroup(title: "Fresh page", videos: [makeVideo("fresh-page")], nextPageToken: "next"))
        await freshTask.value
        #expect(vm.mergedVideos.map(\.id) == ["fresh", "fresh-page"])
        #expect(vm.sections.first { $0.id == sectionID }?.nextPageToken == "next")
        #expect(vm.sections.first { $0.id == sectionID }?.isLoadingMore == false)
    }

    @Test("Obsolete automatic Shorts pages cannot publish or clear a new page's flag", arguments: [false, true])
    func obsoleteShortsPage(subscriptionFallback: Bool) async {
        let mock = MockInnerTubeAPI()
        let oldPage = HomeResponseGate<VideoGroup>()
        let freshPage = HomeResponseGate<VideoGroup>()
        mock.homeRowsResult = [VideoGroup(title: "Home", videos: [makeVideo("home")])]
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "search-old")
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [], nextPageToken: "subs-old")
        mock.shortsMoreAsyncHandler = { _ in
            if subscriptionFallback { return VideoGroup(title: "Empty", videos: []) }
            return await oldPage.value()
        }
        mock.subscriptionsHandler = { token in
            if token != nil { return await oldPage.value() }
            return mock.subscriptionsResult
        }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        let oldLoad = Task { await vm.refresh() }
        await waitForTasks { oldPage.started }
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "search-fresh")
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [], nextPageToken: "subs-fresh")
        mock.shortsMoreAsyncHandler = { _ in
            if subscriptionFallback { return VideoGroup(title: "Empty", videos: []) }
            return await freshPage.value()
        }
        mock.subscriptionsHandler = { token in
            if token != nil { return await freshPage.value() }
            return mock.subscriptionsResult
        }
        let freshLoad = Task { await vm.refresh() }
        await waitForTasks { freshPage.started }
        oldPage.resolve(
            VideoGroup(title: "Stale", videos: [short("stale"), makeVideo("stale-regular")], nextPageToken: "stale"))
        await oldLoad.value
        #expect(vm.isRefreshing)
        #expect(vm.homeShortsVideos.isEmpty)
        #expect(vm.mergedVideos.map(\.id) == ["home"])
        if subscriptionFallback {
            #expect(vm.sections.first { $0.section.type == .subscriptions }?.isLoadingMore == true)
            #expect(vm.sections.first { $0.section.type == .subscriptions }?.nextPageToken == "subs-fresh")
        }
        let callsBeforeDemand = mock.calls.count
        vm.loadShorts(atLeast: 1)
        #expect(mock.calls.count == callsBeforeDemand)
        freshPage.resolve(VideoGroup(title: "Fresh", videos: [short("fresh-short")]))
        await freshLoad.value
        #expect(vm.homeShortsVideos.map(\.id) == ["fresh-short"])
        #expect(!vm.isRefreshing)
    }

    @Test("A larger Shorts target arriving during a page is retained")
    func increasingShortsDemand() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Home", videos: [makeVideo("home")])]
        mock.shortsResult = VideoGroup(
            title: "Shorts", videos: (0..<8).map { short("initial-\($0)") }, nextPageToken: "page-1")
        let firstPage = HomeResponseGate<VideoGroup>()
        mock.shortsMoreAsyncHandler = { token in
            if token == "page-1" { return await firstPage.value() }
            return VideoGroup(title: "More", videos: (10..<16).map { short("short-\($0)") })
        }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        await vm.refresh()
        vm.loadShorts(atLeast: 10)
        await waitForTasks { firstPage.started }
        vm.loadShorts(atLeast: 16)
        vm.loadShorts(atLeast: 11)
        firstPage.resolve(
            VideoGroup(title: "More", videos: [short("short-8"), short("short-9")], nextPageToken: "page-2"))
        await waitForTasks { vm.homeShortsVideos.count == 16 }
        #expect(mock.calls.filter { $0.method == "fetchShortsMore" }.map(\.args) == [["page-1"], ["page-2"]])
    }

    @Test("Outstanding Shorts demand resumes after ordinary subscriptions paging", arguments: [false, true])
    func subscriptionsPagingResumesDemand(searchFinishesWhileBusy: Bool) async throws {
        let mock = MockInnerTubeAPI()
        let subscriptionsPage = HomeResponseGate<VideoGroup>()
        let searchPage = HomeResponseGate<VideoGroup>()
        mock.homeRowsResult = [VideoGroup(title: "Home", videos: [makeVideo("home")])]
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [], nextPageToken: "subs-1")
        mock.shortsResult = VideoGroup(
            title: "Shorts", videos: (0..<8).map { short("initial-\($0)") },
            nextPageToken: searchFinishesWhileBusy ? "search-1" : nil)
        mock.shortsMoreAsyncHandler = { _ in await searchPage.value() }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        await vm.refresh()
        mock.subscriptionsHandler = { token in
            if token == "subs-1" { return await subscriptionsPage.value() }
            return VideoGroup(title: "More", videos: [short("from-subs")])
        }
        let pageTask = try #require(vm.loadMore(sectionId: BrowseSection.SectionType.subscriptions.rawValue))
        await waitForTasks { subscriptionsPage.started }
        vm.loadShorts(atLeast: searchFinishesWhileBusy ? 10 : 9)
        if searchFinishesWhileBusy {
            await waitForTasks { searchPage.started }
            searchPage.resolve(VideoGroup(title: "Last search", videos: [short("from-search")]))
            await waitForTasks { vm.homeShortsVideos.count == 9 }
        }
        subscriptionsPage.resolve(
            VideoGroup(title: "Regular only", videos: [makeVideo("regular-page")], nextPageToken: "subs-2"))
        await pageTask.value
        await waitForTasks { vm.homeShortsVideos.contains { $0.id == "from-subs" } }
        #expect(
            mock.calls.filter { $0.method == "fetchSubscriptions" }.map(\.args) == [["nil"], ["subs-1"], ["subs-2"]])
        #expect(vm.homeRegularVideos.contains { $0.id == "regular-page" })
    }

    @Test("Empty advancing pages preserve demand and a repeated empty token stops it")
    func emptyShortsPages() async {
        let mock = MockInnerTubeAPI()
        mock.homeRowsResult = [VideoGroup(title: "Home", videos: [makeVideo("home")])]
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "empty-1")
        mock.shortsMoreHandler = { token in
            VideoGroup(title: "Empty", videos: [], nextPageToken: token == "empty-1" ? "empty-2" : token)
        }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        await vm.refresh()
        #expect(mock.calls.filter { $0.method == "fetchShortsMore" }.map(\.args) == [["empty-1"], ["empty-2"]])
        #expect(vm.homeShortsVideos.isEmpty)
        #expect(!vm.isRefreshing)
    }

    #if DEBUG
    @Test("The UI fixture exposes new Shorts only through two distinct continuations")
    func uiFixtureRequiresContinuations() throws {
        let initial = HomePaginationUITestFixture.shortsPage(continuationToken: nil)
        #expect(initial.videos.count == 10)
        let firstToken = try #require(initial.nextPageToken)
        let first = HomePaginationUITestFixture.shortsPage(continuationToken: firstToken)
        let secondToken = try #require(first.nextPageToken)
        let second = HomePaginationUITestFixture.shortsPage(continuationToken: secondToken)
        #expect(Set((initial.videos + first.videos + second.videos).map(\.id)).count == 30)
        #expect(first.videos.first?.id == "page-1-short-0")
        #expect(second.videos.first?.id == "page-2-short-0")
        #expect(second.nextPageToken == nil)
        for subscriptions in [false, true] {
            let regular = HomePaginationUITestFixture.regularPage(subscriptions: subscriptions, continuationToken: nil)
            #expect(regular.nextPageToken == nil)
            #expect(regular.videos.allSatisfy { !$0.isShort })
        }
    }
    #endif

    private func short(_ id: String) -> Video {
        Video(id: id, title: id, channelTitle: "Channel", isShort: true)
    }
}
