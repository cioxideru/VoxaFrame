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

// MARK: - Adaptive Composition and WebView HLS

extension PlaybackViewModel {

    /// Composes a video-only + audio-only adaptive stream pair via `AVMutableComposition`.
    /// Returns true on successful `.readyToPlay`.
    func attemptComposition(
        videoURL: URL, audioURL: URL,
        for video: Video, info: PlayerInfo, label: String
    ) async -> Bool {
        guard !Task.isCancelled, currentVideo?.id == video.id else { return false }
        guard let context = compositionRequestContext(videoURL: videoURL, audioURL: audioURL, label: label) else {
            return false
        }
        applyCompositionPlayerInfo(info, label: label)

        let assetHeaders = compositionHeaders(context: context, label: label)

        guard await compositionProbeAccepted(videoURL: videoURL, context: context, label: label) else { return false }

        let videoAsset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": assetHeaders])
        let audioAsset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": assetHeaders])

        do {
            // loadTracks can stall indefinitely when rqh=1 CDN URLs don't fail fast.
            // @MainActor task-group child tasks are subject to main-actor scheduling
            // pressure (XCTest accessibility callbacks), so withThrowingTaskGroup is
            // unreliable here even with Task.detached wrappers.
            //
            // Solution: use AsyncStream as a cross-thread coordination channel.
            // Both the loadTracks work AND the 8-second timeout run in fully-detached
            // tasks (thread pool, no actor isolation). Whichever finishes first yields
            // to the stream. The main-actor consumer resumes when either signal arrives,
            // regardless of main-actor scheduling pressure.
            guard
                let tracks = await loadCompositionTracks(
                    videoAsset: videoAsset, audioAsset: audioAsset, context: context, label: label)
            else { return false }

            guard !Task.isCancelled, currentVideo?.id == video.id else { return false }

            guard let sourceVideoTrack = tracks.video.first,
                let sourceAudioTrack = tracks.audio.first
            else {
                playerLog.error("❌ [\(label)/adaptive] no tracks in remote assets (rqh=\(context.videoRqh))")
                return false
            }

            let videoDuration = try await videoAsset.load(.duration)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return false }
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
                playerLog.error("❌ [\(label)/adaptive] could not add composition tracks")
                return false
            }

