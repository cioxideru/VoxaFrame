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
        let sectionID = subscriptions ? BrowseSection.SectionType.subscriptions.rawValue : BrowseSection.SectionType.home.rawValue
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
        oldPage.resolve(VideoGroup(title: "Stale", videos: [short("stale"), makeVideo("stale-regular")], nextPageToken: "stale"))
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

    private func short(_ id: String) -> Video {
        Video(id: id, title: id, channelTitle: "Channel", isShort: true)
    }
}
