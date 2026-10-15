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

// MARK: - Stream Playback Attempts

extension PlaybackViewModel {

    // MARK: - Stream Exhaustion

    /// Tries HLS → adaptive composition → (optionally) muxed direct from one PlayerInfo.
    /// Returns true if any stream starts playing successfully.
    /// - Parameter skipMuxed: When `true`, the muxed direct-MP4 fallback is skipped so that
    ///   the caller can try higher-priority clients before accepting the 360p muxed last-resort.
    func tryAllStreams(
        video: Video, info: PlayerInfo, label: String,
        skipMuxed: Bool = false
    ) async -> Bool {
        logStreamChoices(info: info, label: label, skipMuxed: skipMuxed)

        // 1. HLS manifest — best quality, native AVPlayer ABR, alternate audio renditions
        if let hlsURL = info.hlsURL {
            playerLog.notice("[\(label)] Trying HLS")
            if await attemptURL(hlsURL, for: video, info: info, label: "\(label)/HLS") { return true }
            playerLog.notice("[\(label)] HLS failed — trying adaptive composition")
        }

        // 2. Adaptive composition — video-only + audio-only; avoids muxed CDN pot restrictions
        if let videoURL = qualityCapVideoURL(from: info.formats),
            let audioURL = info.bestAdaptiveAudioURL
        {
            // Guard: if every adaptive video URL is SABR (c=TVHTML5), AVURLAsset.loadTracks
            // will stall for 60 s then return -11828 "Cannot Open". Skip composition entirely
            // and let exhaustiveRetry's WKWebView path handle the video instead.
            if info.containsSabrFormats {
                playerLog.notice(
                    "[\(label)] All adaptive video URLs are SABR (c=TVHTML5) — skipping loadTracks stall, falling through"
                )
                // Guard: if every adaptive video URL has rqh=1, AVURLAsset.loadTracks stalls
                // for ~8 s on the CDN's byte-range probe because rqh=1 requires CDN auth that
                // URLSession cannot provide (same class of stall as SABR but shorter timeout).
                // Skip composition and route to WKWebView HLS (spc=-authenticated).
                // Exception: if a WKWebView-extracted pot= token is available (Option B), the
                // adaptive URLs have already had &pot=<token> appended via applyingPoToken(),
                // so CDN auth may succeed — attempt composition before falling through.
            } else if info.containsRqhAdaptiveFormats {
                let hasPot = await api.hasPoToken(for: video.id)
                // ANDROID_VR is exempt from CDN rqh=1 enforcement (no GVS_PO_TOKEN_POLICY
                // defined for android_vr per yt-dlp source). attemptComposition also has
                // this exemption via isAndroidVR, but it was unreachable from here because
                // this guard returned early before calling it. Allow VR through directly.
                let isAndroidVRLabel = label.contains("AndroidVR") || label.contains("ANDROID_VR")
                if hasPot || isAndroidVRLabel {
                    #if os(tvOS)
                    // fix2: Pre-fetch TVEmbedded concurrently while AndroidVR rqh=1 composition
                    // times out (2s on tvOS). By the time the timeout fires and exhaustiveRetry
                    // reaches Phase 1, the result is ready — eliminating the sequential ~0.5s fetch.
                    // Fire for all AndroidVR attempts regardless of hasPot: the pot= token doesn't
                    // prevent the CDN from enforcing rqh=1 at the segment level (only firstByte
                    // probe returns 206; actual segments still reject with rqh=1).
                    if isAndroidVRLabel, tvEmbeddedEarlyTask == nil {
                        let prefetchVideoId = video.id
                        tvEmbeddedEarlyTask = Task { [weak self] in
                            guard let self else { return nil }
                            return try? await self.api.fetchPlayerInfoTVEmbedded(videoId: prefetchVideoId)
                        }
                        playerLog.notice("[\(label)] fix2: started TVEmbedded early pre-fetch alongside rqh=1 timeout")
                    }
                    #endif
                    playerLog.notice(
                        "[\(label)] rqh=1 but \(hasPot ? "pot= token available" : "ANDROID_VR exempt") — attempting adaptive composition"
                    )
                    if await attemptComposition(
                        videoURL: videoURL, audioURL: audioURL,
                        for: video, info: info, label: label)
                    {
                        return true
                    }
                    playerLog.notice("[\(label)] adaptive composition with pot= failed — falling through")
                } else {
                    playerLog.notice(
                        "[\(label)] All adaptive video URLs are rqh=1 — skipping 8 s loadTracks stall, falling through")
                }
            } else {
                playerLog.notice("[\(label)] Trying adaptive composition")
                if await attemptComposition(
                    videoURL: videoURL, audioURL: audioURL,
                    for: video, info: info, label: label)
                {
                    return true
                }
                // A background prefetch may have stored an HLS URL in the cache while adaptive
                // was running (confirmed in logs: hls=true stored mid-retry for LSMQ3U1Thzw).
                // Check before falling through to muxed — HLS gives us multi-audio track support.
                let freshCachedInfo = await VideoPreloadCache.shared.consume(videoId: video.id).playerInfo
                if let freshCachedInfo, let freshHLSURL = freshCachedInfo.hlsURL, freshHLSURL != info.hlsURL {
                    playerLog.notice("[\(label)] HLS URL appeared in cache after adaptive failed — trying HLS")
                    if await attemptURL(
                        freshHLSURL, for: video, info: freshCachedInfo,
                        label: "\(label)/HLS-late")
                    {
                        return true
                    }
                }
                playerLog.notice("[\(label)] Adaptive composition failed — trying muxed")
            }
        }

        return await tryMuxedFallback(video: video, info: info, label: label, skipMuxed: skipMuxed)
    }

