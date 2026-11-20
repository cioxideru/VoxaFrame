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
    /// The Short the presentation opened at. A signed-in feed's sequence starts from it (PLAN-0052); it is kept
    /// after trimming, which can drop it from `videos` before the first page is requested.
    public let seedVideoId: String?
    /// Every Short still in the window once it was added (presented, or loaded at either end), kept after later
    /// trimming: a page added at the end never repeats one of them (PLAN-0052). It holds every Short in `videos`.
    private var insertedIds: Set<String> = []
    /// Whether the end follows the account's Shorts sequence, as its last page's tokens showed (`reel:`); nil before
    /// the end's first page. The sequence pages with its own cursor; every other page is the presentation's source,
    /// whose one cursor both ends share as before PLAN-0052, so a page is never asked for twice.
    private var endFollowsSequence: Bool?
    private var sharedCursor: String?
    private var hasLoadedShared = false
    private var sequenceCursor: String?

    public init(videos: [Video], startIndex: Int) {
        self.videos = videos
        currentIndex = min(max(startIndex, 0), max(videos.count - 1, 0))
        seedVideoId = videos.indices.contains(currentIndex) ? videos[currentIndex].id : nil
        trim()
        insertedIds = Set(self.videos.map(\.id))
    }

    private func usesSequence(prepending: Bool) -> Bool { !prepending && endFollowsSequence == true }

    /// The cursor for the next page at the start (`prepending`) or at the end; nil before its source's first page.
    /// When the presentation's source ended before the end's first page, the end's is a bare `reel:`: it may only
    /// start the account's sequence, never that source again.
    public func cursor(prepending: Bool) -> String? {
        if !prepending, endFollowsSequence == nil, hasLoadedShared, sharedCursor == nil {
            return InnerTubeAPI.shortsSequencePrefix
        }
        return usesSequence(prepending: prepending) ? sequenceCursor : sharedCursor
    }

    /// A source's first page can always be asked for, later ones while it has a cursor. Before its first page the end
    /// may ask even when the presentation's source has ended: signed in, that page starts the account's sequence.
    public func canLoadMore(prepending: Bool) -> Bool {
        if !prepending, endFollowsSequence == nil { return true }
        return usesSequence(prepending: prepending) ? sequenceCursor != nil : !hasLoadedShared || sharedCursor != nil
    }

    /// Takes the page requested with `token` at one end. Its tokens tell its source: with a `reel:` one it is the
    /// account's sequence at the end, otherwise the presentation's source, whose cursor then moves on (`nextCursor`).
    /// Its Shorts not yet in the window are inserted there; at the end, none the feed held before either. Returns how
    /// many were added.
    @discardableResult
    public mutating func accept(_ page: VideoGroup, requestedWith token: String?, prepending: Bool) -> Int {
        if !prepending {
            endFollowsSequence = [token, page.nextPageToken].contains {
                $0?.hasPrefix(InnerTubeAPI.shortsSequencePrefix) == true
            }
        }
        let cursor = nextCursor(after: token, proposed: page.nextPageToken)
        if usesSequence(prepending: prepending) {
            sequenceCursor = cursor
        } else {
            hasLoadedShared = true
            sharedCursor = cursor
        }
        var onPage = Set<String>()
        let added: [Video]
        if prepending {
            let inWindow = Set(videos.map(\.id))
            added = page.videos.filter { !inWindow.contains($0.id) && onPage.insert($0.id).inserted }
        } else {
            added = page.videos.filter { !insertedIds.contains($0.id) && onPage.insert($0.id).inserted }
        }
        if !added.isEmpty { insert(added, prepending: prepending) }
        return added.count
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
        // Only the additions trimming kept were there to watch: the others may still come at the end.
        let kept = Set(videos.map(\.id))
        insertedIds.formUnion(additions.map(\.id).filter(kept.contains))
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
