import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - SearchErrorStateTests (PLAN-0027 A5)
//
// A failed search is its own state, separate from "no results", and "Try again" repeats the
// submitted query with the submitted filters even after the field text changed.

@Suite("SearchViewModel error state")
@MainActor
struct SearchErrorStateTests {
    private struct ServiceDown: Error {}

    private func makeVM(_ api: MockInnerTubeAPI) -> SearchViewModel {
        SearchViewModel(api: api, historyStore: SearchHistoryStore(suiteName: "search-error-\(UUID().uuidString)"))
    }

    private var weekFilter: SearchFilter {
        var filter = SearchFilter()
        filter.uploadDate = .thisWeek
        return filter
    }

    @Test("A failed first page is .failed, not .noResults, and keeps the query")
    func failureIsSeparateFromNoResults() async {
        let api = MockInnerTubeAPI()
        api.errorToThrow = ServiceDown()
        let vm = makeVM(api)
        #expect(vm.phase == .idle)

        vm.query = "slow living"
        vm.search()
        #expect(vm.phase == .loading)
        await waitForTasks { vm.phase == .failed }
        #expect(vm.error != nil)
        #expect(vm.submittedQuery == "slow living")

        api.errorToThrow = nil
        vm.search()
        await waitForTasks { vm.phase == .noResults }
        #expect(vm.error == nil)
    }

    @Test("Try again repeats the submitted query and filters, not the edited field text")
    func retryRepeatsSubmittedRequest() async {
        let api = MockInnerTubeAPI()
        api.errorToThrow = ServiceDown()
        let vm = makeVM(api)
        vm.applyFilter(weekFilter)
        vm.query = "slow living"
        vm.search()
        await waitForTasks { vm.phase == .failed }

        vm.query = "something else"
        api.errorToThrow = nil
        api.searchResult = VideoGroup(title: "R", videos: [makeVideo("retried")])
        vm.retry()
        #expect(vm.phase == .loading)
        await waitForTasks { vm.phase == .results }

        let searches = api.calls.filter { $0.method == "search" }
        #expect(searches.last?.args == ["slow living", "nil"])
        #expect(api.searchFilters.last == weekFilter)
        #expect(vm.results.map(\.id) == ["retried"])
    }

    @Test("A failed next page keeps the results, and Try again asks for that page")
    func failedNextPageKeepsResults() async {
        let api = MockInnerTubeAPI()
        api.searchResult = VideoGroup(title: "R", videos: [makeVideo("first")], nextPageToken: "page2")
        let vm = makeVM(api)
        vm.query = "swift"
        vm.search()
        await waitForTasks { vm.phase == .results && !vm.isLoading }

        api.errorToThrow = ServiceDown()
        vm.loadMore()
        await waitForTasks { vm.error != nil && !vm.isLoading }
        #expect(vm.phase == .results)

        api.errorToThrow = nil
        api.searchResult = VideoGroup(title: "R", videos: [makeVideo("second")])
        vm.retry()
        await waitForTasks { vm.results.count == 2 }
        #expect(api.calls.filter { $0.method == "search" }.last?.args == ["swift", "page2"])
        #expect(vm.error == nil)
    }

    @Test("A new page request clears the previous page's failure, so Try again never skips a page")
    func pageRequestClearsPageFailure() async {
        let api = MockInnerTubeAPI()
        api.searchResult = VideoGroup(title: "R", videos: [makeVideo("first")], nextPageToken: "page2")
        let vm = makeVM(api)
        vm.query = "swift"
        vm.search()
        await waitForTasks { vm.phase == .results && !vm.isLoading }
        api.errorToThrow = ServiceDown()
        vm.loadMore()
        await waitForTasks { vm.error != nil && !vm.isLoading }

        api.errorToThrow = nil
        api.searchResult = VideoGroup(title: "R", videos: [makeVideo("second")], nextPageToken: "page3")
        vm.loadMore()  // e.g. scrolling to the end instead of tapping Try again
        #expect(vm.error == nil)
        await waitForTasks { vm.results.count == 2 && !vm.isLoading }
        #expect(vm.error == nil)
        vm.retry()  // nothing failed: no request for page3
        #expect(api.calls.filter { $0.method == "search" }.map(\.args.last) == ["nil", "page2", "page2"])
    }

