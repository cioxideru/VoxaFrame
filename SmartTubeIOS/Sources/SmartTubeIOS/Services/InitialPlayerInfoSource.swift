import SmartTubeIOSCore

/// Resolves initial metadata only; the caller still owns playback and stale-video guards.
@MainActor
struct InitialPlayerInfoSource {
    enum Origin {
        case cache, inFlight, visionOS, legacy
    }

    struct Result {
        let info: PlayerInfo
        let origin: Origin

        var directVisionOSHLS: PlayerInfo? { origin == .visionOS ? info : nil }
    }

    let inFlight: (String) async -> Task<PlayerInfo?, Never>?
    let visionOS: (String) async throws -> PlayerInfo
    let legacy: (String) async throws -> PlayerInfo
    let store: (PlayerInfo, String) async -> Void

    func resolve(videoId: String, cached: PlayerInfo?) async throws -> Result {
        if let cached {
            return Result(info: cached, origin: .cache)
        }
        // This task belongs to the shared cache. Cancelling a consumer must not cancel it.
        if let task = await inFlight(videoId), let info = await task.value {
            return Result(info: info, origin: .inFlight)
        }
        if let info = try? await visionOS(videoId), info.hlsURL != nil {
            await store(info, videoId)
            return Result(info: info, origin: .visionOS)
        }
        try Task.checkCancellation()
        let info = try await legacy(videoId)
        await store(info, videoId)
        return Result(info: info, origin: .legacy)
    }
}
