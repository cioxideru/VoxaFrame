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

// MARK: - Exhaustive Playback Retry

extension PlaybackViewModel {

    // MARK: - Entry Points

    /// Main retry entry point. Called whenever the primary iOS stream fails.
    ///
    /// Strategy:
    ///   Phase 0 — Authenticated TV client: when logged in, the TV client with
    ///             `html5Preference: HTML5_PREF_WANTS` returns `streamingData` including
    ///             an `hlsManifestUrl`. Authenticated HLS URLs bypass rqh=1 CDN enforcement
    ///             and enable quality switching via AVPlayer ABR. Skipped if not logged in.
    ///   Phase 1 — TV embedded (TVHTML5_SIMPLY_EMBEDDED_PLAYER): returns HLS for most
    ///             embeddable videos without pot/rqh=1 restriction.
    ///   Phase 2 — try HLS + adaptive from iOS and Android clients in order.
    ///   Phase 3 — Android VR (Oculus Quest client, nameID=28): per yt-dlp research, this
    ///             client is exempt from the PO-token / rqh=1 requirement on adaptive streams.
    ///             Correct VR headers (nameID=28, Oculus UA on googleapis.com) are required.
    ///   Phase 4 — if all adaptive attempts fail, fall back to the Android muxed 360p stream.
    ///   The entire cycle repeats up to 3 times to survive transient network errors.
    func exhaustiveRetry(
        video: Video, originalError: Error?, playerInfo: PlayerInfo? = nil, cached: CachedVideoData? = nil
    ) async {
        // Testing override: --uitesting-force-stream-method restricts the retry to a
        // single named client so UI tests can probe one path at a time.
        if let method = StreamMethodProbeSupport.forcedStreamMethod {
            await probeStreamMethod(method, video: video)
            return
        }
        // VISIONOS is the JS-less client NewPipe takes all streams from: token-free HLS
        // that AVPlayer plays natively (VP9 through 2160p, else H.264 through 1080p). Tried first on every
        // platform — the WKWebView/BotGuard paths below can each wait up to 40 s.
        if await tryVisionOSRetry(video: video) { return }
        #if canImport(WebKit)
        if await tryCachedWebViewHLS(video: video, playerInfo: playerInfo, cached: cached) { return }
        if let path = await raceLegacyStreams(video: video) {
            finishWinningFallbackPath(path, video: video, playerInfo: playerInfo, cached: cached)
            return
        }
        if await trySerialWebViewHLS(video: video, playerInfo: playerInfo, cached: cached) { return }
        #endif
        for attempt in 1...3 {
            // true also on IP block or cancellation: either way stop retrying.
            let shouldStop = await retryFallbackClients(video: video, attempt: attempt)
            if shouldStop { return }
        }

        guard !Task.isCancelled else { return }
        playerLog.error("❌ All 3 retry attempts exhausted for \(video.id)")
        error = APIError.unavailable("Unable to play this video")
        isLoading = false
    }

    private func tryVisionOSRetry(video: Video) async -> Bool {
        do {
            let visionInfo = try await api.fetchPlayerInfoVisionOS(videoId: video.id)
            if await tryAllStreams(
                video: video,
                info: visionInfo,
                label: "VisionOS",
                skipMuxed: true
            ) {
                playerLog.notice("[VisionOS] ✅ native HLS playback — exhaustiveRetry done")
                return true
            }
            playerLog.notice("[VisionOS] HLS/adaptive playback failed — continuing legacy fallbacks")
        } catch {
            playerLog.notice(
                "[VisionOS] player request failed: \(ViewModelLogger.errorSummary(error)) — continuing legacy fallbacks"
            )
        }
        return false
    }

