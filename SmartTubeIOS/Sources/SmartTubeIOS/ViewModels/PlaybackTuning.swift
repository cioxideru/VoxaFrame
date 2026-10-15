import Foundation

/// Shared timing values for initial playback, fallback attempts and quality changes.
enum PlaybackTuning {
    static let slowVideoLoadMilliseconds = 4_000
    static let bufferReleaseDelay: Duration = .seconds(5)
    static let qualityRampDelay: Duration = .milliseconds(800)
    static let qualityUpgradeDelayNanoseconds: UInt64 = 700_000_000
    static let poTokenPrefetchTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let stallRecoveryDelayNanoseconds: UInt64 = 2_000_000_000
    static let botGuardTimeoutNanoseconds: UInt64 = 6_000_000_000
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