    private func tryMuxedFallback(video: Video, info: PlayerInfo, label: String, skipMuxed: Bool) async -> Bool {
        // 3. Muxed direct MP4 (itag=18, 360p — last resort, skipped when skipMuxed=true)
        if !skipMuxed, let muxedURL = info.bestMuxedDownloadURL {
            // Guard: TVHTML5 SABR-protocol URLs serve binary data, not a standard MP4 container.
            // AVPlayer returns -11828 (AVFoundationErrorDomain "Cannot Open") for these.
            if muxedURL.absoluteString.contains("c=TVHTML5") {
                playerLog.notice("[\(label)] Skipping SABR muxed URL (c=TVHTML5) — not a playable MP4")
            } else {
                playerLog.notice("[\(label)] Trying muxed")
                let muxedItag =
                    muxedURL.absoluteString
                    .components(separatedBy: "&")
                    .first(where: { $0.contains("itag=") })
                    .flatMap { $0.components(separatedBy: "=").last } ?? "?"
                let muxedBitrate =
                    info.formats.first(where: { $0.url == muxedURL })?.bitrate.map { "\($0/1000)kbps" } ?? "?"
                playerLog.notice(
                    "[\(label)] muxed candidate: itag=\(muxedItag) bitrate=\(muxedBitrate) url=\(muxedURL.absoluteString.prefix(100))"
                )
                if await attemptURL(muxedURL, for: video, info: info, label: "\(label)/muxed") { return true }
                playerLog.notice("[\(label)] Muxed failed — no more alternatives for this client")
            }
        }

        return false
    }

    private func logStreamChoices(info: PlayerInfo, label: String, skipMuxed: Bool) {
        let hasHLS = info.hlsURL != nil
        let hasDASH = info.dashURL != nil
        let hasAdaptiveVideo = qualityCapVideoURL(from: info.formats) != nil
        let hasAdaptiveAudio = info.bestAdaptiveAudioURL != nil
        let hasMuxed = info.bestMuxedDownloadURL != nil
        // Diagnostic: show first adaptive video URL prefix to detect SABR (c=TVHTML5) vs standard
        let firstAdaptiveURL =
            info.formats.first(where: {
                $0.mimeType.hasPrefix("video/mp4") && !$0.mimeType.contains(", ") && $0.url != nil
            })?.url?.absoluteString.prefix(200) ?? "none"
        playerLog.notice(
            "[\(label)] streams: HLS=\(hasHLS) DASH=\(hasDASH) adaptiveVideo=\(hasAdaptiveVideo) adaptiveAudio=\(hasAdaptiveAudio) muxed=\(hasMuxed) skipMuxed=\(skipMuxed) firstAdaptiveURL=\(firstAdaptiveURL)"
        )

    }

