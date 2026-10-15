@preconcurrency import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - WebView HLS Languages and Variants

extension PlaybackViewModel {
    #if canImport(WebKit)

    struct HLSLanguageContext {
        let manifestURL: URL
        let manifestText: String
        let nSolver: (unsolved: String, solved: String)?
        let webViewCookies: [HTTPCookie]
    }

    /// Reloads the WKWebView HLS AVPlayerItem with the master manifest filtered for a
    /// dubbed-audio language (or original when contentID is nil). Called when the user
    /// selects an audio track from the picker via AudioTrackManager.onHLSLanguageChange.
    func switchHLSLanguage(
        to contentID: String?, context: HLSLanguageContext, for video: Video, seekTo position: Double
    ) async {
        let manifestURL = context.manifestURL
        let manifestText = context.manifestText
        let nSolver = context.nSolver
        let webViewCookies = context.webViewCookies
        let idDisplay = contentID ?? "original"
        playerLog.notice("[wkHLS/lang] switching to contentID=\(idDisplay)")

        // Update hlsVariantURLs so quality switching preserves the selected language.
        let langVariants = parseHLSVariantURLsForLanguage(
            contentID, from: manifestText,
            baseURL: manifestURL)
        if !langVariants.isEmpty {
            hlsVariantURLs = langVariants
            let variantSummary = langVariants.keys.sorted(by: >).map { "\($0)p" }.joined(separator: ", ")
            playerLog.notice("[wkHLS/lang] updated hlsVariantURLs: \(variantSummary)")
        }

        let ua =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        let proxyLoader = YTHLSProxyLoader(
            ua: ua, nSolver: nSolver, webViewCookies: webViewCookies,
            selectedLanguageContentID: contentID)
        guard let proxyURL = manifestURL.proxyURL else {
            playerLog.error("❌ [wkHLS/lang] failed to build proxy URL")
            return
        }
        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(proxyLoader, queue: DispatchQueue.global(qos: .userInitiated))
        webHLSProxyLoader = proxyLoader

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        item.preferredForwardBufferDuration = 2.0
        if let best = langVariants.keys.filter({ $0 >= 720 }).max() ?? langVariants.keys.max(), best > 0 {
            item.preferredMaximumResolution = CGSize(width: 7680, height: best)
        }
        Task { [weak item] in
            try? await Task.sleep(for: PlaybackTuning.bufferReleaseDelay)
            item?.preferredForwardBufferDuration = 0
        }

        player.replaceCurrentItem(with: item)
        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                let posStr = String(format: "%.1f", position)
                playerLog.notice("[benchmark] readyToPlay — wkHLS/lang — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [wkHLS/lang] readyToPlay — seeking to \(posStr)s")
                if position > 0 {
                    let target = CMTime(seconds: position, preferredTimescale: 600)
                    await item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                player.rate = Float(settings.playbackSpeed)
                return
            case .failed:
                let err = item.error?.localizedDescription ?? "nil"
                playerLog.error("❌ [wkHLS/lang] AVPlayerItem failed: \(err)")
                return
            case .unknown: continue
            @unknown default: continue
            }
        }
    }

    /// Extracts all cookies from the WKWebView's httpCookieStore, including googlevideo.com
    /// cookies required for rqh=1-enforced CDN segment requests.
    func extractWKWebViewCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let gvCount = cookies.filter { $0.domain.contains("googlevideo") }.count
                playerLog.notice("[webView/HLS] extracted \(cookies.count) cookies (\(gvCount) googlevideo) for proxy")
                cont.resume(returning: cookies)
            }
        }
    }

    /// Probes a cached WKWebView HLS master manifest URL with a lightweight HEAD request
    /// to detect expiry before constructing an AVPlayerItem.
    /// Returns `true` if the URL is still accessible (2xx/3xx); `false` on 4xx or timeout.
    func isWKHLSURLValid(_ url: URL) async -> Bool {
        let ua =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = PlaybackTuning.playlistProbeTimeout
        if let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
            let http = response as? HTTPURLResponse
        {
            playerLog.notice("[wkHLS/probe] HEAD returned HTTP \(http.statusCode)")
            return http.statusCode < 400
        }
        playerLog.notice("[wkHLS/probe] HEAD probe timeout or failed — treating as expired")
        return false
    }

    /// Parses YouTube's HLS master manifest for dubbed-audio language tracks encoded via
    /// YT-EXT-AUDIO-CONTENT-ID attributes on #EXT-X-STREAM-INF lines.
    ///
    /// YouTube does NOT use standard #EXT-X-MEDIA:TYPE=AUDIO groups for dubbed content.
    /// Instead each quality level appears N times — once per audio language — with
    /// YT-EXT-AUDIO-CONTENT-ID="xx-XX.N" identifying the language. The original audio
    /// variant has no YT-EXT-AUDIO-CONTENT-ID and is NOT returned here.
    ///
    /// The YT-EXT-XTAGS attribute on each variant is base64-encoded protobuf containing
    /// "acont=original" or "acont=dubbed-auto" plus "lang=xx-XX". We use this to mark
    /// the `acont=original` track as isOriginal=true.
    ///
    /// Returns deduplicated AudioTrack array (original first if present, then dubbed).
    func parseHLSAudioLanguages(from manifest: String) -> [AudioTrack] {
        SmartTubeIOSCore.parseHLSAudioLanguages(from: manifest)
    }

    /// Parses a map of stream height → variant URL from the HLS master manifest for a
    /// specific dubbed-audio content ID. Used by switchHLSLanguage to update hlsVariantURLs.
    /// If `contentID` is nil, returns original-audio variant URLs (no YT-EXT-AUDIO-CONTENT-ID).
    private func parseHLSVariantURLsForLanguage(
        _ contentID: String?,
        from manifest: String,
        baseURL: URL
    ) -> [Int: URL] {
        SmartTubeIOSCore.parseHLSVariantURLsForLanguage(contentID, from: manifest, baseURL: baseURL)
    }

    /// Extracts the value of a quoted HLS attribute (e.g. `ATTR="value"`) from a tag line.
    private func extractQuotedHLSAttribute(_ name: String, from line: String) -> String? {
        SmartTubeIOSCore.extractQuotedHLSAttribute(name, from: line)
    }

    /// Parses an HLS master M3U8 manifest and returns a map of stream height → variant URL
    /// for all streams present. Handles both absolute and relative URIs.
    /// Returns one URL per quality level — the first variant seen per height (original audio when
    /// available, first dubbed entry as fallback when the manifest omits no-CONTENT-ID variants).
    func parseHLSAllVariants(from manifest: String, baseURL: URL) -> [Int: URL] {
        SmartTubeIOSCore.parseHLSAllVariants(from: manifest, baseURL: baseURL)
    }

    /// Parses an HLS master M3U8 manifest and returns the URL of the best stream at ≥ `minHeight`.
    /// Handles both absolute URIs and relative paths (resolved against `baseURL`).
    func parseHLSBestVariant(from manifest: String, baseURL: URL, minHeight: Int) -> URL? {
        let result = SmartTubeIOSCore.parseHLSBestVariant(from: manifest, baseURL: baseURL, minHeight: minHeight)
        if let result {
            playerLog.notice("[webView/HLS] best variant ≥\(minHeight)p: \(result.absoluteString.prefix(80))")
        }
        return result
    }

    /// Proactively extracts and caches the WKWebView HLS master manifest URL for a neighbour
    /// video while the current video is already playing. Stores the result in VideoPreloadCache
    /// so that when the user swipes to the neighbour, exhaustiveRetry skips the 5–9 s
    /// WKWebView extraction step and plays from the cached URL directly.
    ///
    /// Skips silently if the URL is already cached or if extraction returns nil.
    func preExtractWKHLSForVideo(_ videoId: String) async {
        guard await VideoPreloadCache.shared.cachedWKHLSURL(for: videoId) == nil else {
            playerLog.notice("[wkHLS] pre-extract skipped — already cached for \(videoId)")
            return
        }
        playerLog.notice("[wkHLS] pre-extracting HLS URL for neighbour \(videoId)")
        guard let url = await YouTubeWebViewHLSExtractor.shared.extractHLSURL(videoId: videoId) else {
            playerLog.notice("[wkHLS] pre-extract returned nil for \(videoId)")
            return
        }
        await VideoPreloadCache.shared.store(wkHLSManifestURL: url, for: videoId)
        playerLog.notice("✅ [wkHLS] pre-extract done for \(videoId)")
    }
    #endif

    // MARK: - yt-dlp HLS simulator fast-path

    #if targetEnvironment(simulator)
    /// Loads a yt-dlp `hls_playlist` URL directly into AVPlayer. Kept for backward compatibility.
    private func tryYtDlpHLS(_ url: URL, for video: Video) async -> Bool {
        playerLog.notice("[ytDlp[sim]/HLS]: \(url.absoluteString.prefix(120))")
        let ua = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"
        let uaOpts: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ua]]
        let asset = AVURLAsset(url: url, options: uaOpts)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        item.preferredForwardBufferDuration = 2.0
        Task { [weak item] in
            try? await Task.sleep(for: PlaybackTuning.bufferReleaseDelay)
            item?.preferredForwardBufferDuration = 0
        }
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()
        for await status in item.statusStream {
            switch status {
            case .readyToPlay:
                playerLog.notice("[benchmark] readyToPlay — ytDlp/HLS — videoId=\(video.id) title=\(video.title)")
                playerLog.notice("✅ [ytDlp[sim]/HLS] readyToPlay")
                needsQuickStartup = false
                isLoading = false
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                return true
            case .failed:
                let err = item.error?.localizedDescription ?? "nil"
                playerLog.error("❌ [ytDlp[sim]/HLS] AVPlayerItem failed: \(err)")
                return false
            case .unknown: continue
            @unknown default: continue
            }
        }
        return false
    }
    #endif

}
