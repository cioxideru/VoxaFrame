#if DEBUG
import Foundation

/// One initial row; later rows can only come from the real view model's continuation calls.
enum HomePaginationUITestFixture {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting")
            && (arguments.contains("--uitesting-home-pagination") || isMixedFeedEnabled)
    }

    static var isMixedFeedEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting")
            && (arguments.contains("--uitesting-mixed-feed") || isWatchedFeedEnabled)
    }

    static var isWatchedFeedEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--uitesting-watched-feed")
    }

    /// `--uitesting-inject-recommended-ids=<id,id,…>`: these videos are the whole Home
    /// recommendations feed (no continuation), so playback tests need no account feed.
    static var injectedRecommendationIDs: [String] {
        let arguments = ProcessInfo.processInfo.arguments
        let prefix = "--uitesting-inject-recommended-ids="
        guard arguments.contains("--uitesting"), let argument = arguments.first(where: { $0.hasPrefix(prefix) })
        else { return [] }
        return argument.dropFirst(prefix.count).split(separator: ",").map(String.init)
    }

    private static var isWatchedPageEnabled: Bool {
        isWatchedFeedEnabled && ProcessInfo.processInfo.arguments.contains("--uitesting-watched-page")
    }

    private static func progress(at index: Int) -> Double? {
        guard isWatchedFeedEnabled else { return nil }
        if isWatchedPageEnabled { return 1 }
        switch index {
        case 0: return 0.9
        case 1: return 0.25
        case 2: return 0.05
        case 4: return 0.24
        default: return nil
        }
    }

    /// UI pagination must cross the parser boundary, including competing navigation/shelf cursors.
    static func browseResponse(for group: VideoGroup) -> [String: Any] {
        func renderer(_ video: Video) -> [String: Any] {
            let channel = ["browseEndpoint": ["browseId": video.channelId ?? "UCfixture-\(video.id)"]]
            var fields: [String: Any] = [
                "videoId": video.id, "title": ["simpleText": video.title],
                "ownerText": ["runs": [["text": video.channelTitle, "navigationEndpoint": channel]]],
            ]
            if video.isShort {
                fields["navigationEndpoint"] = ["reelWatchEndpoint": ["videoId": video.id]]
            }
            if let progress = video.watchProgress {
                fields["thumbnailOverlays"] = [
                    [
                        "thumbnailOverlayResumePlaybackRenderer": ["percentDurationWatched": progress * 100]
                    ]
                ]
            }
            return ["videoRenderer": fields]
        }
        var feed: [String: Any] = [
            "contents": [
                ["shelfRenderer": ["content": ["horizontalListRenderer": ["items": group.videos.map(renderer)]]]],
                [
                    "shelfRenderer": [
                        "content": [
                            "horizontalListRenderer": [
                                "items": [],
                                "continuations": [["nextContinuationData": ["continuation": "unrelated-shelf"]]],
                            ]
                        ]
                    ]
                ],
            ]
        ]
        if let token = group.nextPageToken {
            feed["continuations"] = [["nextContinuationData": ["continuation": token]]]
        }
        let unrelated = (0..<HomeFeedLayout.shortsPerRow).map {
            renderer(Video(id: "unrelated-short-\($0)", title: "Unrelated", channelTitle: "Other tab", isShort: true))
        }
        return [
            "contents": [
                "tvBrowseRenderer": [
                    "content": [
                        "tvSecondaryNavRenderer": [
                            "sections": [
                                [
                                    "tvSecondaryNavSectionRenderer": [
                                        "tabs": [
                                            [
                                                "tabRenderer": [
                                                    "selected": true, "content": ["sectionListRenderer": feed],
                                                ]
                                            ],
                                            [
                                                "tabRenderer": [
                                                    "selected": false,
                                                    "content": [
                                                        "gridRenderer": [
                                                            "items": unrelated,
                                                            "continuations": [
                                                                [
                                                                    "nextContinuationData": [
                                                                        "continuation": "unrelated-tab"
                                                                    ]
                                                                ]
                                                            ],
                                                        ]
                                                    ],
                                                ]
                                            ],
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    static func regularPage(subscriptions: Bool, continuationToken: String?) -> VideoGroup {
        let prefix = subscriptions ? "subscription" : "recommended"
        if isWatchedFeedEnabled, continuationToken != nil {
            // One card: a lone card in its feed block must keep its `video.card.<id>` identifier.
            return VideoGroup(
                title: prefix,
                videos: [Video(id: "\(prefix)-next", title: "Next unwatched video", channelTitle: "Fixture")])
        }
        if !subscriptions, !isWatchedFeedEnabled {
            return recommendationsPage(continuationToken: continuationToken)
        }
        var videos =
            continuationToken == nil
            ? (0..<(isWatchedFeedEnabled ? 5 : 60)).map {
                Video(
                    id: "\(prefix)-\($0)", title: "\(prefix) video \($0)", channelTitle: "Fixture",
                    watchProgress: progress(at: $0))
            } : []
        if isMixedFeedEnabled, continuationToken == nil {
            // Keep Home's independent Shorts prefetch satisfied while testing a fully hidden page.
            let shortsCount = isWatchedFeedEnabled && !isWatchedPageEnabled ? 5 : 30
            videos += (0..<shortsCount).map {
                Video(
                    id: "\(prefix)-short-\($0)", title: "Short \($0)", channelTitle: "Fixture", isShort: true,
                    watchProgress: progress(at: $0))
            }
        }
        if subscriptions, !isMixedFeedEnabled {
            let shorts = shortsPage(continuationToken: continuationToken)
            return VideoGroup(title: prefix, videos: videos + shorts.videos, nextPageToken: shorts.nextPageToken)
        }
        return VideoGroup(title: prefix, videos: videos, nextPageToken: isWatchedFeedEnabled ? "watched-next" : nil)
    }

    /// An initial page and two continuation pages of `maxVideoResults` recommendations, the Home page size after its first-page cap,
    /// so scrolling Home reaches a third video block only by paging the feed.
    private static func recommendationsPage(continuationToken: String?) -> VideoGroup {
        let tokenPrefix = "recommended-page-"
        let page = continuationToken.flatMap { Int($0.dropFirst(tokenPrefix.count)) } ?? 0
        let size = InnerTubeClients.maxVideoResults
        var videos = (page * size..<(page + 1) * size).map {
            Video(id: "recommended-\($0)", title: "recommended video \($0)", channelTitle: "Fixture")
        }
        if isMixedFeedEnabled, page == 0 {
            videos += (0..<30).map {
                Video(id: "recommended-short-\($0)", title: "Short \($0)", channelTitle: "Fixture", isShort: true)
            }
        }
        return VideoGroup(
            title: "recommended", videos: videos, nextPageToken: page < 2 ? "\(tokenPrefix)\(page + 1)" : nil)
    }

    static func shortsPage(continuationToken: String?) -> VideoGroup {
        let prefix: String
        let nextToken: String?
        switch continuationToken {
        case nil:
            prefix = "initial"
            nextToken = "page-1"
        case "page-1":
            prefix = "page-1"
            nextToken = "page-2"
        case "page-2":
            prefix = "page-2"
            nextToken = nil
        default:
            return VideoGroup(title: "Exhausted", videos: [])
        }
        return VideoGroup(
            title: "Shorts",
            videos: (0..<10).map {
                Video(
                    id: "\(prefix)-short-\($0)", title: "\(prefix) short \($0)", channelTitle: "Fixture",
                    channelId: "UCfixture-\(prefix)-short-\($0)", isShort: true,
                    watchProgress: progress(at: $0))
            },
            nextPageToken: nextToken
        )
    }
}
#endif
