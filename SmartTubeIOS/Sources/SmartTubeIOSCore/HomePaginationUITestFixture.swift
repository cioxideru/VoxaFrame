#if DEBUG
import Foundation

/// One initial row; later rows can only come from the real view model's continuation calls.
enum HomePaginationUITestFixture {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--uitesting-home-pagination")
    }

    static func regularPage(subscriptions: Bool, continuationToken: String?) -> VideoGroup {
        let prefix = subscriptions ? "subscription" : "recommended"
        let videos =
            continuationToken == nil
            ? (0..<20).map {
                Video(id: "\(prefix)-\($0)", title: "\(prefix) video \($0)", channelTitle: "Fixture")
            } : []
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
