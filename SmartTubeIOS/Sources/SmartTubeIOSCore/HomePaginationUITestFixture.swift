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
        return arguments.contains("--uitesting") && arguments.contains("--uitesting-mixed-feed")
    }

    static func regularPage(subscriptions: Bool, continuationToken: String?) -> VideoGroup {
        let prefix = subscriptions ? "subscription" : "recommended"
        var videos =
            continuationToken == nil
            ? (0..<60).map {
                Video(id: "\(prefix)-\($0)", title: "\(prefix) video \($0)", channelTitle: "Fixture")
            } : []
        if isMixedFeedEnabled, continuationToken == nil {
            videos += (0..<30).map {
                Video(id: "\(prefix)-short-\($0)", title: "Short \($0)", channelTitle: "Fixture", isShort: true)
            }
        }
        if subscriptions, !isMixedFeedEnabled {
            let shorts = shortsPage(continuationToken: continuationToken)
            return VideoGroup(title: prefix, videos: videos + shorts.videos, nextPageToken: shorts.nextPageToken)
        }
        return VideoGroup(title: prefix, videos: videos)
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
                    id: "\(prefix)-short-\($0)", title: "\(prefix) short \($0)", channelTitle: "Fixture", isShort: true)
            },
            nextPageToken: nextToken
        )
    }
}
#endif
