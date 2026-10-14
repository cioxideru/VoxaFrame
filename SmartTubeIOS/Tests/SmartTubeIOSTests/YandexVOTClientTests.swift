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

    @Test("audio chunks are at least the vot.js minimum except a single short file")
    func audioChunking() {
        let size = YandexVOTClient.audioChunkSize
        #expect(YandexVOTClient.audioChunks(Data(count: 100)).map(\.count) == [100])
        #expect(YandexVOTClient.audioChunks(Data(count: size * 2 + 10)).map(\.count) == [size, size + 10])
        #expect(YandexVOTClient.audioChunks(Data(count: size * 2)).map(\.count) == [size, size])
    }

    @Test("request signature is hex HMAC-SHA256")
    func signatureFormat() {
        let signature = YandexVOTClient.signature(Data("body".utf8))
        #expect(signature.count == 64)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }
}
