import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("VOT audio files")
struct VOTAudioFileTests {
    private let base = URL(string: "https://audio.example/")!

    @Test("HLS keeps init and segment order, strips ID3, and bounds completed files", arguments: [7, 67])
    func hlsOrder(segmentCount: Int) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AudioDownloadFixture(base: base, segmentCount: segmentCount)
        try await VOTAudioFile.withAudioFile(
            directURL: nil, hlsURL: base, userAgent: "test-agent", directory: directory,
            download: { try await fixture.download($0, to: $1) },
            upload: { file in
                let bytes = try Data(contentsOf: file)
                #expect(bytes == Data([255] + (0..<segmentCount).map(UInt8.init)))
            })
        #expect(await fixture.segmentRequests == segmentCount + 1)
        #expect(await fixture.peakFiles <= VOTAudioFile.parallelDownloads)
        #expect(await fixture.peakActive <= VOTAudioFile.parallelDownloads)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("direct ranges append bytes with offsets and remove the file after success")
    func directRanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AudioDownloadFixture(base: base, segmentCount: 0)
        try await VOTAudioFile.withAudioFile(
            directURL: base.appendingPathComponent("direct"), hlsURL: nil,
            userAgent: "test-agent", directory: directory,
            download: { try await fixture.download($0, to: $1) },
            upload: { file in
                let data = try Data(contentsOf: file)
                #expect(data.count == VOTAudioFile.rangeSize + 3)
                #expect(data.prefix(VOTAudioFile.rangeSize) == Data(repeating: 42, count: VOTAudioFile.rangeSize))
                #expect(data.suffix(3) == Data([1, 2, 3]))
            })
        #expect(await fixture.ranges == ["0-9999999", "10000000-19999999"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("HLS fallback discards partially downloaded direct audio")
    func fallback() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AudioDownloadFixture(base: base, segmentCount: 2, failure: .directSecondRange)
        try await VOTAudioFile.withAudioFile(
            directURL: base.appendingPathComponent("direct"), hlsURL: base,
            userAgent: "test-agent", directory: directory,
            download: { try await fixture.download($0, to: $1) },
            upload: { file in
                let bytes = try Data(contentsOf: file)
                #expect(bytes == Data([255, 0, 1]))
            })
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("a failed HLS segment cancels the window and removes all partial files")
    func segmentFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AudioDownloadFixture(base: base, segmentCount: 67, failure: .segment)
        await #expect(throws: URLError.self) {
            try await VOTAudioFile.withAudioFile(
                directURL: nil, hlsURL: base, userAgent: "test-agent", directory: directory,
                download: { try await fixture.download($0, to: $1) },
                upload: { _ in Issue.record("Must not upload incomplete HLS audio") })
        }
        #expect(await fixture.segmentRequests <= VOTAudioFile.parallelDownloads)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("oversized range response is rejected without requesting another range")
    func ignoredRange() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = AudioDownloadFixture(base: base, segmentCount: 0, failure: .oversized)
        await #expect(throws: YandexVOTClient.VOTError.self) {
            try await VOTAudioFile.withAudioFile(
                directURL: base.appendingPathComponent("direct"), hlsURL: nil,
                userAgent: "test-agent", directory: directory,
                download: { try await fixture.download($0, to: $1) },
                upload: { _ in Issue.record("Must not upload an ignored range") })
        }
        #expect(await fixture.ranges.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("partial files are removed on download failure and cancellation", arguments: [false, true])
    func downloadFailure(cancel: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = Task {
            try await VOTAudioFile.withAudioFile(
                directURL: base, hlsURL: base, userAgent: "test-agent", directory: directory,
                download: { _, file in
                    try Data([1, 2]).write(to: file)
                    if cancel {
                        withUnsafeCurrentTask { $0?.cancel() }
                        throw CancellationError()
                    }
                    throw URLError(.networkConnectionLost)
                },
                upload: { _ in Issue.record("Must not upload after download failure") })
        }
        do {
            try await task.value
            Issue.record("Expected failure")
        } catch {
            #expect(cancel ? error is CancellationError : error is URLError)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("file is removed after upload error and cancellation", arguments: [false, true])
    func uploadFailure(cancel: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = Task {
            try await VOTAudioFile.withAudioFile(
                directURL: base, hlsURL: nil, userAgent: "test-agent", directory: directory,
                download: { _, file in try Data([1, 2]).write(to: file) },
                upload: { _ in
                    if cancel { withUnsafeCurrentTask { $0?.cancel() } } else { throw URLError(.networkConnectionLost) }
                })
        }
        do {
            try await task.value
            Issue.record("Expected failure")
        } catch {
            #expect(cancel ? error is CancellationError : error is URLError)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor AudioDownloadFixture {
    enum Failure { case directSecondRange, oversized, segment }
    let base: URL
    let segmentCount: Int
    let failure: Failure?
    var ranges: [String] = []
    var segmentRequests = 0
    var active = 0
    var peakActive = 0
    var peakFiles = 0

    init(base: URL, segmentCount: Int, failure: Failure? = nil) {
        self.base = base
        self.segmentCount = segmentCount
        self.failure = failure
    }

    func download(_ request: URLRequest, to file: URL) async throws {
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "test-agent")
        let url = try #require(request.url)
        if url.lastPathComponent == "direct" {
            let range = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "range"
            }?.value
            ranges.append(try #require(range))
            guard ranges.count <= 2 else { throw URLError(.badServerResponse) }
            if ranges.count == 2, failure == .directSecondRange { throw URLError(.networkConnectionLost) }
            let data =
                ranges.count == 1
                ? Data(repeating: 42, count: VOTAudioFile.rangeSize + (failure == .oversized ? 1 : 0))
                : Data([1, 2, 3])
            try data.write(to: file)
        } else if url == base {
            try Data(
                "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"original\",DEFAULT=YES,URI=\"playlist\"\n"
                    .utf8
            ).write(to: file)
        } else if url.lastPathComponent == "playlist" {
            let lines = ["#EXTM3U", "#EXT-X-MAP:URI=\"init\""] + (0..<segmentCount).map { "part-\($0)" }
            try Data(lines.joined(separator: "\n").utf8).write(to: file)
        } else {
            active += 1
            peakActive = max(peakActive, active)
            defer { active -= 1 }
            await Task.yield()
            try Task.checkCancellation()
            let data: Data
            if url.lastPathComponent == "init" {
                data = Data([255])
            } else {
                let index = try #require(Int(url.lastPathComponent.dropFirst(5)))
                data = Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 2, 99, 99, UInt8(index)])
            }
            try data.write(to: file)
            if failure == .segment { throw URLError(.networkConnectionLost) }
            segmentRequests += 1
            let files = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            peakFiles = max(peakFiles, files.filter { $0.hasPrefix("segment-") }.count)
        }
    }
}
