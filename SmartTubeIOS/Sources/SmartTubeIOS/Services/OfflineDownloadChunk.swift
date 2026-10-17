import Foundation
import SmartTubeIOSCore

/// Bounded CDN ranges avoid throttling one long YouTube response. Only complete files enter the library.
struct OfflineDownloadChunk {
    static let maximumBytes: Int64 = 10 * 1024 * 1024
    private static let copyBufferBytes = 1024 * 1024
    let start: Int64
    let end: Int64
    let total: Int64

    static func totalBytes(in request: URLRequest) -> Int64? {
        guard let url = request.url,
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "clen" })?.value,
            let total = Int64(value), total > 0
        else { return nil }
        return total
    }

    static func prepare(_ request: URLRequest, bounded: Bool = true) -> URLRequest {
        guard let total = totalBytes(in: request), total > maximumBytes else { return request }
        return ranged(request, start: 0, total: total, bounded: bounded)
    }

    private static func ranged(_ request: URLRequest, start: Int64, total: Int64, bounded: Bool) -> URLRequest {
        var next = request
        let end = bounded ? start + min(maximumBytes, total - start) - 1 : total - 1
        next.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        next.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return next
    }

    init(response: HTTPURLResponse, request: URLRequest, fileSize: Int64) throws {
        guard let total = Self.totalBytes(in: request), fileSize > 0 else { throw OfflineLibraryError.invalidFile }
        self.total = total
        if response.statusCode == 200 {
            // A server may ignore the first Range; never append a whole response to an existing prefix.
            guard request.value(forHTTPHeaderField: "Range")?.hasPrefix("bytes=0-") == true, fileSize == total else {
                throw OfflineLibraryError.invalidFile
            }
            start = 0
            end = total - 1
            return
        }
        guard response.statusCode == 206, let header = response.value(forHTTPHeaderField: "Content-Range"),
            header.hasPrefix("bytes ")
        else { throw OfflineLibraryError.invalidFile }
        let parts = header.dropFirst("bytes ".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, Int64(parts[1]) == total else { throw OfflineLibraryError.invalidFile }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
            start >= 0, end >= start, end < total, end - start + 1 == fileSize,
            request.value(forHTTPHeaderField: "Range") == "bytes=\(start)-\(end)"
        else { throw OfflineLibraryError.invalidFile }
        self.start = start
        self.end = end
    }

    func append(_ location: URL, to destination: URL) throws {
        if start == 0 {
            try FileManager.default.moveItem(at: location, to: destination)
            return
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        guard try output.seekToEnd() == UInt64(start) else { throw OfflineLibraryError.invalidFile }
        let input = try FileHandle(forReadingFrom: location)
        defer { try? input.close() }
        while let data = try input.read(upToCount: Self.copyBufferBytes), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        guard try output.offset() == UInt64(end + 1) else { throw OfflineLibraryError.invalidFile }
        try output.synchronize()
    }

    func nextRequest(after request: URLRequest, bounded: Bool = true) -> URLRequest? {
        guard end < total - 1 else { return nil }
        return Self.ranged(request, start: end + 1, total: total, bounded: bounded)
    }

    static func progress(request: URLRequest?, written: Int64, expected: Int64) -> Double? {
        guard let request, let range = request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="),
            let start = range.dropFirst("bytes=".count).split(separator: "-").first.flatMap({ Int64($0) }),
            let total = totalBytes(in: request), start >= 0, written >= 0, written <= total - start
        else { return expected > 0 ? Double(written) / Double(expected) : nil }
        return Double(start + written) / Double(total)
    }
}
