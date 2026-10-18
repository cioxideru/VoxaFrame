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
                    throw OfflineLibraryError.unavailable
                }
                sources += offlineHLSVariants(manifest, baseURL: playlistURL, duration: info.video.duration).map {
                    OfflineSource(track: $0.0, url: playlistURL, userAgent: agent, hlsVariantURL: $0.1)
                }
            }
            #endif
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
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
        guard !sources.isEmpty else { throw OfflineLibraryError.unavailable }
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
            else { throw OfflineLibraryError.unavailable }
            return source
        }
        guard let source = sources.first(where: { $0.track.id == track.id }) else {
            throw OfflineLibraryError.unavailable
        }
        return source
    }

    private func translation(video: Video, track: OfflineTrack, attempt: UUID) async throws -> OfflineSource {
        try Task.checkCancellation()
        guard let language = track.language, YandexVOTClient.targetLanguages.contains(language) else {
            throw OfflineLibraryError.unavailable
        }
        let duration: TimeInterval
        if let known = video.duration, known > 0 {
            duration = known
        } else {
            duration = try await api.fetchPlayerInfoVisionOS(videoId: video.id).video.duration ?? 0
        }
        guard duration > 0, duration <= YandexVOTClient.maximumDuration else { throw OfflineLibraryError.unavailable }
        let result = try await vot.translate(
            videoId: video.id, duration: duration, sourceLanguage: "auto",
            targetLanguage: language, livelyVoiceToken: nil)
        try Task.checkCancellation()
        switch result.status {
        case .finished:
            uploadedTranslations[attempt] = nil
            guard let url = result.audioURL, url.scheme == "https" else { throw OfflineLibraryError.unavailable }
            return OfflineSource(track: track, url: url, userAgent: InnerTubeClients.iOS.userAgent)
        case .failed, .sessionRequired:
            throw OfflineLibraryError.unavailable
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
                let info = try await api.fetchPlayerInfoVisionOS(videoId: video.id)
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