    // MARK: - Attempt Helpers

    /// Tries a single URL in AVPlayer. Returns true if `.readyToPlay` is received.
    /// `statusStream` finishes after `.readyToPlay` or `.failed`, making it safe to await inline.
    func attemptURL(_ url: URL, for video: Video, info: PlayerInfo, label: String) async -> Bool {
        playerLog.notice("[\(label)]: \(url.absoluteString.prefix(120))")

        playerInfo = info
        let isHLSManifest = label.contains("/HLS")
        let hlsPolicy = HLSPlaybackPolicy.resolve(
            label: label, isHLS: isHLSManifest,
            vp9Enabled: settings.vp9Enabled, h264Enabled: settings.h264Enabled)
        let newFormats = Self.deduplicatedVideoFormats(info.formats)
        // Never reduce quality options for adaptive/HLS streams — preserve the richest set seen.
        // Exception: muxed fallback (label contains "/muxed") always resets availableFormats to
        // the muxed-only formats. This prevents stale rqh=1-blocked adaptive formats from
        // appearing in the quality picker when they can never actually play.
        let maxCurrentHeight = availableFormats.map(\.height).max() ?? 0
        let maxNewHeight = newFormats.map(\.height).max() ?? 0
        let isMuxedFallback = label.contains("/muxed")
        if isMuxedFallback || newFormats.count > availableFormats.count || maxNewHeight > maxCurrentHeight
            || availableFormats.isEmpty
        {
            availableFormats = newFormats
        }
        playerLog.notice(
            "[\(label)] availableFormats after dedup: input=\(info.formats.count) output=\(newFormats.count) kept=\(availableFormats.count) maxH=\(availableFormats.map(\.height).max() ?? 0)"
        )
        availableCaptions = info.captionTracks
        autoApplyCaptionPreference(tracks: info.captionTracks)

        let (effectiveURL, applyHLSHints) = await resolvedAttemptURL(
            url, video: video, info: info, label: label, hlsPolicy: hlsPolicy)

        lastAttemptedStreamURL = effectiveURL
        // WebSafari HLS variant playlists are served from manifest.googlevideo.com and
        // signed for a browser WEB client. The CDN checks that the requesting UA matches
        // a web browser; sending the iOS YouTube UA returns 403. Use the Safari macOS UA
        // for WebSafari HLS, and Origin + Referer for all HLS (browser-style headers).
        let item = makeAttemptItem(url: effectiveURL, hlsPolicy: hlsPolicy, applyHLSHints: applyHLSHints, label: label)

        // fix235: Guard cancellation and video identity immediately before touching the player.
        // Covers adaptive/muxed paths: a stale exhaustiveRetry (cancelled by load() or stop())
        // must not swap the AVPlayerItem under a correctly-playing video.
        guard !Task.isCancelled, currentVideo?.id == video.id else {
            playerLog.notice(
                "⚠️ [\(label)] fix235: task cancelled or video changed (current=\(currentVideo?.id ?? "nil") expected=\(video.id)) — aborting replaceCurrentItem"
            )
            return false
        }
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()

        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                attemptItemBecameReady(item, video: video, info: info, label: label, isMuxedFallback: isMuxedFallback)
                return true
            case .failed:
                let err = item.error.map { "\($0)" } ?? "nil"
                let nsErr = item.error as? NSError
                let failURL =
                    nsErr?.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
                    ?? nsErr?.userInfo["NSErrorFailingURLKey"] as? String
                playerLog.error("❌ [\(label)] AVPlayerItem failed: \(err)")
                if let failURL {
                    playerLog.error("❌ [\(label)] failing URL: \(failURL.prefix(200))")
                }
                return false
            case .unknown:
                continue
            @unknown default:
                continue
            }
        }
        return false
    }

    private func resolvedAttemptURL(
        _ url: URL, video: Video, info: PlayerInfo, label: String, hlsPolicy: HLSPlaybackPolicy
    ) async -> (URL, Bool) {
        var effectiveURL = url
        var applyHLSHints = false
        if let hlsURL = info.hlsURL, url == hlsURL {
            let videoId = video.id
            let allVariantURLs: [Int: URL]
            if hlsPolicy.filtersMasterManifest {
                let fetched = await qualityManager.fetchHLSVariantURLs(
                    url: hlsURL, userAgent: hlsPolicy.userAgent
                )
                if fetched.isEmpty,
                    let cached = PlaybackQualityManager.cachedHLSVariants(for: videoId)
                {
                    allVariantURLs = cached
                } else {
                    allVariantURLs = fetched
                }
                if !fetched.isEmpty {
                    PlaybackQualityManager.cacheHLSVariants(fetched, for: videoId)
                }
            } else if let cached = PlaybackQualityManager.cachedHLSVariants(for: videoId) {
                playerLog.notice("[\(label)] HLS: using cached manifest for \(videoId) variantCount=\(cached.count)")
                allVariantURLs = cached
            } else {
                let fetched = await fetchHLSVariantURLs(url: hlsURL)
                allVariantURLs = fetched
                if !fetched.isEmpty {
                    PlaybackQualityManager.cacheHLSVariants(fetched, for: videoId)
                }
            }
            let urls =
                hlsPolicy.maximumHeight.map { cap in
                    allVariantURLs.filter { $0.key <= cap }
                } ?? allVariantURLs
            playerLog.notice(
                "[\(label)] HLS: hlsURL=yes variantCount=\(urls.count) effectiveQuality=\(effectiveQuality)")
            availableFormats = hlsPolicy.pickerFormats(from: info.formats, current: availableFormats)
            if !urls.isEmpty {
                hlsVariantURLs = urls
                let playableFormats = availableFormats.filter { urls.keys.contains($0.height) }
                availableFormats = playableFormats
                // Use a variant playlist URL directly rather than the master manifest URL.
                // The master manifest (hls_variant) stalls AVPlayer on manifest.googlevideo.com
                // because it requires session-level auth that AVPlayer's isolated network stack
                // cannot provide. Variant playlist URLs (hls_playlist) are directly downloadable
                // — yt-dlp confirms 720p in 13 s, 1080p in 29 s for the same video.
                // Per-video pick (when set) takes precedence over the persisted default —
                // a mid-playback 403 recovery must not silently revert the user's choice.
                let preferredMaxH = hlsPolicy.cappedHeight(requested: effectiveQuality.maxHeight)
                let chosen =
                    preferredMaxH
                    .flatMap { height in urls.filter { $0.key <= height }.max(by: { $0.key < $1.key }) }
                    ?? urls.max(by: { $0.key < $1.key })
                if let chosen {
                    if hlsPolicy.filtersMasterManifest {
                        effectiveURL = hlsURL
                        playerLog.notice(
                            "[\(label)] HLS: using \(hlsPolicy.videoCodecs.joined(separator: "+"))-filtered master (top \(chosen.key)p) with audio renditions"
                        )
                    } else {
                        effectiveURL = chosen.value
                        playerLog.notice("[\(label)] HLS: selected variant \(chosen.key)p")
                    }
                    // DIAGNOSTIC D-14: probe variant playlist + first segment before handing to AVPlayer.
                    // Ephemeral session → no cookies, no shared state.
                    // 200 → URL is publicly accessible; 403 → YouTube session (SAPISID) required.
                    // Also logs first segment URL to determine if rqh=1 is enforced at segment level.
                    probeHLSVariant(chosen.value, label: label)
                }
            } else {
                playerLog.notice("[\(label)] HLS manifest fetch returned 0 variants — using master as-is")
            }
            qualityManager.configureHLSPlayback(
                userAgent: hlsPolicy.userAgent,
                maximumHeight: hlsPolicy.maximumHeight,
                videoCodecs: hlsPolicy.videoCodecs
            )
            qualityManager.setSelectedFormatForCurrentPreference()
            applyHLSHints = true
        } else {
            playerLog.notice("[\(label)] non-HLS URL — no EXT-X-MEDIA, audio tracks will be unavailable")
        }

        return (effectiveURL, applyHLSHints)
    }

    private func probeHLSVariant(_ url: URL, label: String) {
        let capturedAuthToken = currentAuthToken
        Task {
            var diagReq = URLRequest(url: url)
            diagReq.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                forHTTPHeaderField: "User-Agent"
            )
            diagReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            diagReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            diagReq.timeoutInterval = PlaybackTuning.playlistProbeTimeout
            guard
                let (diagData, diagResp) = try? await URLSession(configuration: .ephemeral).data(
                    for: diagReq),
                let http = diagResp as? HTTPURLResponse
            else {
                playerLog.notice(
                    "[\(label)] D-14 HLS variant probe: fail/timeout (no-cookie/Safari UA)")
                return
            }
            let playlistText = String(data: diagData, encoding: .utf8) ?? ""
            // Find first absolute segment URL (https:// line not starting with #)
            let firstSegURL =
                playlistText.components(separatedBy: "\n")
                .first { $0.hasPrefix("https://") } ?? "(no absolute URL found)"
            // rqh=1 appears as /rqh/1/ path-style in HLS URLs (not ?rqh=1 query-style)
            let hasRqh =
                firstSegURL.contains("/rqh/1") || firstSegURL.contains("rqh=1")
                || firstSegURL.contains("rqh%3D1")
            playerLog.notice(
                "[\(label)] D-14 HLS variant probe: HTTP \(http.statusCode) bytes=\(diagData.count) firstSeg_rqh=\(hasRqh) firstSeg=\(firstSegURL.prefix(600))"
            )
            // If no absolute URL, log the first non-comment line to see relative segment format
            if !firstSegURL.hasPrefix("https://") {
                let firstNonComment =
                    playlistText.components(separatedBy: "\n")
                    .first { !$0.hasPrefix("#") && !$0.isEmpty } ?? "(empty)"
                playerLog.notice(
                    "[\(label)] D-14 first non-comment line: \(firstNonComment.prefix(200))")
            }
            // Also test first segment URL (if absolute) to see if segments need auth
            if firstSegURL.hasPrefix("https://"), let segURL = URL(string: firstSegURL) {
                var segReq = URLRequest(url: segURL)
                segReq.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                    forHTTPHeaderField: "User-Agent"
                )
                segReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                segReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                segReq.timeoutInterval = PlaybackTuning.playlistProbeTimeout
                // Range request — just the first byte to test access
                segReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                if let (_, segResp) = try? await URLSession(configuration: .ephemeral).data(for: segReq),
                    let segHttp = segResp as? HTTPURLResponse
                {
                    playerLog.notice(
                        "[\(label)] D-14 segment probe (Safari UA/no-cookie): HTTP \(segHttp.statusCode) rqh=\(hasRqh)"
                    )
                } else {
                    playerLog.notice("[\(label)] D-14 segment probe: fail/timeout")
                }

                // D-15: probe same segment WITH Bearer token — determines if
                // OAuth2 Bearer satisfies rqh=1 for HLS path-style segments.
                // If this returns 200/206, resource-loader interception is viable.
                if let bearerToken = capturedAuthToken, hasRqh {
                    var segBearerReq = URLRequest(url: segURL)
                    segBearerReq.setValue(
                        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
                        forHTTPHeaderField: "User-Agent"
                    )
                    segBearerReq.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                    segBearerReq.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
                    segBearerReq.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                    segBearerReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                    segBearerReq.timeoutInterval = PlaybackTuning.playlistProbeTimeout
                    if let (_, segResp2) = try? await URLSession(configuration: .ephemeral).data(
                        for: segBearerReq),
                        let segHttp2 = segResp2 as? HTTPURLResponse
                    {
                        playerLog.notice(
                            "[\(label)] D-15 segment probe (Safari UA+Bearer): HTTP \(segHttp2.statusCode) rqh=\(hasRqh)"
                        )
                    } else {
                        playerLog.notice("[\(label)] D-15 segment probe (Bearer): fail/timeout")
                    }
                }
            }
        }
    }

    private func makeAttemptItem(
        url: URL, hlsPolicy: HLSPlaybackPolicy, applyHLSHints: Bool, label: String
    ) -> AVPlayerItem {
        let isHLSManifest = label.contains("/HLS")
        let hlsUA = hlsPolicy.userAgent
        var hlsHeaders: [String: String] = ["User-Agent": hlsUA]
        if isHLSManifest {
            hlsHeaders["Origin"] = "https://www.youtube.com"
            hlsHeaders["Referer"] = "https://www.youtube.com/"
        }

        let item: AVPlayerItem
        if applyHLSHints {
            // Use AVURLAsset with custom UA headers for HLS — AVFoundation handles
            // HLS natively and sends our YouTube UA for ALL requests (manifest +
            // segments). AetherEngine cannot be used here because FFmpegBuild has
            // no HTTP protocol handler, so segment sub-requests inside HLS always
            // fail regardless of the io_open callback approach.
            let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": hlsHeaders]
            let asset = qualityManager.makeHLSAsset(url: url, options: uaOpts)
            playerLog.notice("[\(label)] HLS via AVURLAsset (native stack) url=\(url.lastPathComponent)")
            item = AVPlayerItem(asset: asset)
        } else {
            // Non-HLS (muxed / DASH): direct AVURLAsset with iOS UA headers.
            let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": hlsHeaders]
            item = AVPlayerItem(asset: AVURLAsset(url: url, options: uaOpts))
        }
        item.audioTimePitchAlgorithm = .spectral
        // Reduce startup latency: begin playback after 0.5 s of buffered content
        // (matches the primary HLS path). Reset to system default after readyToPlay.
        item.preferredForwardBufferDuration = 0.5
        Task { [weak item] in
            try? await Task.sleep(for: PlaybackTuning.bufferReleaseDelay)
            item?.preferredForwardBufferDuration = 0
        }
        if applyHLSHints {
            if let maxH = hlsPolicy.cappedHeight(requested: effectiveQuality.maxHeight) {
                item.preferredMaximumResolution = CGSize(width: CGFloat(maxH) * 4, height: CGFloat(maxH))
                item.preferredPeakBitRate = peakBitRate(for: maxH)
                playerLog.notice(
                    "[\(label)] HLS ABR hints: maxH=\(maxH)p peakBitRate=\(peakBitRate(for: maxH) / 1_000_000)Mbps (master URL preserved)"
                )
            } else {
                // Auto: remove all constraints so AVPlayer picks the best available variant.
                item.preferredMaximumResolution = .zero
                item.preferredPeakBitRate = 0
                playerLog.notice("[\(label)] HLS ABR hints cleared (Auto quality, unconstrained)")
            }
        }
        return item
    }

    private func attemptItemBecameReady(
        _ item: AVPlayerItem, video: Video, info: PlayerInfo, label: String, isMuxedFallback: Bool
    ) {
        playerLog.notice("[benchmark] readyToPlay — \(label) — videoId=\(video.id) title=\(video.title)")
        playerLog.notice("✅ [\(label)] readyToPlay")
        let itemDur = item.duration.seconds
        if itemDur.isFinite && itemDur > 0 {
            let prevDur = self.duration
            self.duration = itemDur
            playerLog.notice(
                "[duration] updated from AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s from metadata)"
            )
        } else if self.duration == 0 {
            durationObserverTask?.cancel()
            durationObserverTask = Task { [weak self, weak item] in
                guard let self, let item else { return }
                for await seconds in item.firstValidDurationStream {
                    guard !Task.isCancelled else { return }
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
        loadAudioTracks(from: item)
        needsQuickStartup = false
        isLoading = false
        timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
        lastSuccessfulStreamType = label
        player.rate = Float(settings.playbackSpeed)
        isPlaying = true
        launchPhase2(video: video, info: info)
        // Track whether the succeeded stream is muxed so quality-switch attempts
        // can detect the state and trigger fresh WKWebView extraction (#210).
        qualityManager.isMuxedFallback = isMuxedFallback
    }

}
