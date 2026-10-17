#if DEBUG
import Foundation
import SmartTubeIOSCore

/// Only the simulator fixture may use HTTP; production downloads remain HTTPS-only.
enum OfflineUITestFixture {
    static var baseURL: URL? {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting"),
            let raw = ProcessInfo.processInfo.environment["OFFLINE_TEST_MEDIA_URL"],
            let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1"
        else { return nil }
        return url
    }

    static func allows(_ url: URL) -> Bool {
        guard let baseURL else { return false }
        return url.scheme == baseURL.scheme && url.host == baseURL.host && url.port == baseURL.port
    }

    static func resolver() -> (any OfflineResolving)? {
        baseURL.map { Resolver(baseURL: $0) }
    }

    @MainActor static func status(_ vm: PlaybackViewModel) -> String {
        "local=\(vm.currentVideo?.isDownloaded == true) time=\(vm.currentTime) "
            + "rate=\(vm.player.rate) voiceRate=\(vm.voiceOver.testPlaybackRate) "
            + "voiceTime=\(vm.voiceOver.testPlaybackTime) error=\(vm.error != nil)"
    }

    private struct Resolver: OfflineResolving {
        let baseURL: URL

        func catalog(video: Video) throws -> [OfflineSource] {
            [
                source(
                    video, track: .init(id: "fixture-360", kind: .video, label: "360p · H.264", hasAudio: true),
                    file: "video.mp4"),
                source(
                    video, track: .init(id: "fixture-720", kind: .video, label: "720p · H.264", hasAudio: true),
                    file: "video720.mp4"),
                source(
                    video, track: .init(id: "fixture-hls", kind: .hls, label: "HLS · H.264 + AAC", hasAudio: true),
                    file: "master.m3u8"),
                source(
                    video, track: .init(id: "fixture-audio", kind: .audio, label: "en · Original", language: "en"),
                    file: "original.m4a"),
            ] + [external(video, language: "en"), external(video, language: "ru")]
        }

        private func external(_ video: Video, language: String) -> OfflineSource {
            let name = language == "ru" ? "Russian" : "English"
            var track = OfflineTrack(
                id: "fixture-hls-\(language)", kind: .hls,
                label: "720p · H.264 · \(name)", language: language, hasAudio: true)
            track.videoSize = OfflineVideoSize(width: 1280, height: 720)
            track.codec = .h264
            track.fps = 30
            track.hlsPeakBitRate = 2_000_000
            track.hlsAudioName = name
            track.audioLabel = name
            var result = source(video, track: track, file: "external-master.m3u8")
            result.hlsVariantURL = baseURL.appendingPathComponent(video.id).appendingPathComponent(
                "video720-stream.m3u8")
            return result
        }

        func resolve(video: Video, track: OfflineTrack) throws -> OfflineSource {
            if track.kind == .translation { return source(video, track: track, file: "voice.mp3") }
            let sources = try catalog(video: video)
            guard
                let result = sources.first(where: { track.id == OfflineTrack.automatic.id || $0.track.id == track.id })
            else {
                throw OfflineLibraryError.unavailable
            }
            return result
        }

        private func source(_ video: Video, track: OfflineTrack, file: String) -> OfflineSource {
            OfflineSource(
                track: track, url: baseURL.appendingPathComponent(video.id).appendingPathComponent(file),
                userAgent: "Offline UI fixture")
        }
    }
}
#endif
