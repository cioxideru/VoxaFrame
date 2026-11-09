import Foundation
import Testing

@testable import SmartTubeIOS

// OQ-0024: with Audio-Only on in settings, a video started by VisionOS HLS, adaptive composition or the
// fallback kept playing video, because only the iOS-client path swapped to the audio-only item.

@Suite("Audio-only after the stream starts")
struct AudioOnlyAfterStartTests {

    private func needsSwap(
        mode: Bool = true, active: Bool = false, error: Bool = false, current: Bool = true, item: Bool = true
    ) -> Bool {
        PlaybackViewModel.needsAudioOnlySwapAfterStart(
            isAudioOnlyMode: mode, audioOnlyItemActive: active, hasError: error, isCurrentVideo: current, hasItem: item)
    }

    @Test("A started video swaps to audio-only when the setting is on and no audio item plays yet")
    func swapsAfterStart() {
        #expect(needsSwap())
    }

    @Test("No swap when the setting is off, the audio item already plays, or the start failed")
    func skipsWhenNotNeeded() {
        #expect(!needsSwap(mode: false))
        #expect(!needsSwap(active: true))
        #expect(!needsSwap(error: true))
        #expect(!needsSwap(current: false))
        #expect(!needsSwap(item: false))
    }
}
