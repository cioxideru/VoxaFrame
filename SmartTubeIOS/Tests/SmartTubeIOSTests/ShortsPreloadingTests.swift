import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class PreparedTestItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

@MainActor
private final class ControlledShortsPreparer: ShortsStreamPreparing {
    struct Request {
        let video: Video
        let preference: ShortsStreamPreference
        let continuation: CheckedContinuation<PreparedShort, any Error>
    }
    var requests: [Request] = []

    func prepare(video: Video, preference: ShortsStreamPreference) async throws -> PreparedShort {
        try await withCheckedThrowingContinuation {
            requests.append(Request(video: video, preference: preference, continuation: $0))
        }
    }

    func finish(_ index: Int) -> AVPlayerItem {
        let request = requests[index]
        let item = PreparedTestItem(asset: AVMutableComposition())
        let info = PlayerInfo(
            video: request.video, formats: [], hlsURL: nil, dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])
        request.continuation.resume(
            returning: PreparedShort(
                info: info, item: item,
                preference: request.preference, formats: [], variants: [:], proxy: nil,
                warmingPlayer: AVPlayer(playerItem: item)))
        return item
    }
}

@Suite("Shorts preload ownership (PLAN-0015)")
@MainActor
struct ShortsPreloadingTests {
    private func video(_ id: String) -> Video {
        Video(id: id, title: id, channelTitle: "Test", isShort: true)
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(predicate())
    }

    private func queue() -> AVQueuePlayer {
        let player = AVQueuePlayer(playerItem: PreparedTestItem(asset: AVMutableComposition()))
        player.actionAtItemEnd = .pause
        return player
    }

    @Test func promotionReusesTheItemAndRepeatedRequestsCoalesce() async throws {
        let player = queue()
        let preparer = ControlledShortsPreparer()
        let preloader = ShortsPreloader(player: player, preparer: preparer)
        let next = video("next")
        for _ in 0..<100 { preloader.prepare(next, settings: AppSettings()) }
        try await eventually { preparer.requests.count == 1 }
        let item = preparer.finish(0)
        try await eventually { preloader.prepared != nil }
        #expect(player.currentItem !== item)
        let prepared = try #require(preloader.take(video: next, settings: AppSettings()))
        #expect(prepared.item === item)
        #expect(prepared.warmingPlayer.currentItem === item)
        #expect(player.items().count == 1)
        #expect(preloader.prepared == nil)
        #expect(player.rate == 0)
        player.removeAllItems()
    }

    @Test func viewModelTransfersAllPlaybackOwnersAndReleasesTheOutgoingItem() async throws {
        let vm = PlaybackViewModel(isShortsPlayer: true)
        vm.isIncognito = true
        let outgoing = vm.player
        outgoing.isMuted = true
        outgoing.replaceCurrentItem(with: PreparedTestItem(asset: AVMutableComposition()))
        let preparer = ControlledShortsPreparer()
        let preloader = ShortsPreloader(player: outgoing, preparer: preparer)
        vm.shortsPreloader = preloader
        let next = video("next")
        preloader.prepare(next, settings: vm.settings)
        try await eventually { preparer.requests.count == 1 }
        let item = preparer.finish(0)
        try await eventually { preloader.prepared != nil }
        let incoming = try #require(preloader.prepared?.warmingPlayer)
        vm.load(video: next, incognito: true)
        vm.loadTask?.cancel()
        #expect(vm.player === incoming)
        #expect(vm.player.currentItem === item)
        #expect(vm.player.isMuted)
        #expect(vm.audioManager.player === incoming)
        #expect(vm.qualityManager.player as AnyObject === incoming)
        #expect(vm.sponsorBlockManager.player as AnyObject === incoming)
        #expect(preloader.player === incoming)
        #expect(outgoing.currentItem == nil)
        #expect(outgoing.rate == 0)
        vm.stop()
    }

    @Test func lateCancelledPreparationCannotReplaceTheNewTarget() async throws {
        let player = queue()
        let preparer = ControlledShortsPreparer()
        let preloader = ShortsPreloader(player: player, preparer: preparer)
        preloader.prepare(video("old"), settings: AppSettings())
        try await eventually { preparer.requests.count == 1 }
        preloader.prepare(video("new"), settings: AppSettings())
        try await eventually { preparer.requests.count == 2 }
        let newest = preparer.finish(1)
        try await eventually { preloader.prepared != nil }
        _ = preparer.finish(0)
        preloader.prepare(video("new"), settings: AppSettings())
        await Task.yield()
        #expect(preloader.prepared?.item === newest)
        #expect(player.items().count == 1)
        preloader.cancel()
        #expect(player.items().count == 1)
        player.removeAllItems()
    }

