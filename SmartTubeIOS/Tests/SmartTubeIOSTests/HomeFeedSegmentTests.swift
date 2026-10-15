import Testing

@testable import SmartTubeIOSCore

@Suite("Home feed Shorts/video interleave")
struct HomeFeedSegmentTests {

    private func segments(
        _ layout: HomeFeedLayout = HomeFeedLayout(), shorts: Int, videos: Int, columns: Int, shortsPerRow: Int
    ) -> [HomeFeedSegment<Int>] {
        layout.segments(
            shorts: Array(100..<100 + shorts), videos: Array(0..<videos), columns: columns, shortsPerRow: shortsPerRow)
    }

    /// `kind` + item count per segment, the shape the assertions compare against.
    private func shape(_ segments: [HomeFeedSegment<Int>]) -> [String] {
        segments.map { "\($0.kind.rawValue)\($0.items.count)" }
    }

    private func layout(shorts: Int, videos: Int, columns: Int, shortsPerRow: Int) -> [String] {
        shape(segments(shorts: shorts, videos: videos, columns: columns, shortsPerRow: shortsPerRow))
    }

    @Test func alternatesShortsRowWithTwoVideoRows() {
        #expect(
            layout(shorts: 9, videos: 12, columns: 3, shortsPerRow: 3)
                == ["shorts3", "videos6", "shorts3", "videos6"])
    }

    @Test func videoBlocksFollowTheColumnCount() {
        for columns in 1...6 {
            let feed = segments(shorts: 0, videos: 100, columns: columns, shortsPerRow: 5)
            // Every block but the last holds exactly two full rows.
            #expect(feed.dropLast().allSatisfy { $0.items.count == 2 * columns })
            #expect(feed.flatMap(\.items) == Array(0..<100))
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
        let feed = segments(shorts: 6, videos: 8, columns: 2, shortsPerRow: 3)
        #expect(feed.map(\.id) == ["shorts.0", "videos.0", "shorts.1", "videos.1"])
        #expect(feed.filter { $0.kind == .shorts }.flatMap(\.items) == Array(100..<106))
        #expect(feed.filter { $0.kind == .videos }.flatMap(\.items) == Array(0..<8))

        // Appending a page leaves the earlier blocks untouched.
        let grown = segments(shorts: 6, videos: 12, columns: 2, shortsPerRow: 3)
        #expect(Array(grown.prefix(feed.count)) == feed)
    }

    @Test func clampsNonPositiveSizes() {
        #expect(
            layout(shorts: 2, videos: 4, columns: 0, shortsPerRow: 0) == ["shorts1", "videos2", "shorts1", "videos2"])
    }

    // MARK: - Laid-out blocks stay put

    @Test func lateShortsGoBelowLaidOutBlocks() {
        var layout = HomeFeedLayout()
        let before = segments(layout, shorts: 3, videos: 16, columns: 2, shortsPerRow: 3)
        #expect(shape(before) == ["shorts3", "videos4", "videos4", "videos4", "videos4"])
        layout.markLaidOut(block: 2, in: before)

        let after = segments(layout, shorts: 9, videos: 16, columns: 2, shortsPerRow: 3)
        // Blocks 0–2 were seen: the new rows start in front of block 3, nothing above moves.
        #expect(shape(after) == ["shorts3", "videos4", "videos4", "videos4", "shorts3", "videos4"])
        #expect(Array(after.prefix(4)) == Array(before.prefix(4)))
    }

    @Test func settledRowsKeepTheirBlockAsTheFeedGrows() {
        var layout = HomeFeedLayout()
        let first = segments(layout, shorts: 4, videos: 8, columns: 2, shortsPerRow: 2)
        layout.markLaidOut(block: 1, in: first)
        let grown = segments(layout, shorts: 20, videos: 24, columns: 2, shortsPerRow: 2)
        #expect(Array(grown.prefix(first.count)) == first)
        #expect(grown.filter { $0.kind == .shorts }.count == 6)

        // The mark never moves back.
        layout.markLaidOut(block: 0, in: grown)
        #expect(layout.laidOutThrough == 1)
    }

    @Test func shortsWantedCountsOnlyBlocksThatCanStillTakeARow() {
        var layout = HomeFeedLayout()
        #expect(layout.shortsWanted(through: 2, shortsPerRow: 10) == 30)

        // One row was placed, blocks 1–3 were laid out without one: they never get a row.
        layout.markLaidOut(block: 3, in: segments(layout, shorts: 10, videos: 40, columns: 2, shortsPerRow: 10))
        #expect(layout.shortsWanted(through: 3, shortsPerRow: 10) == 10)
        #expect(layout.shortsWanted(through: 5, shortsPerRow: 10) == 30)
    }
}
