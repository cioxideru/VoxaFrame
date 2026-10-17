import AVFoundation
import SmartTubeIOSCore

/// Only settings that affect the prepared media invalidate it; translation starts on promotion.
struct ShortsStreamPreference: Equatable {
    let quality: VideoQualityPreference
    let policy: HLSPlaybackPolicy

    init(settings: AppSettings) {
        quality = settings.videoQualityPreference
        policy = .resolve(
            label: "VisionOS/HLS", isHLS: true,
            vp9Enabled: settings.vp9Enabled, h264Enabled: settings.h264Enabled)
    }
}

@MainActor
struct PreparedShort {
    let info: PlayerInfo
    let item: AVPlayerItem
    let preference: ShortsStreamPreference
    let formats: [VideoFormat]
    let variants: [Int: URL]
    let proxy: YTHLSProxyLoader?
    let warmingPlayer: AVPlayer
}

@MainActor
protocol ShortsStreamPreparing {
    func prepare(video: Video, preference: ShortsStreamPreference) async throws -> PreparedShort
}

/// Resolves one native stream. No tracking, translation, browser fallback or persistent media cache.
@MainActor
final class ShortsStreamPreparer: ShortsStreamPreparing {
    private let api: InnerTubeAPI
    private let session: URLSession

    init(api: InnerTubeAPI) {
        self.api = api
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = PlaybackTuning.playlistProbeTimeout
        configuration.timeoutIntervalForResource = PlaybackTuning.shortsPreparationSeconds
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    func prepare(video: Video, preference: ShortsStreamPreference) async throws -> PreparedShort {
        let info = try await api.fetchPlayerInfoVisionOS(videoId: video.id)
        try Task.checkCancellation()
        guard let url = info.hlsURL else { throw URLError(.unsupportedURL) }
        let policy = preference.policy
        var request = URLRequest(url: url)
        request.setValue(policy.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let manifest = String(data: data, encoding: .utf8)
        else { throw URLError(.badServerResponse) }
        let formats = policy.playableManifestFormats(
            parseHLSVideoFormats(manifest, baseURL: url.deletingLastPathComponent()))
        guard !formats.isEmpty else { throw URLError(.cannotDecodeContentData) }
        let selected = preference.quality.bestMatch(in: formats)
        let codecs = selected?.videoCodec.map { [$0.rawValue] } ?? policy.videoCodecs
        let (asset, proxy) = PlaybackQualityManager.makeHLSAsset(
            url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": policy.userAgent]],
            userAgent: policy.userAgent, maximumHeight: policy.maximumHeight, codecs: codecs, session: session)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        item.preferredForwardBufferDuration = PlaybackTuning.shortsForwardBufferSeconds
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        // Auto speculates at a moderate resolution; the user's cap is restored on promotion.
        let height = min(
            selected?.height ?? PlaybackTuning.shortsPreloadMaximumHeight,
            PlaybackTuning.shortsPreloadMaximumHeight)
        item.preferredMaximumResolution = CGSize(width: height * 4, height: height)
        item.preferredPeakBitRate = PlaybackQualityManager.peakBitRate(for: height)
        let variants = parseHLSMasterManifest(manifest, baseURL: url.deletingLastPathComponent())
            .filter { key, _ in formats.contains { $0.height == key } }
        let warmingPlayer = AVPlayer(playerItem: item)
        warmingPlayer.isMuted = true
        warmingPlayer.allowsExternalPlayback = false
        warmingPlayer.preventsDisplaySleepDuringVideoPlayback = false
        let primed = await withTaskCancellationHandler {
            for await status in item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
                guard !Task.isCancelled else { return false }
                if status == .failed { return false }
                if status == .readyToPlay, warmingPlayer.status == .readyToPlay {
                    return await warmingPlayer.preroll(atRate: 1)
                }
            }
            return false
        } onCancel: {
            warmingPlayer.cancelPendingPrerolls()
            warmingPlayer.replaceCurrentItem(with: nil)
        }
        guard primed, !Task.isCancelled else {
            warmingPlayer.replaceCurrentItem(with: nil)
            throw CancellationError()
        }
        return PreparedShort(
            info: info, item: item, preference: preference,
            formats: formats, variants: variants, proxy: proxy, warmingPlayer: warmingPlayer)
    }
}
