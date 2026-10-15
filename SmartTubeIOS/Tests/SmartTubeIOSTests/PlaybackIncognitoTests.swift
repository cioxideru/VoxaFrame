import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class ReadyIncognitoPlayerItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

private final class IncognitoURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

// MARK: - PlaybackIncognitoTests (#94)
//
// "Play Incognito" must not record the video to on-device history, and the flag
// applies only to the load that requested it.

@Suite("Playback incognito (#94)")
@MainActor
struct PlaybackIncognitoTests {
    private func makeAPI() -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IncognitoURLProtocol.self]
        return InnerTubeAPI(authToken: nil, session: URLSession(configuration: config))
    }

    private func makeVM() throws -> PlaybackViewModel {
        let vm = PlaybackViewModel(api: makeAPI())
        vm.settings.historyState = .enabled
        vm.localHistory = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "incognito-\(UUID().uuidString)")))
        return vm
    }

    @Test("Incognito load is not recorded to local history")
    func incognitoSkipsHistory() throws {
        let vm = try makeVM()
        vm.resetPlaybackForLoad(video: Video(id: "secret", title: "S", channelTitle: "C"), incognito: true)
        #expect(vm.isIncognito)
        #expect(!vm.recordsHistory)
        #expect(vm.localHistory.videos.isEmpty)
    }

    @Test("A normal load after an incognito one records again")
    func normalLoadRevertsIncognito() throws {
        let vm = try makeVM()
        vm.resetPlaybackForLoad(video: Video(id: "secret", title: "S", channelTitle: "C"), incognito: true)
        vm.resetPlaybackForLoad(video: Video(id: "next", title: "N", channelTitle: "C"), incognito: false)
        #expect(!vm.isIncognito)
        #expect(vm.recordsHistory)
        #expect(vm.localHistory.videos.map(\.id) == ["next"])
    }

    @Test("Same-video load changes privacy mode while loading", arguments: [false, true])
    func modeChangeReplacesInFlightLoad(incognito: Bool) async throws {
        let vm = try makeVM()
        let video = Video(id: UUID().uuidString, title: "S", channelTitle: "C")
        vm.resetPlaybackForLoad(video: video, incognito: !incognito)
        vm.localHistory.clear()
        vm.isLoading = true
        let trackingURL = try #require(URL(string: "https://example.invalid/watchtime?ei=E&vm=V&of=O"))
        vm.tracker.setTrackingURLs(PlaybackTrackingURLs(playbackURL: trackingURL, watchtimeURL: trackingURL))
        let previousLoad = Task { @MainActor in }
        vm.loadTask = previousLoad

        vm.load(video: video, incognito: incognito)
        vm.loadTask?.cancel()  // Keep this test on the synchronous load/reset path.

        #expect(previousLoad.isCancelled)
        #expect(vm.isIncognito == incognito)
        #expect(!vm.tracker.hasTrackingSession)
        #expect(vm.localHistory.videos.map(\.id) == (incognito ? [] : [video.id]))
        await vm.tracker.checkpoint(position: 30, duration: 300)
        let saved = await VideoStateStore.shared.state(for: video.id)
        #expect(saved?.position == (incognito ? nil : 30))
        await VideoStateStore.shared.clear(videoId: video.id)
    }

    @Test("Same-video duplicate load preserves a matching privacy mode", arguments: [false, true])
    func matchingModeKeepsInFlightLoad(incognito: Bool) throws {
        let vm = try makeVM()
        let video = Video(id: "same", title: "S", channelTitle: "C")
        vm.resetPlaybackForLoad(video: video, incognito: incognito)
        vm.isLoading = true
        vm.currentTime = 12
        let previousLoad = Task { @MainActor in }
        vm.loadTask = previousLoad
        defer { previousLoad.cancel() }

        vm.load(video: video, incognito: incognito)

        #expect(!previousLoad.isCancelled)
        #expect(vm.currentTime == 12)
        #expect(vm.history.isEmpty)
    }

    @Test("A ready parked item cannot keep the previous privacy session", arguments: [false, true])
    func parkedItemModeChangeResetsTracking(incognito: Bool) async throws {
        let vm = try makeVM()
        let video = Video(id: UUID().uuidString, title: "S", channelTitle: "C")
        vm.resetPlaybackForLoad(video: video, incognito: !incognito)
        vm.localHistory.clear()
        // Reproduce stop()'s parked state without starting its WebView prewarm.
        let item = ReadyIncognitoPlayerItem(asset: AVMutableComposition())
        vm.player.replaceCurrentItem(with: item)
        vm.parkedVideoId = video.id

        vm.load(video: video, incognito: incognito)
        vm.loadTask?.cancel()

        #expect(vm.player.currentItem == nil)
        #expect(vm.parkedVideoId == nil)
        #expect(vm.isLoading)
        #expect(vm.isIncognito == incognito)
        #expect(vm.localHistory.videos.map(\.id) == (incognito ? [] : [video.id]))
        await vm.tracker.checkpoint(position: 30, duration: 300)
        let saved = await VideoStateStore.shared.state(for: video.id)
        #expect(saved?.position == (incognito ? nil : 30))
        await VideoStateStore.shared.clear(videoId: video.id)
    }

    #if os(iOS)
    @Test("Opening a playing mini-player video applies the requested privacy mode", arguments: [false, true])
    func miniPlayerModeChangeReloads(incognito: Bool) throws {
        let store = PlayerStateStore(api: makeAPI())
        store.vm.localHistory = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "incognito-store-\(UUID().uuidString)")))
        let video = Video(id: "same", title: "S", channelTitle: "C")
        store.vm.resetPlaybackForLoad(video: video, incognito: !incognito)
        store.vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        store.vm.isPlaying = true
        store.minimize()

        store.play(video: video, settings: store.vm.settings, incognito: incognito)
        store.vm.loadTask?.cancel()

        #expect(store.vm.isIncognito == incognito)
        #expect(store.vm.isLoading)
        #expect(store.presentation == .fullScreen)
    }
    #endif
}