    @Test(arguments: ["settings", "differentVideo", "expiry", "pressure", "cancel"])
    func invalidationReleasesQueuedMedia(reason: String) async throws {
        let player = queue()
        let preparer = ControlledShortsPreparer()
        let preloader = ShortsPreloader(player: player, preparer: preparer)
        let next = video("next")
        preloader.prepare(next, settings: AppSettings())
        try await eventually { preparer.requests.count == 1 }
        _ = preparer.finish(0)
        try await eventually { preloader.prepared != nil }
        switch reason {
        case "settings":
            var settings = AppSettings()
            settings.lastVideoQuality = .init(height: 360, codec: .h264)
            #expect(preloader.take(video: next, settings: settings) == nil)
        case "differentVideo":
            #expect(preloader.take(video: video("other"), settings: AppSettings()) == nil)
        case "expiry", "pressure": preloader.retention.releaseNow()
        default: preloader.cancel()
        }
        #expect(preloader.prepared == nil)
        #expect(player.items().count == 1)
        player.removeAllItems()
    }

    @Test func deadlineAndOwnerReleaseRejectLateResponses() async throws {
        let player = queue()
        let preparer = ControlledShortsPreparer()
        var preloader: ShortsPreloader? = ShortsPreloader(player: player, preparer: preparer)
        weak var reference = preloader
        preloader?.prepare(video("late"), settings: AppSettings())
        try await eventually { preparer.requests.count == 1 }
        preloader?.deadline.releaseNow()
        preloader = nil
        #expect(reference == nil)
        _ = preparer.finish(0)
        await Task.yield()
        #expect(player.items().count == 1)
        player.removeAllItems()
    }

    @Test func shortsDoesNotAccumulateRegularNavigationHistoryAndStopReleasesItems() {
        let vm = PlaybackViewModel(isShortsPlayer: true)
        for index in 0..<1_000 {
            vm.resetPlaybackForLoad(video: video("short-\(index)"), incognito: true)
        }
        #expect(vm.history.isEmpty)
        vm.player.replaceCurrentItem(with: PreparedTestItem(asset: AVMutableComposition()))
        vm.stop()
        #expect(vm.player.currentItem == nil)
    }

    @Test func closingSessionReleasesViewModelPreloaderAndBothNativeItems() async throws {
        let preparer = ControlledShortsPreparer()
        var vm: PlaybackViewModel? = PlaybackViewModel(isShortsPlayer: true)
        vm?.isIncognito = true
        vm?.player.replaceCurrentItem(with: PreparedTestItem(asset: AVMutableComposition()))
        weak var activeItem = vm?.player.currentItem
        weak var model = vm
        vm?.shortsPreloader = ShortsPreloader(player: try #require(vm?.player), preparer: preparer)
        weak var preloader = vm?.shortsPreloader
        vm?.shortsPreloader?.prepare(video("next"), settings: AppSettings())
        try await eventually { preparer.requests.count == 1 }
        weak var preparedItem = preparer.finish(0)
        try await eventually { vm?.shortsPreloader?.prepared != nil }
        vm?.stop()
        vm = nil
        try await eventually { model == nil && preloader == nil && activeItem == nil && preparedItem == nil }
    }
}

@Suite("Bounded Shorts feed window (PLAN-0015)")
struct ShortsFeedWindowTests {
    private func videos(_ range: Range<Int>) -> [Video] {
        range.map { Video(id: "short-\($0)", title: "Short", channelTitle: "Test", isShort: true) }
    }

    @Test func longSessionRetainsOnlyRecentNavigationAndBoundedCursors() {
        var window = ShortsFeedWindow(videos: videos(0..<20), startIndex: 0)
        for index in 0..<10_000 {
            if window.currentIndex == window.videos.count - 1 {
                window.insert(videos((index + 1)..<(index + 21)), prepending: false)
            }
            #expect(window.videos[window.currentIndex].id == "short-\(index)")
            window.move(to: window.currentIndex + 1)
            #expect(window.currentIndex <= ShortsFeedWindow.previousCount)
            #expect(window.videos.count <= ShortsFeedWindow.maximumCount)
            _ = window.nextCursor(after: "page-\(index)", proposed: "page-\(index + 1)")
            #expect(window.consumedCursors.count <= ShortsFeedWindow.maximumCursorCount)
        }
        #expect(window.nextCursor(after: nil, proposed: "page-9999") == nil)
    }

    @Test func initialSelectionAndPrependingPreserveThePlayingVideo() {
        var window = ShortsFeedWindow(videos: videos(0..<1_000), startIndex: 500)
        #expect(window.videos[window.currentIndex].id == "short-500")
        #expect(window.videos.count == ShortsFeedWindow.maximumCount)
        window.insert(videos(-20..<0), prepending: true)
        #expect(window.videos[window.currentIndex].id == "short-500")
        #expect(window.currentIndex == ShortsFeedWindow.previousCount)
    }
}
