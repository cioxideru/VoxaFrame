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

// MARK: - Stream Method Diagnostics and Simulator HLS Proxy

extension PlaybackViewModel {

    // MARK: - Single-method probe (testing only)

    /// Exercises exactly one stream-fetching client for `video` and attempts to play.
    ///
    /// Called from `exhaustiveRetry` when `StreamMethodProbeSupport.forcedStreamMethod`
    /// is set (via `--uitesting-force-stream-method=<method>`).  The result — success or
    /// failure — is observable through the existing `player.titleLabel` /
    /// `player.errorBanner` accessibility identifiers so UI tests need no extra wiring.
    ///
    /// - Parameters:
    ///   - method: One of `StreamMethodProbeSupport.knownMethods`.
    ///   - video: The video to probe.
    func probeStreamMethod(_ method: String, video: Video) async {
        playerLog.notice("[probe] starting single-method probe: \(method) for \(video.id)")
        isLoading = true
        retryStatusMessage = "Probing \(method)…"

        do {
            let info: PlayerInfo

            switch method {
            case "ios":
                info = try await api.fetchPlayerInfo(videoId: video.id)

            case "ios-auth":
                info = try await api.fetchPlayerInfoiOSAuthenticated(videoId: video.id)

            case "tvembedded":
                info = try await api.fetchPlayerInfoTVEmbedded(videoId: video.id)

            case "tvauth":
                info = try await api.fetchPlayerInfoAuthenticated(videoId: video.id)

            case "websafari":
                info = try await api.fetchPlayerInfoWebSafari(videoId: video.id)

            case "mweb":
                info = try await api.fetchPlayerInfoMWEB(videoId: video.id)

            case "android":
                info = try await api.fetchPlayerInfoAndroid(videoId: video.id)

            case "android-vr":
                info = try await api.fetchPlayerInfoAndroidVR(videoId: video.id)

            case "visionos":
                info = try await api.fetchPlayerInfoVisionOS(videoId: video.id)

            case "web-creator":
                info = try await api.fetchPlayerInfoWebCreator(videoId: video.id)

            case "web-auth":
                info = try await api.fetchPlayerInfoWebAuthenticated(videoId: video.id)

            #if canImport(WebKit)
            case "wkwebview-hls":
                let url = await YouTubeWebViewHLSExtractor.shared.serialExtract(videoId: video.id)
                let solver = YouTubeWebViewHLSExtractor.shared.extractedNSolver
                if let url, await tryWebViewHLS(url, nSolver: solver, for: video) {
                    probeStreamResult = "WKWebView-HLS"
                    playerLog.notice("[probe] ✅ wkwebview-hls succeeded for \(video.id)")
                } else {
                    playerLog.error("[probe] ❌ wkwebview-hls failed for \(video.id)")
                    error = APIError.unavailable("wkwebview-hls extraction failed")
                    isLoading = false
                }
                return
            #endif

            default:
                playerLog.error("[probe] unknown method '\(method)' — failing")
                error = APIError.unavailable("Unknown stream method '\(method)'")
                isLoading = false
                return
            }

            if await tryAllStreams(video: video, info: info, label: "probe/\(method)") {
                let desc = probeStreamDescription(for: info)
                probeStreamResult = desc
                playerLog.notice("[probe] ✅ \(method) succeeded for \(video.id) — \(desc)")
            } else {
                playerLog.error("[probe] ❌ \(method) returned no playable stream for \(video.id)")
                error = APIError.unavailable("No playable stream from \(method)")
                isLoading = false
            }
        } catch {
            playerLog.error("[probe] ❌ \(method) threw: \(error) for \(video.id)")
            self.error = error
            isLoading = false
        }
    }

    /// Returns a compact human-readable description of what a `PlayerInfo` offers:
    /// stream type + max video resolution. Used by `player.probeStreamResult` accessibility
    /// element so `StreamMethodProbeUITests` can capture the resolution per-test.
    private func probeStreamDescription(for info: PlayerInfo) -> String {
        let videoFormats = info.formats.filter {
            $0.mimeType.hasPrefix("video/") && !$0.mimeType.contains(", ") && $0.height > 0
        }
        let maxH = videoFormats.map(\.height).max() ?? 0
        let maxFPS = videoFormats.filter { $0.height == maxH }.map(\.fps).max() ?? 0
        let resLabel = maxH > 0 ? "\(maxH)p\(maxFPS > 30 ? "\(maxFPS)" : "")" : ""

        if info.hlsURL != nil {
            return resLabel.isEmpty ? "HLS" : "HLS \(resLabel)"
        }
        if maxH > 0 {
            let suffix = info.containsRqhAdaptiveFormats ? " rqh=1" : ""
            return "\(resLabel)\(suffix)"
        }
        // Muxed only
        let muxedFormats = info.formats.filter {
            $0.mimeType.hasPrefix("video/mp4") && $0.mimeType.contains(", ") && $0.height > 0
        }
        let muxedH = muxedFormats.map(\.height).max() ?? 0
        return muxedH > 0 ? "muxed \(muxedH)p" : "unknown"
    }
}

#if targetEnvironment(simulator)
/// Minimal `AVAssetResourceLoaderDelegate` that serves a pre-rewritten HLS variant playlist
/// via a custom `smarttubehls://` URL scheme. Simulator-only.
///
/// Background: `AVURLAsset(url: file://)` + `AVURLAssetHTTPHeaderFieldsKey` hangs indefinitely
/// in `.unknown` status — AVFoundation never transitions to `.readyToPlay` on the Simulator.
/// Routing the initial playlist fetch through `AVAssetResourceLoader` avoids the `file://` code
/// path while still letting AVPlayer request CDN segment URLs (`https://`) normally.
final class HLSVariantProxy: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let playlistData: Data

    init(playlistContent: String) {
        self.playlistData = playlistContent.data(using: .utf8) ?? Data()
    }

    /// Returns a unique `smarttubehls://` URL. Each call produces a new value to prevent caching.
    static func makeProxyURL() -> URL {
        let ts = UInt64(Date().timeIntervalSince1970 * 1_000)
        guard let url = URL(string: "smarttubehls://variant/\(ts).m3u8") else {
            preconditionFailure("An HLS variant timestamp must form a valid proxy URL")
        }
        return url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            // UTI for HLS / M3U8 playlists. AVFoundation uses this to decide how to parse
            // the returned bytes. "public.m3u-playlist" is the registered UTI for .m3u8.
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(playlistData.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: playlistData)
        loadingRequest.finishLoading()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {}
}
#endif