    #if canImport(WebKit)
    private func tryCachedWebViewHLS(
        video: Video, playerInfo: PlayerInfo?, cached: CachedVideoData?
    ) async -> Bool {
        // Phase -1a: Cached WKWebView HLS URL shortcut — skip 5–9 s extraction when the
        // master manifest URL for this video was stored by a prior session or neighbour
        // pre-extraction. Falls through to live WKWebView extraction if the URL has expired
        // or if tryWebViewHLS fails (e.g. 403 on an expired signed URL).
        //
        // Note: for preWarm origin + pot=nil videos (e.g. uN7uKLsGRWw), tryWebViewHLS will
        // fail (~1.32 s) because pfa/1 variant playlist segments need pot= or a warm CDN
        // session. However, this failure is USEFUL: it gives wkHLSEarlyTask (launched by
        // loadAsync concurrently) ~1.78 s of head start so Path B wins immediately after
        // Phase -1a fails. Do NOT skip Phase -1a for preWarm+pot=nil — doing so removes the
        // concurrent overlap and forces Path B to wait the full ~2.17 s alone, costing ~0.6 s.
        if let cachedHLSURL = await VideoPreloadCache.shared.cachedWKHLSURL(for: video.id) {
            playerLog.notice("[wkHLS] cached HLS URL found — probing validity")
            let nSolver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
            // fix21: Read pot= from VideoPreloadCache instead of from the extractor's
            // volatile extractedPoToken field. The extractor resets that field to nil at the
            // START of every new extractHLSURL call; wkHLSEarlyTask triggers that reset
            // before this point, so extractedPoToken is always nil here. The cache entry is
            // written by preWarm() AFTER extraction completes and is only evicted together
            // with the HLS URL itself — so it reliably holds the preWarm-extracted token.
            // fix24: Fall back to InnerTubeAPI's BotGuard-minted token when VideoPreloadCache
            // has no pot=. For videos with no serviceIntegrityDimensions.poToken (e.g.
            // uN7uKLsGRWw), preWarm stores nil in wkHLSPoTokenCache but BotGuard may have
            // minted a valid CDN token during loadAsync's 2 s prefetchPoToken window. Using
            // this token allows the proxy's Step 4 to inject pot= into segment URLs so the
            // CDN accepts them without iOS UA rejection.
            var capturedPoToken = await VideoPreloadCache.shared.cachedPoToken(for: video.id)
            // NOTE: Do NOT fall back to InnerTubeAPI.currentPoToken (BotGuard token, ~107 chars).
            // The BotGuard pot= is for youtubei/v1/player API auth; it is NOT a valid CDN
            // segment token. Injecting it into segment URLs TRIGGERS pot= validation on CDN
            // servers that would otherwise not enforce rqh=1 (returning HTTP 206). The result
            // is that CDN rejects segments with the wrong pot= type (-12753/-12860) even though
            // it would have accepted them with pot=nil. Only WKWebView-player-minted tokens
            // (from serviceIntegrityDimensions.poToken) are valid CDN segment tokens.
            // fix24 fallback removed in fix26.
            // fix25: Skip the HEAD probe if the URL was stored within the last 10 s.
            // The double-prewarm in VideoCardView ensures the cached URL is from a fresh
            // WKWebView session (< 1s old when the heartbeat fires). A fresh URL's CDN
            // session is guaranteed active — probing wastes ~0.22s that the user perceives.
            // For older URLs (> 10s), keep the probe to detect expired manifest URLs early.
            let urlIsFresh = await VideoPreloadCache.shared.isWKHLSURLFresh(for: video.id, within: 10)
            if urlIsFresh {
                playerLog.notice("[wkHLS/fix25] fresh URL (< 10s) — skipping probe")
            }
            let probeValid: Bool
            if urlIsFresh {
                probeValid = true
            } else {
                probeValid = await isWKHLSURLValid(cachedHLSURL)
            }
            if probeValid {
                if await tryWebViewHLS(
                    cachedHLSURL, nSolver: nSolver, poToken: capturedPoToken, skipIfPfa1: true, for: video)
                {
                    playerLog.notice("[wkHLS] cached URL played — exhaustiveRetry done")
                    if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
                    return true
                }
                playerLog.notice(
                    "[wkHLS] cached URL failed (tryWebViewHLS) — invalidating and falling back to live WKWebView")
                await VideoPreloadCache.shared.invalidateWKHLSURL(for: video.id)
            } else {
                playerLog.notice(
                    "[wkHLS] cached URL expired (probe 403/timeout) — invalidating and using live extraction")
                await VideoPreloadCache.shared.invalidateWKHLSURL(for: video.id)
            }
        }
        return false
    }

