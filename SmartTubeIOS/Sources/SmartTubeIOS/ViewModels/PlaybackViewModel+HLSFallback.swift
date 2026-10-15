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

// MARK: - HLS and Adaptive Stream Selection

extension PlaybackViewModel {

    // MARK: - Helpers

    /// Returns the AVFoundation User-Agent for `url` based on its `c=` signing parameter.
    /// NOTE: This helper is no longer used by `rebuildCompositionForQuality`, which now always
    /// uses iOS UA. Kept for reference — the original assumption (Android UA needed for
    /// c=ANDROID URLs) was incorrect; the initial `attemptComposition` path proves iOS UA
    /// works for all URL signing variants.
    static func userAgent(for url: URL) -> String {
        let client =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "c" })?.value ?? ""
        return client.hasPrefix("ANDROID") ? InnerTubeClients.Android.userAgent : InnerTubeClients.iOS.userAgent
    }

    /// Returns the best adaptive video-only MP4 URL, respecting the user's quality preference.
    /// When `preferredQuality != .auto`, filters to formats at or below `maxHeight`, sorts
    /// by height descending then bitrate descending. Falls back to highest bitrate when no
    /// format meets the height cap.
    /// When `preferredQuality == .auto`, caps at the display's native resolution so the
    /// player never fetches a resolution higher than the screen can render.
    ///
    /// H.264 (avc1) is preferred over AV1 (av01) at any given resolution because Android-client
    /// AV1 streams require a proof-of-origin token (pot) that the app does not supply, causing
    /// systematic HTTP 403 errors on adaptive composition. H.264 streams are served without
    /// that restriction and are well-supported by AVFoundation.
    func qualityCapVideoURL(from formats: [SmartTubeIOSCore.VideoFormat]) -> URL? {
        let maxH: Int
        if settings.preferredQuality != .auto, let height = settings.preferredQuality.maxHeight {
            maxH = height
        } else {
            // Auto: cap at the display's native resolution — no benefit loading higher
            // than what the screen can actually render.
            maxH = Self.displayMaxVideoHeight()
        }
        return PlaybackQualityManager.selectBestVideoFormat(
            from: formats,
            preferredMaxHeight: maxH,
            preferH264: true
        )?.url
    }

    /// Returns the maximum video height (pixels) that this display can render for
    /// landscape 16:9 content. Used to cap quality in Auto mode.
    ///
    /// The shorter native-pixel dimension equals the landscape height — the maximum
    /// video height the screen can actually show for standard 16:9 YouTube content.
    static func displayMaxVideoHeight() -> Int {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first(where: { scene in
                scene.activationState == .foregroundActive && scene.windows.contains(where: \.isKeyWindow)
            })
            ?? scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        if let bounds = scene?.screen.nativeBounds {
            return Int(max(bounds.width, bounds.height))
        }
        #endif
        return 1080  // Conservative fallback when no scene or UIKit is available
    }

    // MARK: - HLS n-descrambling (simulator only)

    #if targetEnvironment(simulator)
    /// Probes the first segment of an HLS variant playlist.
    /// Returns `variantURL` unchanged if the segment is already accessible (n is valid).
    /// If the segment returns 403 (scrambled n), applies the JS solver to descramble the n
    /// in `variantURL` and returns the corrected URL. When the CDN receives a request with
    /// the descrambled n, it embeds the descrambled n in all segment URLs it returns, so
    /// AVPlayer can fetch every segment without receiving 403.
    private func descrambledVariantURL(_ variantURL: URL, label: String) async -> (URL, HLSVariantProxy?) {
        let ua = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"

        // 1. Fetch the variant playlist to obtain segment URLs.
        var req = URLRequest(url: variantURL)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = PlaybackTuning.playlistProbeTimeout
        guard let (data, _) = try? await URLSession.shared.data(for: req),
            let text = String(data: data, encoding: .utf8)
        else {
            playerLog.notice("[\(label)] n-probe: playlist fetch failed — using original URL")
            return (variantURL, nil)
        }

        // 2. Find the first absolute segment URL in the playlist.
        let lines = text.components(separatedBy: .newlines)
        guard let segStr = lines.first(where: { !$0.hasPrefix("#") && !$0.isEmpty && $0.hasPrefix("http") }),
            let segURL = URL(string: segStr)
        else {
            playerLog.notice("[\(label)] n-probe: no segment URL found — using original URL")
            return (variantURL, nil)
        }

        // 3. HEAD-probe the segment to detect scrambled n.
        var segReq = URLRequest(url: segURL)
        segReq.httpMethod = "HEAD"
        segReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        segReq.timeoutInterval = PlaybackTuning.segmentProbeTimeout
        if let (_, resp) = try? await URLSession.shared.data(for: segReq),
            let http = resp as? HTTPURLResponse, http.statusCode == 200
        {
            playerLog.notice("[\(label)] n-probe: segment 200 — n is valid, no descrambling needed")
            return (variantURL, nil)
        }

        // 4. Segment inaccessible (403) — extract scrambled n from the SEGMENT URL, not the
        //    variant playlist URL. The segment URLs inside the playlist carry an independent n
        //    that the CDN does NOT change based on the variant URL's n. Descrambling only the
        //    variant URL's n leaves segment n values scrambled → AVPlayer still gets 403.
        //    We must rewrite segment n values in the playlist content itself, then serve the
        //    modified playlist from a local temp file so AVPlayer fetches descrambled segments.
        playerLog.notice("[\(label)] n-probe: segment not 200 — rewriting segment n in playlist")

        // Extract n from segment URL (YouTube HLS uses path-based /n/VALUE/ format).
        let segPathParts = segURL.pathComponents
        let scrambledSegN: String?
        if let idx = segPathParts.firstIndex(of: "n"), idx + 1 < segPathParts.count,
            !segPathParts[idx + 1].isEmpty
        {
            scrambledSegN = segPathParts[idx + 1]
        } else if let nItem = URLComponents(url: segURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "n" }),
            let val = nItem.value, !val.isEmpty
        {
            scrambledSegN = val
        } else {
            scrambledSegN = nil
        }

        guard let scrambledN = scrambledSegN else {
            playerLog.notice("[\(label)] n-probe: could not extract n from segment URL — using original")
            return (variantURL, nil)
        }

        // 5. Descramble the segment n via the JS solver.
        //    Build a synthetic path-format URL so YouTubeNDescrambler.extractNParam can locate n.
        guard let syntheticURL = URL(string: "https://googlevideo.com/videoplayback/n/\(scrambledN)/seg.ts") else {
            return (variantURL, nil)
        }
        let descrambledSynthetic = await YouTubeNDescrambler.shared.descrambleURL(syntheticURL)
        guard descrambledSynthetic != syntheticURL else {
            playerLog.notice("[\(label)] n-probe: solver returned unchanged URL for segment n — using original")
            return (variantURL, nil)
        }

        // Extract the descrambled n value from the synthetic result.
        let descParts = descrambledSynthetic.pathComponents
        guard let dIdx = descParts.firstIndex(of: "n"), dIdx + 1 < descParts.count,
            !descParts[dIdx + 1].isEmpty
        else {
            return (variantURL, nil)
        }
        let descrambledN = descParts[dIdx + 1]
        playerLog.notice("[\(label)] n-probe: segment n descrambled")

        // 6. Rewrite ALL n occurrences in the playlist (path + query-string formats).
        //    All segments in a YouTube HLS playlist share the same n value, so a single
        //    replace-all pass covers every segment URL.
        var rewritten = text
        rewritten = rewritten.replacingOccurrences(of: "/n/\(scrambledN)/", with: "/n/\(descrambledN)/")
        // Also handle query-string format (n=OLD covers ?n=OLD& and &n=OLD& and &n=OLD\n)
        rewritten = rewritten.replacingOccurrences(of: "n=\(scrambledN)", with: "n=\(descrambledN)")

        // 6b. Verify the rewrite: probe the first rewritten segment to confirm 200.
        //     If still 403, the descrambled n is wrong (solver/player.js mismatch).
        guard await verifyDescrambledPlaylist(rewritten, userAgent: ua, label: label) else {
            return (variantURL, nil)
        }

        // 7. Serve the rewritten playlist via AVAssetResourceLoader (custom URL scheme).
        //    Using a file:// URL + AVURLAssetHTTPHeaderFieldsKey causes AVPlayer to silently hang
        //    in .unknown status indefinitely on the iOS Simulator — AVFoundation never fires
        //    readyToPlay. The file:// + HTTP-header-options combination appears to suppress the
        //    AVFoundation networking stack that fetches CDN segments, so the item never becomes
        //    ready. Using a custom non-http scheme instead routes the initial playlist request
        //    through AVAssetResourceLoader, which returns our pre-rewritten content. AVPlayer then
        //    fetches CDN segment URLs (https://) via its normal network stack — no file I/O needed.
        let proxy = HLSVariantProxy(playlistContent: rewritten)
        let proxyURL = HLSVariantProxy.makeProxyURL()
        playerLog.notice("[\(label)] n-probe: HLS proxy ready — serving \(rewritten.count) bytes")
        return (proxyURL, proxy)
    }
    private func verifyDescrambledPlaylist(
        _ rewritten: String, userAgent ua: String, label: String
    ) async -> Bool {
        let rewrittenLines = rewritten.components(separatedBy: .newlines)
        if let firstRewrittenSeg = rewrittenLines.first(where: {
            !$0.hasPrefix("#") && !$0.isEmpty && $0.hasPrefix("http")
        }),
            let verifyURL = URL(string: firstRewrittenSeg)
        {
            playerLog.notice(
                "[\(label)] n-probe: verifying rewritten segment host=\(ViewModelLogger.urlHost(verifyURL))")
            var verifyReq = URLRequest(url: verifyURL)
            verifyReq.httpMethod = "HEAD"
            verifyReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            verifyReq.timeoutInterval = PlaybackTuning.segmentProbeTimeout
            if let (_, verifyResp) = try? await URLSession.shared.data(for: verifyReq),
                let verifyHTTP = verifyResp as? HTTPURLResponse
            {
                playerLog.notice("[\(label)] n-probe: post-rewrite verify → HTTP \(verifyHTTP.statusCode)")
                if verifyHTTP.statusCode == 403 {
                    playerLog.error(
                        "[\(label)] n-probe: VERIFY FAILED — descrambled n returns 403; reverting to original URL")
                    return false
                }
            } else {
                playerLog.notice("[\(label)] n-probe: post-rewrite verify timed out or failed — proceeding anyway")
            }
        }

        return true
    }
    #endif

}
