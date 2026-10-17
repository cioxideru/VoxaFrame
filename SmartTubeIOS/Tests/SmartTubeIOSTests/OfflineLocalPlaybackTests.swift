import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor @Suite("Offline local playback", .serialized)
struct OfflineLocalPlaybackTests {
    private func wait(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        return predicate()
    }
    @Test func localVoiceMirrorsPauseRateAndSeekWithoutTranslationRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("voice.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80_000))
        buffer.frameLength = 80_000
        let samples = try #require(buffer.floatChannelData?.pointee)
        samples.initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let player = AVPlayer(url: url)
        let controller = VoiceOverTranslationController(localFileAllowed: {
            OfflineLibraryStore.contains($0, in: directory)
        })
        defer {
            controller.stop()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        var requestedVideoChanges: [Bool] = []
        controller.startLocal(
            url: url, videoID: "local", mainPlayer: player, setVideoPlaying: { requestedVideoChanges.append($0) })
        #expect(controller.state == .playing(livelyVoice: false))
        #expect(requestedVideoChanges.isEmpty)
        player.playImmediately(atRate: 1.5)
        #expect(
            await wait {
                controller.sync()
                return controller.testPlaybackRate == 1.5
            })
        player.pause()
        controller.sync()
        #expect(controller.testPlaybackRate == 0)
        await player.seek(
            to: CMTime(seconds: 4, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.playImmediately(atRate: 1)
        #expect(
            await wait {
                controller.sync()
                return abs(controller.testPlaybackTime - player.currentTime().seconds) < 0.5
            })
        #expect(controller.testPlaybackTime >= 3.5)
    }
    @Test func localFailureCannotEnterNetworkRecovery() async {
        let model = PlaybackViewModel(api: InnerTubeAPI())
        var video = Video(id: "offline-missing", title: "Offline", channelTitle: "Test")
        video.localFileURL = URL(fileURLWithPath: "/missing/video.mp4")
        model.currentVideo = video
        await model.exhaustiveRetry(video: video, originalError: nil)
        #expect(model.error != nil)
        #expect(!model.isLoading)
        #expect(model.player.currentItem == nil)
        #expect(model.playerInfo == nil)
        model.stop()
    }
}
