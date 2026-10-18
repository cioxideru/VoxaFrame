import Foundation
import SwiftUI
import Testing

@testable import SmartTubeIOSCore

// MARK: - CurrentQueueStoreTests
//
// Uses an isolated UserDefaults suite per test to avoid cross-test pollution.
// Mirrors VideoStateStoreTests patterns exactly.

@Suite("Current Queue Store")
struct CurrentQueueStoreTests {

    // MARK: - Helpers

    private func makeStore() -> CurrentQueueStore {
        CurrentQueueStore(suiteName: "test-\(UUID().uuidString)")
    }

    private func makeVideo(id: String) -> Video {
        Video(id: id, title: "Video \(id)", channelTitle: "Channel")
    }

    // MARK: - Append & tag

    @Test("Appended video receives queue playlistId")
    func appendTagsPlaylistId() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        let v = await store.videoAt(index: 0)
        #expect(v?.playlistId == CurrentQueueStore.playlistID)
    }

    @Test("Appended video receives correct playlistIndex")
    func appendTagsPlaylistIndex() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        let v = await store.videoAt(index: 0)
        #expect(v?.playlistIndex == 0)
    }

    @Test("Three appended videos receive sequential playlistIndex values")
    func appendThreeIndexed() async {
        let store = makeStore()
        for id in ["aaa11111111", "bbb22222222", "ccc33333333"] {
            await store.append(makeVideo(id: id))
        }
        for i in 0..<3 {
            #expect(await store.videoAt(index: i)?.playlistIndex == i)
        }
    }

    @Test("videos.count increases with each append")
    func appendIncreasesCount() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "bbb22222222"))
        let count = await store.videos.count
        #expect(count == 2)
    }

    // MARK: - insertNext

    @Test("insertNext inserts video after specified index")
    func insertNextAfterIndex() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "ccc33333333"))
        await store.insertNext(makeVideo(id: "bbb22222222"), afterIndex: 0)
        let count = await store.videos.count
        #expect(count == 3)
        #expect(await store.videos[1].id == "bbb22222222")
    }

    @Test("insertNext with afterIndex -1 inserts at position 0")
    func insertNextAtStart() async {
        let store = makeStore()
        await store.append(makeVideo(id: "bbb22222222"))
        await store.insertNext(makeVideo(id: "aaa11111111"), afterIndex: -1)
        #expect(await store.videos[0].id == "aaa11111111")
    }

    // MARK: - playNext (Play Next after the playing item)

    private func makeQueue(_ ids: [String]) async -> CurrentQueueStore {
        let store = makeStore()
        await store.replaceAll(with: ids.map(makeVideo(id:)))
        return store
    }

    @Test("Play Next with nothing playing from the queue puts the video first")
    func playNextNothingPlaying() async {
        let store = await makeQueue(["a", "b", "c"])
        await store.playNext(makeVideo(id: "new"), playingIndex: nil)
        #expect(await store.videos.map(\.id) == ["new", "a", "b", "c"])
    }

    @Test("Play Next into an empty queue makes it the only item")
    func playNextEmptyQueue() async {
        let store = makeStore()
        await store.playNext(makeVideo(id: "new"), playingIndex: nil)
        #expect(await store.videos.map(\.id) == ["new"])
    }

    @Test("Play Next goes right after the playing item (first, middle, last)", arguments: [0, 1, 2])
    func playNextAfterPlaying(playing: Int) async {
        let store = await makeQueue(["a", "b", "c"])
        await store.playNext(makeVideo(id: "new"), playingIndex: playing)
        let ids = await store.videos.map(\.id)
        #expect(ids.count == 4)
        #expect(ids.firstIndex(of: "new") == playing + 1)
        #expect(ids.filter { $0 != "new" } == ["a", "b", "c"])
    }

    @Test("Play Next while the last item plays appends, and a stale index past the end appends too")
    func playNextLastAndStale() async {
        let store = await makeQueue(["a", "b"])
        await store.playNext(makeVideo(id: "last"), playingIndex: 1)
        await store.playNext(makeVideo(id: "stale"), playingIndex: 40)
        #expect(await store.videos.map(\.id) == ["a", "b", "last", "stale"])
    }

    @Test("Play Next keeps the playing item's index valid for the player's next step")
    func playNextIsNextForPlayer() async {
        let store = await makeQueue(["a", "b", "c"])
        let playing = await store.videoAt(index: 1)
        await store.playNext(makeVideo(id: "new"), playingIndex: CurrentQueueStore.queueIndex(of: playing))
        #expect(await store.videoAt(index: 1)?.id == "b")
        #expect(await store.videoAt(index: 2)?.id == "new")
    }

    @Test("Play Next of a video already queued changes nothing")
    func playNextDuplicate() async {
        let store = await makeQueue(["a", "b", "c"])
        await store.playNext(makeVideo(id: "c"), playingIndex: 0)
        await store.playNext(makeVideo(id: "a"), playingIndex: nil)
        #expect(await store.videos.map(\.id) == ["a", "b", "c"])
    }

    @Test("Play Next into a full queue is ignored")
    func playNextAtCapacity() async {
        let store = await makeQueue((0..<500).map { String(format: "v%011d", $0) })
        await store.playNext(makeVideo(id: "new"), playingIndex: nil)
        await store.playNext(makeVideo(id: "new"), playingIndex: 3)
        let ids = await store.videos.map(\.id)
        #expect(ids.count == 500)
        #expect(!ids.contains("new"))
    }

    @Test("queueIndex reads the position only from Current Queue items")
    func queueIndexOfVideo() async {
        let store = await makeQueue(["a", "b"])
        #expect(CurrentQueueStore.queueIndex(of: await store.videoAt(index: 1)) == 1)
        var fromPlaylist = makeVideo(id: "a")
        fromPlaylist.playlistId = "PL123"
        fromPlaylist.playlistIndex = 4
        #expect(CurrentQueueStore.queueIndex(of: fromPlaylist) == nil)
        #expect(CurrentQueueStore.queueIndex(of: makeVideo(id: "a")) == nil)
        #expect(CurrentQueueStore.queueIndex(of: nil) == nil)
    }

    // MARK: - remove

    @Test("remove(at:) shrinks the queue")
    func removeShrinksQueue() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "bbb22222222"))
        await store.remove(at: 0)
        let count = await store.videos.count
        #expect(count == 1)
        #expect(await store.videos[0].id == "bbb22222222")
    }

    @Test("remove(at:) with out-of-range index does not crash")
    func removeOutOfRangeNoCrash() async {
        let store = makeStore()
        await store.remove(at: 99)  // passes if no crash
    }

    // MARK: - move

    @Test("move(from:to:) reorders videos")
    func moveReorders() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "bbb22222222"))
        await store.append(makeVideo(id: "ccc33333333"))
        await store.move(from: IndexSet(integer: 0), to: 3)  // move first to last
        #expect(await store.videos[0].id == "bbb22222222")
        #expect(await store.videos[2].id == "aaa11111111")
    }

    @Test("Queue moves match SwiftUI for every selection and insertion position")
    func moveMatchesSwiftUI() async {
        let original = (0..<5).map { makeVideo(id: "video-\($0)") }
        let store = makeStore()
        for mask in 0..<(1 << original.count) {
            let source = IndexSet(original.indices.filter { mask & (1 << $0) != 0 })
            for destination in 0...original.count {
                var expected = original
                expected.move(fromOffsets: source, toOffset: destination)
                await store.replaceAll(with: original)
                await store.move(from: source, to: destination)
                #expect(await store.videos == expected)
            }
        }
    }

    // MARK: - clear

    @Test("clear() empties the queue")
    func clearEmptiesQueue() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.clear()
        let count = await store.videos.count
        #expect(count == 0)
    }

    @Test("clear() on already-empty queue does not crash")
    func clearEmptyNoCrash() async {
        let store = makeStore()
        await store.clear()  // passes if no crash
    }

    // MARK: - videoAt

    @Test("videoAt(index:) returns nil for out-of-range index")
    func videoAtOutOfRange() async {
        let store = makeStore()
        let v = await store.videoAt(index: 99)
        #expect(v == nil)
    }

    @Test("videoAt(index:) returns nil on empty queue")
    func videoAtEmptyQueue() async {
        let store = makeStore()
        let v = await store.videoAt(index: 0)
        #expect(v == nil)
    }

    // MARK: - asPlaylistInfo

    @Test("asPlaylistInfo uses the reserved playlistID")
    func asPlaylistInfoId() async {
        let store = makeStore()
        let info = await store.asPlaylistInfo
        #expect(info.id == CurrentQueueStore.playlistID)
    }

    @Test("asPlaylistInfo reflects current video count")
    func asPlaylistInfoVideoCount() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "bbb22222222"))
        let info = await store.asPlaylistInfo
        #expect(info.videoCount == 2)
    }

    @Test("asPlaylistInfo thumbnailURL matches first video's thumbnailURL")
    func asPlaylistInfoThumbnail() async {
        let store = makeStore()
        let v = makeVideo(id: "aaa11111111")
        await store.append(v)
        let info = await store.asPlaylistInfo
        #expect(info.thumbnailURL == v.thumbnailURL)
    }

    // MARK: - Persistence

    @Test("Persistence round-trip restores videos in order")
    func persistenceRoundTrip() async {
        let suiteName = "test-\(UUID().uuidString)"
        let storeA = CurrentQueueStore(suiteName: suiteName)
        await storeA.append(makeVideo(id: "aaa11111111"))
        await storeA.append(makeVideo(id: "bbb22222222"))

        let storeB = CurrentQueueStore(suiteName: suiteName)
        let count = await storeB.videos.count
        #expect(count == 2)
        #expect(await storeB.videos[0].id == "aaa11111111")
        #expect(await storeB.videos[1].id == "bbb22222222")
    }

    @Test("clear() removes persisted data so a new store starts empty")
    func clearRemovesPersistence() async {
        let suiteName = "test-\(UUID().uuidString)"
        let storeA = CurrentQueueStore(suiteName: suiteName)
        await storeA.append(makeVideo(id: "aaa11111111"))
        await storeA.clear()

        let storeB = CurrentQueueStore(suiteName: suiteName)
        let count = await storeB.videos.count
        #expect(count == 0)
    }

    // MARK: - Duplicate guard

    @Test("Appending the same video ID twice keeps count at 1")
    func appendDuplicateIgnored() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "aaa11111111"))
        let count = await store.videos.count
        #expect(count == 1)
    }

    @Test("insertNext with duplicate ID is a no-op")
    func insertNextDuplicateIgnored() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.insertNext(makeVideo(id: "aaa11111111"), afterIndex: 0)
        let count = await store.videos.count
        #expect(count == 1)
    }

    // MARK: - Capacity

    @Test("Appending beyond maxCount is silently ignored")
    func maxCountEnforced() async {
        let store = makeStore()
        for i in 0..<501 {
            await store.append(makeVideo(id: String(format: "v%011d", i)))
        }
        let count = await store.videos.count
        #expect(count == 500)
    }

    // MARK: - replaceAll

    @Test("replaceAll replaces existing videos with new set")
    func replaceAllReplacesAllVideos() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        await store.append(makeVideo(id: "bbb22222222"))
        await store.append(makeVideo(id: "ccc33333333"))
        let newVideos = [makeVideo(id: "ddd44444444"), makeVideo(id: "eee55555555")]
        await store.replaceAll(with: newVideos)
        let count = await store.videos.count
        #expect(count == 2)
        #expect(await store.videos[0].id == "ddd44444444")
        #expect(await store.videos[1].id == "eee55555555")
    }

    @Test("replaceAll assigns correct playlistIndex via videoAt")
    func replaceAllAssignsCorrectPlaylistIndexViaVideoAt() async {
        let store = makeStore()
        let v0 = makeVideo(id: "aaa11111111")
        let v1 = makeVideo(id: "bbb22222222")
        let v2 = makeVideo(id: "ccc33333333")
        await store.replaceAll(with: [v0, v1, v2])
        let queued = await store.videoAt(index: 1)
        #expect(queued?.playlistIndex == 1)
        #expect(queued?.playlistId == CurrentQueueStore.playlistID)
    }

    @Test("replaceAll respects maxCount")
    func replaceAllRespectsMaxCount() async {
        let store = makeStore()
        let videos = (0..<501).map { makeVideo(id: String(format: "v%011d", $0)) }
        await store.replaceAll(with: videos)
        let count = await store.videos.count
        #expect(count == 500)
    }

    @Test("replaceAll allows duplicate video IDs")
    func replaceAllAllowsDuplicateVideoIds() async {
        let store = makeStore()
        let v = makeVideo(id: "aaa11111111")
        await store.replaceAll(with: [v, v])
        let count = await store.videos.count
        #expect(count == 2)
    }

    @Test("queue populated from search results: videoAt returns queue-tagged video and next advances in order")
    func queueFromSearchResultsAdvancesInOrder() async {
        let store = makeStore()
        let videos = [
            makeVideo(id: "aaa11111111"),
            makeVideo(id: "bbb22222222"),
            makeVideo(id: "ccc33333333"),
        ]
        // Simulate SearchView.resultsView onSelect: replaceAll with visible results, play index 1
        await store.replaceAll(with: videos)
        let startIdx = videos.firstIndex(where: { $0.id == "bbb22222222" }) ?? 0
        let toPlay = await store.videoAt(index: startIdx)
        #expect(toPlay?.id == "bbb22222222")
        #expect(toPlay?.playlistId == CurrentQueueStore.playlistID)
        #expect(toPlay?.playlistIndex == 1)
        // Simulate handlePlaybackEnd: next video is index + 1
        let next = await store.videoAt(index: (toPlay?.playlistIndex ?? 0) + 1)
        #expect(next?.id == "ccc33333333")
        #expect(next?.playlistIndex == 2)
    }

    @Test("queue populated from search results: videoAt tags video with queue playlistId not raw search playlistId")
    func queueFromSearchResultsUsesQueuePlaylistId() async {
        let store = makeStore()
        var v = makeVideo(id: "aaa11111111")
        v.playlistId = "some_raw_playlist_id"  // as if fetched from YouTube search
        await store.replaceAll(with: [v])
        let queued = await store.videoAt(index: 0)
        #expect(queued?.playlistId == CurrentQueueStore.playlistID)
    }

    // MARK: - remainingVideos(after:)

    @Test("remainingVideos: empty queue returns empty array")
    func remainingVideosEmptyQueue() async {
        let store = makeStore()
        let result = await store.remainingVideos(after: 0)
        #expect(result.isEmpty)
    }

    @Test("remainingVideos: after last index returns empty array")
    func remainingVideosAfterLastIndex() async {
        let store = makeStore()
        for id in ["aaa11111111", "bbb22222222", "ccc33333333"] {
            await store.append(makeVideo(id: id))
        }
        let result = await store.remainingVideos(after: 2)
        #expect(result.isEmpty)
    }

    @Test("remainingVideos: after out-of-bounds index returns empty array")
    func remainingVideosOutOfBounds() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        let result = await store.remainingVideos(after: 99)
        #expect(result.isEmpty)
    }

    @Test("remainingVideos: returns correct slice from middle of queue")
    func remainingVideosMiddleSlice() async {
        let store = makeStore()
        for id in ["aaa11111111", "bbb22222222", "ccc33333333", "ddd44444444"] {
            await store.append(makeVideo(id: id))
        }
        let result = await store.remainingVideos(after: 1)
        #expect(result.count == 2)
        #expect(result[0].id == "ccc33333333")
        #expect(result[1].id == "ddd44444444")
    }

    @Test("remainingVideos: all returned videos have queue playlistId")
    func remainingVideosTaggedWithPlaylistId() async {
        let store = makeStore()
        for id in ["aaa11111111", "bbb22222222", "ccc33333333"] {
            await store.append(makeVideo(id: id))
        }
        let result = await store.remainingVideos(after: 0)
        #expect(result.allSatisfy { $0.playlistId == CurrentQueueStore.playlistID })
    }

    @Test("remainingVideos: returned videos carry correct sequential playlistIndex values")
    func remainingVideosPlaylistIndexTags() async {
        let store = makeStore()
        for id in ["aaa11111111", "bbb22222222", "ccc33333333", "ddd44444444"] {
            await store.append(makeVideo(id: id))
        }
        let result = await store.remainingVideos(after: 1)
        // after index 1, videos are at original positions 2 and 3
        #expect(result[0].playlistIndex == 2)
        #expect(result[1].playlistIndex == 3)
    }

    @Test("remainingVideos: single-video queue returns empty (no video after last)")
    func remainingVideosSingleVideoQueue() async {
        let store = makeStore()
        await store.append(makeVideo(id: "aaa11111111"))
        let result = await store.remainingVideos(after: 0)
        #expect(result.isEmpty)
    }
}