    private func raceLegacyStreams(video: Video) async -> Int? {
        // Phase -2 + Phase -1b: race BotGuardWV adaptive path vs WKWebView HLS path.
        //
        // Both paths start simultaneously. They interleave cooperatively at every `await`
        // (suspension point) since both run on @MainActor. Whichever path reaches
        // `readyToPlay` first wins; the other task is cancelled immediately.
        //
        // Path A — BotGuardWV adaptive: waits for BotGuard mint (up to 6 s on cold start,
        //   <5 ms if already warm), probes CDN, tries WEB adaptive / proxy HLS / iOS+Android
        //   adaptive. Fast for videos where the CDN accepts the minted token (~1–2 s).
        //
        // Path B — WKWebView HLS: awaits `wkHLSEarlyTask` (started in loadAsync, already
        //   in-flight). Bypasses the 6 s BotGuard wait on cold starts. Fast for rqh=1 videos
        //   where the CDN probe returns 403 (~3–4 s from loadAsync start).
        //
        // Path C — AndroidVR adaptive: fetches playerInfo via the ANDROID_VR (Oculus Quest)
        //   client, which is CDN-exempt from rqh=1 / pot= token requirements. Runs concurrently
        //   with Path A and B. Expected ~2–3 s cold; beats serial WKWebView extraction (~3–5 s).
        //
        // fix30 (task #230): Pre-fetch TVEmbedded playerInfo in parallel with the race on iOS.
        // If all race paths fail, Phase 1 (TVEmbedded serial) can consume the already-resolved
        // result instead of waiting an additional ~0.5–1 s for a fresh network request.
        // tvOS already starts tvEmbeddedEarlyTask inside tryAllStreams (fix2); on iOS we fire
        // it here so the prefetch begins as soon as the race paths do.
        #if !os(tvOS)
        if tvEmbeddedEarlyTask == nil {
            let prefetchVideoId = video.id
            tvEmbeddedEarlyTask = Task { [weak self] in
                guard let self else { return nil }
                return try? await self.api.fetchPlayerInfoTVEmbedded(videoId: prefetchVideoId)
            }
            playerLog.notice("[TVEmbedded] fix30: started iOS TVEmbedded early pre-fetch alongside race paths")
        }
        #endif
        //
        // Key safety property: all paths are @MainActor, so `player.replaceCurrentItem` and
        // `itemObserverTask` mutations are always serialised. Losing paths' status streams
        // exit via task cancellation.
        var winningPath: Int?
        await withTaskGroup(of: (Bool, Int).self) { raceGroup in
            // Path A, B, C are @MainActor methods — calling them via `await self.`
            // from these nonisolated closures hops to the main actor for each path.
            // They interleave cooperatively at every `await` suspension point.
            raceGroup.addTask { (await self.racePathA(video: video), 0) }
            raceGroup.addTask { (await self.racePathB(video: video), 1) }
            #if os(tvOS)
            // fix2: Skip racePathC on tvOS. A fresh AndroidVR fetch hits the same rqh=1
            // timeout (2s) for the same video — wasting 2s just to fail again. The
            // TVEmbedded pre-fetch (tvEmbeddedEarlyTask) already runs concurrently from
            // tryAllStreams; Phase 1 will consume it instantly after the race.
            raceGroup.addTask { (false, 2) }
            #else
            raceGroup.addTask { (await self.racePathC(video: video), 2) }
            #endif
            for await (result, path) in raceGroup where result {
                winningPath = path
                raceGroup.cancelAll()
                return
            }
        }
        return winningPath
    }

