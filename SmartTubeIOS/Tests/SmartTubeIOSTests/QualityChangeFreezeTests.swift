import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// A quality switch freezes the timeline until its new item is ready. A switch that is cancelled
// (player closed, next video loaded) must not leave that freeze behind: on the iPad every later
// video then showed 0:00 and saved its position as 0 s until the app was relaunched.

private final class StubPlayer: PlayerItemSwappable {
    var rate: Float = 0
    func replaceCurrentItem(with item: AVPlayerItem?) {}
}

@MainActor
private final class FreezeRecordingDelegate: QualityContext, QualityEventHandler {
    var playerInfo: PlayerInfo?
    var settings = AppSettings()
    var currentVideo: Video?
    var currentTime: TimeInterval = 0
    var toastMessage: String?
    var isSwappingItem = false
    var isQualityChangePending = false
    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo: TimeInterval) {}
    func qualityItemDidFail(error: Error?, quality: VideoQualityPreference, hasAppliedH264Cap: Bool) {}
    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) {}
}

@Suite("Quality-change timeline freeze")
@MainActor
struct QualityChangeFreezeTests {

    private func makeManager() -> (PlaybackQualityManager, FreezeRecordingDelegate) {
        let manager = PlaybackQualityManager(player: StubPlayer())
        let delegate = FreezeRecordingDelegate()
        manager.delegate = delegate
        return (manager, delegate)
    }

    @Test("Loading the next video ends an unfinished switch's freeze")
    func resetEndsFreeze() {
        let (manager, delegate) = makeManager()
        delegate.isQualityChangePending = true
        manager.reset()
        #expect(delegate.isQualityChangePending == false)
    }

    @Test("Stopping the player ends an unfinished switch's freeze")
    func cancelEndsFreeze() {
        let (manager, delegate) = makeManager()
        delegate.isQualityChangePending = true
        manager.cancel()
        #expect(delegate.isQualityChangePending == false)
    }
}
