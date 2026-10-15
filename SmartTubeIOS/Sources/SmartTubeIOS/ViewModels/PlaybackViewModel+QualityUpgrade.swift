@preconcurrency import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

private let playerLog = ViewModelLogger(category: "Player")

// MARK: - Playback Quality Upgrades

extension PlaybackViewModel {

    func launchPhase2(video: Video, info: PlayerInfo, cached: CachedVideoData? = nil) {
        phase2Task?.cancel()
        phase2Task = Task(priority: .utility) { [weak self] in
            // Use the caller-supplied cached data when available so Phase 2 can use
            // already-consumed nextInfo/endCards/sponsorSegments instead of re-fetching.
            // Falls back to empty (full network fetch) when no cached data is passed
            // (e.g. from the 3-attempt retry loop which doesn't have the original cached struct).
            let p2Cached =
                cached
                ?? CachedVideoData(
                    playerInfo: nil, trackingURLs: nil, nextInfo: nil,
                    endCards: nil, sponsorSegments: nil, deArrowBranding: nil,
                    staleFields: []
                )
            await self?.loadAsyncPhase2(
                video: video, cached: p2Cached, info: info,
                cachedTrackingURLs: cached?.trackingURLs ?? nil, authTrackingTask: nil,
                sponsorCached: cached?.sponsorSegments != nil
            )
        }
        // Background pre-warming runs alongside phase2:
        //  • muxed fallback → fetch AndroidVR playerInfo so quality-tap skips 403 recovery
        //  • adaptive playing → pre-warm tracks for the user's preferred quality tier
        prefetchTask?.cancel()
        if info.bestAdaptiveAudioURL == nil {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.fetchAndCacheAdaptivePlayerInfo(video: video, muxedInfo: info)
            }
        } else if settings.preferredQuality != .auto {
            prefetchTask = Task(priority: .utility) { [weak self] in
                await self?.prefetchPreferredQualityTracks(info: info)
            }
        }
    }

    /// Called from `launchPhase2` when muxed 360p is the only available stream
    /// (`info.bestAdaptiveAudioURL == nil`).  Fetches AndroidVR player info in the
    /// background and upgrades `self.playerInfo` so that the first quality-tap skips
    /// the 17-second 403-recovery cycle.
    private func fetchAndCacheAdaptivePlayerInfo(video: Video, muxedInfo: PlayerInfo) async {
        playerLog.notice("[prefetch] muxed fallback — fetching AndroidVR playerInfo in background")
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            guard !Task.isCancelled else { return }
            guard vrInfo.bestAdaptiveAudioURL != nil else {
                playerLog.notice("[prefetch] AndroidVR returned no adaptive audio — playerInfo not upgraded")
                return
            }
            guard currentVideo?.id == video.id, playerInfo?.bestAdaptiveAudioURL == nil else {
                playerLog.notice("[prefetch] playerInfo already upgraded or video changed — discarding prefetch result")
                return
            }
            playerInfo = vrInfo
            let vrFormats = Self.deduplicatedVideoFormats(vrInfo.formats)
            let maxCurrentH = availableFormats.map(\.height).max() ?? 0
            let maxVRH = vrFormats.map(\.height).max() ?? 0
            // Only update availableFormats (quality-picker options) when at least one format
            // is rqh-free. rqh=1 formats are immediately reverted by reloadDASHItem's rqh guard
            // and should not appear in the picker.
            let hasRqhFreeFormat = vrFormats.contains { fmt in
                guard let url = fmt.url else { return false }
                return !PlaybackQualityManager.urlHasRqhEnforcement(url)
            }
            if hasRqhFreeFormat && (vrFormats.count > availableFormats.count || maxVRH > maxCurrentH) {
                availableFormats = vrFormats
            }
            playerLog.notice(
                "⚡ [prefetch] playerInfo upgraded to AndroidVR (\(vrFormats.count) formats) — quality switches skip 403 recovery"
            )
            await prefetchPreferredQualityTracks(info: vrInfo)
        } catch {
            playerLog.notice("[prefetch] background AndroidVR fetch failed: \(error)")
        }
    }

    /// Pre-loads `AVAssetTrack` arrays for `settings.preferredQuality` into
    /// `AVAssetTrackCache` so that the first quality-tap after initial playback
    /// is a cache hit rather than a CDN round-trip.
    private func prefetchPreferredQualityTracks(info: PlayerInfo) async {
        guard settings.preferredQuality != .auto,
            let maxH = settings.preferredQuality.maxHeight
        else { return }
        guard
            let videoURL = PlaybackQualityManager.selectBestVideoFormat(
                from: info.formats, preferredMaxHeight: maxH,
                preferH264: settings.preferH264
            )?.url,
            let audioURL = info.bestAdaptiveAudioURL
        else { return }
        if AVAssetTrackCache.shared.videoTracks(for: videoURL) != nil { return }
        let itag =
            URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let ua = InnerTubeClients.iOS.userAgent
        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        playerLog.notice("[prefetch] pre-warming tracks for preferredQuality=\(maxH)p (itag=\(itag))")
        // Immutable tracks pass once through AsyncStream to the MainActor cache; no concurrent mutation.
        struct PrefetchTrackBox: @unchecked Sendable {
            let video: [AVAssetTrack]
            let audio: [AVAssetTrack]
        }
        let (stream, cont) = AsyncStream<PrefetchTrackBox?>.makeStream()
        Task {
            do {
                async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
                async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
                let (vv, aa) = try await (videoTracks, audioTracks)
                cont.yield(PrefetchTrackBox(video: vv, audio: aa))
            } catch {
                cont.yield(nil)
            }
            cont.finish()
        }
        Task {
            try? await Task.sleep(for: PlaybackTuning.prefetchTrackTimeout)
            cont.yield(nil)
            cont.finish()
        }
        if let result = await stream.first(where: { @Sendable _ in true }),
            let box = result, !box.video.isEmpty, !box.audio.isEmpty
        {
            AVAssetTrackCache.shared.store(
                videoTracks: box.video, audioTracks: box.audio,
                videoURL: videoURL, audioURL: audioURL)
            playerLog.notice("⚡ [prefetch] tracks cached for preferredQuality=\(maxH)p (itag=\(itag))")
        } else {
            playerLog.notice("[prefetch] track prefetch timed out/failed for preferredQuality=\(maxH)p")
        }
    }

    /// Prefetches `AVAssetTrack` metadata for ALL available quality tiers at `.userInitiated`
    /// priority. Call this when the quality picker opens so that by the time the user taps a
    /// quality, the tracks are already cached and the switch completes in < 100ms (Fix 2A).
    func prefetchAllQualityTracks() async {
        guard let info = playerInfo else { return }
        guard info.hlsURL == nil else { return }  // HLS doesn't need DASH track prefetch
        guard let audioURL = info.bestAdaptiveAudioURL else { return }
        guard !PlaybackQualityManager.urlHasRqhEnforcement(audioURL) else { return }

        let formats = Self.deduplicatedVideoFormats(info.formats)
        let ua = InnerTubeClients.iOS.userAgent

        // Load audio tracks once — shared across all video qualities.
        let audioTracks: [AVAssetTrack]
        if let cached = AVAssetTrackCache.shared.audioTracks(for: audioURL), !cached.isEmpty {
            audioTracks = cached
        } else {
            let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
            guard let loaded = try? await audioAsset.loadTracks(withMediaType: .audio), !loaded.isEmpty else { return }
            audioTracks = loaded
        }

        for fmt in formats.prefix(6) {
            guard !Task.isCancelled else { return }
            guard let videoURL = fmt.url else { continue }
            guard !PlaybackQualityManager.urlHasRqhEnforcement(videoURL) else { continue }
            guard AVAssetTrackCache.shared.videoTracks(for: videoURL) == nil else { continue }
            let itag =
                URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
            let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
            playerLog.notice("[prefetch/picker] pre-warming \(fmt.height)p itag=\(itag)")
            if let vTracks = try? await videoAsset.loadTracks(withMediaType: .video), !vTracks.isEmpty {
                AVAssetTrackCache.shared.store(
                    videoTracks: vTracks, audioTracks: audioTracks,
                    videoURL: videoURL, audioURL: audioURL)
                playerLog.notice("⚡ [prefetch/picker] cached \(fmt.height)p itag=\(itag)")
            }
        }
    }

    /// Rebuilds the `AVMutableComposition` during a quality switch for DASH/MP4-only videos
    /// (where `hlsURL == nil`). Mirrors `attemptComposition` but does not reset `playerInfo`
    /// or `availableFormats` and does not call `launchPhase2` — this is a mid-playback swap.
    func rebuildCompositionForQuality(videoURL: URL, audioURL: URL, seekTo: TimeInterval) async {
        let videoItag =
            URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let audioItag =
            URLComponents(url: audioURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        // Always use the iOS UA regardless of URL signing (c=ANDROID or c=IOS).
        // The initial attemptComposition path uses iOS UA for all URLs including
        // Android-client-signed ones, and it succeeds. Using Android UA for c=ANDROID
        // URLs was an incorrect assumption — it caused HTTP 403 instead of preventing it.
        let ua = InnerTubeClients.iOS.userAgent
        playerLog.notice("[quality/DASH] rebuilding composition — videoItag=\(videoItag) audioItag=\(audioItag) ua=iOS")

        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]])

        do {
            // ── loadTracks with 60-second timeout ────────────────────────────────────
            // Without a timeout, rqh=1 CDN URLs hold the TCP connection open indefinitely,
            // causing quality-switch composition to hang forever (player stays at 360p).
            // The AsyncStream + Task.detached pattern mirrors attemptComposition to avoid
            // @MainActor scheduling pressure on withThrowingTaskGroup child tasks.
            guard
                let tracks = await loadQualityCompositionTracks(
                    videoURL: videoURL, audioURL: audioURL, videoAsset: videoAsset, audioAsset: audioAsset,
                    videoItag: videoItag)
            else { return }

            guard let sourceVideoTrack = tracks.video.first,
                let sourceAudioTrack = tracks.audio.first
            else {
                playerLog.error("❌ [quality/DASH] no tracks in remote assets — triggering 403 recovery retry")
                selectedFormat = nil
                if statsForNerdsVisible { updateStatsSnapshot() }
                if let video = currentVideo {
                    await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                    HLSManifestCache.shared.invalidate(for: video.id)
                    await retryWith403Recovery(video: video, originalError: nil)
                }
                return
            }

            let videoDuration = try await videoAsset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: videoDuration)
            let composition = AVMutableComposition()

            guard
                let compVideo = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid),
                let compAudio = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                playerLog.error("❌ [quality/DASH] could not add composition tracks")
                selectedFormat = nil
                if statsForNerdsVisible { updateStatsSnapshot() }
                return
            }

            try compVideo.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            try compAudio.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
            playerLog.notice("✅ [quality/DASH] composition built — swapping item")

            lastAttemptedStreamURL = videoURL
            let compositeItem = AVPlayerItem(asset: composition)
            isQualityChangePending = true
            isSwappingItem = true
            player.replaceCurrentItem(with: compositeItem)
            isSwappingItem = false
            itemObserverTask?.cancel()

            await observeQualityComposition(compositeItem, seekTo: seekTo)
        } catch {
            playerLog.error("❌ [quality/DASH] composition build error: \(error) — triggering 403 recovery retry")
            selectedFormat = nil
            if statsForNerdsVisible { updateStatsSnapshot() }
            if let video = currentVideo {
                await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                HLSManifestCache.shared.invalidate(for: video.id)
                await retryWith403Recovery(video: video, originalError: error)
            }
        }
    }

    // Immutable track arrays are transferred through AsyncStream and consumed only on MainActor.
    private struct QualityCompositionTracks: @unchecked Sendable {
        let video: [AVAssetTrack]
        let audio: [AVAssetTrack]
    }

    private func loadQualityCompositionTracks(
        videoURL: URL, audioURL: URL, videoAsset: AVURLAsset, audioAsset: AVURLAsset, videoItag: String
    ) async -> QualityCompositionTracks? {
        let vTracks: [AVAssetTrack]
        let aTracks: [AVAssetTrack]
        let cachedV = AVAssetTrackCache.shared.videoTracks(for: videoURL)
        let cachedA = AVAssetTrackCache.shared.audioTracks(for: audioURL)
        if let cv = cachedV, let ca = cachedA, !cv.isEmpty, !ca.isEmpty {
            vTracks = cv
            aTracks = ca
            playerLog.notice("⚡ [quality/DASH] loadTracks cache hit (itag=\(videoItag)) — skipping CDN round-trip")
        } else {
            do {
                let (raceStream, raceCont) = AsyncStream<QualityCompositionTracks?>.makeStream()
                Task {
                    do {
                        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
                        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
                        let (vv, aa) = try await (videoTracks, audioTracks)
                        raceCont.yield(QualityCompositionTracks(video: vv, audio: aa))
                    } catch {
                        raceCont.yield(nil)
                    }
                    raceCont.finish()
                }
                Task {
                    try? await Task.sleep(for: PlaybackTuning.qualityTrackTimeout)
                    raceCont.yield(nil)
                    raceCont.finish()
                }
                if let firstOrNil = await raceStream.first(where: { @Sendable _ in true }),
                    let box = firstOrNil
                {
                    vTracks = box.video
                    aTracks = box.audio
                    AVAssetTrackCache.shared.store(
                        videoTracks: vTracks, audioTracks: aTracks,
                        videoURL: videoURL, audioURL: audioURL)
                } else {
                    playerLog.error(
                        "❌ [quality/DASH] loadTracks timed out after 10s — triggering 403 recovery retry")
                    selectedFormat = nil
                    if statsForNerdsVisible { updateStatsSnapshot() }
                    if let video = currentVideo {
                        await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                        HLSManifestCache.shared.invalidate(for: video.id)
                        await retryWith403Recovery(video: video, originalError: nil)
                    }
                    return nil
                }
            }
        }  // end cache-miss else
        // ─────────────────────────────────────────────────────────────────────────

        return QualityCompositionTracks(video: vTracks, audio: aTracks)
    }

    private func observeQualityComposition(_ compositeItem: AVPlayerItem, seekTo: TimeInterval) async {
        for await status in compositeItem.statusStream {
            switch status {
            case .readyToPlay:
                let size = compositeItem.presentationSize
                let benchVid = self.currentVideo?.id ?? "nil"
                let benchTitle = self.currentVideo?.title ?? "nil"
                playerLog.notice("[benchmark] readyToPlay — quality/DASH — videoId=\(benchVid) title=\(benchTitle)")
                playerLog.notice(
                    "✅ [quality/DASH] readyToPlay — presentationSize=\(Int(size.width))x\(Int(size.height))")
                isQualityChangePending = false
                // Use currentTime (preserved by time observer freeze) instead of seekTo
                // to honour any user seek that occurred during the DASH rebuild transition.
                let seekTarget = currentTime > 0 ? currentTime : seekTo
                playerLog.notice(
                    "[quality/DASH] readyToPlay — seekTarget=\(seekTarget)s (currentTime=\(currentTime)s savedSeekTo=\(seekTo)s)"
                )
                if seekTarget > 0 { seek(to: seekTarget) }
                loadAudioTracks(from: compositeItem)
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                return
            case .failed:
                let itemError = compositeItem.error
                let errStr = itemError.map { "\($0)" } ?? "nil"
                playerLog.error("❌ [quality/DASH] AVPlayerItem failed: \(errStr) — triggering 403 recovery retry")
                selectedFormat = nil
                if statsForNerdsVisible { updateStatsSnapshot() }
                if let video = currentVideo {
                    await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
                    HLSManifestCache.shared.invalidate(for: video.id)
                    await retryWith403Recovery(video: video, originalError: itemError)
                }
                return
            case .unknown:
                continue
            @unknown default:
                continue
            }
        }
    }

}