    @Test("Responses arriving out of order never replace the newer search")
    func outOfOrderResponses() async {
        let api = MockInnerTubeAPI()
        var held: [String: CheckedContinuation<VideoGroup, Never>] = [:]
        var answered: Set<String> = []  // the view model has handled these responses
        api.searchHandler = { query, token in
            let group = await withCheckedContinuation { held[token ?? query] = $0 }
            answered.insert(token ?? query)
            return group
        }
        let vm = makeVM(api)
        vm.query = "old"
        vm.search()
        await waitForTasks { held["old"] != nil }
        vm.query = "new"
        vm.search()
        await waitForTasks { held["new"] != nil }

        held["new"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("new-1")], nextPageToken: "new-p2"))
        await waitForTasks { vm.phase == .results }
        held["old"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("old-1")], nextPageToken: "old-p2"))
        await waitForTasks { answered.contains("old") }

        #expect(vm.results.map(\.id) == ["new-1"])
        #expect(vm.submittedQuery == "new")
        #expect(!vm.isLoading)
        vm.loadMore()
        await waitForTasks { held["new-p2"] != nil }
        #expect(held["old-p2"] == nil)
        held["new-p2"]?.resume(returning: VideoGroup(title: "R", videos: []))
        await waitForTasks { !vm.isLoading }
    }

    @Test("A late response after clearing, or a late page after a new search, writes nothing")
    func cancelledRequestsWriteNothing() async {
        let api = MockInnerTubeAPI()
        var held: [String: CheckedContinuation<VideoGroup, Never>] = [:]
        var answered: Set<String> = []  // the view model has handled these responses
        api.searchHandler = { query, token in
            let group = await withCheckedContinuation { held[token ?? query] = $0 }
            answered.insert(token ?? query)
            return group
        }
        let vm = makeVM(api)

        // Cleared while the first page loads.
        vm.query = "cleared"
        vm.search()
        await waitForTasks { held["cleared"] != nil }
        vm.clearResults()
        held["cleared"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("ghost")], nextPageToken: "x"))
        await waitForTasks { answered.contains("cleared") }
        #expect(vm.phase == .idle)
        #expect(vm.results.isEmpty)
        #expect(!vm.isLoading)

        // A page of the previous search that lands after a new search started.
        vm.query = "first"
        vm.search()
        await waitForTasks { held["first"] != nil }
        held["first"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("first-1")], nextPageToken: "p2"))
        await waitForTasks { vm.phase == .results && !vm.isLoading }
        vm.loadMore()
        await waitForTasks { held["p2"] != nil }
        vm.query = "second"
        vm.search()
        await waitForTasks { held["second"] != nil }
        held["p2"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("stale-page")]))
        await waitForTasks { answered.contains("p2") }
        #expect(vm.phase == .loading)
        #expect(vm.results.isEmpty)
        held["second"]?.resume(returning: VideoGroup(title: "R", videos: [makeVideo("second-1")]))
        await waitForTasks { vm.phase == .results && !vm.isLoading }
        #expect(vm.results.map(\.id) == ["second-1"])
    }

    @Test("Clearing the results returns to the idle screen")
    func clearResultsIsIdle() async {
        let api = MockInnerTubeAPI()
        api.errorToThrow = ServiceDown()
        let vm = makeVM(api)
        vm.query = "swift"
        vm.search()
        await waitForTasks { vm.phase == .failed }
        vm.clearResults()
        #expect(vm.phase == .idle)
        #expect(vm.submittedQuery == nil)
    }
}
