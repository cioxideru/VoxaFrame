import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS

/// Resource-loader fake: accepts every request for its custom scheme and never answers,
/// so `loadTracks` stalls without any network.
/// `didCancel` is not used: on macOS it is not delivered even after an explicit
/// `cancelLoading()`, so this seam cannot observe the asset cancellation itself.
private final class StallingResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var requested = 0

    var requestCount: Int { lock.withLock { requested } }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        lock.withLock { requested += 1 }
        return true
    }
}

@Suite("Asset track loader race")
struct AssetTrackLoaderTests {
    // AVAssetResourceLoader.setDelegate(_:queue:) requires a dispatch queue.
    private let delegateQueue = DispatchQueue(label: "AssetTrackLoaderTests.resourceLoader")

    private func stallingAsset(_ name: String, loader: StallingResourceLoader) throws -> AVURLAsset {
        let asset = AVURLAsset(url: try #require(URL(string: "stall-test://cdn.invalid/\(name).mp4")))
        asset.resourceLoader.setDelegate(loader, queue: delegateQueue)
        return asset
    }

    @Test("Timeout wins over a stalled load and returns nil")
    func timeoutWinsOverStalledLoad() async throws {
        let loader = StallingResourceLoader()
        let start = ContinuousClock.now

        let tracks = await loadTracksRacingTimeout(
            videoAsset: try stallingAsset("video", loader: loader),
            audioAsset: try stallingAsset("audio", loader: loader),
            timeout: .milliseconds(200))

        #expect(tracks == nil)
        #expect(loader.requestCount > 0)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Cancelling the caller ends the race with nil before the timeout")
    func callerCancellationReturnsNil() async throws {
        let loader = StallingResourceLoader()
        let videoAsset = try stallingAsset("video", loader: loader)
        let audioAsset = try stallingAsset("audio", loader: loader)
        let start = ContinuousClock.now
        let race = Task {
            await loadTracksRacingTimeout(videoAsset: videoAsset, audioAsset: audioAsset, timeout: .seconds(30))
        }
        race.cancel()

        #expect(await race.value == nil)
        #expect(ContinuousClock.now - start < .seconds(30))
    }

    @Test("Load failure returns nil before the timeout")
    func loadFailureReturnsNil() async {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).mp4")
        let start = ContinuousClock.now

        let tracks = await loadTracksRacingTimeout(
            videoAsset: AVURLAsset(url: missing), audioAsset: AVURLAsset(url: missing), timeout: .seconds(30))

        #expect(tracks == nil)
        #expect(ContinuousClock.now - start < .seconds(30))
    }
}
