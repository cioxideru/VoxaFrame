import Foundation
import SmartTubeIOSCore

/// The same Yandex operations serve live playback and saved translation jobs.
protocol YandexVOTServing: Sendable {
    func translate(
        videoId: String, duration: TimeInterval, sourceLanguage: String, targetLanguage: String,
        livelyVoiceToken: String?
    ) async throws -> YandexVOTClient.Translation
    func uploadOriginalAudio(
        videoId: String, translationId: String, directURL: URL?, hlsURL: URL?, userAgent: String
    ) async throws
}

extension YandexVOTClient: YandexVOTServing {}

extension YandexVOTClient {
    static func sourceLanguage(_ code: String) -> String? {
        let base = String(code.lowercased().prefix { $0 != "-" && $0 != "_" })
        return sourceLanguages.contains(base) ? base : nil
    }
}

extension PlayerInfo {
    var voiceOverSourceLanguage: String {
        originalAudioLanguageCandidates.lazy.compactMap(YandexVOTClient.sourceLanguage).first ?? "auto"
    }
}

@MainActor
protocol OfflineTranslationFinding {
    func savedTranslation(videoID: String, language: String) async throws -> URL?
    func originalAudioLanguage(videoID: String) async throws -> String
}

extension OfflineCoordinator: OfflineTranslationFinding {
    func savedTranslation(videoID: String, language: String) async throws -> URL? {
        let library = try await store.snapshot()
        guard
            let asset = library.entries.first(where: { $0.id == videoID })?.assets.first(where: {
                $0.track.kind == .translation && $0.track.language == language
            })
        else { return nil }
        return try await store.fileURL(asset)
    }

    func originalAudioLanguage(videoID: String) async throws -> String {
        let library = try await store.snapshot()
        guard let entry = library.entries.first(where: { $0.id == videoID }) else { return "auto" }
        return entry.assets.lazy.filter { $0.track.isOriginalAudio == true }
            .compactMap(\.track.language).compactMap(YandexVOTClient.sourceLanguage).first ?? "auto"
    }
}
