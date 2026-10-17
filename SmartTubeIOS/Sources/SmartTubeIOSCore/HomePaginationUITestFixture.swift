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
            var fields: [String: Any] = [
                "videoId": video.id, "title": ["simpleText": video.title],
                "ownerText": ["simpleText": video.channelTitle],
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
            return VideoGroup(
                title: prefix,
                videos: [
                    Video(
                        id: "\(prefix)-next", title: "Next unwatched video", channelTitle: "Fixture")
                ])
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
                    id: "\(prefix)-short-\($0)", title: "\(prefix) short \($0)", channelTitle: "Fixture", isShort: true,
                    watchProgress: progress(at: $0))
            },
            nextPageToken: nextToken
        )
    }
}
#endif
