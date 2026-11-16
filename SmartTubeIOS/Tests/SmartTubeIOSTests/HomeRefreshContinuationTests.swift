import Foundation
import Testing

@testable import SmartTubeIOSCore

/// The signed-in (TV) Home ends each recommendations batch with a "Refresh" button and no section cursor;
/// its `loadReloadContinuationCommand` continues the feed (PLAN-0049).
@Suite("Home Refresh-button continuation (PLAN-0049)")
struct HomeRefreshContinuationTests {
    @Test("A batch ending with only the Refresh button continues with its token")
    func refreshButtonBecomesNextPage() async throws {
        let rows = await InnerTubeAPI().parseHomeRowsForTesting(
            try refreshBatchResponse(videoIDs: ["vid-a", "vid-b"], refreshToken: "REFRESH_TOKEN"))
        #expect(rows.flatMap(\.videos).map(\.id) == ["vid-a", "vid-b"])
        #expect(rows.last?.nextPageToken == "REFRESH_TOKEN")
    }

    @Test("A regular feed continuation wins over the Refresh button")
    func sectionContinuationWins() async throws {
        let rows = await InnerTubeAPI().parseHomeRowsForTesting(
            try refreshBatchResponse(
                videoIDs: ["vid-a"], refreshToken: "REFRESH_TOKEN", sectionToken: "SECTION_TOKEN"))
        #expect(rows.last?.nextPageToken == "SECTION_TOKEN")
    }

    @Test("Row continuations and non-video tiles do not become the Home cursor")
    func rowContinuationIsNotThePageToken() async throws {
        let rows = await InnerTubeAPI().parseHomeRowsForTesting(
            try refreshBatchResponse(videoIDs: ["vid-a"], refreshToken: nil))
        #expect(rows.flatMap(\.videos).map(\.id) == ["vid-a"])
        #expect(rows.last?.nextPageToken == nil)
    }

    @Test("Other feeds parsed by the flat parser ignore the Refresh button")
    func flatFeedsIgnoreRefresh() async throws {
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(
            try refreshBatchResponse(videoIDs: ["vid-a"], refreshToken: "REFRESH_TOKEN"), title: "Subscriptions")
        #expect(group.nextPageToken == nil)
    }

    @Test("Home loads the next batch after a page that ends with only the Refresh button")
    @MainActor
    func homeContinuesPastBatchEnd() async throws {
        let parser = InnerTubeAPI()
        let lastPage = await parser.parseHomeRowsForTesting(
            try refreshBatchResponse(videoIDs: ["vid-b", "vid-c"], refreshToken: "REFRESH_TOKEN"))
        // The new batch repeats every card already shown, so paging must reach the batch after it by itself.
        let duplicateBatch = await parser.parseHomeRowsForTesting(
            try refreshBatchResponse(videoIDs: ["vid-a", "vid-b"], refreshToken: "REFRESH_TOKEN_2"))
        let api = MockInnerTubeAPI()
        api.homeRowsHandler = { token in
            switch token {
            case nil: [VideoGroup(videos: [makeVideo("vid-a")], nextPageToken: "PAGE_2")]
            case "PAGE_2": lastPage
            case "REFRESH_TOKEN": duplicateBatch
            default: [VideoGroup(videos: [makeVideo("vid-d")])]
            }
        }
        let home = HomeViewModel(api: api)
        defer { home.cancel() }
        await home.refresh()
        await home.loadMoreMerged()?.value
        #expect(home.recommendations?.nextPageToken == "REFRESH_TOKEN")

        await home.loadMoreMerged()?.value
        #expect(home.homeRegularVideos.map(\.id) == ["vid-a", "vid-b", "vid-c", "vid-d"])
        #expect(
            api.calls.filter { $0.method == "fetchHomeRows" }.map(\.args)
                == [["nil"], ["PAGE_2"], ["REFRESH_TOKEN"], ["REFRESH_TOKEN_2"]])
        #expect(!home.recommendationsStalled)
    }
}

/// Synthetic TV browse continuation in the shape of a batch's last page: video shelves with row
/// continuations, a topics shelf of non-video tiles, and a final shelf holding only the Refresh button.
private func refreshBatchResponse(
    videoIDs: [String], refreshToken: String?, sectionToken: String? = nil
) throws -> [String: Any] {
    let tiles = videoIDs.map { id in
        """
        {"tileRenderer": {"contentType": "TILE_CONTENT_TYPE_VIDEO",
          "onSelectCommand": {"watchEndpoint": {"videoId": "\(id)"}},
          "metadata": {"tileMetadataRenderer": {"title": {"simpleText": "Title \(id)"}}}}}
        """
    }
    let refreshShelf =
        refreshToken.map { token in
            """
            , {"shelfRenderer": {"content": {"horizontalListRenderer": {"items": [
              {"gridButtonRenderer": {"icon": {"iconType": "ARROW_CIRCLE"},
                "title": {"runs": [{"text": "Refresh"}]},
                "navigationEndpoint": {"loadReloadContinuationCommand": {
                  "continuation": "\(token)", "targetId": "browse-feedFEtopics"}}}}]}}}}
            """
        } ?? ""
    let sectionContinuation =
        sectionToken.map { #", "continuations": [{"nextContinuationData": {"continuation": "\#($0)"}}]"# } ?? ""
    let json = """
        {"continuationContents": {"sectionListContinuation": {"contents": [
          {"shelfRenderer": {"headerRenderer": {"shelfHeaderRenderer": {"title": {"simpleText": "Made-up topic"}}},
            "content": {"horizontalListRenderer": {"items": [\(tiles.joined(separator: ","))],
              "continuations": [{"nextContinuationData": {"continuation": "ROW_ONLY_TOKEN"}}]}}}},
          {"shelfRenderer": {"content": {"horizontalListRenderer": {"items": [
            {"tileRenderer": {"contentType": "TILE_CONTENT_TYPE_EDU",
              "onSelectCommand": {"searchEndpoint": {"query": "made-up topic"}}}}],
            "continuations": [{"nextContinuationData": {"continuation": "TOPICS_ROW_TOKEN"}}]}}}}
          \(refreshShelf)
        ]\(sectionContinuation)}}}
        """
    return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}
