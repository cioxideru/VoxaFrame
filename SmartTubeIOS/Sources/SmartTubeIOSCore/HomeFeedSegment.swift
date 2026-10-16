import Foundation

// MARK: - HomeFeedSegment

/// One block of a mixed feed: a horizontal Shorts row, or a block of exactly six video-grid
/// rows (only the very last video block may be shorter).
public struct HomeFeedSegment<Item>: Identifiable {
    public enum Kind: String, Sendable {
        case shorts
        case videos
    }

    public let kind: Kind
    /// Shorts row `n` always holds `shorts[n * perRow ..< (n + 1) * perRow]` and video block `n`
    /// a fixed chunk of video rows, so ids stay stable while the lists grow.
    public let index: Int
    public let items: [Item]
    public var id: String { "\(kind.rawValue).\(index)" }
}

extension HomeFeedSegment: Equatable where Item: Equatable {}

// MARK: - HomeFeedLayout

/// Places the mixed feed's Shorts rows between its video blocks: ten Shorts, six video rows,
/// ten Shorts, six video rows, … Each Shorts row goes in front of the next free video block;
/// once the Shorts run out the feed continues with video blocks only.
///
/// Blocks already laid out (`markLaidOut`) never gain or lose a Shorts row, so Shorts that
/// arrive late are placed further down instead of pushing content the user has seen.
public struct HomeFeedLayout: Equatable, Sendable {
    public static let shortsPerRow = 10
    public static let videoRowsPerBlock = 6

    /// Highest video block laid out so far; -1 before the first one appears.
    public private(set) var laidOutThrough = -1
    /// Video block in front of which each settled Shorts row sits (all at or before `laidOutThrough`).
    private var settledRowBlocks: [Int] = []

    public init() {}

    /// The video block each of `rowCount` Shorts rows sits in front of. With no videos, the
    /// first row still shows on its own.
    func rowBlocks(rowCount: Int, blockCount: Int) -> [Int] {
        var blocks = Array(settledRowBlocks.prefix(rowCount))
        var next = max((blocks.last ?? -1) + 1, laidOutThrough + 1)
        while blocks.count < rowCount, next < max(blockCount, 1) {
            blocks.append(next)
            next += 1
        }
        return blocks
    }

    /// The feed in display order. `columns` is the column count the video grid actually lays
    /// out, so every video block but the last fills exactly six rows.
    public func segments<Item>(
        shorts: [Item], videos: [Item], columns: Int, shortsPerRow: Int = Self.shortsPerRow
    ) -> [HomeFeedSegment<Item>] {
        let videosPerBlock = max(columns, 1) * Self.videoRowsPerBlock
        let shortsPerBlock = max(shortsPerRow, 1)
        let blockCount = (videos.count + videosPerBlock - 1) / videosPerBlock
        let rows = rowBlocks(rowCount: (shorts.count + shortsPerBlock - 1) / shortsPerBlock, blockCount: blockCount)
        func chunk(_ items: [Item], _ index: Int, _ size: Int) -> [Item] {
            Array(items[index * size..<min((index + 1) * size, items.count)])
        }
        var segments: [HomeFeedSegment<Item>] = []
        var row = 0
        // A row whose block vanished (videos hidden from the feed) trails at the end.
        for block in 0..<max(blockCount, (rows.last ?? -1) + 1) {
            if row < rows.count, rows[row] == block {
                segments.append(.init(kind: .shorts, index: row, items: chunk(shorts, row, shortsPerBlock)))
                row += 1
            }
            if block < blockCount {
                segments.append(.init(kind: .videos, index: block, items: chunk(videos, block, videosPerBlock)))
            }
        }
        return segments
    }

    /// Records that video block `block` of `segments` has been laid out: every Shorts row in
    /// front of it, or of an earlier block, stays where it is.
    public mutating func markLaidOut<Item>(block: Int, in segments: [HomeFeedSegment<Item>]) {
        guard block > laidOutThrough else { return }
        var rowBlocks: [Int] = []
        var nextBlock = 0
        for segment in segments {
            if segment.kind == .videos {
                nextBlock = segment.index + 1
            } else if nextBlock <= block {
                rowBlocks.append(nextBlock)
            }
        }
        settledRowBlocks = rowBlocks
        laidOutThrough = block
    }

    /// Shorts needed for every video block through `block` that can still take a Shorts row to get one.
    public func shortsWanted(through block: Int, shortsPerRow: Int = Self.shortsPerRow) -> Int {
        rowBlocks(rowCount: .max, blockCount: block + 1).count * max(shortsPerRow, 1)
    }
}
