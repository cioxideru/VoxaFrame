import AVFoundation
import Testing

@testable import SmartTubeIOS

// MARK: - LiveStreamItemTests (PLAN-0048)
//
// iPad log (2026-11-09): a 15-minute video was tracked as a live stream because its item still reported an
// indefinite duration one second before it became ready to play.

@Suite("Live stream item detection")
struct LiveStreamItemTests {
    @Test("an item that is not ready yet is never a live stream, whatever its duration")
    func unreadyItemIsNotLive() {
        #expect(!PlaybackViewModel.isLiveStreamItem(status: .unknown, duration: .indefinite))
        #expect(!PlaybackViewModel.isLiveStreamItem(status: .failed, duration: .indefinite))
    }

    @Test("a ready item is a live stream only when its duration stays indefinite")
    func readyItemFollowsDuration() {
        #expect(PlaybackViewModel.isLiveStreamItem(status: .readyToPlay, duration: .indefinite))
        #expect(
            !PlaybackViewModel.isLiveStreamItem(
                status: .readyToPlay, duration: CMTime(seconds: 880, preferredTimescale: 600)))
    }
}
