import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - FeedHideNotificationTests
//
// Verifies that SearchViewModel, ChannelViewModel, and PlaylistViewModel
// all remove the relevant videos when .hideVideoFromFeed and
// .hideChannelFromFeed notifications fire (task #216).

private func makeVideo(id: String, channelId: String = "ch_default") -> Video {
    Video(id: id, title: "Video \(id)", channelTitle: "Channel", channelId: channelId)
}

private func postHideVideo(id: String) {
    NotificationCenter.default.post(
        name: .hideVideoFromFeed,
        object: nil,
        userInfo: ["videoId": id]
    )
}

private func postHideChannel(id: String) {
    NotificationCenter.default.post(
        name: .hideChannelFromFeed,
        object: nil,
        userInfo: ["channelId": id]
    )
}

/// Yields until the observer has processed the expected change, with a failure deadline.
@MainActor
private func waitForObserver(until condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline {
        await Task.yield()
    }
}

/// Posts `.hideVideoFromFeed` and waits for the ViewModel's notification
/// observer task to process it before returning.
@MainActor
private func postHideVideoAndWait(id: String, until removed: @MainActor () -> Bool) async {
    postHideVideo(id: id)
    await waitForObserver(until: removed)
}

/// Posts `.hideChannelFromFeed` and waits for the ViewModel's notification
/// observer task to process it before returning.
@MainActor
private func postHideChannelAndWait(id: String, until removed: @MainActor () -> Bool) async {
    postHideChannel(id: id)
    await waitForObserver(until: removed)
}

// MARK: - SearchViewModel

@Suite("SearchViewModel feed hide notifications")
@MainActor
struct SearchViewModelFeedHideTests {

    private func makeVM(videos: [Video]) -> SearchViewModel {
        let mock = MockInnerTubeAPI()
        mock.searchResult = VideoGroup(title: "Results", videos: videos)
        return SearchViewModel(
            api: mock,
            historyStore: SearchHistoryStore(suiteName: "test-\(UUID().uuidString)")
        )
    }

    private func loadedVM(videos: [Video]) async throws -> SearchViewModel {
        let vm = makeVM(videos: videos)
        vm.query = "test query"
        vm.search()
        let deadline = Date().addingTimeInterval(2)
        while vm.results.isEmpty && Date() < deadline {
            await Task.yield()
        }
        return vm
    }

    @Test("hideVideoFromFeed removes matching video from search results")
    func hideVideoRemovesFromResults() async throws {
        let id1 = "search-hide-video-keep-\(UUID().uuidString)"
        let id2 = "search-hide-video-remove-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: id2),
            makeVideo(id: id1),
        ])
        #expect(vm.results.count == 2)

        await postHideVideoAndWait(id: id2) { vm.results.count == 1 }

        #expect(vm.results.count == 1)
        #expect(vm.results.first?.id == id1)
    }

    @Test("hideVideoFromFeed with unknown id does not change results")
    func hideVideoUnknownIdNoChange() async throws {
        let id = "search-no-change-\(UUID().uuidString)"
        let marker = "search-marker-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [makeVideo(id: id), makeVideo(id: marker)])

        postHideVideo(id: "search-unknown-\(UUID().uuidString)")
        // The same observer processes the marker after the unknown ID.
        await postHideVideoAndWait(id: marker) { !vm.results.contains { $0.id == marker } }

        #expect(vm.results.map(\.id) == [id])
    }

    @Test("hideChannelFromFeed removes all videos from that channel")
    func hideChannelRemovesAllFromChannel() async throws {
        let channel1 = "search-ch-remove-\(UUID().uuidString)"
        let channel2 = "search-ch-keep-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: "va-\(UUID().uuidString)", channelId: channel1),
            makeVideo(id: "vb-\(UUID().uuidString)", channelId: channel1),
            makeVideo(id: "vc-\(UUID().uuidString)", channelId: channel2),
        ])
        #expect(vm.results.count == 3)

        await postHideChannelAndWait(id: channel1) { vm.results.count == 1 }

        #expect(vm.results.count == 1)
        #expect(vm.results.first?.channelId == channel2)
    }

    @Test("hideChannelFromFeed with unknown channelId does not change results")
    func hideChannelUnknownIdNoChange() async throws {
        let channel = "search-ch-safe-\(UUID().uuidString)"
        let markerChannel = "search-marker-channel-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: "vd-\(UUID().uuidString)", channelId: channel),
            makeVideo(id: "marker-\(UUID().uuidString)", channelId: markerChannel),
        ])

        postHideChannel(id: "search-unknown-ch-\(UUID().uuidString)")
        // Wait for a following notification on the same observer.
        await postHideChannelAndWait(id: markerChannel) { !vm.results.contains { $0.channelId == markerChannel } }

        #expect(vm.results.map(\.channelId) == [channel])
    }
}

// MARK: - ChannelViewModel

