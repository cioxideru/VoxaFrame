import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Initial Stream Loading

extension PlaybackViewModel {

    func loadAsync(video: Video) async {
        await prepareStreamLoading(video: video)

        if startLocalPlayback(video: video) { return }

        do {
            try await loadPrimaryStream(video: video)
        } catch {
            isLoading = false
            // Ignore CancellationError — it is expected when stop() or a new load()
            // cancels an in-flight loadTask. Surfacing it would show a spurious error
            // banner on the next video open.
            guard !(error is CancellationError) else { return }
            playerLog.error("❌ loadAsync error: \(String(describing: error))")
            // signInRequired from the primary iOS client can be a false-positive when
            // the user's auth session is broken (Multilogin INVALID_TOKENS): YouTube
            // returns LOGIN_REQUIRED even for public content. Route to exhaustiveRetry
            // so fallback clients (WKWebView, TVEmbedded, WebSafari) can try without
            // the broken auth token. Only applies when signed-in — unsigned users
            // hitting truly age-restricted content get the error immediately.
            // Firebase: 0edf6a2f (AutoDiagnostic(1)) + db9e0581 (APIError(6)).
            //
            // httpError(403) from the authenticated TV client is the same class of failure:
            // a stale/expired auth token causes YouTube to return a raw HTTP 403 (no JSON
            // body) instead of a LOGIN_REQUIRED playabilityStatus. Since signInRequired
            // detection requires a parseable body, these arrive here as httpError(403).
            // Route them to exhaustiveRetry too — unauthenticated fallback clients may
            // succeed without the broken token. Firebase: 5f445659 (APIError(0) HTTP 403).
            let shouldRetryWithFallback: Bool
            if let apiErr = error as? APIError {
                switch apiErr {
                case .signInRequired:
                    shouldRetryWithFallback = hasAuthToken
                case .httpError(403):
                    shouldRetryWithFallback = hasAuthToken
                default:
                    shouldRetryWithFallback = false
                }
            } else {
                shouldRetryWithFallback = false
            }
            if shouldRetryWithFallback {
                playerLog.notice(
                    "⚠️ \(error.localizedDescription) from primary client (signed-in user) — routing to exhaustiveRetry for fallback clients"
                )
                exhaustiveRetryTask?.cancel()
                exhaustiveRetryTask = Task { [weak self] in
                    await self?.exhaustiveRetry(video: video, originalError: error)
                }
            } else {
                self.error = error
            }
        }
    }