    private func finishWinningFallbackPath(
        _ path: Int, video: Video, playerInfo: PlayerInfo?, cached: CachedVideoData?
    ) {
        switch path {
        case 1:
            playerLog.notice(
                "✅ [webView] Path B won — WKWebView HLS playing via wkHLSEarlyTask — exhaustiveRetry done")
            // tryWebViewHLS does not call launchPhase2 internally — do it here so Phase 2
            // metadata (nextVideo, endCards, sponsorSegments) is fetched and cached data is used.
            if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
        case 2:
            playerLog.notice("[AndroidVR] ✅ Path C won — AndroidVR adaptive — exhaustiveRetry done")
            // attemptComposition already called launchPhase2(vrInfo) with the correct AndroidVR
            // playerInfo. Do NOT call it again — a second call would cancel the first phase2Task
            // and restart it with the stale iOS playerInfo, reverting availableFormats to
            // rqh=1-blocked streams and breaking quality switches.
            //
            // If AndroidVR composed at low quality (maxH < 480 and below user's preferred),
            // schedule a background HLS quality upgrade via TVEmbedded or MWEB while the
            // video is already playing at the lower quality. Does not affect readyToPlay timing.
            let vrMaxH = availableFormats.map(\.height).max() ?? 0
            let preferredH =
                settings.preferredQuality == .auto
                ? Self.displayMaxVideoHeight()
                : (settings.preferredQuality.maxHeight ?? 1080)
            if vrMaxH > 0 && vrMaxH < min(preferredH, 480) {
                playerLog.notice(
                    "[AndroidVR] maxH=\(vrMaxH) < preferred \(min(preferredH, 480))p — scheduling background HLS quality upgrade"
                )
                let upgradeVideo = video
                Task { [weak self] in await self?.backgroundQualityUpgrade(video: upgradeVideo) }
            }
        default:
            playerLog.notice("[BotGuardWV] ✅ adaptive streaming via minted BotGuard token — exhaustiveRetry done")
        // attemptComposition / attemptURL already called launchPhase2(webInfo). Same
        // reasoning as Path C: don't override with stale playerInfo.
        }
    }

    private func trySerialWebViewHLS(
        video: Video, playerInfo: PlayerInfo?, cached: CachedVideoData?
    ) async -> Bool {
        // Both race paths failed — fall back to serial WKWebView extraction in case
        // the early task returned nil (e.g. network timeout, JS player error).
        // Skip serial extraction when Path B already hit a CDN permission error — a fresh
        // extraction produces the same CDN-signed URL which will get the same 403.
        // fix235: guard cancellation before expensive serial extraction — the exhaustiveRetry
        // task may have been cancelled by a subsequent load() or stop() call.
        guard !Task.isCancelled else {
            playerLog.notice(
                "⚠️ [webView] race failed but task is cancelled — skipping serial extraction for \(video.id)")
            return true
        }
        if wkHLSPermissionDenied {
            playerLog.notice(
                "⚠️ [webView] race Path B hit CDN permission error — skipping serial extraction, going straight to client chain"
            )
        } else {
            playerLog.notice("⚠️ [webView] race failed — attempting serial WKWebView extraction")
            isLoading = true
            retryStatusMessage = "Still loading\u{2026}"
            // Use serialExtract() instead of extractHLSURL() directly: serialExtract awaits any
            // in-flight extraction (for any video) before starting a new one, preventing the
            // cross-video cancellation chain where two concurrent serial callers (for video A and
            // video B) each call extractHLSURL and cancel each other via finish(url:nil).
            let serialURL = await YouTubeWebViewHLSExtractor.shared.serialExtract(videoId: video.id)
            let nSolverSerial = YouTubeWebViewHLSExtractor.shared.extractedNSolver
            if let pot = YouTubeWebViewHLSExtractor.shared.extractedPoToken {
                await api.storeExternalPoToken(pot, for: video.id)
            }
            if let serialURL {
                if await tryWebViewHLS(serialURL, nSolver: nSolverSerial, for: video) {
                    playerLog.notice("✅ [webView] serial WKWebView HLS playing — exhaustiveRetry done")
                    if let playerInfo { launchPhase2(video: video, info: playerInfo, cached: cached) }
                    return true
                }
                playerLog.notice("⚠️ [webView] serial HLS load failed — falling through to client retry chain")
            } else {
                playerLog.notice("⚠️ [webView] serial WKWebView extraction returned nil — proceeding with client chain")
            }
        }
        return false
    }
    #endif

