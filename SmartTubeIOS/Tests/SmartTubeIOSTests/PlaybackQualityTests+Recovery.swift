import Foundation
import Testing

@testable import SmartTubeIOSCore

extension PlaybackQualityTests {
    // MARK: - Quality recovery policy (#141)

    private func make403Error() -> NSError {
        NSError(domain: NSURLErrorDomain, code: -1102, userInfo: nil)
    }

    private func makeH264DecodeError() -> NSError {
        NSError(domain: "AVFoundationErrorDomain", code: -11833, userInfo: nil)
    }

    private func makeGenericError() -> NSError {
        NSError(domain: NSURLErrorDomain, code: -1001, userInfo: nil)
    }

    @Test func recoveryAction_403_returnsRetry403Recovery() {
        let action = qualityRecoveryAction(for: make403Error(), quality: .auto, hasAppliedH264Cap: false)
        guard case .retry403Recovery = action else {
            Issue.record("Expected .retry403Recovery, got \(action)")
            return
        }
    }

    @Test func recoveryAction_qualityCapFailed_returnsRevertToAuto() {
        let action = qualityRecoveryAction(
            for: makeGenericError(), quality: .init(height: 1080), hasAppliedH264Cap: false)
        guard case .revertToAuto = action else {
            Issue.record("Expected .revertToAuto, got \(action)")
            return
        }
    }

    @Test func recoveryAction_h264DecodeError_returnsRetryWithH264Cap() {
        let action = qualityRecoveryAction(for: makeH264DecodeError(), quality: .auto, hasAppliedH264Cap: false)
        guard case .retryWithH264Cap = action else {
            Issue.record("Expected .retryWithH264Cap, got \(action)")
            return
        }
    }

    @Test func recoveryAction_h264DecodeErrorAfterCapAlreadyApplied_returnsFail() {
        let action = qualityRecoveryAction(for: makeH264DecodeError(), quality: .auto, hasAppliedH264Cap: true)
        guard case .fail = action else {
            Issue.record("Expected .fail, got \(action)")
            return
        }
    }

    @Test func recoveryAction_unknownError_returnsFail() {
        let action = qualityRecoveryAction(for: makeGenericError(), quality: .auto, hasAppliedH264Cap: false)
        guard case .fail = action else {
            Issue.record("Expected .fail, got \(action)")
            return
        }
    }

    @Test func recoveryAction_403_takesPriorityOverQualityCap() {
        // 403 + non-auto quality → 403 wins (priority 1 > priority 2)
        let action = qualityRecoveryAction(for: make403Error(), quality: .init(height: 720), hasAppliedH264Cap: false)
        guard case .retry403Recovery = action else {
            Issue.record("Expected .retry403Recovery (403 priority), got \(action)")
            return
        }
    }

    // MARK: - HLS manifest cache (#163)

    /// Task #163: cached variants are returned for the same videoId within the TTL window.
    @Test func hlsManifestCache_returnsStoredVariantsWithinTTL() {
        var cache = HLSManifestCache()
        let videoId = "test-video-abc"
        let variants: [Int: URL] = [
            1080: URL(string: "https://example.com/1080.m3u8")!,
            720: URL(string: "https://example.com/720.m3u8")!,
        ]
        cache.store(variants, for: videoId)
        let result = cache.variants(for: videoId)
        #expect(result != nil, "Cache must return variants immediately after storing them")
        #expect(result?[1080] == variants[1080], "1080p URL must be preserved in cache")
        #expect(result?[720] == variants[720], "720p URL must be preserved in cache")
    }

    /// Task #163: a different videoId must not be served from the cache.
    @Test func hlsManifestCache_missForUnknownVideoId() {
        var cache = HLSManifestCache()
        let result = cache.variants(for: "video-that-was-never-cached-xyz")
        #expect(result == nil, "Unknown videoId must return nil — no cross-contamination between videos")
    }

    /// Task #163: invalidating a videoId removes it from the cache.
    @Test func hlsManifestCache_invalidateRemovesEntry() {
        var cache = HLSManifestCache()
        let videoId = "video-to-invalidate"
        cache.store([1080: URL(string: "https://example.com/1080.m3u8")!], for: videoId)
        cache.invalidate(for: videoId)
        #expect(cache.variants(for: videoId) == nil, "Invalidated entry must not be returned")
    }

    /// Task #164: after a 403 error the cached variant URLs (which may contain expired CDN
    /// tokens) must be evicted so the next retry fetches fresh signed URLs. This verifies the
    /// `invalidate(for:)` call that was added to the `.retry403Recovery` path.
    @Test func hlsManifestCache_403Recovery_clearsStaleVariants() {
        var cache = HLSManifestCache()
        let videoId = "video-with-expired-cdn-token"
        let staleVariants: [Int: URL] = [
            1080: URL(string: "https://r3---sn-ab5l6nld.googlevideo.com/videoplayback?expire=1716235200&id=stale")!
        ]
        cache.store(staleVariants, for: videoId)
        // 403 recovery: invalidate so retry gets fresh CDN-signed URLs
        cache.invalidate(for: videoId)
        #expect(
            cache.variants(for: videoId) == nil,
            "After 403, stale CDN variant URLs must be evicted so retry fetches fresh ones"
        )
    }

}
