import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - PerVideoQualityOverrideTests
//
// Explicit choices survive video changes and temporary stream fallbacks.
// The legacy default applies only before the first explicit selection.

// MARK: - Mocks

private final class MockPlayer: PlayerItemSwappable {
    var rate: Float = 0
    func replaceCurrentItem(with item: AVPlayerItem?) {}
}

@MainActor
private final class MockQualityDelegate: QualityContext, QualityEventHandler {
    var playerInfo: PlayerInfo? = nil
    var settings = AppSettings()
    var currentVideo: Video? = nil
    var currentTime: TimeInterval = 0
    var toastMessage: String? = nil
    var isSwappingItem = false
    var isQualityChangePending = false
    func qualityItemDidBecomeReady(_ item: AVPlayerItem, seekTo: TimeInterval) {}
    func qualityItemDidFail(error: Error?, quality: VideoQualityPreference, hasAppliedH264Cap: Bool) {}
    func qualitySelectDASHFormat(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {}
}

// MARK: - Tests

@Suite("Remembered quality preference")
struct RememberedQualityTests {

    private func makeFormat(height: Int) -> VideoFormat {
        VideoFormat(
            label: "\(height)p",
            width: height * 16 / 9, height: height, fps: 30,
            mimeType: "video/mp4; codecs=\"avc1.640028\"",
            url: URL(string: "https://example.com/\(height)")
        )
    }

    @MainActor
    private func makeManager(
        default quality: AppSettings.VideoQuality
    )
        -> (PlaybackQualityManager, MockQualityDelegate)
    {
        let mgr = PlaybackQualityManager(player: MockPlayer())
        let delegate = MockQualityDelegate()
        delegate.settings.preferredQuality = quality
        mgr.delegate = delegate
        return (mgr, delegate)  // caller keeps delegate alive (mgr.delegate is weak)
    }

    @Test("Picking a format remembers resolution and codec without changing the legacy default")
    @MainActor
    func pickRecordsIntentWithoutTouchingDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 720))
        #expect(delegate.settings.lastVideoQuality == VideoQualityPreference(height: 720, codec: .h264))
        #expect(delegate.settings.preferredQuality == .q480)
        #expect(mgr.effectiveQuality == VideoQualityPreference(height: 720, codec: .h264))
    }

    @Test("Explicitly picking Auto overrides a non-auto default")
    @MainActor
    func explicitAutoOverridesDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(nil)
        _ = delegate  // keep weak delegate alive through the assertions
        #expect(delegate.settings.lastVideoQuality == .auto)
        mgr.reset()
        #expect(mgr.effectiveQuality == .auto)
    }

    @Test("With no pick, effectiveQuality falls back to the persisted default")
    @MainActor
    func noPickFallsBackToDefault() {
        let (mgr, delegate) = makeManager(default: .q480)
        _ = delegate
        #expect(delegate.settings.lastVideoQuality == nil)
        #expect(mgr.effectiveQuality == VideoQualityPreference(height: 480))
    }

    @Test("reset() keeps the choice and a temporary fallback does not overwrite it")
    @MainActor
    func nextVideoRetainsChoice() {
        let (mgr, delegate) = makeManager(default: .q480)
        mgr.selectFormat(makeFormat(height: 1080))
        mgr.reset()
        _ = delegate
        mgr.availableFormats = [makeFormat(height: 720), makeFormat(height: 360)]
        mgr.setSelectedFormatForCurrentPreference()
        #expect(mgr.selectedFormat?.height == 720)
        #expect(mgr.effectiveQuality == VideoQualityPreference(height: 1080, codec: .h264))
        mgr.reset()
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720)]
        mgr.setSelectedFormatForCurrentPreference()
        #expect(mgr.selectedFormat?.height == 1080)
    }

    @Test("setSelectedFormatForCurrentPreference prefers the remembered choice over the default")
    @MainActor
    func cdnRevertRestoresPerVideoPick() {
        let (mgr, delegate) = makeManager(default: .q1080)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.selectFormat(makeFormat(height: 720))
        mgr.selectedFormat = nil  // simulate CDN-failure revert
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }

    @Test("setSelectedFormatForCurrentPreference uses the default when no pick exists")
    @MainActor
    func cdnRevertUsesDefaultWithoutPick() {
        let (mgr, delegate) = makeManager(default: .q720)
        mgr.availableFormats = [makeFormat(height: 1080), makeFormat(height: 720), makeFormat(height: 480)]
        mgr.setSelectedFormatForCurrentPreference()
        _ = delegate
        #expect(mgr.selectedFormat?.height == 720)
    }
}