    private func loadPrimaryStream(video: Video) async throws {
        // --- Cache-first load ---
        // Check VideoPreloadCache for all data types. Fresh hits skip the network
        // call entirely; partial hits fill only the missing pieces in parallel.
        let cached = await VideoPreloadCache.shared.consume(videoId: video.id)
        // Log the full cache verdict as a single breadcrumb so wrong-video / prefetch-race
        // scenarios are immediately visible in Firebase reports.
        let cacheVerdict =
            "playerInfo=\(cached.playerInfo != nil) nextInfo=\(cached.nextInfo != nil) sponsor=\(cached.sponsorSegments != nil) endCards=\(cached.endCards != nil) tracking=\(cached.trackingURLs != nil) complete=\(cached.isComplete)"
        if cached.playerInfo != nil {
            playerLog.notice("PREFETCH_HIT: \(video.id) — \(cacheVerdict)")
        } else {
            playerLog.notice("PREFETCH_MISS: \(video.id) — \(cacheVerdict)")
        }
        let wkHLSCacheHit = await VideoPreloadCache.shared.cachedWKHLSURL(for: video.id) != nil
        self.cacheStatusSummary =
            "pi:\(cached.playerInfo != nil ? "HIT" : "MISS") wkHLS:\(wkHLSCacheHit ? "HIT" : "MISS")"

        // Apply cached DeArrow overrides (community title / thumbnail timestamp).
        // Done immediately after consume() so VideoCardView can show the override
        // as soon as the player screen appears, before Phase 2 completes.
        if settings.deArrowEnabled, let deArrow = cached.deArrowBranding {
            currentVideo?.deArrowTitle = deArrow.title
            currentVideo?.deArrowThumbnailTimestamp = deArrow.thumbnailTimestamp
        }

        // --- Player info (stream URLs + metadata) ---
        // Kick off an authenticated TV-client player request in parallel with the
        // primary iOS player fetch when the cache doesn't already have tracking URLs.
        // cached.trackingURLs is PlaybackTrackingURLs?? — .some(nil) means the prefetch
        // ran before auth was ready; treat that as a miss so we still get live URLs.
        let cachedTrackingURLs: PlaybackTrackingURLs? = cached.trackingURLs.flatMap { $0 }
        let authTrackingTask: Task<PlaybackTrackingURLs?, Never>?
        if cachedTrackingURLs != nil {
            // Tracking URLs came from the cache; no need for a parallel TV-client call.
            authTrackingTask = nil
        } else {
            authTrackingTask = Task<PlaybackTrackingURLs?, Never> { [api = self.api] in
                await api.fetchAuthenticatedTrackingURLs(videoId: video.id)
            }
        }

        // Fetch player info using the iOS client (unauthenticated).
        // If YouTube returns UNPLAYABLE/LOGIN_REQUIRED and the user is signed in,
        // automatically retry with the authenticated TV client before showing an error.
        let (info, visionOSHLSInfo) = try await initialPlayerInfo(video: video, cached: cached)

        // BUG-005 fix: guard against rapid navigation — if the user navigated away while we
        // were awaiting the player info, discard this result rather than overwrite ViewModel state.
        guard currentVideo?.id == video.id else {
            playerLog.notice("[loadAsync] superseded: discarding playerInfo for \(video.id)")
            return
        }
        applyInitialPlayerInfo(info)

        let sponsorCached = applyInitialSponsorSegments(video: video, cached: cached)

        // Restore saved watch position (mirrors VideoStateController)
        let savedState = await VideoStateStore.shared.state(for: video.id)
        if let pos = savedState?.position, pos > 5 {
            savedPositionToRestore = pos
            playerLog.notice("Restoring position \(Int(pos))s for \(video.id)")
        }
        // Filter the quality picker to only heights that the HLS manifest actually
        // offers. The iOS player response lists all adaptive CDN formats at every
        // quality, but the HLS variant playlist may omit qualities the CDN has not
        // encoded for this video. Parsing the manifest prevents the user from
        // selecting a quality tier that AVPlayer's ABR would silently ignore.
        // HLS variant fetch is NOT on the critical path: we use the master URL for
        // initial playback, so AVPlayer does not need variant URLs to show the first
        // frame. Fetch in a background Task and update the quality picker when done.
        prefetchInitialHLSVariants(info: info)

        guard let streamURL = info.preferredStreamURL else {
            // iOS client returned adaptive-only formats (no HLS, no muxed stream).
            // Try adaptive composition first — iOS adaptive streams (c=IOS) may be rqh=0.
            // attemptComposition has a rqh=1 guard and returns false immediately if blocked;
            // in that case (or if AVPlayer 403s) we fall through to exhaustiveRetry.
            if !info.formats.isEmpty {
                playerLog.notice("⚠️ adaptive-only iOS response — trying adaptive composition (c=IOS may be rqh=0)")
                if await tryAllStreams(video: video, info: info, label: "iOS", skipMuxed: true) { return }
                playerLog.notice("⚠️ iOS adaptive composition failed — retrying exhaustively")
                await exhaustiveRetry(video: video, originalError: nil, playerInfo: info, cached: cached)
                return
            }
            playerLog.error("❌ No stream URL after successful parse (should not happen)")
            throw APIError.decodingError("No stream URL")
        }
        // When the iOS client has no HLS URL (non-embeddable videos return only muxed
        // 360p), playing streamURL directly would settle for 360p without ever
        // trying AndroidVR adaptive (which works for these videos via visitorData).
        // Route through exhaustiveRetry first; it will try all adaptive paths and fall
        // back to muxed 360p as Phase 2 if all adaptive attempts fail.
        // VISIONOS HLS needs its own policy (codec-filtered master, visionOS UA) —
        // also when the VISIONOS response comes back from VideoPreloadCache on a replay.
        if let visionOSHLSInfo = visionOSHLSInfo ?? (info.hlsURL != nil && info.isFromVisionOSClient ? info : nil) {
            if await tryAllStreams(video: video, info: visionOSHLSInfo, label: "VisionOS", skipMuxed: true) {
                playerLog.notice("[VisionOS] ✅ native HLS playback from loadAsync")
                #if canImport(WebKit)
                YouTubeWebViewHLSExtractor.shared.cancelCurrentExtraction()
                #endif
                return
            }
            await exhaustiveRetry(video: video, originalError: nil, playerInfo: info, cached: cached)
            return
        }
        if info.hlsURL == nil {
            playerLog.notice(
                "⚠️ iOS response: no HLS — routing to exhaustiveRetry for adaptive quality before muxed fallback")
            await exhaustiveRetry(video: video, originalError: nil, playerInfo: info, cached: cached)
            return
        }
        // Build the item after the guard above has validated preferredStreamURL.
        // parsePlayerInfo throws APIError.unavailable when streamingData is absent.
        // For initial load always use the master HLS manifest so that AVPlayer
        // receives EXT-X-MEDIA alternate audio renditions (dubbed tracks, etc.).
        // Variant playlists omit EXT-X-MEDIA entries, which causes AudioTrackManager
        // to exit early and produce silent audio when a non-auto quality is preferred.
        // Quality is steered via AVPlayerItem hints (preferredMaximumResolution /
        // preferredPeakBitRate) which AVPlayer honours during ABR adaptation.
        let (item, isHLS) = makeInitialPlayerItem(streamURL: streamURL, info: info)

        observeInitialPlayerItem(item, info: info, isHLS: isHLS)

        observePlaybackEndAndStalls(for: item)

        await beginInitialPlayback(
            video: video,
            context: InitialPlaybackContext(
                cached: cached, info: info, cachedTrackingURLs: cachedTrackingURLs,
                authTrackingTask: authTrackingTask, sponsorCached: sponsorCached))
    }

