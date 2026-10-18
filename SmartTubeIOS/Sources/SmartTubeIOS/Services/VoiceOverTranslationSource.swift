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

@MainActor
protocol OfflineTranslationFinding {
    func savedTranslation(videoID: String, language: String) async throws -> URL?
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
}
