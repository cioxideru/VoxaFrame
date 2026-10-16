import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Yandex VOT client")
struct YandexVOTClientTests {

    @Test("protobuf writer output decodes back field by field")
    func protobufRoundTrip() throws {
        var nested = ProtoWriter()
        nested.int(1, 3)
        var writer = ProtoWriter()
        writer.string(3, "https://youtu.be/dQw4w9WgXcQ")
        writer.bool(5, true)
        writer.double(6, 213.5)
        writer.int(16, 300)
        writer.bool(18, false)  // default value — omitted
        writer.message(4, nested)
        let fields = try ProtoReader.decode(writer.data)
        #expect(fields[3]?.string == "https://youtu.be/dQw4w9WgXcQ")
        #expect(fields[5]?.int == 1)
        #expect(fields[6]?.double == 213.5)
        #expect(fields[16]?.int == 300)
        #expect(fields[18] == nil)
        #expect(fields[4] == .bytes(nested.data))
    }

    @Test("truncated protobuf is rejected")
    func truncatedProtobuf() {
        #expect(throws: YandexVOTClient.VOTError.self) { try ProtoReader.decode(Data([0x1A, 0x05, 0x61])) }
    }

    @Test(
        "file chunks preserve bytes and merge only the short tail",
        arguments: [0, 1, 100, 5_295_307, 5_295_308, 5_295_309, 10_590_616, 10_590_626])
    func audioChunking(length: Int) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var source = Data(repeating: 42, count: length)
        for offset in stride(from: 0, to: length, by: YandexVOTClient.audioChunkSize) {
            source[offset] = UInt8(offset / YandexVOTClient.audioChunkSize)
        }
        try source.write(to: url)
        let recorder = AudioChunkRecorder()
        try await YandexVOTClient.readAudioChunks(fileURL: url) { index, count, data in
            await recorder.append(index: index, count: count, data: data)
        }
        let size = YandexVOTClient.audioChunkSize
        let count = length == 0 ? 0 : max(1, length / size)
        let parts = await recorder.parts
        #expect(parts.count == count)
        #expect(parts.map(\.index) == Array(0..<count))
        #expect(parts.allSatisfy { $0.count == count && $0.data.count < size * 2 })
        #expect(parts.dropLast().allSatisfy { $0.data.count == size })
        #expect(parts.reduce(into: Data()) { $0.append($1.data) } == source)
    }

    @Test("upload failure or cancellation stops reading subsequent parts", arguments: [false, true])
    func stopsUpload(cancel: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: YandexVOTClient.audioChunkSize * 3).write(to: url)
        let recorder = AudioChunkRecorder()
        let task = Task {
            try await YandexVOTClient.readAudioChunks(fileURL: url) { index, count, data in
                await recorder.append(index: index, count: count, data: data)
                if cancel { withUnsafeCurrentTask { $0?.cancel() } } else { throw URLError(.cannotWriteToFile) }
            }
        }
        do {
            try await task.value
            Issue.record("Expected failure")
        } catch {
            #expect(cancel ? error is CancellationError : error is URLError)
        }
        #expect(await recorder.parts.count == 1)
    }

    @Test("request signature is hex HMAC-SHA256")
    func signatureFormat() {
        let signature = YandexVOTClient.signature(Data("body".utf8))
        #expect(signature.count == 64)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }
}

private actor AudioChunkRecorder {
    struct Part: Sendable {
        let index: Int
        let count: Int
        let data: Data
    }
    var parts: [Part] = []
    func append(index: Int, count: Int, data: Data) {
        parts.append(Part(index: index, count: count, data: data))
    }
}
