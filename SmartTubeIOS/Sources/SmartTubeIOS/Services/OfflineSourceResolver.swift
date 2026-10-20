import Foundation
import SmartTubeIOSCore
import os

private let offlineSourceLog = Logger(subsystem: appSubsystem, category: "OfflineSource")

struct OfflineSource: Sendable {
    let track: OfflineTrack
    let url: URL
    let userAgent: String
    var hlsVariantURL: URL?
}

struct OfflineResolutionDeferred: Error { let delay: TimeInterval }

struct OfflineTranslationUploadError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Yandex did not accept the source audio. Retry the translation download.", bundle: .module)
    }
}

struct OfflineTranslationError: LocalizedError {
    let message: String?
    var errorDescription: String? {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return message }
        return String(localized: "Yandex couldn't translate this video. Try again later.", bundle: .module)
    }
}

protocol OfflineResolving: Sendable {
    func catalog(video: Video) async throws -> [OfflineSource]
    func resolve(video: Video, track: OfflineTrack, attempt: UUID) async throws -> OfflineSource
}

actor OfflineSourceResolver: OfflineResolving {
    let api: InnerTubeAPI
    let vot: any YandexVOTServing
    private struct AudioUpload {
        let translationID: String
        var attempts = 0
        var polls = 0
    }
    private var uploadedTranslations: [UUID: AudioUpload] = [:]
    init(api: InnerTubeAPI, vot: any YandexVOTServing = YandexVOTClient()) {
        self.api = api
        self.vot = vot
    }

    func catalog(video: Video) async throws -> [OfflineSource] {
        var sources: [OfflineSource] = []
        do {
            let info = try await api.fetchPlayerInfoVisionOS(videoId: video.id)
            let agent = InnerTubeClients.VisionOS.userAgent
            sources += Self.directSources(info, userAgent: agent)
            #if os(iOS)
            if let playlistURL = info.hlsURL, playlistURL.scheme == "https" {
                var request = URLRequest(url: playlistURL)
                request.setValue(agent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                    let manifest = String(data: data, encoding: .utf8), manifest.contains("#EXTM3U")
                else {
                    throw OfflineDownloadTransport.unavailable(
                        "HLS master status=\((response as? HTTPURLResponse)?.statusCode ?? 0) videoId=\(video.id)")
                }
                sources += offlineHLSVariants(manifest, baseURL: playlistURL, duration: info.video.duration).map {
                    OfflineSource(track: $0.0, url: playlistURL, userAgent: agent, hlsVariantURL: $0.1)
                }
            }
            #endif
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            let failure = error as NSError
            offlineSourceLog.error(
                "VisionOS catalog failed videoId=\(video.id, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code)"
            )
        }
        do {
            let direct = try await api.fetchPlayerInfoAndroid(videoId: video.id)
            let alternatives = Self.directSources(direct, userAgent: InnerTubeClients.Android.userAgent)
            sources += alternatives.filter { candidate in !sources.contains { $0.track.id == candidate.track.id } }
        } catch {
            try Task.checkCancellation()
            if sources.isEmpty || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
        }
        guard !sources.isEmpty else { throw OfflineDownloadTransport.unavailable("empty catalog videoId=\(video.id)") }
        return sources
    }

    func resolve(video: Video, track: OfflineTrack, attempt: UUID) async throws -> OfflineSource {
        let started = Date()
        defer {
            offlineSourceLog.notice(
                "Source attempt videoId=\(video.id, privacy: .public) kind=\(track.kind.rawValue, privacy: .public) elapsedMs=\(Int(Date().timeIntervalSince(started) * 1_000))"
            )
        }
        if track.kind == .translation {
            do {
                return try await translation(video: video, track: track, attempt: attempt)
            } catch {
                if !(error is OfflineResolutionDeferred) { uploadedTranslations[attempt] = nil }
                throw error
            }
        }
        let sources = try await catalog(video: video)
        if track.id == OfflineTrack.automatic.id {
            guard
                let source = sources.first(where: { $0.track.hasAudio })
                    ?? sources.first(where: { $0.track.kind == .video })
            else {
                throw OfflineDownloadTransport.unavailable(
                    "no automatic source among \(sources.count) videoId=\(video.id)")
            }
            return source
        }
        guard let source = sources.first(where: { $0.track.id == track.id }) else {
            let offered = sources.filter { $0.track.kind == track.kind }.map(\.track.id)
            throw OfflineDownloadTransport.unavailable("track=\(track.id) is not in the refreshed catalog \(offered)")
        }
        return source
    }

    private func translation(video: Video, track: OfflineTrack, attempt: UUID) async throws -> OfflineSource {
        try Task.checkCancellation()
        guard let language = track.language, YandexVOTClient.targetLanguages.contains(language) else {
            throw OfflineDownloadTransport.unavailable("translation language=\(track.language ?? "-") is not supported")
        }
        let info = try await api.fetchPlayerInfoVisionOS(videoId: video.id)
        try Task.checkCancellation()
        let duration = video.duration.flatMap { $0 > 0 ? $0 : nil } ?? info.video.duration ?? 0
        guard duration > 0, duration <= YandexVOTClient.maximumDuration else {
            throw OfflineDownloadTransport.unavailable(
                "translation duration=\(Int(duration))s is out of range videoId=\(video.id)")
        }
        let result = try await vot.translate(
            videoId: video.id, duration: duration, sourceLanguage: info.voiceOverSourceLanguage,
            targetLanguage: language, livelyVoiceToken: nil)
        try Task.checkCancellation()
        switch result.status {
        case .finished:
            uploadedTranslations[attempt] = nil
            guard let url = result.audioURL, url.scheme == "https" else {
                throw OfflineDownloadTransport.unavailable(
                    "translation finished without an HTTPS audio URL videoId=\(video.id)")
            }
            return OfflineSource(track: track, url: url, userAgent: InnerTubeClients.iOS.userAgent)
        case .failed, .sessionRequired:
            offlineSourceLog.error(
                "Translation refused videoId=\(video.id, privacy: .public) status=\(result.status.rawValue) message=\(result.message ?? "", privacy: .private)"
            )
            throw OfflineTranslationError(message: result.message)
        case .audioRequested:
            guard !result.translationId.isEmpty else { throw YandexVOTClient.VOTError.malformedResponse }
            var upload = uploadedTranslations[attempt] ?? AudioUpload(translationID: result.translationId)
            if upload.translationID != result.translationId {
                upload = AudioUpload(translationID: result.translationId)
            }
            if upload.attempts > 0 { upload.polls += 1 }
            if upload.attempts == 0 || upload.polls >= PlaybackTuning.offlineTranslationReuploadPolls {
                guard upload.attempts < PlaybackTuning.offlineTranslationUploadLimit else {
                    throw OfflineTranslationUploadError()
                }
                try await vot.uploadOriginalAudio(
                    videoId: video.id, translationId: result.translationId,
                    directURL: info.bestAdaptiveAudioURL, hlsURL: info.hlsURL,
                    userAgent: InnerTubeClients.VisionOS.userAgent)
                try Task.checkCancellation()
                upload.attempts += 1
                upload.polls = 0
            }
            uploadedTranslations[attempt] = upload
        default: break  // PART_CONTENT is not a complete offline track.
        }
        throw OfflineResolutionDeferred(delay: TimeInterval(min(30, max(5, result.remainingTime ?? 5))))
    }

    private static func query(_ name: String, url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    static func directSources(_ info: PlayerInfo, userAgent: String) -> [OfflineSource] {
        info.formats.compactMap { format in
            guard let url = format.url, url.scheme == "https", !url.absoluteString.contains("c=TVHTML5"),
                format.mimeType.hasPrefix("video/mp4") || format.mimeType.hasPrefix("audio/mp4")
            else { return nil }
            let audio = format.mimeType.hasPrefix("audio/")
            let language = format.audioLanguage
            let itag = query("itag", url: url) ?? "\(format.height)-\(format.fps)-\(format.codecShortLabel)"
            var track = OfflineTrack(
                id: "direct-\(itag)-\(format.audioTrackID ?? "original")", kind: audio ? .audio : .video,
                label: audio
                    ? "\(language ?? "Unknown language") · \(format.isOriginalAudio == true ? "Original" : format.isOriginalAudio == false ? "Dubbed" : "Audio") · \(format.mimeType.contains("mp4a") ? "AAC" : "MP4 audio") \(format.bitrate.map { "\($0 / 1000) kbps" } ?? "")"
                    : "\(format.qualityLabel) · \(format.codecShortLabel)", language: language,
                hasAudio: !audio && format.mimeType.contains(","))
            track.isOriginalAudio = format.isOriginalAudio
            if !audio {
                track.videoSize = OfflineVideoSize(width: format.width, height: format.height)
                track.fps = format.fps
                track.codec = format.videoCodec
                track.audioLabel = "Included audio"
            }
            track.estimatedBytes =
                query("clen", url: url).flatMap(Int64.init).flatMap { $0 > 0 ? $0 : nil }

            return OfflineSource(track: track, url: url, userAgent: userAgent)
        }
    }
}
