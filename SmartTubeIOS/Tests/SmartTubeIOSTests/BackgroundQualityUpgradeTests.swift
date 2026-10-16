import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Background quality upgrade ownership (PLAN-0011)")
@MainActor
struct BackgroundQualityUpgradeTests {
    private let video = Video(id: "upgrade", title: "Upgrade", channelTitle: "Test")

    private func makeVM() -> PlaybackViewModel {
        let vm = PlaybackViewModel()
        vm.currentVideo = video
        vm.isIncognito = true
        vm.isPlaying = true
        return vm
    }

    @Test(arguments: ["stop", "suspend", "reset", "pause", "background", "outputLost"])
    func lifecycleCancelsUpgrade(action: String) async throws {
        let vm = makeVM()
        vm.scheduleBackgroundQualityUpgrade(video: video)
        let task = try #require(vm.backgroundQualityUpgradeTask)

        switch action {
        case "stop": vm.stop()
        case "suspend": vm.suspend()
        case "reset": vm.resetPlaybackForLoad(video: video, incognito: true)
        case "pause": vm.togglePlayPause()
        case "background":
            vm.settings.backgroundPlaybackEnabled = false
            vm.handleBackground()
        default: vm.handleAudioOutputLost()
        }

        #expect(task.isCancelled)
        #expect(vm.backgroundQualityUpgradeTask == nil)
        await task.value
        #expect(!vm.isPlaying)
        #expect(vm.player.currentItem == nil)
        #expect(vm.phase2Task == nil)
    }

    @Test func permittedBackgroundPlaybackKeepsUpgrade() throws {
        let vm = makeVM()
        vm.scheduleBackgroundQualityUpgrade(video: video)
        let task = try #require(vm.backgroundQualityUpgradeTask)
        defer { vm.cancelBackgroundQualityUpgrade() }
        vm.settings.backgroundPlaybackEnabled = true
        vm.handleBackground()
        #expect(!task.isCancelled)
        #expect(vm.isPlaying)
    }

    @Test func cancelledUpgradeCannotClearSameVideoReplacement() async throws {
        let vm = makeVM()
        vm.scheduleBackgroundQualityUpgrade(video: video)
        let old = try #require(vm.backgroundQualityUpgradeTask)
        vm.resetPlaybackForLoad(video: video, incognito: true)
        vm.isPlaying = true
        vm.scheduleBackgroundQualityUpgrade(video: video)
        let replacement = try #require(vm.backgroundQualityUpgradeTask)
        // Cancel before yielding so neither task can reach the network.
        replacement.cancel()
        await old.value
        #expect(old.isCancelled)
        #expect(vm.backgroundQualityUpgradeTask != nil)
        await replacement.value
        vm.cancelBackgroundQualityUpgrade()
    }

    @Test func delayedCancelledResultCannotReplaceSameVideoSession() async {
        let vm = makeVM()
        let info = PlayerInfo(
            video: video, formats: [], hlsURL: nil, dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])
        let (started, signal) = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let old = Task { @MainActor in
            await withCheckedContinuation { continuation in
                release = continuation
                signal.yield(())
                signal.finish()
            }
            _ = await vm.attemptURL(
                URL(fileURLWithPath: "/dev/null"), for: video, info: info, label: "upgrade/muxed")
        }
        vm.backgroundQualityUpgradeTask = old
        for await _ in started { break }
        vm.stop()
        vm.resetPlaybackForLoad(video: video, incognito: true)
        vm.savedPositionToRestore = 42
        release?.resume()
        await old.value
        #expect(vm.player.currentItem == nil)
        #expect(vm.playerInfo == nil)
        #expect(vm.savedPositionToRestore == 42)
        #expect(!vm.isPlaying)
    }
}
