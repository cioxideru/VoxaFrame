import Testing

@testable import SmartTubeIOSCore

@Suite("Home feed Shorts/video interleave")
struct HomeFeedSegmentTests {

    private typealias Segment = HomeFeedSegment<Int>

    /// `(kind, items)` pairs, the shape the assertions compare against.
    private func layout(shorts: Int, videos: Int, columns: Int, shortsPerRow: Int) -> [String] {
        Segment.interleave(
            shorts: Array(100..<100 + shorts), videos: Array(0..<videos), columns: columns,
            shortsPerRow: shortsPerRow
        ).map { "\($0.kind.rawValue)\($0.items.count)" }
    }

    @Test func alternatesShortsRowWithTwoVideoRows() {
        #expect(
            layout(shorts: 9, videos: 12, columns: 3, shortsPerRow: 3)
                == ["shorts3", "videos6", "shorts3", "videos6"])
    }

    @Test func videoBlocksFollowTheColumnCount() {
        for columns in 1...6 {
            let segments = Segment.interleave(shorts: [], videos: Array(0..<100), columns: columns, shortsPerRow: 5)
            // Every block but the last holds exactly two full rows.
            #expect(segments.dropLast().allSatisfy { $0.items.count == 2 * columns })
            #expect(segments.flatMap(\.items) == Array(0..<100))
        }
    }

    @Test func continuesWithVideoBlocksWhenShortsRunOut() {
        #expect(
            layout(shorts: 5, videos: 16, columns: 2, shortsPerRow: 4)
                == ["shorts4", "videos4", "shorts1", "videos4", "videos4", "videos4"])
    }

    @Test func onlyTheLastVideoBlockIsPartial() {
        #expect(
            layout(shorts: 10, videos: 9, columns: 2, shortsPerRow: 2)
                == ["shorts2", "videos4", "shorts2", "videos4", "shorts2", "videos1"])
    }

    @Test func leftoverShortsWaitForMoreVideos() {
        // Shorts rows only precede video blocks: 3 blocks of videos → 3 Shorts rows.
        #expect(
            layout(shorts: 50, videos: 12, columns: 2, shortsPerRow: 5)
                == ["shorts5", "videos4", "shorts5", "videos4", "shorts5", "videos4"])
    }

    @Test func emptyInputs() {
        #expect(layout(shorts: 0, videos: 0, columns: 3, shortsPerRow: 5).isEmpty)
        #expect(layout(shorts: 7, videos: 0, columns: 3, shortsPerRow: 5) == ["shorts5"])
        #expect(layout(shorts: 0, videos: 3, columns: 3, shortsPerRow: 5) == ["videos3"])
    }

    @Test func keepsOrderAndStableIDs() {
        let segments = Segment.interleave(
            shorts: Array(100..<106), videos: Array(0..<8), columns: 2, shortsPerRow: 3)
        #expect(segments.map(\.id) == ["shorts.0", "videos.0", "shorts.1", "videos.1"])
        #expect(segments.filter { $0.kind == .shorts }.flatMap(\.items) == Array(100..<106))
        #expect(segments.filter { $0.kind == .videos }.flatMap(\.items) == Array(0..<8))

        // Appending a page leaves the earlier blocks untouched.
        let grown = Segment.interleave(
            shorts: Array(100..<106), videos: Array(0..<12), columns: 2, shortsPerRow: 3)
        #expect(Array(grown.prefix(segments.count)) == segments)
    }

    @Test func clampsNonPositiveSizes() {
        #expect(
            layout(shorts: 2, videos: 4, columns: 0, shortsPerRow: 0) == ["shorts1", "videos2", "shorts1", "videos2"])
    }
}
