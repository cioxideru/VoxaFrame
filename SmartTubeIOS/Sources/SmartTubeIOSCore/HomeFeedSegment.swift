import Foundation

// MARK: - HomeFeedSegment

/// One block of the Home feed: a horizontal Shorts row, or a block of exactly two video-grid
/// rows (only the very last video block may be shorter).
public struct HomeFeedSegment<Item>: Identifiable {
    public enum Kind: String, Sendable {
        case shorts
        case videos
    }

    public let kind: Kind
    /// Position among the segments of the same kind. Block `n` always holds
    /// `items[n * size ..< (n + 1) * size]`, so the id stays stable while the lists only grow.
    public let index: Int
    public let items: [Item]
    public var id: String { "\(kind.rawValue).\(index)" }

    /// Interleaves the feed as Shorts row, two video rows, Shorts row, two video rows, …
    ///
    /// - A Shorts row only precedes a video block, so Shorts left over after the last video
    ///   wait for the next page of videos. With no videos at all, the first Shorts row still shows.
    /// - Once the Shorts run out, the feed continues with video blocks only.
    /// - `columns` is the column count the video grid actually lays out; each video block
    ///   holds `2 * columns` videos, so it fills exactly two rows.
    public static func interleave(
        shorts: [Item], videos: [Item], columns: Int, shortsPerRow: Int
    ) -> [HomeFeedSegment] {
        let videosPerBlock = max(columns, 1) * 2
        let shortsPerBlock = max(shortsPerRow, 1)
        var segments: [HomeFeedSegment] = []
        func append(_ kind: Kind, _ items: [Item], block: Int, size: Int) {
            let start = block * size
            guard start < items.count else { return }
            segments.append(
                .init(kind: kind, index: block, items: Array(items[start..<min(start + size, items.count)])))
        }
        var block = 0
        repeat {
            append(.shorts, shorts, block: block, size: shortsPerBlock)
            append(.videos, videos, block: block, size: videosPerBlock)
            block += 1
        } while block * videosPerBlock < videos.count
        return segments
    }
}

extension HomeFeedSegment: Equatable where Item: Equatable {}
