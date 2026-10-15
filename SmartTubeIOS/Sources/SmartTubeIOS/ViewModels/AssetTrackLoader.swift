import AVFoundation

/// Video and audio tracks loaded from a pair of remote assets.
/// AVAssetTrack is not Sendable; the immutable arrays pass once through the race stream
/// to the caller and are not touched concurrently afterwards.
struct LoadedAssetTracks: @unchecked Sendable {
    let video: [AVAssetTrack]
    let audio: [AVAssetTrack]
}

/// Loads the video and audio tracks of two assets, racing them against `timeout`.
///
/// rqh=1 CDN URLs can stall `loadTracks` indefinitely, and main-actor task groups are
/// unreliable under scheduling pressure, so the load and the timer run in unstructured
/// tasks and the first one to yield to an AsyncStream wins.
///
/// Returns nil when loading fails or the timeout wins. In that case the loader task is
/// cancelled and `cancelLoading()` is called on both assets, so no CDN request keeps running.
func loadTracksRacingTimeout(
    videoAsset: AVURLAsset, audioAsset: AVURLAsset, timeout: Duration
) async -> LoadedAssetTracks? {
    let (raceStream, raceCont) = AsyncStream<LoadedAssetTracks?>.makeStream()
    let loaderTask = Task {
        do {
            async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
            async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
            let (vv, aa) = try await (videoTracks, audioTracks)
            raceCont.yield(LoadedAssetTracks(video: vv, audio: aa))
        } catch {
            raceCont.yield(nil)
        }
        raceCont.finish()
    }
    // After finish() is called by either task, later yield/finish calls are no-ops.
    let timeoutTask = Task {
        try? await Task.sleep(for: timeout)
        raceCont.yield(nil)
        raceCont.finish()
    }
    let tracks = await raceStream.first(where: { @Sendable _ in true }) ?? nil
    timeoutTask.cancel()
    if tracks == nil {
        loaderTask.cancel()
        videoAsset.cancelLoading()
        audioAsset.cancelLoading()
    }
    return tracks
}