    private func prepareStreamLoading(video: Video) async {
        // Defensive re-establish: guarantees rateObserver is live for every load,
        // even if this view model instance went through suspend() (which
        // invalidates it) and is now loading a different video directly via
        // load()/loadAsync() rather than resume(). Idempotent — safe to call even
        // when already set up.
        setupRateObserver()
        isLoading = true
        stallCount = 0
        firstRapidStallTime = nil
        needsQuickStartup = true
        // Note: isLoading = false is set in the AVPlayerItem .readyToPlay observer so the
        // spinner stays visible until the first frame is actually ready. It was previously
        // cleared after player.rate was set, which dismissed the spinner before buffering
        // completed on slow networks (GitHub issue #53).
        playerLog.notice(
            "[loadAsync] start id=\(video.id) title=\(video.title) player.rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue)"
        )

        #if canImport(UIKit)
        // Seed the lock-screen Now Playing widget BEFORE the ~10 s network phase so
        // the user sees the title/channel on the lock screen immediately.
        // stop() calls setActive(false) which tears down the MediaRemote XPC connection;
        // re-activating here (rather than waiting until readyToPlay) closes the gap
        // during which PlayerRemoteXPC reports err=-12860/-12785 and the widget is absent.
        setupRemoteCommandCenter()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            playerLog.notice("[loadAsync] AVAudioSession activated early (lock-screen pre-seed)")
        } catch {
            playerLog.error("[loadAsync] early setActive failed: \(error.localizedDescription)")
        }
        updateNowPlayingInfo()
        #endif