    private struct FallbackFetchedStream: Sendable {
        let priority: Int
        let label: String
        let info: PlayerInfo
        let skipMuxed: Bool
    }
    private enum FallbackFetchOutcome: Sendable {
        case result(FallbackFetchedStream)
        case ipBlocked(Error)
    }

    private struct FallbackFetchResults {
        var pendingNonHLS: [FallbackFetchedStream] = []
        var androidInfoForMuxed: PlayerInfo?
        var fetchIPBlockError: Error?
        var parallelPlaySucceeded = false
    }

    private func fetchFallbackResults(video: Video, attempt: Int) async -> FallbackFetchResults {
        // Capture @MainActor state before entering the task group.
        let capturedEarlyTask = tvEmbeddedEarlyTask
        tvEmbeddedEarlyTask = nil
        let capturedHasAuth = hasAuthToken

        var fetched = FallbackFetchResults()

        await withTaskGroup(of: Optional<FallbackFetchOutcome>.self) { fetchGroup in

            addFallbackFetchTasks(
                to: &fetchGroup, video: video, attempt: attempt, earlyTask: capturedEarlyTask, hasAuth: capturedHasAuth)

            // Process results as they arrive
            for await maybeOutcome in fetchGroup {
                guard let outcome = maybeOutcome else { continue }
                switch outcome {
                case .ipBlocked(let err):
                    fetched.fetchIPBlockError = err
                    fetchGroup.cancelAll()
                    return
                case .result(let candidate):
                    // Side-effects that need the concrete label/info
                    if candidate.label.hasPrefix("iOS[") {
                        await VideoPreloadCache.shared.store(playerInfo: candidate.info, for: video.id)
                    }
                    if candidate.label.hasPrefix("Android[") && !candidate.label.contains("VR") {
                        fetched.androidInfoForMuxed = candidate.info
                    }
                    // HLS present → try immediately; first success wins and cancels rest
                    if candidate.info.hlsURL != nil {
                        if await tryAllStreams(
                            video: video, info: candidate.info,
                            label: candidate.label, skipMuxed: candidate.skipMuxed)
                        {
                            fetched.parallelPlaySucceeded = true
                            fetchGroup.cancelAll()
                            return
                        }
                    } else {
                        // No HLS (adaptive/muxed only) → defer until all fetches done
                        fetched.pendingNonHLS.append(candidate)
                    }
                }
            }
        }  // end withTaskGroup

        return fetched
    }

