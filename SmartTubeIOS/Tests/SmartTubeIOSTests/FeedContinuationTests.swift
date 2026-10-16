import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Feed continuation ownership (PLAN-0014)")
struct FeedContinuationTests {
    private func continuation(_ token: String) -> [[String: Any]] {
        [["nextContinuationData": ["continuation": token]]]
    }

    private func continuationItem(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]]
    }

    private func short(_ id: String) -> [String: Any] {
        ["richItemRenderer": ["content": ["reelItemRenderer": ["videoId": id, "headline": ["simpleText": id]]]]]
    }

    @Test("TV feed continuation cannot be replaced by the last nested shelf", arguments: [false, true])
    func tvFeedOwnsContinuation(rows: Bool) async throws {
        let response: [String: Any] = [
            "contents": [
                "sectionListRenderer": [
                    "continuations": continuation("account-page-2"),
                    "contents": [
                        [
                            "shelfRenderer": [
                                "content": [
                                    "horizontalListRenderer": [
                                        "items": [short("account-short")],
                                        "continuations": continuation("shelf-only"),
                                    ]
                                ]
                            ]
                        ]
                    ],
                ]
            ]
        ]
        let api = InnerTubeAPI()
        let groups =
            if rows {
                await api.parseVideoGroupRowsForTesting(response)
            } else {
                [try await api.parseVideoGroupForTesting(response, title: nil)]
            }
        #expect(groups.last?.nextPageToken == "account-page-2")
    }

    @Test("WEB feed continuation wins even if a nested shelf follows it", arguments: [false, true])
    func webFeedOwnsContinuation(rows: Bool) async throws {
        let response: [String: Any] = [
            "contents": [
                "richGridRenderer": [
                    "contents": [
                        continuationItem("account-page-2"),
                        [
                            "richSectionRenderer": [
                                "content": [
                                    "richShelfRenderer": [
                                        "contents": [short("account-short"), continuationItem("shelf-only")]
                                    ]
                                ]
                            ]
                        ],
                    ]
                ]
            ]
        ]
        let api = InnerTubeAPI()
        let groups =
            if rows {
                await api.parseVideoGroupRowsForTesting(response)
            } else {
                [try await api.parseVideoGroupForTesting(response, title: nil)]
            }
        #expect(groups.last?.nextPageToken == "account-page-2")
    }

    @Test("Only the selected navigation tab contributes videos and continuation", arguments: [false, true])
    func selectedTabOwnsFeed(rows: Bool) async throws {
        func tab(_ id: String, selected: Bool) -> [String: Any] {
            [
                "tabRenderer": [
                    "selected": selected,
                    "content": [
                        "sectionListRenderer": [
                            "contents": [short(id)], "continuations": continuation(id + "-next"),
                        ]
                    ],
                ]
            ]
        }
        let response: [String: Any] = [
            "contents": [
                "tvBrowseRenderer": [
                    "content": [
                        "tvSecondaryNavRenderer": [
                            "sections": [
                                [
                                    "tvSecondaryNavSectionRenderer": [
                                        "tabs": [
                                            tab("unselected-before", selected: false),
                                            tab("account", selected: true),
                                            tab("unselected-after", selected: false),
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let api = InnerTubeAPI()
        let groups =
            if rows {
                await api.parseVideoGroupRowsForTesting(response)
            } else {
                [try await api.parseVideoGroupForTesting(response, title: nil)]
            }
        #expect(groups.flatMap(\.videos).map(\.id) == ["account"])
        #expect(groups.last?.nextPageToken == "account-next")
    }

    @Test("A terminal multi-shelf feed does not continue an unrelated shelf", arguments: [false, true])
    func exhaustedFeedDoesNotBecomeShelf(rows: Bool) async throws {
        let response: [String: Any] = [
            "contents": [
                "sectionListRenderer": [
                    "contents": [
                        ["shelfRenderer": ["content": ["horizontalListRenderer": ["items": [short("account")]]]]],
                        [
                            "shelfRenderer": [
                                "content": [
                                    "horizontalListRenderer": [
                                        "items": [short("another-shelf")], "continuations": continuation("shelf-only"),
                                    ]
                                ]
                            ]
                        ],
                    ]
                ]
            ]
        ]
        let api = InnerTubeAPI()
        let groups =
            if rows {
                await api.parseVideoGroupRowsForTesting(response)
            } else {
                [try await api.parseVideoGroupForTesting(response, title: nil)]
            }
        #expect(groups.last?.nextPageToken == nil)
    }

    @Test(
        "Standalone TV lists and continuation pages keep their own cursor",
        arguments: ["gridRenderer", "horizontalListRenderer", "gridContinuation", "sectionListContinuation"])
    func standaloneListContinues(renderer: String) async throws {
        let response: [String: Any] = [
            "continuationContents": [
                renderer: [
                    "items": [short("account")], "continuations": continuation("account-next"),
                ]
            ]
        ]
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil)
        #expect(group.videos.map(\.id) == ["account"])
        #expect(group.nextPageToken == "account-next")
    }
}