        // Fetch the BotGuard PO token before the primary stream attempt.
        // Awaited (with a 2 s safety timeout) so api.hasPoToken(for:) returns true during
        // the rqh=1 adaptive stream check in tryAllStreams — preventing an unnecessary
        // WKWebView fallback on every cold start.
        // BotGuardClient completes in <500 ms on first run; cached result returns in <1 ms
        // thereafter (TTL ~12 h). The 2 s timeout is a safety net for slow networks only.
        let capturedAPI = api
        let capturedVideoId = video.id
        if !(await api.hasPoToken(for: video.id)) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await capturedAPI.prefetchPoToken(for: capturedVideoId) }
                group.addTask { try? await Task.sleep(nanoseconds: PlaybackTuning.poTokenPrefetchTimeoutNanoseconds) }
                _ = await group.next()
                group.cancelAll()
            }
        }
        #if canImport(WebKit)
        // Fire-and-forget: start WKWebView BotGuard pipeline in the background.
        // Takes 3–8 s; by the time the primary attempt fails and exhaustiveRetry runs,
        // it may be ready to provide a full getMinter-minted token (CDN-accepted for rqh=1).
        // Zero impact on primary path timing — runs concurrently.
        if !BotGuardWebViewRunner.shared.isReady {
            let capturedVideoIdForWV = video.id
            Task { @MainActor in
                await BotGuardWebViewRunner.shared.prepare(for: capturedVideoIdForWV)
            }
        }
        // Fire-and-forget: start WKWebView HLS extraction concurrently with the primary path.
        // For rqh=1 videos the ~2 s extraction overlaps the primary iOS attempt so the URL
        // is ready (or nearly ready) by the time exhaustiveRetry reaches Phase -2, saving
        // the serial 2–4 s wait. For non-rqh=1 videos the task completes silently unused.
        // Use priorityExtract() (not serialExtract) so earlyTask starts wv.load() IMMEDIATELY
        // without waiting for any in-flight VideoCardView second-serialExtract. A background
        // card extraction (e.g. POTUARPb1CU) may have captured pendingSerialTask just before
        // the tap; chaining onto it (serialExtract's behaviour) delays wv.load() by ~2.3 s,
        // making CDN trust too stale (~0.5 s) for AndroidVR loadTracks (R12 regression).
        // priorityExtract registers itself in pendingSerialTask so race-failed handlers still
        // chain onto it correctly via serialExtract.
        let capturedVideoIdForHLS = video.id
        // Reuse an in-flight pre-warm started by stop() for the same video (fix10).
        // If stop() already started serialExtract for this videoId, wkHLSEarlyTask is
        // non-nil and for the same video — just let it run; racePathB awaits its value.
        if wkHLSEarlyTask == nil {
            wkHLSEarlyTaskVideoId = capturedVideoIdForHLS
            wkHLSEarlyTask = Task { @MainActor in
                // priorityExtract bypasses pendingSerialTask chaining → wv.load() starts
                // immediately at tap time. For pfa/1 rqh=1 videos like _DY9cTWakcM, this
                // refreshes CDN IP-level trust so it is only ~2.5 s old when AndroidVR
                // loadTracks runs — within the ~2.5 s trust window.
                return await YouTubeWebViewHLSExtractor.shared.priorityExtract(videoId: capturedVideoIdForHLS)
            }
        }
        #endif

    }

    private func initialPlayerInfo(
        video: Video, cached: CachedVideoData
    ) async throws -> (PlayerInfo, PlayerInfo?) {
        let info: PlayerInfo
        var visionOSHLSInfo: PlayerInfo?
        if let cachedInfo = cached.playerInfo {
            playerLog.notice(
                "PREFETCH_HIT: playerInfo for \(video.id) — skipping network (hls=\(cachedInfo.hlsURL != nil) dash=\(cachedInfo.dashURL != nil) formats=\(cachedInfo.formats.count))"
            )
            info = cachedInfo
        } else if let inFlight = await VideoPreloadCache.shared.inFlightPlayerFetch(videoId: video.id),
            let coalescedInfo = await inFlight.value
        {
            playerLog.notice("PREFETCH_COALESCE: playerInfo for \(video.id) — joined in-flight prefetch task")
            info = coalescedInfo
        } else if let visionInfo = try? await api.fetchPlayerInfoVisionOS(videoId: video.id),
            visionInfo.hlsURL != nil
        {
            // VISIONOS first: token-free HLS in one request. The iOS → TV → Android chain
            // below returns SABR-only / 360p-only responses for most videos and costs ~2 s.
            info = visionInfo
            visionOSHLSInfo = visionInfo
            await VideoPreloadCache.shared.store(playerInfo: info, for: video.id)
        } else {
            info = try await fetchPrimaryPlayerInfo(video: video)
            await VideoPreloadCache.shared.store(playerInfo: info, for: video.id)
        }
        return (info, visionOSHLSInfo)
    }

    private func applyInitialPlayerInfo(_ info: PlayerInfo) {
        playerInfo = info
        availableFormats = Self.deduplicatedVideoFormats(info.formats)
        playerLog.notice(
            "[loadAsync] availableFormats after initial dedup: raw=\(info.formats.count) deduped=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)"
        )
        availableCaptions = info.captionTracks
        autoApplyCaptionPreference(tracks: info.captionTracks)
        selectedFormat = nil

        playerLog.notice(
            "playerInfo: formats=\(info.formats.count) hlsURL=\(info.hlsURL?.absoluteString ?? "nil") dashURL=\(info.dashURL?.absoluteString ?? "nil")"
        )
        for (index, fmt) in info.formats.enumerated() {
            playerLog.notice(
                "  format[\(index)] mimeType=\(fmt.mimeType) quality=\(fmt.label) url=\(fmt.url?.absoluteString.prefix(80) ?? "nil")"
            )
        }

        let prefURL = info.preferredStreamURL
        playerLog.notice("preferredStreamURL=\(prefURL?.absoluteString.prefix(120) ?? "nil")")

    }

    private func applyInitialSponsorSegments(video: Video, cached: CachedVideoData) -> Bool {
        // --- SponsorBlock ---
        // Segments from the cache are applied inline (fast path, zero network cost).
        // Stale segments are applied immediately and revalidated in Phase 2.
        // When not cached, the fetch is deferred to Phase 2 (runs concurrently with
        // AVPlayer buffering) so it does not block the spinner.
        sponsorSegments = []
        let channelIsExcluded =
            video.channelId.map {
                settings.sponsorBlockExcludedChannels.keys.contains($0)
            } ?? false
        playerLog.notice(
            "[sponsorBlock] enabled=\(settings.sponsorBlockEnabled) channelExcluded=\(channelIsExcluded) categories=\(settings.activeSponsorCategories.count)"
        )
        var sponsorCached = false
        if settings.sponsorBlockEnabled, !channelIsExcluded {
            if let cachedSegments = cached.sponsorSegments {
                // Cache hit (fresh or stale) — apply immediately.
                let isStaleSponsor = cached.staleFields.contains(.sponsorSegments)
                let minDur = settings.sponsorBlockMinSegmentDuration
                let filtered =
                    minDur > 0
                    ? cachedSegments.filter { ($0.end - $0.start) >= minDur }
                    : cachedSegments
                sponsorSegments = filtered
                let sbCacheLabel = isStaleSponsor ? "STALE" : "HIT"
                playerLog.notice(
                    "[sponsorBlock] cache \(sbCacheLabel): \(cachedSegments.count) raw -> \(filtered.count) applied"
                )
                // Mark as "not fully cached" only when stale so Phase 2 revalidates.
                sponsorCached = !isStaleSponsor
            } else {
                playerLog.notice("[sponsorBlock] cache MISS — will fetch in phase2")
            }
            // Full miss or stale: Phase 2 will fetch or revalidate.
        } else {
            playerLog.notice("[sponsorBlock] skipped (disabled or channel excluded)")
            sponsorCached = true  // disabled/excluded — no fetch needed in Phase 2
        }

        return sponsorCached
    }

    private func prefetchInitialHLSVariants(info: PlayerInfo) {
        if let hlsURL = info.hlsURL {
            Task { [weak self] in
                let variantURLs = await self?.fetchHLSVariantURLs(url: hlsURL) ?? [:]
                guard let self, !Task.isCancelled, !variantURLs.isEmpty else { return }
                self.hlsVariantURLs = variantURLs
                let beforeCount = self.availableFormats.count
                self.availableFormats = self.availableFormats.filter { variantURLs.keys.contains($0.height) }
                playerLog.notice(
                    "HLS variants (bg): \(variantURLs.keys.sorted().reversed()) — filtered quality picker \(beforeCount) → \(self.availableFormats.count) options"
                )
                if let sel = self.selectedFormat, !variantURLs.keys.contains(sel.height) {
                    self.selectedFormat = nil
                }
            }
        }
    }

    private func makeInitialPlayerItem(
        streamURL: URL, info: PlayerInfo
    ) -> (AVPlayerItem, Bool) {
        let initialStreamURL = streamURL
        // Compute effective quality cap: explicit setting only.
        // Auto quality leaves hints unconstrained (zero) so AVPlayer's ABR can freely
        // select the highest variant the network supports.
        let initialMaxH: Int
        if settings.preferredQuality != .auto, let height = settings.preferredQuality.maxHeight {
            initialMaxH = height
            let matchingFormat = availableFormats.first { $0.height <= height }
            selectedFormat = matchingFormat
            playerLog.notice("Initial quality \(height)p — using master URL with ABR hints")
        } else {
            initialMaxH = 0  // unconstrained — resolved to .zero / 0 below
            playerLog.notice("Initial quality Auto — unconstrained (no resolution/bitrate cap)")
        }
        playerLog.notice("Starting AVPlayer with: \(initialStreamURL.absoluteString.prefix(120))")
        lastAttemptedStreamURL = initialStreamURL
        // HLS manifests are signed by WEB_EMBEDDED_PLAYER (web client) — use browser UA
        // plus Origin + Referer matching the embed context to unlock higher-quality variants.
        // Muxed/adaptive direct URLs are signed by the iOS client — use iOS UA.
        let isHLS = (info.hlsURL != nil && initialStreamURL == info.hlsURL)
        let initialUA = isHLS ? InnerTubeClients.Web.userAgent : InnerTubeClients.iOS.userAgent
        var initialHeaders: [String: String] = ["User-Agent": initialUA]
        if isHLS {
            initialHeaders["Origin"] = "https://www.youtube.com"
            initialHeaders["Referer"] = "https://www.youtube.com/"
        }
        let playerAsset = AVURLAsset(
            url: initialStreamURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": initialHeaders]
        )
        let item = AVPlayerItem(asset: playerAsset)
        // .spectral gives the highest-quality pitch-preserving time-stretch at
        // non-1× speeds, reducing the tinny/phase artefacts audible on AirPods
        // compared to the default .timeDomain algorithm.
        item.audioTimePitchAlgorithm = .spectral
        // Fast-start: require only 0.5 s of buffered content before the first frame
        // fires (readyToPlay). At 360p / 1.5 Mbps this is ~94 KB — well under a
        // single CDN segment. The forward buffer is reset to system default (0) in
        // the quality ramp task after readyToPlay so scrubbing has enough lookahead.
        item.preferredForwardBufferDuration = 0.5
        // Apply quality hints when a non-auto preference is set. These steer AVPlayer's
        // ABR algorithm toward the user's preferred resolution without bypassing audio
        // metadata (which variant URLs would lose). Hints are applied unconditionally
        // to the master URL for all HLS streams.
        // Apply ABR hints so AVPlayer selects the right variant immediately.
        // Consistent with the quality-switch path in PlaybackQualityManager.
        if info.hlsURL != nil {
            // Fast-start: cap initial ABR at 360p so AVPlayer picks a low-bitrate
            // variant for the first segment → first frame on screen as quickly as
            // possible. After .readyToPlay the hint is upgraded to the user's
            // preferred quality (see initialPlayerItemBecameReady in +StreamObservers).
            item.preferredMaximumResolution = CGSize(width: 640, height: 360)
            item.preferredPeakBitRate = peakBitRate(for: 360)
            let target = initialMaxH > 0 ? "\(initialMaxH)p" : "Auto"
            playerLog.notice("[fast-start] initial ABR hint → 360p (preferred target: \(target))")
        }
        // The caller wires the status observer (observeInitialPlayerItem) after this returns.
        // BUG-009 fix: replaceCurrentItem BEFORE wiring the observer to avoid a race
        // where statusStream fires with stale state before the item is installed.
        // This matches the already-correct ordering in all fallback/audio-only paths.
        player.replaceCurrentItem(with: item)
        duration = info.video.duration ?? 0
        return (item, isHLS)
    }

    private func fetchPrimaryPlayerInfo(video: Video) async throws -> PlayerInfo {
        do {
            return try await api.fetchPlayerInfo(videoId: video.id)
        } catch {
            if case APIError.ipBlocked(let reason) = error {
                // NW-6-FIX: IP-block short-circuit. Every extra /player call from a
                // blocked IP can extend the block duration — skip ALL retries,
                // including the TV-authenticated path (an authenticated request
                // carries the same blocked IP and will fail too). Throw immediately
                // so the error banner appears with the specific VPN message and
                // without a "Try Again" button. Suppress Crashlytics recording —
                // this is a user-side network condition, not an app bug.
                playerLog.error("⚠️ iOS client detected IP block — reason: \(reason)")
                throw error
            } else if case APIError.unavailable = error, hasAuthToken {
                playerLog.notice("⚠️ iOS client returned unavailable — retrying with authenticated TV client")
                do {
                    var tvInfo = try await api.fetchPlayerInfoAuthenticated(videoId: video.id)
                    // NW-3-FIX: TV client may return no HLS manifest and no adaptive
                    // streams for DRM/protected or region-locked content
                    // (hlsURL=nil, bestAdaptiveVideoURL=nil). Attempting to play the
                    // TV muxed direct URL (itag=18, c=TVHTML5) fails with
                    // AVFoundationErrorDomain -11828 / NSOSStatusErrorDomain -12847.
                    // Skip the unnecessary AVPlayer attempt and go straight to the
                    // Android client.
                    if tvInfo.hlsURL == nil,
                        tvInfo.bestAdaptiveVideoURL == nil || tvInfo.bestAdaptiveAudioURL == nil
                    {
                        playerLog.notice(
                            "⚠️ TV client returned no HLS/adaptive streams — falling through to Android client")
                        tvInfo = try await api.fetchPlayerInfoAndroid(videoId: video.id)
                    }
                    return tvInfo
                } catch {
                    if case APIError.unavailable = error {
                        // TV client also returned unavailable / cipher-protected formats.
                        // Fall through to the Android client as a last resort.
                        playerLog.notice("⚠️ TV client also unavailable — retrying with Android client")
                        return try await api.fetchPlayerInfoAndroid(videoId: video.id)
                    } else {
                        throw error
                    }
                }
            } else {
                throw error
            }
        }
    }

    private struct InitialPlaybackContext {
        let cached: CachedVideoData
        let info: PlayerInfo
        let cachedTrackingURLs: PlaybackTrackingURLs?
        let authTrackingTask: Task<PlaybackTrackingURLs?, Never>?
        let sponsorCached: Bool
    }

    private func beginInitialPlayback(video: Video, context: InitialPlaybackContext) async {
        let cached = context.cached
        let info = context.info
        let cachedTrackingURLs = context.cachedTrackingURLs
        let authTrackingTask = context.authTrackingTask
        let sponsorCached = context.sponsorCached
        // Audio-only mode: if enabled, replace the HLS item with an audio-only asset.
        // Falls back to HLS (already in player) on any failure. No-op when disabled.
        await loadAudioOnlyItemIfEnabled()

        #if canImport(UIKit)
        // Re-register lock screen commands before starting playback.
        // Commands are removed in suspend()/stop(); re-registering here
        // ensures they work when load() is called after a stop().
        setupRemoteCommandCenter()
        // Re-activate the audio session. stop() calls setActive(false) to release
        // the session to other apps; without this call on the next load() the player
        // starts silently because AVFoundation cannot acquire the inactive session.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            playerLog.notice("[loadAsync] AVAudioSession activated before playback")
        } catch {
            playerLog.error("[loadAsync] AVAudioSession setActive(true) failed: \(error.localizedDescription)")
        }
        #endif
        playerLog.notice(
            "[loadAsync] setting rate=\(self.settings.playbackSpeed) — player.timeControlStatus=\(self.player.timeControlStatus.rawValue) isAudioOnlyMode=\(self.isAudioOnlyMode)"
        )
        player.rate = Float(settings.playbackSpeed)
        isPlaying = true
        playerLog.notice(
            "[loadAsync] rate set — player.rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue)"
        )
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        updateNowPlayingInfo()
        #endif
        // Only reschedule the auto-hide timer when controls are already visible.
        // Calling scheduleControlsHide() unconditionally cancels any timer that
        // was started by a user tap during loading, extending the visible window
        // unexpectedly and breaking UI tests that wait for the auto-hide.
        if controlsVisible { scheduleControlsHide() }

        // Phase 2 as a cancellable utility Task. Cancelled on the next load()
        // or stop() so stale network callbacks never write to a new video's state.
        let p2Cached = cached
        let p2Info = info
        let p2CachedTracking = cachedTrackingURLs
        let p2AuthTask = authTrackingTask
        let p2SponsorCached = sponsorCached
        let p2Video = video
        phase2Task = Task(priority: .utility) { [weak self] in
            await self?.loadAsyncPhase2(
                video: p2Video,
                cached: p2Cached,
                info: p2Info,
                cachedTrackingURLs: p2CachedTracking,
                authTrackingTask: p2AuthTask,
                sponsorCached: p2SponsorCached
            )
        }
    }
}
