import Foundation
import Testing

@testable import SmartTubeIOSCore

// YouTube ignores the sort field for the WEB client (upstream issue #178), so each page of results
// is ordered on the device (PLAN-0049).

@Suite("Search local ordering")
@MainActor
struct SearchLocalOrderTests {

    private func video(_ id: String, daysAgo: Double? = nil, views: Int? = nil) -> Video {
        var video = Video(id: id, title: id, channelTitle: "Channel")
        video.publishedAt = daysAgo.map { Date(timeIntervalSinceReferenceDate: 1_000_000_000 - $0 * 86_400) }
        video.viewCount = views
        return video
    }

    private func filter(_ order: SearchFilter.SortOrder) -> SearchFilter {
        SearchFilter(sortOrder: order)
    }

    @Test("Upload date puts the newest first and undated videos last in their order")
    func uploadDateOrder() {
        let page = [
            video("monthOld", daysAgo: 30), video("undatedA"), video("yesterday", daysAgo: 1),
            video("undatedB"), video("weekOld", daysAgo: 7),
        ]

        #expect(
            filter(.uploadDate).ordered(page).map(\.id) == ["yesterday", "weekOld", "monthOld", "undatedA", "undatedB"])
    }

    @Test("View count puts the most viewed first and keeps ties in their order")
    func viewCountOrder() {
        let page = [video("few", views: 10), video("tieA", views: 500), video("none"), video("tieB", views: 500)]

        #expect(filter(.viewCount).ordered(page).map(\.id) == ["tieA", "tieB", "few", "none"])
    }

    @Test("Relevance and rating keep YouTube's order")
    func serverOrderKept() {
        let page = [video("b", daysAgo: 9, views: 1), video("a", daysAgo: 1, views: 9)]

        #expect(filter(.relevance).ordered(page).map(\.id) == ["b", "a"])
        #expect(filter(.rating).ordered(page).map(\.id) == ["b", "a"])
    }

    @Test("Each page is ordered on its own, so loaded cards keep their place")
    func pagesOrderedSeparately() async {
        let api = MockInnerTubeAPI()
        let vm = SearchViewModel(api: api, historyStore: SearchHistoryStore(suiteName: "order-\(UUID().uuidString)"))
        vm.applyFilter(filter(.uploadDate))
        api.searchResult = VideoGroup(
            title: "P1", videos: [video("old", daysAgo: 20), video("new", daysAgo: 2)], nextPageToken: "p2")
        vm.query = "electric car"
        vm.search()
        await waitForTasks { !vm.isLoading && !vm.results.isEmpty }

        api.searchResult = VideoGroup(title: "P2", videos: [video("older", daysAgo: 40), video("newest", daysAgo: 1)])
        vm.loadMore()
        await waitForTasks { !vm.isLoading && vm.results.count == 4 }

        #expect(vm.results.map(\.id) == ["new", "old", "newest", "older"])
    }
}
