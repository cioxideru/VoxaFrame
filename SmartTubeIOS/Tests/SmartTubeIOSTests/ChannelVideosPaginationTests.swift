import Foundation
import Testing

@testable import SmartTubeIOSCore

// A channel's video list stopped after the first page (upstream #138): the Home tab's continuation
// tokens are per shelf and return no videos. The list pages the Videos tab; Shorts come from Home.

@Suite("Channel Videos tab pagination")
@MainActor
struct ChannelVideosPaginationTests {

    private struct FetchFailure: Error {}

    private func video(_ id: String, isShort: Bool = false) -> Video {
        Video(id: id, title: "Video \(id)", channelTitle: "Channel", isShort: isShort)
    }

    private func loadedViewModel(
        channelId: String = "UCchannel", home: [Video], videosTab: VideoGroup, videosTabError: Error? = nil
    ) async -> (ChannelViewModel, MockInnerTubeAPI) {
        let mock = MockInnerTubeAPI()
        mock.channelResult = (
            Channel(id: "UCchannel", title: "Channel"),
            VideoGroup(title: "Home", videos: home, nextPageToken: "home_shelf_token")
        )
        mock.channelVideosResult = videosTab
        mock.channelVideosError = videosTabError
        let vm = ChannelViewModel(api: mock)
        await vm.loadAsync(channelId: channelId)
        return (vm, mock)
    }

    @Test("The first page comes from the Videos tab, not the Home shelves")
    func firstPageFromVideosTab() async {
        let (vm, mock) = await loadedViewModel(
            home: [video("homeOnly")],
            videosTab: VideoGroup(title: "V", videos: [video("grid1"), video("grid2")], nextPageToken: "grid_p2"))

        #expect(vm.videos.map(\.id) == ["grid1", "grid2"])
        #expect(mock.calls.filter { $0.method == "fetchChannelVideos" }.map(\.args) == [["UCchannel", "nil"]])
    }

    @Test("Load more sends the Videos tab token, never the Home shelf token")
    func loadMoreUsesVideosTabToken() async {
        let (vm, mock) = await loadedViewModel(
            home: [video("homeOnly")],
            videosTab: VideoGroup(title: "V", videos: [video("grid1")], nextPageToken: "grid_p2"))

        mock.channelVideosResult = VideoGroup(title: "V", videos: [video("grid2")], nextPageToken: "grid_p3")
        await vm.loadMoreAsync()
        mock.channelVideosResult = VideoGroup(title: "V", videos: [video("grid3")])
        await vm.loadMoreAsync()

        #expect(vm.videos.map(\.id) == ["grid1", "grid2", "grid3"])
        #expect(
            mock.calls.filter { $0.method == "fetchChannelVideos" }.map { $0.args[1] } == ["nil", "grid_p2", "grid_p3"])
        #expect(!mock.calls.contains { $0.args.contains("home_shelf_token") })
    }

    @Test("Shorts from the Home shelf back the Shorts filter, not the paged list")
    func shortsFromHome() async {
        let (vm, _) = await loadedViewModel(
            home: [video("homeShort", isShort: true), video("homeVideo")],
            videosTab: VideoGroup(title: "V", videos: [video("grid1")], nextPageToken: "grid_p2"))

        #expect(vm.shorts.map(\.id) == ["homeShort"])
        #expect(vm.videos.map(\.id) == ["grid1"])
    }

    @Test("An empty Videos tab falls back to the Home videos")
    func emptyVideosTabFallsBack() async {
        let (vm, _) = await loadedViewModel(home: [video("homeVideo")], videosTab: VideoGroup(title: "V", videos: []))

        #expect(vm.videos.map(\.id) == ["homeVideo"])
    }

    @Test("A failing Videos tab shows the Home page without an error")
    func failingVideosTabFallsBack() async {
        let (vm, _) = await loadedViewModel(
            home: [video("homeVideo"), video("homeShort", isShort: true)],
            videosTab: VideoGroup(title: "V", videos: []), videosTabError: FetchFailure())

        #expect(vm.videos.map(\.id) == ["homeVideo", "homeShort"])
        #expect(vm.shorts.map(\.id) == ["homeShort"])
        #expect(vm.error == nil)
    }

    @Test("A handle requests the Videos tab with the resolved channel ID")
    func handleUsesResolvedID() async {
        let (vm, mock) = await loadedViewModel(
            channelId: "@channel", home: [],
            videosTab: VideoGroup(title: "V", videos: [video("grid1")]))

        #expect(vm.videos.map(\.id) == ["grid1"])
        #expect(mock.calls.filter { $0.method == "fetchChannelVideos" }.map(\.args) == [["UCchannel", "nil"]])
    }
}
