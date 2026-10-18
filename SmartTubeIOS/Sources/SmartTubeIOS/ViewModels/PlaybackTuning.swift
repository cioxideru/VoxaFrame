import Foundation

/// Shared timing values for initial playback, fallback attempts and quality changes.
enum PlaybackTuning {
    static let levelFeedbackDuration: Duration = .seconds(1.5)
    static let macControlsHoverThrottle: Duration = .milliseconds(500)
    static let playbackDemandRecovery: Duration = .seconds(1)
    static let playbackDemandBufferBudget: Duration = .seconds(10)
    static let shortsPreparationSeconds: TimeInterval = 30
    static let shortsPreloadRetention: Duration = .seconds(300)
    static let shortsForwardBufferSeconds: TimeInterval = 3
    static let shortsPreloadMaximumHeight = 720
    static let idleResourceRetention: Duration = .seconds(60)
    /// Re-read the queue after reselection without keeping an action alive through endless changes.
    static let maxQueueContextAttempts = 3
    /// A stream that never reports readiness must yield to the next playback source.
    static let itemReadinessTimeout: Duration = .seconds(15)
    static let bufferReleaseDelay: Duration = .seconds(5)
    static let qualityRampDelay: Duration = .milliseconds(800)
    static let qualityUpgradeDelayNanoseconds: UInt64 = 700_000_000
    static let poTokenPrefetchTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let stallRecoveryDelayNanoseconds: UInt64 = 2_000_000_000
    /// Stalls closer together than this on one item count as a rapid stall loop.
    static let rapidStallWindow: TimeInterval = 30
    /// Seek-in-place recoveries attempted per stall sequence before giving up or escalating.
    static let maxStallRecoveryAttempts = 3
    /// Rapid-stall-loop escalations to exhaustiveRetry allowed per video (reset by load()).
    static let maxStallEscalationsPerVideo = 2
    static let botGuardTimeoutNanoseconds: UInt64 = 6_000_000_000
    static let botGuardPreparationTimeout: Duration = .seconds(45)
    static let adaptiveVRTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let adaptiveTVTimeoutNanoseconds: UInt64 = 3_000_000_000
    static let adaptiveStartupTimeoutNanoseconds: UInt64 = 1_500_000_000
    static let adaptiveTimeoutNanoseconds: UInt64 = 8_000_000_000
    static let qualityTrackTimeout: Duration = .seconds(10)
    static let prefetchTrackTimeout: Duration = .seconds(60)
    static let adaptiveProbeTimeout: TimeInterval = 1.5
    static let botGuardProbeTimeout: TimeInterval = 1
    static let hlsManifestTimeout: TimeInterval = 20
    static let playlistProbeTimeout: TimeInterval = 8
    static let segmentProbeTimeout: TimeInterval = 5
}
