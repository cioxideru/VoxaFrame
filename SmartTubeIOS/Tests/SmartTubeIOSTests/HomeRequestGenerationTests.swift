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
    @Test("Signed-in Home reuses account shelves and never requests discovery Shorts", arguments: [false, true])
    func accountShortsReuseShelves(homeEmpty: Bool) async {
        let api = MockInnerTubeAPI()
        let regular = (0..<30).map { makeVideo("regular-\($0)") }
        api.homeRowsResult = homeEmpty ? [] : [VideoGroup(videos: regular + [short("recommended-short")])]
        api.searchResult = VideoGroup(videos: [short("global-popular-short")])
        api.subscriptionsResult = VideoGroup(videos: regular + [short("subscribed-short")])
        api.shortsResult = VideoGroup(videos: [short("global-search-short")])
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.updateAuthToken("account", sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        #expect(home.homeShortsVideos.map(\.id) == (homeEmpty ? [] : ["recommended-short"]) + ["subscribed-short"])
        #expect(api.calls.filter { $0.method == "fetchSubscriptions" }.count == 1)
        #expect(!api.calls.contains { $0.method == "fetchShorts" })
        await home.updateAuthToken(nil, sessionID: 2)
        #expect(home.homeShortsVideos.isEmpty)
    }

    @Test("Shorts demand scans a bounded batch and resumes only on another request")
    func boundsMixedAccountPages() async {
        let api = MockInnerTubeAPI()
        api.homeRowsResult = [VideoGroup(videos: [makeVideo("home")])]
        api.subscriptionsResult = VideoGroup(videos: [makeVideo("initial")], nextPageToken: "1")
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.updateAuthToken("account", sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        var pages = 0
        api.subscriptionsHandler = { _ in
            pages += 1
            return VideoGroup(videos: [makeVideo("page-\(pages)")], nextPageToken: String(pages + 1))
        }
        home.loadShorts(atLeast: 30)
        await waitForTasks {
            pages >= InnerTubeClients.maxShortsPagesPerRequest
                && !home.sections.contains(where: \.isLoadingMore)
        }
        #expect(pages == InnerTubeClients.maxShortsPagesPerRequest)
        #expect(home.homeShortsVideos.isEmpty)
        // Subscription pages fetched for Shorts never add their regular videos to Home.
        #expect(home.mergedVideos.map(\.id) == ["home"])
        home.loadShorts(atLeast: 40)
        await waitForTasks {
            pages >= 2 * InnerTubeClients.maxShortsPagesPerRequest
                && !home.sections.contains(where: \.isLoadingMore)
        }
        #expect(pages == 2 * InnerTubeClients.maxShortsPagesPerRequest)
    }

    @Test("Foreground refresh waits for auth preparation and does not duplicate the initial load")
    func foregroundDuringAuthPreparation() async {
        let api = MockInnerTubeAPI()
        let gate = HomeResponseGate<Void>()
        api.authTokenHandler = { _ in await gate.value() }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        let authentication = Task { await home.updateAuthToken("ready", signedIn: true, sessionID: 1) }
        await waitForTasks { gate.started }
        home.refreshIfStale()
        #expect(!api.calls.contains { $0.method == "fetchHomeRows" })
        gate.resolve(())
        await authentication.value
        await waitForTasks { home.loadedAt != nil }
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
    }

    @Test("An expired token waits for refresh, then loads Home only once")
    func expiredTokenStartup() async {
        let api = MockInnerTubeAPI()
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.updateAuthToken(nil, signedIn: true, sessionID: 1)
        home.refreshIfStale()
        #expect(!api.calls.contains { $0.method == "fetchHomeRows" })
        await home.updateAuthToken("ready", signedIn: true, sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        await home.updateAuthToken("rotated", signedIn: true, sessionID: 1)
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
    }

    @Test("One composed Home owner loads once, publishes visible refresh, and clears on sign-out")
    func sharedHomePublishesRefresh() async {
        let api = MockInnerTubeAPI()
        api.homeRowsResult = [VideoGroup(videos: [makeVideo("first")])]
        let browse = BrowseViewModel(api: api)
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        var snapshot: [Video] = []
        home.onHomeLoaded = { snapshot = $0 }
        await browse.updateAuthToken("token", reloadOnSignIn: browse.currentSection.type != .home)
        await home.updateAuthToken("token", sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
        #expect(snapshot == home.mergedVideos)
        #expect(snapshot.map(\.id) == ["first"])
        await home.updateAuthToken("refreshed-token", sessionID: 1)
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == 1)
        api.homeRowsResult = [VideoGroup(videos: [makeVideo("refreshed")])]
        await home.refresh()
        #expect(snapshot.map(\.id) == ["refreshed"])
        let count = api.calls.filter { $0.method == "fetchHomeRows" }.count
        await home.updateAuthToken(nil, sessionID: 2)
        home.refreshIfStale()
        #expect(snapshot.isEmpty)
        #expect(home.mergedVideos.isEmpty)
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == count)
    }

    @Test("An old account's response cannot republish after sign-out or account replacement", arguments: [false, true])
    func accountChangeRejectsLateHome(replacement: Bool) async {
        let api = MockInnerTubeAPI()
        let gate = HomeResponseGate<[VideoGroup]>()
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        var snapshot: [Video] = []
        home.onHomeLoaded = { snapshot = $0 }
        await home.updateAuthToken("old", sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        api.homeRowsHandler = { _ in await gate.value() }
        let oldRefresh = Task { await home.refresh() }
        await waitForTasks { gate.started }
        api.homeRowsHandler = nil
        api.homeRowsResult = [VideoGroup(videos: [makeVideo("new-account")])]
        await home.updateAuthToken(replacement ? "new" : nil, sessionID: 2)
        if replacement { await waitForTasks { home.loadedAt != nil } }
        gate.resolve([VideoGroup(videos: [makeVideo("private-old-account")])])
        await oldRefresh.value
        #expect(snapshot.map(\.id) == (replacement ? ["new-account"] : []))
        #expect(home.mergedVideos == snapshot)
    }

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
        // Only recommendation pages extend the Home feed.
        #expect(vm.mergedVideos.map(\.id) == (subscriptions ? ["fresh"] : ["fresh", "fresh-page"]))
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

    @Test("An obsolete Shorts page failure cannot clear the refreshed continuation")
    func obsoleteShortsPageFailure() async {
        let mock = MockInnerTubeAPI()
        let oldPage = HomeResponseGate<Bool>()
        mock.homeRowsResult = [VideoGroup(title: "Home", videos: [makeVideo("home")])]
        mock.shortsResult = VideoGroup(title: "Shorts", videos: [], nextPageToken: "search-old")
        mock.shortsMoreAsyncHandler = { _ in
            _ = await oldPage.value()
            throw URLError(.timedOut)
        }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        let oldLoad = Task { await vm.refresh() }
        await waitForTasks { oldPage.started }

        mock.shortsResult = VideoGroup(
            title: "Fresh", videos: (0..<8).map { short("fresh-\($0)") }, nextPageToken: "search-fresh")
        mock.shortsMoreAsyncHandler = { _ in
            VideoGroup(title: "Fresh page", videos: [short("fresh-page")])
        }
        await vm.refresh()
        oldPage.resolve(true)
        await oldLoad.value

        vm.loadShorts(atLeast: 9)
        await waitForTasks { vm.homeShortsVideos.count == 9 }
        #expect(vm.homeShortsVideos.last?.id == "fresh-page")
        #expect(mock.calls.filter { $0.method == "fetchShortsMore" }.map(\.args) == [["search-old"], ["search-fresh"]])
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
        // Subscriptions feed the Shorts rows only; their regular videos stay out of Home.
        #expect(!vm.homeRegularVideos.contains { $0.id == "regular-page" })
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
        let subscriptions = HomePaginationUITestFixture.regularPage(subscriptions: true, continuationToken: nil)
        #expect(subscriptions.nextPageToken == firstToken)
        #expect(subscriptions.videos.filter(\.isShort).count == 10)
        let next = HomePaginationUITestFixture.regularPage(subscriptions: true, continuationToken: firstToken)
        #expect(next.videos == first.videos)
        #expect(next.nextPageToken == secondToken)

        // Recommendations page through their own continuations, never the Shorts ones, and carry no Shorts.
        var token: String?
        var recommendations: [Video] = []
        repeat {
            let page = HomePaginationUITestFixture.regularPage(subscriptions: false, continuationToken: token)
            #expect(page.videos.count == InnerTubeClients.maxVideoResults)
            #expect(![firstToken, secondToken].contains(page.nextPageToken ?? ""))
            recommendations += page.videos
            token = page.nextPageToken
        } while token != nil && recommendations.count < 10 * InnerTubeClients.maxVideoResults
        #expect(recommendations.count == 3 * InnerTubeClients.maxVideoResults)
        #expect(Set(recommendations.map(\.id)).count == recommendations.count)
        #expect(recommendations.allSatisfy { !$0.isShort })
    }
    #endif

    private func short(_ id: String) -> Video {
        Video(id: id, title: id, channelTitle: "Channel", isShort: true)
    }
}
