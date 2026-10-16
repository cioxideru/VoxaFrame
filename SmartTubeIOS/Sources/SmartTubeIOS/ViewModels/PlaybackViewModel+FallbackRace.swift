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

// MARK: - Fallback Races and Background Upgrades

extension PlaybackViewModel {

    // MARK: - Race helpers (called from withTaskGroup in exhaustiveRetry)

    /// Path A of the exhaustiveRetry race: BotGuardWV adaptive / proxy HLS path.
    /// Waits up to 6 s for BotGuard to mint a token, then tries WEB/iOS/Android adaptive.
    /// Returns `true` if a stream reached `readyToPlay`.
    #if canImport(WebKit)
    func racePathA(video: Video) async -> Bool {
        if !BotGuardWebViewRunner.shared.isReady {
            playerLog.notice("[BotGuardWV] waiting up to 6 s for minted token (race Path A)…")
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await BotGuardWebViewRunner.shared.prepare(for: video.id) }
                group.addTask { try? await Task.sleep(nanoseconds: PlaybackTuning.botGuardTimeoutNanoseconds) }
                _ = await group.next()
                group.cancelAll()
            }
        }
        guard !Task.isCancelled else { return false }
        guard BotGuardWebViewRunner.shared.isReady else {
            playerLog.notice("[BotGuardWV] not ready after 6 s wait — Path A done")
            return false
        }
        // fix9: SAPISID recovery from WKWebView propagated cookies.
        // BotGuardWebViewRunner.prepare() calls propagateWebViewCookies() which copies
        // youtube.com cookies (including SAPISID) from the WKWebView session into
        // HTTPCookieStorage.shared. On real device, the WKWebView is signed into YouTube
        // (default WKWebsiteDataStore shares cookies with the signed-in browser session)
        // so SAPISID is now in HTTPCookieStorage.shared even when AuthService couldn't get
        // it via OAuthLogin/Multilogin (openid scope missing / old token).
        // Recovering SAPISID here lets postWebSafari use SAPISIDHASH auth → YouTube returns
        // rqh=0 adaptive URLs → CDN probe passes → Path A wins instead of waiting for Path B.
        if await !api.hasSAPISID,
            let webSAPISID = HTTPCookieStorage.shared
                .cookies(for: URL(string: "https://www.youtube.com")!)?.first(where: { $0.name == "SAPISID" })?.value
        {
            await api.setSAPISID(webSAPISID)
            playerLog.notice(
                "[BotGuardWV] fix9: recovered SAPISID from WKWebView propagated cookies (len=\(webSAPISID.count))")
        }
        let webVD = BotGuardWebViewRunner.shared.webVisitorData
        // fix8: use webVD as the mintToken identifier so the minted pot= token is bound
        // to the WEB session visitorData — the same VD that will be sent in
        // fetchPlayerInfoWebWithPoToken's context.client.visitorData and X-Goog-Visitor-Id.
        // Previously, api.currentVisitorData() (iOS/TV session VD) was used as identifier,
        // causing apiVD ≠ webVD — the CDN tied the streaming URLs to the iOS session but
        // our pot= token was minted for the WEB session, causing HTTP 403 on every segment.
        // If webVD is empty (BotGuard warm-up hasn't fetched guide yet), fall back to apiVD.
        let apiVD = await api.currentVisitorData() ?? ""
        let identifier = webVD.isEmpty ? apiVD : webVD
        guard let mintedToken = await BotGuardWebViewRunner.shared.mintToken(identifier: identifier) else {
            playerLog.notice("[BotGuardWV] ⚠️ mintToken returned nil — Path A done")
            return false
        }
        await api.storeExternalPoToken(mintedToken, for: video.id)
        hasMintedPoToken = true
        playerLog.notice(
            "[BotGuardWV] ✅ minted token (len=\(mintedToken.count) webVD.len=\(webVD.count) apiVD.len=\(apiVD.count) match=\(apiVD == webVD)) — Path A racing WKWebView HLS"
        )
        guard !Task.isCancelled else { return false }
        return await tryBotGuardStreams(video: video, webVD: webVD, mintedToken: mintedToken)
    }
    private func botGuardProbeStatus(for probeURL: URL?) async -> Int? {
        if let probeURL {
            let hasRqh = probeURL.absoluteString.contains("rqh=1")
            // Only run the CDN HEAD probe when the URL has rqh=1. The probe is only
            // used to skip tryAllStreams on 403. For non-rqh=1 URLs the CDN serves
            // the stream directly — skipping the probe removes one network round-trip
            // (~0.5–1s) from Path A, helping it win the race against Path B.
            if hasRqh {
                var req = URLRequest(
                    url: probeURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: PlaybackTuning.botGuardProbeTimeout)
                req.httpMethod = "HEAD"
                let hasPot = probeURL.absoluteString.contains("pot=")
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                    let http = resp as? HTTPURLResponse
                {
                    playerLog.notice(
                        "[BotGuardWV/WEB probe] CDN HEAD: HTTP \(http.statusCode) — pot=\(hasPot ? "YES" : "NO") rqh=1"
                    )
                    return http.statusCode
                }
            } else {
                playerLog.notice("[BotGuardWV/WEB probe] skipping CDN probe — no rqh=1, proceeding directly")
            }
        }
        return nil
    }

    private func tryBotGuardProxyHLS(proxyURL: URL, mintedToken: String, video: Video) async -> Bool {
        guard !Task.isCancelled else { return false }
        playerLog.notice("[BotGuardWV] trying HLS via pot= proxy (Path A)")
        let safariUA = InnerTubeClients.WebSafari.userAgent
        let potProxyLoader = YTHLSProxyLoader(ua: safariUA, poToken: mintedToken)
        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(potProxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
        webHLSProxyLoader = potProxyLoader
        let proxyItem = AVPlayerItem(asset: asset)
        proxyItem.audioTimePitchAlgorithm = .spectral
        proxyItem.preferredForwardBufferDuration = 0.5
        player.replaceCurrentItem(with: proxyItem)
        observePlaybackEndAndStalls(for: proxyItem)
        itemObserverTask?.cancel()
        for await st in proxyItem.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
            guard !Task.isCancelled, currentVideo?.id == video.id, player.currentItem === proxyItem else {
                return false
            }
            switch st {
            case .readyToPlay:
                playerLog.notice("[benchmark] readyToPlay — BotGuardWV/proxy-HLS — videoId=\(video.id)")
                timeToPlayMs = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1000)
                playerLog.notice("[BotGuardWV] ✅ Path A won — proxy HLS")
                return true
            case .failed:
                playerLog.notice(
                    "[BotGuardWV] ⚠️ proxy HLS failed: \(ViewModelLogger.errorSummary(proxyItem.error))")
            default:
                continue
            }
            break
        }
        return false
    }

    private func tryBotGuardStreams(video: Video, webVD: String, mintedToken: String) async -> Bool {
        do {
            let webInfo = try await api.fetchPlayerInfoWebWithPoToken(
                videoId: video.id, visitorData: webVD.isEmpty ? nil : webVD
            )
            let probeURL = webInfo.formats.first(where: {
                $0.mimeType.hasPrefix("video/mp4") && $0.url != nil
            })?.url
            let webProbeStatus = await botGuardProbeStatus(for: probeURL)
            guard !Task.isCancelled else { return false }
            if webProbeStatus != 403,
                await tryAllStreams(video: video, info: webInfo, label: "BotGuardWV", skipMuxed: true)
            {
                playerLog.notice("[BotGuardWV] ✅ Path A won — WEB adaptive")
                return true
            } else if webProbeStatus == 403 {
                playerLog.notice("[BotGuardWV] WEB probe 403 — skipping tryAllStreams + proxy HLS in Path A")
            }
            if webProbeStatus != 403, let hlsURL = webInfo.hlsURL, let proxyURL = hlsURL.proxyURL {
                if await tryBotGuardProxyHLS(proxyURL: proxyURL, mintedToken: mintedToken, video: video) { return true }

            }
            guard !Task.isCancelled, webProbeStatus != 403 else { return false }
            playerLog.notice("[BotGuardWV] trying iOS adaptive with WAA minted token (Path A)")
            do {
                let iosInfo = try await api.fetchPlayerInfo(videoId: video.id)
                if await tryAllStreams(video: video, info: iosInfo, label: "BotGuardWV", skipMuxed: true) {
                    playerLog.notice("[BotGuardWV] ✅ Path A won — iOS adaptive")
                    return true
                }
            } catch {
                playerLog.notice("[BotGuardWV] ⚠️ iOS adaptive fetch failed: \(ViewModelLogger.errorSummary(error))")
            }
            guard !Task.isCancelled else { return false }
            playerLog.notice("[BotGuardWV] trying Android adaptive with WAA minted token (Path A)")
            do {
                let androidInfo = try await api.fetchPlayerInfoAndroid(videoId: video.id)
                if await tryAllStreams(video: video, info: androidInfo, label: "BotGuardWV", skipMuxed: true) {
                    playerLog.notice("[BotGuardWV] ✅ Path A won — Android adaptive")
                    return true
                }
            } catch {
                playerLog.notice("[BotGuardWV] ⚠️ Android adaptive fetch failed: \(ViewModelLogger.errorSummary(error))")
            }
        } catch {
            playerLog.notice("[BotGuardWV] ⚠️ WEB client fetch failed: \(ViewModelLogger.errorSummary(error))")
        }
        playerLog.notice("[BotGuardWV] Path A exhausted — all BotGuardWV attempts failed")
        return false
    }

    #endif  // canImport(WebKit)

    /// Path B of the exhaustiveRetry race: early WKWebView HLS path.
    /// Awaits the `wkHLSEarlyTask` started in `loadAsync` (already in-flight).
    /// Returns `true` if a stream reached `readyToPlay`.
    #if canImport(WebKit)
    func racePathB(video: Video) async -> Bool {
        guard let earlyTask = wkHLSEarlyTask else {
            playerLog.notice("⚠️ [webView] no earlyTask — Path B done")
            return false
        }
        playerLog.notice("⚠️ [webView] Path B awaiting early WKWebView HLS task…")
        guard let url = await earlyTask.value, !Task.isCancelled else {
            playerLog.notice("⚠️ [webView] earlyTask returned nil or cancelled — Path B done")
            return false
        }
        // fix20: Capture nSolver and poToken after earlyTask completes — the fresh
        // extraction has the up-to-date values (extractedPoToken is set at end of extractHLSURL).
        let nSolver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
        let capturedPoToken = YouTubeWebViewHLSExtractor.shared.extractedPoToken
        if let pot = capturedPoToken {
            await api.storeExternalPoToken(pot, for: video.id)
            playerLog.notice("[webView] pot= token stored from WKWebView (\(pot.count) chars)")
        }
        let nInfo = nSolver.map { "\($0.unsolved)→\($0.solved)" } ?? "nil"
        playerLog.notice("⚠️ [webView] Path B got hlsManifestUrl — nSolver=\(nInfo as NSString)")
        let won = await tryWebViewHLS(url, nSolver: nSolver, poToken: capturedPoToken, for: video)
        if won { playerLog.notice("✅ [webView] Path B won — WKWebView HLS") }
        return won
    }
    #endif  // canImport(WebKit)

    /// Path C of the exhaustiveRetry race: Android VR (Oculus Quest) adaptive path.
    /// CDN-exempt from rqh=1 / pot= token requirements. Runs concurrently with Path A and B.
    /// Returns `true` if adaptive composition reached `readyToPlay`.
    func racePathC(video: Video) async -> Bool {
        guard !Task.isCancelled else { return false }
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            if await tryAllStreams(video: video, info: vrInfo, label: "AndroidVR/race", skipMuxed: true) {
                playerLog.notice("[AndroidVR] ✅ Path C won — AndroidVR adaptive composition")
                return true
            }
        } catch {
            playerLog.notice("[AndroidVR] ⚠️ Path C fetch failed: \(ViewModelLogger.errorSummary(error))")
        }
        playerLog.notice("[AndroidVR] Path C done — AndroidVR adaptive failed")
        return false
    }

    /// Background quality upgrade after AndroidVR wins the race at low quality (maxH < 480).
    ///
    /// Called from the `raceWon / case 2` block when AndroidVR composes at e.g. 240p for
    /// rqh=1 worst-case videos. Fires after a 700 ms stabilisation delay so the initial
    /// `readyToPlay` playback is already running. Tries:
    ///   1. TVEmbedded HLS (WEB_EMBEDDED_PLAYER — HLS for most embeddable videos)
    ///   2. MWEB HLS (m.youtube.com — no pot= for HLS, wider coverage than TVEmbedded)
    ///
    /// On success, replaces the current AVPlayerItem at the current playback position so
    /// the user sees no gap (position is saved to `savedPositionToRestore` just before
    /// calling `attemptURL`, and consumed by `attemptURL`'s `.readyToPlay` handler).
    /// On failure, stays on the AndroidVR quality silently — no error shown to the user.
    func backgroundQualityUpgrade(video: Video) async {
        // Stabilisation delay — let readyToPlay fire and playback begin before replacing the item.
        try? await Task.sleep(nanoseconds: PlaybackTuning.qualityUpgradeDelayNanoseconds)
        guard !Task.isCancelled else { return }
        // Bail if the user navigated to a different video while we were waiting.
        guard currentVideo?.id == video.id else {
            playerLog.notice("[VR→HLS/upgrade] video changed — cancelling quality upgrade")
            return
        }

        // 1. Try TVEmbedded HLS (WEB_EMBEDDED_PLAYER, nameID=56).
        do {
            let tvEmbedInfo = try await api.fetchPlayerInfoTVEmbedded(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            if let hlsURL = tvEmbedInfo.hlsURL {
                playerLog.notice("[VR→HLS/upgrade] TVEmbedded HLS available — upgrading from AndroidVR quality")
                // Capture position right before replacement so the stale window is minimal.
                let pos = currentTime
                if pos > 0.5 { savedPositionToRestore = pos }
                if await attemptURL(hlsURL, for: video, info: tvEmbedInfo, label: "VR→HLS/upgrade/TVEmbed") {
                    playerLog.notice("[VR→HLS/upgrade] ✅ quality upgrade via TVEmbedded HLS complete")
                    return
                }
                // attemptURL returned false — clear the now-stale saved position.
                savedPositionToRestore = nil
            }
        } catch {
            playerLog.notice("[VR→HLS/upgrade] TVEmbedded fetch failed: \(ViewModelLogger.errorSummary(error))")
        }

        guard !Task.isCancelled, currentVideo?.id == video.id else { return }

        // 2. Try MWEB HLS (m.youtube.com — no pot= required for HLS, wider coverage).
        do {
            let mwebInfo = try await api.fetchPlayerInfoMWEB(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            if let hlsURL = mwebInfo.hlsURL {
                playerLog.notice("[VR→HLS/upgrade] MWEB HLS available — upgrading from AndroidVR quality")
                let pos = currentTime
                if pos > 0.5 { savedPositionToRestore = pos }
                if await attemptURL(hlsURL, for: video, info: mwebInfo, label: "VR→HLS/upgrade/MWEB") {
                    playerLog.notice("[VR→HLS/upgrade] ✅ quality upgrade via MWEB HLS complete")
                    return
                }
                savedPositionToRestore = nil
            }
        } catch {
            playerLog.notice("[VR→HLS/upgrade] MWEB fetch failed: \(ViewModelLogger.errorSummary(error))")
        }

        if await upgradeWithAndroidVR(video: video) { return }

        playerLog.notice("[upgrade] no quality upgrade available — staying on muxed stream")
    }

    private func upgradeWithAndroidVR(video: Video) async -> Bool {
        // 3. Try AndroidVR adaptive (CDN-exempt rqh=1, no HLS needed).
        // Useful when muxed (360p) is playing and AndroidVR can deliver 1080p+ via adaptive
        // composition. The 2s loadTracks timeout applies — if CDN stalls we bail quickly.
        // Position is saved so the upgraded stream resumes from current playback point.
        //
        // On failure: keep availableFormats = AndroidVR's format list (so the quality picker
        // shows e.g. 1080p/720p options). Also restore isMuxedFallback = true because
        // tryAllStreams() unconditionally sets it to false via the label check. Without this
        // restoration, tapping a quality routes through reloadDASHItem (silent rqh=1 failure)
        // instead of triggering retryWith403Recovery → exhaustiveRetry.
        guard !Task.isCancelled, currentVideo?.id == video.id else { return true }
        do {
            let vrInfo = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return true }
            let vrPos = currentTime
            if vrPos > 0.5 { savedPositionToRestore = vrPos }
            if await tryAllStreams(
                video: video, info: vrInfo,
                label: "muxed→upgrade/AndroidVR", skipMuxed: true)
            {
                playerLog.notice("[upgrade] ✅ quality upgrade via AndroidVR adaptive complete")
                return true
            }
            savedPositionToRestore = nil
            // Upgrade failed: availableFormats now has AndroidVR's list (set by attemptComposition)
            // which is correct — user can see quality options and tap to trigger a retry.
            // Restore isMuxedFallback so quality taps route to retryWith403Recovery.
            qualityManager.isMuxedFallback = true
            playerLog.notice(
                "[upgrade] AndroidVR adaptive failed — isMuxedFallback restored, \(availableFormats.count) formats visible in picker"
            )
        } catch {
            playerLog.notice("[upgrade] AndroidVR fetch failed: \(ViewModelLogger.errorSummary(error))")
        }

        return false
    }

    /// Kept for the `PlaybackQualityManagerDelegate` protocol.
    /// Quality-switch 403 errors start a fresh 3-attempt exhaustive cycle.
    func retryWith403Recovery(video: Video, originalError: Error?) async {
        playerLog.notice("403 recovery (quality switch) — exhaustive retry for \(video.id)")
        // Capture the current playback position so the new stream resumes from here.
        // Without this, attemptComposition / attemptURL have no seekTo target and the
        // new item starts from t=0 — causing the position-preservation assertion to fail.
        let pos = currentTime
        if pos > 0 {
            savedPositionToRestore = pos
        }
        retryAttempts = 0
        await exhaustiveRetry(video: video, originalError: originalError)
    }

}
