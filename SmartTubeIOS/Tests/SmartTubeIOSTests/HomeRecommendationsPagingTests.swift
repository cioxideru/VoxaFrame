import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Home is the recommendations feed only: no substitute source, and paging that never stalls on a page
/// without new regular videos.
@Suite("Home recommendations paging")
@MainActor
struct HomeRecommendationsPagingTests {
    @Test("An empty account Home stays empty and never substitutes a search")
    func emptyHomeNeverSearches() async {
        let api = MockInnerTubeAPI()
        api.homeRowsResult = []
        api.searchResult = VideoGroup(videos: [makeVideo("popular")])
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.updateAuthToken("account", sessionID: 1)
        await waitForTasks { home.loadedAt != nil }
        #expect(home.mergedVideos.isEmpty)
        #expect(home.recommendations?.nextPageToken == nil)
        #expect(!api.calls.contains { $0.method == "search" })
    }

    enum EmptyPage: CaseIterable { case empty, duplicates, shortsOnly }

    @Test("A page that adds no regular video continues to the next page by itself", arguments: EmptyPage.allCases)
    func pagesWithoutRegularVideosContinue(page: EmptyPage) async {
        let api = MockInnerTubeAPI()
        api.homeRowsHandler = { token in
            switch token {
            case nil: return [VideoGroup(videos: [makeVideo("first")], nextPageToken: "t1")]
            case "t1":
                let videos: [Video] =
                    switch page {
                    case .empty: []
                    case .duplicates: [makeVideo("first"), makeVideo("first")]
                    case .shortsOnly: [short("short")]
                    }
                return [VideoGroup(videos: videos, nextPageToken: "t2")]
            default: return [VideoGroup(videos: [makeVideo("second")])]
            }
        }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.refresh()
        await home.loadMoreMerged()?.value
        #expect(home.homeRegularVideos.map(\.id) == ["first", "second"])
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.map(\.args) == [["nil"], ["t1"], ["t2"]])
        #expect(home.recommendations?.isLoadingMore == false)
        #expect(home.recommendations?.nextPageToken == nil)
    }

    @Test("A repeated continuation token stops paging instead of looping")
    func repeatedTokenStops() async {
        let api = MockInnerTubeAPI()
        api.homeRowsHandler = { token in
            token == nil
                ? [VideoGroup(videos: [makeVideo("first")], nextPageToken: "loop")]
                : [VideoGroup(videos: [], nextPageToken: "loop")]
        }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.refresh()
        await home.loadMoreMerged()?.value
        #expect(api.calls.filter { $0.method == "fetchHomeRows" }.count == 2)
        #expect(home.recommendations?.nextPageToken == nil)
        #expect(home.loadMoreMerged() == nil)
    }

    @Test("Empty pages are fetched a bounded number of times per request and the cursor is kept")
    func emptyPagesAreBounded() async {
        let api = MockInnerTubeAPI()
        var pages = 0
        api.homeRowsHandler = { token in
            guard token != nil else { return [VideoGroup(videos: [makeVideo("first")], nextPageToken: "p0")] }
            pages += 1
            return [VideoGroup(videos: [], nextPageToken: "p\(pages)")]
        }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.refresh()
        await home.loadMoreMerged()?.value
        #expect(pages == HomeViewModel.maxEmptyPagesPerRequest)
        #expect(home.recommendations?.nextPageToken == "p\(pages)")
        #expect(home.recommendations?.isLoadingMore == false)
        // One regular card and no new one to trigger paging: the view must offer More.
        #expect(home.recommendationsStalled)

        // More resumes beyond the limit from the kept cursor.
        api.homeRowsHandler = { token in
            #expect(token == "p\(HomeViewModel.maxEmptyPagesPerRequest)")
            return [VideoGroup(videos: [makeVideo("after-limit")])]
        }
        await home.loadMoreMerged()?.value
        #expect(home.homeRegularVideos.map(\.id) == ["first", "after-limit"])
        #expect(!home.recommendationsStalled)
        #expect(home.recommendations?.nextPageToken == nil)
    }

    @Test("A first page without regular videos continues the recommendations without a scroll trigger")
    func firstPageWithoutRegularVideosContinues() async {
        let api = MockInnerTubeAPI()
        api.homeRowsHandler = { token in
            token == nil
                ? [VideoGroup(videos: [short("short")], nextPageToken: "t1")]
                : [VideoGroup(videos: [makeVideo("regular")])]
        }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        var published: [[Video]] = []
        home.onHomeLoaded = { published.append($0) }
        await home.refresh()
        await waitForTasks { !home.homeRegularVideos.isEmpty && published.count >= 2 }
        #expect(home.homeRegularVideos.map(\.id) == ["regular"])
        // The widget snapshot follows automatic paging, not just the Shorts-only first page.
        #expect(published.last?.filter { !$0.isShort }.map(\.id) == ["regular"])
        #expect(!api.calls.contains { $0.method == "search" })
    }
}

private func short(_ id: String) -> Video {
    Video(id: id, title: id, channelTitle: "Ch", isShort: true)
}