@Suite("ChannelViewModel feed hide notifications")
@MainActor
struct ChannelViewModelFeedHideTests {

    private func loadedVM(videos: [Video]) async throws -> ChannelViewModel {
        let mock = MockInnerTubeAPI()
        mock.channelResult = (
            Channel(id: "ch_root", title: "Root Channel"),
            VideoGroup(title: "Videos", videos: videos)
        )
        let vm = ChannelViewModel(api: mock)
        vm.load(channelId: "ch_root")
        let deadline = Date().addingTimeInterval(2)
        while vm.videos.isEmpty && Date() < deadline {
            await Task.yield()
        }
        return vm
    }

    @Test("hideVideoFromFeed removes matching video from channel videos")
    func hideVideoRemovesFromChannelVideos() async throws {
        let id1 = "ch-keep-\(UUID().uuidString)"
        let id2 = "ch-remove-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: id2),
            makeVideo(id: id1),
        ])
        #expect(vm.videos.count == 2)

        await postHideVideoAndWait(id: id2) { vm.videos.count == 1 }

        #expect(vm.videos.count == 1)
        #expect(vm.videos.first?.id == id1)
    }

    @Test("hideChannelFromFeed removes all videos matching channelId")
    func hideChannelRemovesAllFromChannelVideos() async throws {
        let ch1 = "chvm-remove-\(UUID().uuidString)"
        let ch2 = "chvm-keep-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: "va-\(UUID().uuidString)", channelId: ch1),
            makeVideo(id: "vb-\(UUID().uuidString)", channelId: ch2),
        ])
        #expect(vm.videos.count == 2)

        await postHideChannelAndWait(id: ch1) { vm.videos.count == 1 }

        #expect(vm.videos.count == 1)
        #expect(vm.videos.first?.channelId == ch2)
    }
}

// MARK: - PlaylistViewModel

private struct EmptyQueueLoader: QueuedPlaylistLoader {
    func loadQueuedVideos(for playlistId: String) async -> [Video]? { nil }
}

@Suite("PlaylistViewModel feed hide notifications")
@MainActor
struct PlaylistViewModelFeedHideTests {

    private func loadedVM(videos: [Video]) async throws -> PlaylistViewModel {
        let mock = MockInnerTubeAPI()
        mock.playlistVideosResult = VideoGroup(title: "Playlist", videos: videos)
        let vm = PlaylistViewModel(api: mock, queueLoader: EmptyQueueLoader())
        vm.load(playlistId: "pl_test_123")
        let deadline = Date().addingTimeInterval(2)
        while vm.videos.isEmpty && Date() < deadline {
            await Task.yield()
        }
        return vm
    }

    @Test("hideVideoFromFeed removes matching video from playlist videos")
    func hideVideoRemovesFromPlaylist() async throws {
        let id1 = "pl-keep-\(UUID().uuidString)"
        let id2 = "pl-remove-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: id2),
            makeVideo(id: id1),
        ])
        #expect(vm.videos.count == 2)

        await postHideVideoAndWait(id: id2) { vm.videos.count == 1 }

        #expect(vm.videos.count == 1)
        #expect(vm.videos.first?.id == id1)
    }

    @Test("hideChannelFromFeed removes all videos from that channel in playlist")
    func hideChannelRemovesFromPlaylist() async throws {
        let ch1 = "plch-remove-\(UUID().uuidString)"
        let ch2 = "plch-keep-\(UUID().uuidString)"
        let vm = try await loadedVM(videos: [
            makeVideo(id: "va-\(UUID().uuidString)", channelId: ch1),
            makeVideo(id: "vb-\(UUID().uuidString)", channelId: ch1),
            makeVideo(id: "vc-\(UUID().uuidString)", channelId: ch2),
        ])
        #expect(vm.videos.count == 3)

        await postHideChannelAndWait(id: ch1) { vm.videos.count == 1 }

        #expect(vm.videos.count == 1)
        #expect(vm.videos.first?.channelId == ch2)
    }
}

// MARK: - AppSettings blockedChannels persistence

@Suite("AppSettings blockedChannels")
struct AppSettingsBlockedChannelsTests {

    @Test("blockedChannels defaults to empty")
    func defaultsToEmpty() {
        let settings = AppSettings()
        #expect(settings.blockedChannels.isEmpty)
    }

    @Test("blockedChannels encodes and decodes correctly")
    func encodeDecode() throws {
        var settings = AppSettings()
        settings.blockedChannels = ["ch_1": "Cool Channel", "ch_2": "Another Channel"]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.blockedChannels["ch_1"] == "Cool Channel")
        #expect(decoded.blockedChannels["ch_2"] == "Another Channel")
        #expect(decoded.blockedChannels.count == 2)
    }

    @Test("blockedChannels missing from JSON decodes to empty (migration safe)")
    func missingKeyDecodesToEmpty() throws {
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(decoded.blockedChannels.isEmpty)
    }
}