    private func addFallbackFetchTasks(
        to group: inout TaskGroup<FallbackFetchOutcome?>, video: Video, attempt: Int,
        earlyTask: Task<PlayerInfo?, Never>?, hasAuth: Bool
    ) {
        // 0 — TVAuth (authenticated TV client, HLS)
        if hasAuth {
            group.addTask {
                guard let info = try? await self.api.fetchPlayerInfoAuthenticated(videoId: video.id) else {
                    return nil
                }
                return .result(
                    FallbackFetchedStream(priority: 0, label: "TVAuth[\(attempt)]", info: info, skipMuxed: true))
            }
        }

        // 1 — MWEB (no embedding restriction, no pot= required for HLS)
        group.addTask {
            guard let info = try? await self.api.fetchPlayerInfoMWEB(videoId: video.id) else { return nil }
            return .result(FallbackFetchedStream(priority: 1, label: "MWEB[\(attempt)]", info: info, skipMuxed: true))
        }

        // 2 — TVEmbedded (consume fix2/fix30 pre-fetch if available)
        let earlyTask2 = earlyTask
        group.addTask {
            if let et = earlyTask2, let info = await et.value {
                return .result(
                    FallbackFetchedStream(priority: 2, label: "TVEmbedded[\(attempt)]", info: info, skipMuxed: true))
            }
            guard let info = try? await self.api.fetchPlayerInfoTVEmbedded(videoId: video.id) else {
                return nil
            }
            return .result(
                FallbackFetchedStream(priority: 2, label: "TVEmbedded[\(attempt)]", info: info, skipMuxed: true))
        }

        // 3 — WebSafari (WEB + macOS Safari UA, HLS for embedding-disabled)
        group.addTask {
            guard let info = try? await self.api.fetchPlayerInfoWebSafari(videoId: video.id) else { return nil }
            return .result(
                FallbackFetchedStream(priority: 3, label: "WebSafari[\(attempt)]", info: info, skipMuxed: true))
        }

        // 4 — iOS (authenticated preferred; IP-block detection)
        let hasAuth4 = hasAuth
        group.addTask {
            do {
                let info: PlayerInfo
                if hasAuth4, let auth = try? await self.api.fetchPlayerInfoiOSAuthenticated(videoId: video.id) {
                    info = auth
                } else {
                    info = try await self.api.fetchPlayerInfo(videoId: video.id)
                }
                return .result(
                    FallbackFetchedStream(priority: 4, label: "iOS[\(attempt)]", info: info, skipMuxed: true))
            } catch {
                if case APIError.ipBlocked = error { return .ipBlocked(error) }
                return nil
            }
        }

        // 5 — Android (IP-block detection; saved for muxed fallback)
        group.addTask {
            do {
                let info = try await self.api.fetchPlayerInfoAndroid(videoId: video.id)
                return .result(
                    FallbackFetchedStream(priority: 5, label: "Android[\(attempt)]", info: info, skipMuxed: true))
            } catch {
                if case APIError.ipBlocked = error { return .ipBlocked(error) }
                return nil
            }
        }

        // 6 — AndroidVR (CDN-exempt rqh=1, 2s composition timeout)
        group.addTask {
            guard let info = try? await self.api.fetchPlayerInfoAndroidVR(videoId: video.id) else { return nil }
            return .result(
                FallbackFetchedStream(priority: 6, label: "AndroidVR[\(attempt)]", info: info, skipMuxed: true))
        }
    }

    private func retryFallbackClients(video: Video, attempt: Int) async -> Bool {
        guard !Task.isCancelled else { return true }
        retryAttempts = attempt
        isLoading = true
        retryStatusMessage = attempt == 1 ? "Trying alternative sources\u{2026}" : "Retrying (\(attempt)/3)\u{2026}"
        playerLog.notice("Exhaustive retry \(attempt)/3 for \(video.id)")

        // Evict the stale cache entry so each attempt gets fresh signed URLs.
        await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)

        // --- Parallel fetch: fire all 7 API calls concurrently ---
        //
        // Each fetchPlayerInfo* is an independent network round-trip (~0.5–1 s).
        // Running them serially added 3.5–7 s of unnecessary latency on every load
        // for videos where the first few clients fail (rqh=1, embedding-disabled, etc.).
        // Running them in parallel collapses that to ~1 s (slowest single fetch).
        //
        // Play strategy:
        //  • HLS results are tried immediately as they arrive — first HLS success wins.
        //  • Non-HLS (adaptive-only) results are queued and tried in priority order
        //    after all fetches complete, so the fastest HLS client always gets priority
        //    regardless of which fetch finished first.
        //
        // Priority (lower = higher priority, mirrors proven probe data 2026-06-05):
        //   0 TVAuth  1 MWEB  2 TVEmbedded  3 WebSafari  4 iOS  5 Android  6 AndroidVR

