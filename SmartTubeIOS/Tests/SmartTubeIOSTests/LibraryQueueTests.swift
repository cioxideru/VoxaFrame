import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - LibraryQueueTests (PLAN-0027 A1, A4, B3)
//
// Library segments: the Queue is always there and reads the store, not the browse feed (A1);
// a guest gets History, only Playlists asks to sign in (A4); the queue screen reloads empty
// after Clear Queue is confirmed (B3).

@Suite("Library sections and the queue screen")
struct LibraryQueueTests {
    private typealias Section = LibraryView.LibrarySection

    @Test("Queue is a segment on every platform, between Playlists and RSS")
    func queueSegment() throws {
        let cases = Section.allCases
        let playlists = try #require(cases.firstIndex(of: .playlists))
        #expect(cases[playlists + 1] == .queue)
        #expect(cases[playlists + 2] == .rss)
        // Raw values stay the UI-test identifiers.
        #expect(Section.subscriptions.rawValue == "Subs")
        #expect(Section.rss.rawValue == "RSS Feeds")
    }

    @Test("Only the browse segments load the browse feed; the queue has its own source")
    func queueIsNotABrowseFeed() {
        #expect(Section.queue.browseSection == nil)
        #expect(Section.rss.browseSection == nil)
        #expect(Section.downloads.browseSection == nil)
        #expect(Section.subscriptions.browseSection?.type == .subscriptions)
        #expect(Section.history.browseSection?.type == .history)
        #expect(Section.playlists.browseSection?.type == .playlists)
    }

    @Test("A guest sees History and the Queue; only Playlists asks to sign in")
    func guestAccess() {
        #expect(Section.allCases.filter(\.requiresSignIn) == [.playlists])
    }

    @Test("The queue screen reads the store in order, tagged with queue positions")
    func queueReadsStore() async {
        let store = CurrentQueueStore(suiteName: "queue-screen-\(UUID().uuidString)")
        await store.replaceAll(with: [makeVideo("a"), makeVideo("b"), makeVideo("a")])
        let loader = CurrentQueuePlaylistLoader(store: store)

        let videos = await loader.loadQueuedVideos(for: CurrentQueueStore.playlistID)

        #expect(videos?.map(\.id) == ["a", "b", "a"])
        #expect(videos?.map(\.playlistIndex) == [0, 1, 2])
        #expect(videos?.allSatisfy { $0.playlistId == CurrentQueueStore.playlistID } == true)
    }

    @MainActor
    @Test("The queue screen's model drops Not Interested videos and Don't Recommend channels")
    func queueScreenHidesFeedRemovals() async {
        let store = CurrentQueueStore(suiteName: "queue-hide-\(UUID().uuidString)")
        let id = UUID().uuidString  // other suites post hide notifications for their own ids
        var other = makeVideo("\(id)-c")
        other.channelId = "\(id)-channel"
        await store.replaceAll(with: [makeVideo("\(id)-a"), makeVideo("\(id)-b"), other])
        let vm = PlaylistViewModel(api: MockInnerTubeAPI(), queueLoader: CurrentQueuePlaylistLoader(store: store))

        await vm.refresh(playlistId: CurrentQueueStore.playlistID)
        #expect(vm.videos.count == 3)
        NotificationCenter.default.post(name: .hideVideoFromFeed, object: nil, userInfo: ["videoId": "\(id)-a"])
        await waitForTasks { vm.videos.count == 2 }
        NotificationCenter.default.post(
            name: .hideChannelFromFeed, object: nil, userInfo: ["channelId": "\(id)-channel"])
        await waitForTasks { vm.videos.count == 1 }
        #expect(vm.videos.map(\.id) == ["\(id)-b"])
    }

    @Test("Playing from the queue screen hands over the visible list: Next skips the hidden video")
    func playSkipsHiddenVideos() async {
        let store = CurrentQueueStore(suiteName: "queue-play-\(UUID().uuidString)")
        await store.replaceAll(with: [makeVideo("a"), makeVideo("hidden"), makeVideo("c")])
        let loader = CurrentQueuePlaylistLoader(store: store)
        let stored = await loader.loadQueuedVideos(for: CurrentQueueStore.playlistID) ?? []
        #expect(await loader.storedCount() == 3)

        let visible = stored.filter { $0.id != "hidden" }  // e.g. Not Interested or Hide Shorts
        let playing = await loader.play(visible[0], from: visible)

        #expect(playing.id == "a")
        #expect(playing.playlistIndex == 0)
        let next = await store.videoAt(index: (playing.playlistIndex ?? 0) + 1)
        #expect(next?.id == "c")
        #expect(await store.videos.map(\.id) == ["a", "c"])
        // The selected position is kept, also for a later item.
        #expect(await loader.play(visible[1], from: visible).playlistIndex == 1)
    }

    @Test("After a confirmed Clear Queue the screen reloads empty")
    func reloadAfterClear() async {
        let store = CurrentQueueStore(suiteName: "queue-clear-\(UUID().uuidString)")
        await store.replaceAll(with: [makeVideo("a")])
        let loader = CurrentQueuePlaylistLoader(store: store)

        await store.clear()

        #expect(await loader.loadQueuedVideos(for: CurrentQueueStore.playlistID) == [])
    }
}
