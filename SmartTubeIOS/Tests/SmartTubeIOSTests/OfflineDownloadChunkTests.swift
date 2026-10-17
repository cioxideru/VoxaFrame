import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Offline bounded HTTP downloads")
struct OfflineDownloadChunkTests {
    private func request(total: Int64, start: Int64 = 0, end: Int64? = nil) throws -> URLRequest {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid/video?clen=\(total)")))
        request.setValue("Test agent", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(start)-\(end ?? total - 1)", forHTTPHeaderField: "Range")
        return request
    }
    private func response(_ range: String?, code: Int = 206) throws -> HTTPURLResponse {
        try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.invalid/video")!, statusCode: code, httpVersion: nil,
                headerFields: range.map { ["Content-Range": $0] }))
    }
    @Test func requestsAreBoundedAndPreserveIdentity() throws {
        let total = OfflineDownloadChunk.maximumBytes * 2 + 3
        let original = try request(total: total)
        let first = OfflineDownloadChunk.prepare(original)
        #expect(first.url == original.url)
        #expect(first.value(forHTTPHeaderField: "Range") == "bytes=0-\(OfflineDownloadChunk.maximumBytes - 1)")
        #expect(first.value(forHTTPHeaderField: "User-Agent") == "Test agent")
        #expect(first.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        let chunk = try OfflineDownloadChunk(
            response: response("bytes 0-\(OfflineDownloadChunk.maximumBytes - 1)/\(total)"), request: first,
            fileSize: OfflineDownloadChunk.maximumBytes)
        let second = try #require(chunk.nextRequest(after: first))
        #expect(
            second.value(forHTTPHeaderField: "Range")
                == "bytes=\(OfflineDownloadChunk.maximumBytes)-\(OfflineDownloadChunk.maximumBytes * 2 - 1)")
        var translation = URLRequest(url: try #require(URL(string: "https://example.invalid/voice.mp3")))
        translation.setValue("Test agent", forHTTPHeaderField: "User-Agent")
        #expect(OfflineDownloadChunk.prepare(translation) == translation)
    }
    @Test func backgroundContinuationKeepsOffsetAndFinishesWithoutMoreChunks() throws {
        let total = OfflineDownloadChunk.maximumBytes * 3 + 7
        let first = OfflineDownloadChunk.prepare(try request(total: total))
        let chunk = try OfflineDownloadChunk(
            response: response("bytes 0-\(OfflineDownloadChunk.maximumBytes - 1)/\(total)"),
            request: first, fileSize: OfflineDownloadChunk.maximumBytes)
        let remainder = try #require(chunk.nextRequest(after: first, bounded: false))
        #expect(remainder.url == first.url)
        #expect(remainder.value(forHTTPHeaderField: "User-Agent") == "Test agent")
        #expect(
            remainder.value(forHTTPHeaderField: "Range")
                == "bytes=\(OfflineDownloadChunk.maximumBytes)-\(total - 1)")
        let completed = try OfflineDownloadChunk(
            response: response("bytes \(OfflineDownloadChunk.maximumBytes)-\(total - 1)/\(total)"),
            request: remainder, fileSize: total - OfflineDownloadChunk.maximumBytes)
        #expect(completed.nextRequest(after: remainder) == nil)
        #expect(
            OfflineDownloadChunk.progress(
                request: remainder, written: total - OfflineDownloadChunk.maximumBytes,
                expected: total - OfflineDownloadChunk.maximumBytes) == 1)
        let backgroundStart = OfflineDownloadChunk.prepare(try request(total: total), bounded: false)
        #expect(backgroundStart.value(forHTTPHeaderField: "Range") == "bytes=0-\(total - 1)")
    }

    @Test func appendsExactRangesAndStopsAtTotal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("saved.mp4")
        let firstFile = directory.appendingPathComponent("first")
        try Data([1, 2, 3]).write(to: firstFile)
        let firstRequest = try request(total: 5, end: 2)
        let first = try OfflineDownloadChunk(response: response("bytes 0-2/5"), request: firstRequest, fileSize: 3)
        try first.append(firstFile, to: destination)
        let secondRequest = try #require(first.nextRequest(after: firstRequest))
        #expect(secondRequest.value(forHTTPHeaderField: "Range") == "bytes=3-4")
        let secondFile = directory.appendingPathComponent("second")
        try Data([4, 5]).write(to: secondFile)
        let second = try OfflineDownloadChunk(response: response("bytes 3-4/5"), request: secondRequest, fileSize: 2)
        try second.append(secondFile, to: destination)
        #expect(try Data(contentsOf: destination) == Data([1, 2, 3, 4, 5]))
        #expect(second.nextRequest(after: secondRequest) == nil)
        #expect(OfflineDownloadChunk.progress(request: secondRequest, written: 1, expected: 2) == 0.8)
        #expect(throws: OfflineLibraryError.self) { try second.append(secondFile, to: destination) }
        #expect(try Data(contentsOf: destination) == Data([1, 2, 3, 4, 5]))
    }
    @Test(arguments: [nil, "bytes 1-3/5", "bytes 0-2/6", "bytes 0-5/5", "bytes 0-2/*", "bytes 0-2/5/5"])
    func rejectsWrongResponseRange(header: String?) throws {
        #expect(throws: OfflineLibraryError.self) {
            try OfflineDownloadChunk(response: response(header), request: request(total: 5, end: 2), fileSize: 3)
        }
    }
    @Test func rejectsTruncatedChunkAndIgnoredContinuationRange() throws {
        #expect(throws: OfflineLibraryError.self) {
            try OfflineDownloadChunk(response: response("bytes 0-2/5"), request: request(total: 5, end: 2), fileSize: 2)
        }
        #expect(throws: OfflineLibraryError.self) {
            try OfflineDownloadChunk(
                response: response(nil, code: 200), request: request(total: 5, start: 3), fileSize: 5)
        }
        let whole = try OfflineDownloadChunk(
            response: response(nil, code: 200), request: request(total: 5, end: 2), fileSize: 5)
        #expect(whole.nextRequest(after: try request(total: 5)) == nil)
    }
    @Test func partialDirectReceiptCannotBecomePlayableAndBulkDeleteRemovesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineLibraryStore(directory: directory)
        let job = try await store.enqueue(
            video: Video(id: "test", title: "Test", channelTitle: "Test"),
            tracks: [OfflineTrack(id: "720", kind: .video, label: "720p")]
        ).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        let partial = directory.appendingPathComponent(job.attempt.uuidString + ".mp4")
        try Data([1, 2, 3]).write(to: partial)
        try OfflineTransferReceipt(attempt: job.attempt, url: partial, systemPackage: false, isPartial: true)
            .persist(in: directory)
        #expect(try await store.snapshot().entries[0].assets.isEmpty)
        #expect(try await store.recover(activeAttempts: [job.attempt]).jobs[0].attempt == job.attempt)
        try await store.beginRemoval(videoID: nil)
        #expect(try await store.completeRemovals().entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(try await store.pendingReceipts().isEmpty)
    }
}