        let fetched = await fetchFallbackResults(video: video, attempt: attempt)
        let parallelPlaySucceeded = fetched.parallelPlaySucceeded
        let fetchIPBlockError = fetched.fetchIPBlockError
        let androidInfoForMuxed = fetched.androidInfoForMuxed
        var pendingNonHLS = fetched.pendingNonHLS

        if parallelPlaySucceeded { return true }

        if let ipErr = fetchIPBlockError {
            playerLog.error(
                "❌ IP blocked during parallel fetch (attempt \(attempt)) — \(ViewModelLogger.errorSummary(ipErr))")
            self.error = ipErr
            return true
        }
        guard !Task.isCancelled else { return true }

        // Try non-HLS results (adaptive-only) in priority order.
        //
        // AndroidVR (priority=6) is skipped when a muxed fallback is available:
        // its 2s loadTracks timeout would delay muxed play with no gain when all
        // other methods already failed. Instead, muxed plays immediately and
        // backgroundQualityUpgrade retries AndroidVR (+ TVEmbedded/MWEB) in the
        // background — upgrading to higher quality while the video is already playing.
        pendingNonHLS.sort { $0.priority < $1.priority }
        let hasMuxedFallback = androidInfoForMuxed?.bestMuxedDownloadURL != nil
        playerLog.notice(
            "[parallel fetch] attempt \(attempt): \(pendingNonHLS.count) non-HLS candidate(s) — trying in priority order (hasMuxed=\(hasMuxedFallback))"
        )
        for candidate in pendingNonHLS {
            guard !Task.isCancelled else { return true }
            // Skip AndroidVR when muxed is available — see comment above.
            if hasMuxedFallback && candidate.label.hasPrefix("AndroidVR[") {
                playerLog.notice(
                    "[parallel fetch] skipping \(candidate.label) (muxed available — background upgrade will retry)"
                )
                continue
            }
            if await tryAllStreams(
                video: video, info: candidate.info,
                label: candidate.label, skipMuxed: candidate.skipMuxed)
            {
                return true
            }
        }

        guard !Task.isCancelled else { return true }

        // --- Muxed direct MP4 (360p last resort) ---
        // Only reached when ALL HLS + adaptive attempts above failed.
        // On success: schedule backgroundQualityUpgrade to try TVEmbedded/MWEB HLS
        // and AndroidVR adaptive in the background while the video is already playing.
        if let androidInfo = androidInfoForMuxed, androidInfo.bestMuxedDownloadURL != nil {
            isLoading = true
            retryStatusMessage = "Using fallback stream\u{2026}"
            playerLog.notice("[Android[\(attempt)]] All adaptive failed — trying muxed fallback")
            if await tryAllStreams(
                video: video, info: androidInfo,
                label: "Android[\(attempt)]/muxed")
            {
                // Muxed playing — attempt quality upgrade in background while user watches.
                let upgradeVideo = video
                Task { [weak self] in await self?.backgroundQualityUpgrade(video: upgradeVideo) }
                return true
            }
            // Android muxed failed (possibly AVF -11828 "Cannot Open" on SABR/long-video URLs,
            // or URL expiry). Try the Web/iOS client muxed URL as a final rescue path.
            // fetchPlayerInfo() returns iOS-client playerInfo whose muxed URL is
            // CDN-signed with standard MP4 headers, avoiding the TVHTML5 SABR issue.
            playerLog.notice("[Android[\(attempt)]] Muxed failed — trying Web client muxed fallback")
            do {
                let webInfo = try await api.fetchPlayerInfo(videoId: video.id)
                if webInfo.bestMuxedDownloadURL != nil {
                    if await tryAllStreams(
                        video: video, info: webInfo,
                        label: "Web[\(attempt)]/muxed")
                    {
                        return true
                    }
                }
            } catch {
                playerLog.error(
                    "Web client muxed fallback fetch failed (attempt \(attempt)): \(ViewModelLogger.errorSummary(error))"
                )
            }
        }
        return false
    }

}