            try compVideo.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            try compAudio.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)

            playerLog.notice("✅ [\(label)/adaptive] composition built — testing playback for \(video.id)")
            lastAttemptedStreamURL = videoURL
            let compositeItem = AVPlayerItem(asset: composition)
            compositeItem.audioTimePitchAlgorithm = .spectral
            // fix11: Fast-start — fire readyToPlay after 0.5 s of buffered content.
            // Without this, AVMutableComposition items use the system default heuristic
            // (effectively unconstrained), which adds 0.3–0.5 s to initial buffering.
            // Reset to system default (0) in a ramp Task so downstream buffering is
            // not constrained after startup (same pattern as HLS paths).
            compositeItem.preferredForwardBufferDuration = 0.5
            Task { [weak compositeItem] in
                try? await Task.sleep(for: PlaybackTuning.bufferReleaseDelay)
                compositeItem?.preferredForwardBufferDuration = 0
            }
            // fix235: Guard cancellation and video identity before touching the player.
            guard !Task.isCancelled, currentVideo?.id == video.id else {
                playerLog.notice(
                    "⚠️ [\(label)/adaptive] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem"
                )
                return false
            }
            player.replaceCurrentItem(with: compositeItem)
            observePlaybackEndAndStalls(for: compositeItem)
            itemObserverTask?.cancel()

            return await observeCompositionItem(compositeItem, video: video, info: info, label: label)
        } catch {
            let nsErr = error as NSError
            let httpStatus = (nsErr.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == -12660 ? 403 : nsErr.code
            playerLog.error(
                "❌ [\(label)/adaptive] setup failed: domain=\(nsErr.domain) code=\(nsErr.code) httpStatus=\(httpStatus)"
            )
            return false
        }
    }

    // MARK: - Adaptive Composition Helpers

    private struct CompositionRequestContext {
        let userAgent: String
        let clientParam: String
        let videoRqh: Bool
        let isTVAuthBearer: Bool
        let isBotGuardMinted: Bool
    }

    private func compositionRequestContext(videoURL: URL, audioURL: URL, label: String) -> CompositionRequestContext? {
        let videoItag =
            URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let audioItag =
            URLComponents(url: audioURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value ?? "?"
        let videoRqh = videoURL.absoluteString.contains("rqh=1") || videoURL.absoluteString.contains("/rqh/1")

        // Use the client UA that matches the URL's signing client.
        let clientParam =
            URLComponents(url: videoURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "c" })?.value?.uppercased() ?? ""

        // Skip every rqh=1 stream by default — no client works without a pot= token.
        // Exception: TVAuth (TVHTML5) with a valid Bearer token. The official YouTube TV
        // app plays TVHTML5 rqh=1 adaptive streams without BotGuard — Bearer token may
        // satisfy CDN auth for authenticated TV sessions. An 8-second timeout (added to
        // the raceStream below) prevents indefinite hangs if the CDN holds the connection.
        // NOTE: BotGuard websafe fallback token (json[3] from GenerateIT) is NOT accepted
        // by the CDN for rqh=1 segments — only the full minting path (getMinter) produces
        // a CDN-accepted token, which requires a real browser JS context (WKWebView).
        // hasMintedPoToken is set in exhaustiveRetry when BotGuardWebViewRunner succeeds
        // with a full getMinter-minted token — those ARE accepted by the CDN.
        let isTVAuthBearer = label.contains("TVAuth") && hasAuthToken && currentAuthToken != nil
        let isAndroidVR = clientParam == "ANDROID_VR"
        #if canImport(WebKit)
        let isBotGuardMinted = label == "BotGuardWV" && hasMintedPoToken
        #else
        let isBotGuardMinted = false
        #endif
        if videoRqh && !isTVAuthBearer && !isAndroidVR && !isBotGuardMinted {
            playerLog.notice("[\(label)/adaptive] skipping rqh=1 (client=\(clientParam)) — not exempt")
            return nil
        }
        if videoRqh && isBotGuardMinted {
            playerLog.notice(
                "[\(label)/adaptive] attempting rqh=1 with WKWebView-minted BotGuard token (client=\(clientParam)) — CDN should accept"
            )
        } else if videoRqh {
            playerLog.notice("[\(label)/adaptive] attempting rqh=1 TVAuth with Bearer — CDN auth experiment")
        }
        let ua: String
        switch clientParam {
        case "ANDROID_VR": ua = InnerTubeClients.AndroidVR.userAgent
        case "ANDROID": ua = InnerTubeClients.Android.userAgent
        case "VISIONOS": ua = InnerTubeClients.VisionOS.userAgent
        case "TVHTML5": ua = InnerTubeClients.TV.userAgent
        case "MWEB": ua = InnerTubeClients.MWEB.userAgent
        case "WEB_CREATOR": ua = InnerTubeClients.Web.userAgent
        default: ua = InnerTubeClients.iOS.userAgent
        }

        playerLog.notice("[\(label)/adaptive] videoItag=\(videoItag) client=\(clientParam) audioItag=\(audioItag)")

        return CompositionRequestContext(
            userAgent: ua, clientParam: clientParam, videoRqh: videoRqh,
            isTVAuthBearer: isTVAuthBearer, isBotGuardMinted: isBotGuardMinted)
    }

    private func applyCompositionPlayerInfo(_ info: PlayerInfo, label: String) {
        playerInfo = info
        selectedFormat = effectiveQuality == .auto ? nil : qualityManager.preferredVideoFormat(from: info.formats)
        let newFormats = Self.deduplicatedVideoFormats(info.formats)
        // Never reduce quality options — same policy as attemptURL.
        let maxCurrentHeight = availableFormats.map(\.height).max() ?? 0
        let maxNewHeight = newFormats.map(\.height).max() ?? 0
        if newFormats.count > availableFormats.count || maxNewHeight > maxCurrentHeight || availableFormats.isEmpty {
            availableFormats = newFormats
        }
        playerLog.notice(
            "[\(label)/adaptive] availableFormats after dedup: input=\(info.formats.count) output=\(newFormats.count) kept=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)"
        )
        availableCaptions = info.captionTracks
        autoApplyCaptionPreference(tracks: info.captionTracks)

    }

    private func compositionHeaders(context: CompositionRequestContext, label: String) -> [String: String] {
        let ua = context.userAgent
        let videoRqh = context.videoRqh
        let isTVAuthBearer = context.isTVAuthBearer
        let isBotGuardMinted = context.isBotGuardMinted
        var assetHeaders: [String: String] = ["User-Agent": ua]
        // Inject Bearer only for TVAuth (TVHTML5 authenticated) — CDN validates the
        // TV session token for rqh=1 streams. Android VR uses Oculus UA without OAuth;
        // injecting a TV Bearer token causes CDN to hold the connection and reject it.
        if videoRqh && isTVAuthBearer, let token = currentAuthToken {
            assetHeaders["Authorization"] = "Bearer \(token)"
            playerLog.notice("[\(label)/adaptive] injecting Bearer auth into CDN headers for TVAuth rqh=1")
        }
        if videoRqh && isBotGuardMinted {
            // Inject youtube.com cookies (VISITOR_INFO1_LIVE) cross-domain to googlevideo.com.
            // The CDN validates bui= against VISITOR_INFO1_LIVE — without it, the CDN holds
            // the connection (no immediate 403, but our 3s loadTracks timeout fires).
            // BotGuardWebViewRunner.propagateWebViewCookies() copies WKWebView session cookies
            // into HTTPCookieStorage.shared, making VISITOR_INFO1_LIVE available here.
            let ytCookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.youtube.com")!) ?? []
            if !ytCookies.isEmpty {
                assetHeaders["Cookie"] = ytCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                playerLog.notice(
                    "[\(label)/adaptive] injecting \(ytCookies.count) youtube.com cookies for BotGuard rqh=1 CDN auth")
            }
        }

        return assetHeaders
    }

    private func compositionProbeAccepted(
        videoURL: URL, context: CompositionRequestContext, label: String
    ) async -> Bool {
        let videoRqh = context.videoRqh
        let isAndroidVR = context.clientParam == "ANDROID_VR"
        let ua = context.userAgent
        // CDN probe for Android VR rqh=1 — avoids loadTracks timeout when CDN enforces
        // SABR at the content level. URLSession.data(for:) accumulates the full response
        // body before returning; if the CDN stalls mid-body the 1.5s timeout fires → nil.
        //
        // Range must cover the moov atom. The CDN returns HTTP 206 for small byte ranges
        // (including bytes=0-0 and bytes=0-1023) even for SABR-enforced videos — it
        // serves the initial container bytes (ftyp box, partial moov header) freely —
        // but then stalls larger sequential reads that AVURLAsset.loadTracks needs to
        // parse track metadata. The moov atom for a typical YouTube 720p video is
        // 20–200 KB; using bytes=0-131071 (128 KB) ensures we cover it. A stalling CDN
        // delivers a few KB then hangs; URLSession.data(for:) won't return until the
        // complete 128 KB body arrives, so the 1.5s timeout fires and we bail early.
        //
        // Timing: 128 KB at 148 Mbps ≈ 7 ms; at 10 Mbps ≈ 100 ms; stall → 1.5s.
        // TVAuth with Bearer is intentionally excluded — injecting an OAuth token into
        // a bare URLSession changes CDN session state, separate from AVURLAsset context.
        if videoRqh && isAndroidVR {
            var probeReq = URLRequest(url: videoURL)
            probeReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            probeReq.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
            probeReq.timeoutInterval = PlaybackTuning.adaptiveProbeTimeout
            if let (_, probeResp) = try? await URLSession(configuration: .ephemeral).data(for: probeReq),
                let http = probeResp as? HTTPURLResponse
            {
                if http.statusCode == 403 || http.statusCode == 401 {
                    playerLog.notice(
                        "❌ [\(label)/adaptive] rqh=1 probe: HTTP \(http.statusCode) — CDN enforcing rqh, skipping composition"
                    )
                    return false
                }
                playerLog.notice(
                    "[\(label)/adaptive] rqh=1 probe: HTTP \(http.statusCode) 128KB delivered — moov atom accessible, proceeding"
                )
            } else {
                // CDN stalled before delivering 128 KB. This predicts loadTracks failure
                // (moov atom not accessible), so bail immediately rather than waiting 2s.
                playerLog.notice(
                    "⚠️ [\(label)/adaptive] rqh=1 probe: timeout after 1.5s (128KB stall) — CDN enforcing SABR, skipping composition"
                )
                return false
            }
        }

        return true
    }

    private func loadCompositionTracks(
        videoAsset: AVURLAsset, audioAsset: AVURLAsset, context: CompositionRequestContext, label: String
    ) async -> LoadedAssetTracks? {
        let clientParam = context.clientParam
        let videoRqh = context.videoRqh
        do {
            // Timeout — prevents indefinite CDN hang for rqh=1 Bearer experiments.
            // On tvOS/iOS: AndroidVR gets 2s — the firstByte probe (Range: bytes=0-0) is a
            // false positive for rqh=1 CDN enforcement: the CDN serves the first byte (206)
            // but stalls actual AVURLAsset segment requests. fast non-rqh videos complete
            // loadTracks in ~0.4s, so 2s is a safe margin on both platforms.
            // fix1/tvOS: 2s validated correct. fix_task240: apply same 2s cap to iOS — log
            // shows 8s × 2 (race + serial) = 16s wasted on `cnsKl2JouOc` class of video.
            let isVRAttempt = clientParam == "ANDROID_VR"
            #if os(tvOS)
            let timeoutNs: UInt64 =
                isVRAttempt ? PlaybackTuning.adaptiveVRTimeoutNanoseconds : PlaybackTuning.adaptiveTVTimeoutNanoseconds
            #else
            // fix30 (task #230): 1.5s for non-VR iOS first-video loads.
            // fix_task240: 2s for AndroidVR (was 8s) — false-positive probe scenario.
            let timeoutNs: UInt64 =
                isVRAttempt
                ? PlaybackTuning.adaptiveVRTimeoutNanoseconds
                : (needsQuickStartup
                    ? PlaybackTuning.adaptiveStartupTimeoutNanoseconds : PlaybackTuning.adaptiveTimeoutNanoseconds)
            #endif

            if let box = await loadTracksRacingTimeout(
                videoAsset: videoAsset, audioAsset: audioAsset, timeout: .nanoseconds(timeoutNs))
            {
                return box
            } else {
                #if os(tvOS)
                let timeoutSec = isVRAttempt ? 2 : 3
                #else
                // VR=2s (fix_task240), non-VR quick=1.5s (fix30)
                let timeoutSec = isVRAttempt ? 2 : (needsQuickStartup ? 1 : 8)
                #endif
                let reason = "timed out after \(timeoutSec)s or loadTracks failed"
                playerLog.error("❌ [\(label)/adaptive] loadTracks \(reason) (rqh=\(videoRqh))")
                return nil
            }
        }

    }

    private func observeCompositionItem(
        _ compositeItem: AVPlayerItem, video: Video, info: PlayerInfo, label: String
    ) async -> Bool {
        for await status in compositeItem.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
            guard !Task.isCancelled, currentVideo?.id == video.id, player.currentItem === compositeItem else {
                return false
            }
            switch status {
            case .readyToPlay:
                playerLog.notice(
                    "[benchmark] readyToPlay — \(label)/adaptive — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [\(label)/adaptive] readyToPlay")
                let compDur = compositeItem.duration.seconds
                if compDur.isFinite && compDur > 0 {
                    let prevDur = self.duration
                    self.duration = compDur
                    playerLog.notice(
                        "[duration] updated from composition AVPlayerItem: \(String(format: "%.1f", compDur))s (was \(String(format: "%.1f", prevDur))s from metadata)"
                    )
                } else if self.duration == 0 {
                    durationObserverTask?.cancel()
                    durationObserverTask = Task { [weak self, weak compositeItem] in
                        guard let compositeItem else { return }
                        for await seconds in compositeItem.firstValidDurationStream {
                            guard !Task.isCancelled, let self else { return }
                            let prev = self.duration
                            self.duration = seconds
                            playerLog.notice(
                                "[duration] deferred KVO update: \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)"
                            )
                            break
                        }
                    }
                }
                if let pos = savedPositionToRestore, pos > 0 {
                    savedPositionToRestore = nil
                    seek(to: pos)
                }
                loadAudioTracks(from: compositeItem)
                needsQuickStartup = false
                isLoading = false
                timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                launchPhase2(video: video, info: info)
                return true
            case .failed:
                let nsErr = compositeItem.error as? NSError
                let httpStatus =
                    (nsErr?.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == -12660 ? 403 : (nsErr?.code ?? -1)
                playerLog.error(
                    "❌ [\(label)/adaptive] AVPlayerItem failed: domain=\(nsErr?.domain ?? "?") code=\(nsErr?.code ?? -1) httpStatus=\(httpStatus)"
                )
                return false
            case .unknown:
                continue
            @unknown default:
                continue
            }
        }
        return false
    }

    #if canImport(WebKit)
    /// Loads an HLS manifest URL extracted by `YouTubeWebViewHLSExtractor` directly into AVPlayer.
    ///
    /// The URL was obtained by intercepting the YouTube JS player's internal InnerTube call in a
    /// hidden WKWebView — the JS player computes the `spc=` token that bypasses `rqh=1` CDN
    /// restrictions. Segment URLs in the manifest are signed by YouTube and served without 403.
    ///
    /// Fetches the `hls_variant` master manifest, parses it for a per-quality `hls_playlist`
    /// URL at ≥720p, then loads that into AVPlayer via YTHLSProxyLoader so that ALL
    /// HLS requests (playlist + segments) are forwarded through URLSession with the
    /// correct desktop-Safari User-Agent that manifest.googlevideo.com requires.
    /// - Parameter poToken: When non-nil, the proxy rewrites variant playlist URIs to the
    ///   proxy scheme and injects ?pot=<token> into every segment URL so rqh=1-enforced
    ///   CDN requests are authenticated without needing googlevideo.com session cookies.
    /// - Parameter skipIfPfa1: When `true` (Phase -1a only), bail immediately if the selected
    ///   variant URL contains `pfa/1` and `poToken` is nil. The Phase -1a cached preWarm URL has
    ///   a STALE `xpc=` credential that CDN always rejects for pfa/1 videos. Racing paths and
    ///   serial-extraction paths pass `false` because those use a FRESH `xpc=` URL (earlyTask).
    func tryWebViewHLS(
        _ masterURL: URL, nSolver: (unsolved: String, solved: String)?, poToken: String? = nil,
        skipIfPfa1: Bool = false, for video: Video
    ) async -> Bool {
        playerLog.notice("[webView/HLS] fetching master manifest: \(ViewModelLogger.urlHost(masterURL))")

        let ua =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

        // 1. Download the master M3U8 via URLSession (spc= in URL = self-authenticating)
        var request = URLRequest(url: masterURL, timeoutInterval: PlaybackTuning.hlsManifestTimeout)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let manifestText = String(data: data, encoding: .utf8)
        else {
            playerLog.error("❌ [webView/HLS] failed to fetch master manifest")
            return false
        }
        playerLog.notice("[webView/HLS] master manifest OK bytes=\(data.count)")

        // 2. Parse ALL variants for the quality picker and best ≥720p for initial playback.
        let allVariants = parseHLSAllVariants(from: manifestText, baseURL: masterURL)
        let bestURL =
            parseHLSBestVariant(from: manifestText, baseURL: masterURL, minHeight: 720)
            ?? parseHLSBestVariant(from: manifestText, baseURL: masterURL, minHeight: 0)
        guard let bestURL else {
            playerLog.error("❌ [webView/HLS] no quality URL found in master manifest")
            return false
        }
        playerLog.notice("[webView/HLS] selected per-quality URL: \(ViewModelLogger.urlHost(bestURL))")

        // fix28: Fast-fail for pfa/1 urls in Phase -1a when no pot= is available.
        //
        // For pfa/1 variants the CDN rejects segment requests (-12660) unless the URL's
        // xpc= credential is FRESH (< ~5 s, minted by the YouTube player at wv.load() time).
        // When Phase -1a calls tryWebViewHLS with the CACHED preWarm URL (stored 90+ s ago),
        // that URL's xpc= is always stale → CDN rejects all segments → 1.1 s wasted.
        //
        // Returning false immediately lets the race start earlier. Race Path B awaits
        // wkHLSEarlyTask (priorityExtract), which has already extracted a FRESH xpc= URL.
        // Path B wins with that fresh URL, reducing c1 from ~2.87 s → ~1.0-1.4 s.
        //
        // IMPORTANT: this guard only fires when `skipIfPfa1 == true` (Phase -1a mode).
        // The race path (racePathB) and serial extraction after race-failed pass
        // `skipIfPfa1: false` so fresh liveRace URLs are never prematurely rejected.
        if skipIfPfa1, poToken == nil,
            (bestURL.absoluteString.contains("/pfa/1/") || bestURL.absoluteString.contains("pfa%2F1"))
        {
            playerLog.notice(
                "[webView/HLS] Phase -1a pfa/1 + pot=nil — stale xpc= cannot auth CDN segments; bailing early (fix28)")
            return false
        }

        // Cache the master manifest URL so future loads of this video (or pre-extracted
        // neighbours) can skip the 5–9 s WKWebView extraction step entirely.
        await VideoPreloadCache.shared.store(wkHLSManifestURL: masterURL, for: video.id)

        // Extract WKWebView cookies for the proxy loader.
        // Note: segment URLs in variant playlists are served natively by AVPlayer (not proxied),
        // so the proxy does not need googlevideo.com cookies for rqh=1 content. The master
        // manifest URL is self-authenticated via spc=, and youtube.com session cookies
        // (VISITOR_INFO1_LIVE, YSC, etc.) are sufficient for CDN segment auth in practice.
        let webViewCookies = await extractWKWebViewCookies()
        let gvCount = webViewCookies.filter { $0.domain.contains("googlevideo") }.count
        playerLog.notice("[webView/HLS] extracted \(webViewCookies.count) cookies (\(gvCount) googlevideo) for proxy")

        // Populate the quality picker with the HLS variant heights from the master manifest.
        // These are the only formats guaranteed to work via the proxy — iOS adaptive rqh=1
        // streams are intentionally excluded from the picker.
        configureWebViewHLSVariants(allVariants, manifestURL: masterURL)
        let context = HLSLanguageContext(
            manifestURL: masterURL, manifestText: manifestText,
            nSolver: nSolver, webViewCookies: webViewCookies)

        let hlsLanguageTracks = configureWebViewHLSAudio(context: context, video: video)

        guard
            let (item, preferredHeight) = makeWebViewHLSItem(
                context: context, ua: ua, poToken: poToken,
                allVariants: allVariants, hlsLanguageTracks: hlsLanguageTracks)
        else { return false }

        // fix235: Final cancellation / video-identity check before touching the player.
        // A stale exhaustiveRetry task (cancelled by a subsequent load() or stop()) must not
        // call replaceCurrentItem — doing so would silently swap the visible video.
        guard !Task.isCancelled, currentVideo?.id == video.id else {
            playerLog.notice(
                "⚠️ [webView/HLS] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem"
            )
            return false
        }
        lastAttemptedStreamURL = masterURL
        player.replaceCurrentItem(with: item)
        observePlaybackEndAndStalls(for: item)
        itemObserverTask?.cancel()
        for await status in item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
            guard !Task.isCancelled, currentVideo?.id == video.id, player.currentItem === item else { return false }
            switch status {
            case .readyToPlay:
                webViewHLSItemBecameReady(item, video: video, preferredHeight: preferredHeight)
                return true
            case .failed:
                let err = ViewModelLogger.errorSummary(item.error)
                playerLog.error("❌ [webView/HLS] AVPlayerItem failed: \(err)")
                // If the CDN denied access (permission error), a fresh WKWebView extraction
                // will produce the same URL signed by the same CDN session → same 403.
                // Flag this so exhaustiveRetry skips the serial extraction entirely.
                if err.lowercased().contains("permission") || err.lowercased().contains("not have access") {
                    wkHLSPermissionDenied = true
                    playerLog.notice("[webView/HLS] CDN permission error — serial extraction will be skipped")
                }
                return false
            case .unknown: continue
            @unknown default: continue
            }
        }
        return false
    }

    private func configureWebViewHLSVariants(_ allVariants: [Int: URL], manifestURL: URL) {
        if !allVariants.isEmpty {
            hlsVariantURLs = allVariants
            wkHLSMasterURL = manifestURL
            let syntheticFormats = allVariants.keys.sorted(by: >).map { h in
                SmartTubeIOSCore.VideoFormat(
                    label: "\(h)p", width: 0, height: h, fps: 30,
                    mimeType: "video/mp4; codecs=\"avc1.640028\"",
                    url: allVariants[h], bitrate: nil)
            }
            availableFormats = syntheticFormats
            qualityManager.setSelectedFormatForCurrentPreference()
            playerLog.notice(
                "[webView/HLS] quality picker: \(syntheticFormats.map { $0.qualityLabel }.joined(separator: ", "))")
        }

    }

    private func configureWebViewHLSAudio(context: HLSLanguageContext, video: Video) -> [AudioTrack] {
        let manifestText = context.manifestText
        // 2b. Parse dubbed-audio language tracks from YT-EXT-AUDIO-CONTENT-ID attributes.
        //     YouTube encodes dubbed languages in #EXT-X-STREAM-INF lines (not #EXT-X-MEDIA
        //     TYPE=AUDIO), so loadMediaSelectionGroup returns nil. We parse them directly here
        //     and populate AudioTrackManager so the language selector appears immediately.
        let hlsLanguageTracks = parseHLSAudioLanguages(from: manifestText)
        playerLog.notice(
            "[webView/HLS] YT-EXT-AUDIO-CONTENT-ID tracks: \(hlsLanguageTracks.count) — \(hlsLanguageTracks.map { $0.name }.joined(separator: ", "))"
        )
        if !hlsLanguageTracks.isEmpty {
            audioManager.loadHLSVariantTracks(hlsLanguageTracks)
            // Wire language switching: when the user picks a track, reload the AVPlayerItem
            // with the proxy filtered for that language. The callback is cleared by reset()
            // when a new video loads.
            audioManager.onHLSLanguageChange = { [weak self] (track: AudioTrack?) in
                guard let self else { return }
                let savedPos = self.player.currentTime().seconds
                // Use contentID (the YT-EXT-AUDIO-CONTENT-ID value) for proxy filtering.
                // nil means original audio: for real originals that lack the attribute,
                // contentID is nil on the synthetic "Original" entry; for real originals
                // with the attribute (e.g. "en-US.4"), contentID equals the real value.
                // The "Auto" picker row passes track=nil → contentID=nil → original filter.
                let contentID = track?.contentID
                Task { [weak self] in
                    await self?.switchHLSLanguage(
                        to: contentID,
                        context: context,
                        for: video,
                        seekTo: savedPos
                    )
                }
            }
        }

        return hlsLanguageTracks
    }

    private func makeWebViewHLSItem(
        context: HLSLanguageContext, ua: String, poToken: String?,
        allVariants: [Int: URL], hlsLanguageTracks: [AudioTrack]
    ) -> (AVPlayerItem, Int)? {
        let manifestURL = context.manifestURL
        let nSolver = context.nSolver
        let webViewCookies = context.webViewCookies
        // 3. Route through YTHLSProxyLoader using the MASTER manifest URL (not a per-quality
        //    variant URL). The proxy filters #EXT-X-STREAM-INF variants for the selected
        //    dubbed language (or original audio when none is selected). Without the proxy,
        //    AVPlayer would receive all N×M language+quality variant entries and could pick
        //    any language during ABR adaptation.
        guard let proxyURL = manifestURL.proxyURL else {
            playerLog.error("❌ [webView/HLS] failed to build proxy URL for master")
            return nil
        }
        // Determine the initial content ID: if the user has a saved language preference that
        // matches one of the HLS variant tracks, start with that language; otherwise nil (original).
        // Use contentID (not id) so the synthetic "Original" entry (id="yt-original-audio",
        // contentID=nil) correctly maps to nil → proxy keeps no-content-ID variants.
        let initialContentID: String?
        if let pref = settings.preferredAudioLanguage,
            let preferred = hlsLanguageTracks.first(where: { $0.languageCode == pref })
        {
            initialContentID = preferred.contentID
        } else {
            initialContentID = nil
        }
        let langDisplay = initialContentID ?? "original"
        // fix20: Use the caller-supplied poToken (captured before wkHLSEarlyTask clears
        // extractedPoToken). With a non-nil poToken the proxy rewrites variant playlist URLs
        // to ytwebhls:// and injects ?pot=<token> into segment URLs, authenticating rqh=1
        // CDN requests without requiring googlevideo.com session cookies in the cookie jar.
        // Falls back to extractedPoToken in case the caller didn't supply one.
        let effectivePoToken = poToken ?? YouTubeWebViewHLSExtractor.shared.extractedPoToken
        let potDisplay = effectivePoToken.map { "\($0.count) chars" } ?? "nil"
        playerLog.notice(
            "[webView/HLS] ✅ proxying master URL (lang=\(langDisplay), pot=\(potDisplay), YT-EXT-AUDIO-CONTENT-ID filter active)"
        )
        let proxyLoader = YTHLSProxyLoader(
            ua: ua, nSolver: nSolver, webViewCookies: webViewCookies,
            selectedLanguageContentID: initialContentID,
            poToken: effectivePoToken)
        let asset = AVURLAsset(url: proxyURL)
        // Keep proxy loader alive for the lifetime of this asset
        asset.resourceLoader.setDelegate(proxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
        // Store reference so ARC doesn't release the loader while AVPlayer uses the asset
        webHLSProxyLoader = proxyLoader

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        // Fast-start: require only 0.5 s of buffered content before readyToPlay fires
        // (matches the primary HLS path in loadAsync). Forward buffer is reset to system
        // default in the readyToPlay ramp task below.
        item.preferredForwardBufferDuration = 0.5
        // Resolve the saved choice before playback; Auto retains the fast-start ramp.
        let preferredHeight: Int
        if let height = effectiveQuality.closestHeight(in: allVariants.keys) ?? effectiveQuality.height {
            preferredHeight = height
        } else if let best = allVariants.keys.filter({ $0 >= 720 }).max()
            ?? allVariants.keys.max()
        {
            preferredHeight = best
        } else {
            preferredHeight = 0
        }
        let initialHeight = effectiveQuality == .auto ? 360 : preferredHeight
        item.preferredMaximumResolution =
            effectiveQuality == .auto
            ? CGSize(width: 640, height: 360)
            : CGSize(width: CGFloat(initialHeight) * 4, height: CGFloat(initialHeight))
        playerLog.notice(
            "[webView/HLS] initial cap \(initialHeight)p → target \(preferredHeight > 0 ? "\(preferredHeight)p" : "Auto")"
        )
        return (item, preferredHeight)
    }

    private func webViewHLSItemBecameReady(_ item: AVPlayerItem, video: Video, preferredHeight: Int) {
        playerLog.notice("[benchmark] readyToPlay — webView/HLS — videoId=\(video.id) title=\(video.title)")
        playerLog.notice("✅ [webView/HLS] readyToPlay")
        // Refresh duration from AVPlayerItem — the YouTube API metadata may be
        // absent (nil) or inaccurate, leaving duration=0 and breaking scrubbing.
        let itemDur = item.duration.seconds
        if itemDur.isFinite && itemDur > 0 {
            let prevDur = self.duration
            self.duration = itemDur
            playerLog.notice(
                "[duration] updated from webView/HLS AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s)"
            )
        } else if self.duration == 0 {
            durationObserverTask?.cancel()
            durationObserverTask = Task { [weak self, weak item] in
                guard let item else { return }
                for await seconds in item.firstValidDurationStream {
                    guard !Task.isCancelled, let self else { return }
                    let prev = self.duration
                    self.duration = seconds
                    playerLog.notice(
                        "[duration] deferred KVO update (webView/HLS): \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)"
                    )
                    break
                }
            }
        }
        // Try the standard #EXT-X-MEDIA path (works if manifest has audio groups).
        // For YouTube's YT-EXT-AUDIO-CONTENT-ID format, loadAudioTracks returns nil
        // but tracks are already loaded via loadHLSVariantTracks above.
        loadAudioTracks(from: item)
        needsQuickStartup = false
        isLoading = false
        timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
        lastSuccessfulStreamType = "webView/HLS"
        player.rate = Float(settings.playbackSpeed)
        isPlaying = true
        qualityManager.isMuxedFallback = false
        // Auto ramps after its first frame; manual quality is already applied.
        Task { [weak self, weak item] in
            try? await Task.sleep(for: PlaybackTuning.qualityRampDelay)
            guard let self, !Task.isCancelled else { return }
            self.timeToHighQualityMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
            item?.preferredForwardBufferDuration = 0
            if preferredHeight > 0 {
                item?.preferredMaximumResolution = CGSize(width: 7680, height: preferredHeight)
                playerLog.notice("[webView/HLS] ABR ramp → \(preferredHeight)p + buffer unconstrained")
            } else {
                item?.preferredMaximumResolution = .zero
                playerLog.notice("[webView/HLS] ABR ramp → Auto (unconstrained) + buffer unconstrained")
            }
        }
    }

    #endif
}
