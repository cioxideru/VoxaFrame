import Foundation

/// A presentation keeps recent backward navigation, not the entire viewing session.
public struct ShortsFeedWindow {
    public static let previousCount = 12
    public static let maximumCount = 120
    public static let maximumCursorCount = 64
    public private(set) var videos: [Video]
    public private(set) var currentIndex: Int
    public private(set) var discardedCount = 0
    public private(set) var consumedCursors: [String] = []

    public init(videos: [Video], startIndex: Int) {
        self.videos = videos
        currentIndex = min(max(startIndex, 0), max(videos.count - 1, 0))
        trim()
    }

    public mutating func move(to index: Int) {
        guard videos.indices.contains(index) else { return }
        currentIndex = index
        trim()
    }

    public mutating func insert(_ additions: [Video], prepending: Bool) {
        if prepending {
            videos.insert(contentsOf: additions, at: 0)
            currentIndex += additions.count
        } else {
            videos.append(contentsOf: additions)
        }
        trim()
    }

    public mutating func nextCursor(after consumed: String?, proposed: String?) -> String? {
        if let consumed {
            consumedCursors.append(consumed)
            if consumedCursors.count > Self.maximumCursorCount {
                consumedCursors.removeFirst(consumedCursors.count - Self.maximumCursorCount)
            }
        }
        return proposed.flatMap { consumedCursors.contains($0) ? nil : $0 }
    }

    private mutating func trim() {
        let removed = max(0, currentIndex - Self.previousCount)
        if removed > 0 {
            videos.removeFirst(removed)
            currentIndex -= removed
            discardedCount += removed
        }
        if videos.count > Self.maximumCount {
            videos.removeLast(videos.count - Self.maximumCount)
        }
    }
}
