import Foundation
import os

private let audioFileLog = Logger(subsystem: appSubsystem, category: "VOTAudioFile")

/// Disk-backed source audio for one translation request. No media bytes survive the upload.
enum VOTAudioFile {
    static let rangeSize = 10_000_000
    static let parallelDownloads = 6
    static let copyBufferSize = 64 * 1024
    typealias Download = @Sendable (URLRequest, URL) async throws -> Void

    static func withAudioFile(
        directURL: URL?, hlsURL: URL?, userAgent: String,
        directory: URL = FileManager.default.temporaryDirectory,
        download: @escaping Download = download,
        upload: @Sendable (URL) async throws -> Void
    ) async throws {
        let workspace = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let audio = workspace.appendingPathComponent("audio")
        do {
            try Task.checkCancellation()
            do {
                guard let directURL else { throw YandexVOTClient.VOTError.malformedResponse }
                try await downloadDirect(directURL, to: audio, userAgent: userAgent, download: download)
            } catch {
                try Task.checkCancellation()
                guard let hlsURL else { throw error }
                audioFileLog.notice("Direct audio failed; trying HLS: \(error.localizedDescription)")
                try await downloadHLS(hlsURL, to: audio, userAgent: userAgent, download: download)
            }
            try Task.checkCancellation()
            try await upload(audio)
            try Task.checkCancellation()
        } catch {
            do { try FileManager.default.removeItem(at: workspace) } catch {
                audioFileLog.error("Audio cleanup failed: \(error.localizedDescription)")
            }
            throw error
        }
        try FileManager.default.removeItem(at: workspace)
    }

    private static func downloadDirect(
        _ url: URL, to output: URL, userAgent: String, download: Download
    ) async throws {
        try Data().write(to: output)
        let destination = try FileHandle(forWritingTo: output)
        defer { try? destination.close() }
        let part = output.deletingLastPathComponent().appendingPathComponent("range")
        var offset = 0
        while true {
            try Task.checkCancellation()
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw YandexVOTClient.VOTError.malformedResponse
            }
            components.queryItems =
                (components.queryItems ?? []).filter { $0.name != "range" }
                + [URLQueryItem(name: "range", value: "\(offset)-\(offset + rangeSize - 1)")]
            guard let rangeURL = components.url else { throw YandexVOTClient.VOTError.malformedResponse }
            try await download(request(rangeURL, userAgent: userAgent), part)
            let attributes = try FileManager.default.attributesOfItem(atPath: part.path)
            guard let size = attributes[.size] as? Int else { throw YandexVOTClient.VOTError.malformedResponse }
            // A server ignoring range must not append the full file repeatedly.
            guard size <= rangeSize else { throw YandexVOTClient.VOTError.malformedResponse }
            try append(part, to: destination, stripID3: false)
            try FileManager.default.removeItem(at: part)
            offset += size
            if size < rangeSize { break }
        }
        try destination.close()
    }

    private static func downloadHLS(
        _ url: URL, to output: URL, userAgent: String, download: @escaping Download
    ) async throws {
        let workspace = output.deletingLastPathComponent()
        let manifest = workspace.appendingPathComponent("manifest")
        try await download(request(url, userAgent: userAgent), manifest)
        // Preserve lossy playlist decoding. swiftlint:disable:next optional_data_string_conversion
        let multivariantPlaylist = String(decoding: try Data(contentsOf: manifest), as: UTF8.self)
        guard let playlistURL = hlsOriginalAudioPlaylistURL(in: multivariantPlaylist, baseURL: url) else {
            throw YandexVOTClient.VOTError.malformedResponse
        }
        try FileManager.default.removeItem(at: manifest)
        try await download(request(playlistURL, userAgent: userAgent), manifest)
        // Preserve lossy playlist decoding. swiftlint:disable:next optional_data_string_conversion
        let playlist = String(decoding: try Data(contentsOf: manifest), as: UTF8.self)
        let segments = hlsSegmentURLs(in: playlist, baseURL: playlistURL)
        try Data().write(to: output)  // Discard partial direct audio before the fallback.
        let destination = try FileHandle(forWritingTo: output)
        defer { try? destination.close() }
        // Only one window of files exists at a time, including out-of-order completions.
        for start in stride(from: 0, to: segments.count, by: parallelDownloads) {
            try Task.checkCancellation()
            let indices = start..<min(start + parallelDownloads, segments.count)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in indices {
                    let part = workspace.appendingPathComponent("segment-\(index)")
                    let request = request(segments[index], userAgent: userAgent)
                    group.addTask {
                        try Task.checkCancellation()
                        try await download(request, part)
                        try Task.checkCancellation()
                    }
                }
                for try await _ in group {}
            }
            for index in indices {
                let part = workspace.appendingPathComponent("segment-\(index)")
                try append(part, to: destination, stripID3: true)
                try FileManager.default.removeItem(at: part)
            }
        }
        try destination.close()
    }

    private static func append(_ source: URL, to destination: FileHandle, stripID3: Bool) throws {
        let file = try FileHandle(forReadingFrom: source)
        defer { try? file.close() }
        if stripID3 {
            let size = try file.seekToEnd()
            try file.seek(toOffset: 0)
            let header = try file.read(upToCount: 10) ?? Data()
            try file.seek(toOffset: min(UInt64(leadingID3TagLength(header: header)), size))
        }
        while true {
            try Task.checkCancellation()
            guard let bytes = try file.read(upToCount: copyBufferSize), !bytes.isEmpty else { break }
            try destination.write(contentsOf: bytes)
        }
        try file.close()
    }

    private static func request(_ url: URL, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func download(_ request: URLRequest, to destination: URL) async throws {
        try Task.checkCancellation()
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw YandexVOTClient.VOTError.http(status) }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}
