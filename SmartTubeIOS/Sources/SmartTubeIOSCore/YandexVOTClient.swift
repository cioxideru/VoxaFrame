import CryptoKit
import Foundation
import os

private let votLog = Logger(subsystem: appSubsystem, category: "YandexVOT")

// MARK: - YandexVOTClient
//
// Client for Yandex's (unofficial, Yandex Browser) video voice-over translation API.
// Protocol mirrored from the MIT-licensed FOSWLY/vot.js (packages/core/src/providers/yandex.ts):
// protobuf bodies, HMAC-SHA256 request signing with the Yandex Browser key, and a
// per-module session. The result is one MP3 covering the whole video timeline.
//
// Flow: translate() → WAITING (poll after remainingTime) / AUDIO_REQUESTED (upload the
// original audio with uploadAudio(), then poll) → PART_CONTENT (first ~10 min ready,
// keep polling) → FINISHED.

public actor YandexVOTClient {

    public enum Status: Int, Sendable {
        case failed = 0
        case finished = 1
        case waiting = 2
        case longWaiting = 3
        case partContent = 5
        case audioRequested = 6
        case sessionRequired = 7
    }

    public struct Translation: Sendable {
        public let status: Status
        public let audioURL: URL?
        /// Seconds until the translation (or its remainder) is ready.
        public let remainingTime: Int?
        public let translationId: String
        public let isLivelyVoice: Bool
        public let message: String?
    }

    public enum VOTError: Error, Sendable {
        case http(Int)
        case malformedResponse
        case unknownStatus(Int)
    }

    /// Languages Yandex can voice the translation in.
    public static let targetLanguages: Set<String> = ["ru", "en", "kk"]
    /// Source languages Yandex recognises; anything else is sent as "auto".
    public static let sourceLanguages: Set<String> = ["ru", "en", "zh", "ko", "ar", "fr", "it", "es", "de", "ja"]
    /// Yandex refuses videos longer than this.
    public static let maximumDuration: TimeInterval = 4 * 3600
    /// Upload chunk size used by vot.js (`config.minChunkSize`); every chunk but the last is at least this big.
    static let audioChunkSize = 5_295_308

    // Yandex Browser identity — vot.js packages/shared/src/data/config.ts. Yandex bumps
    // componentVersion every few weeks but has kept accepting older values.
    private static let host = "https://api.browser.yandex.ru"
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 YaBrowser/26.8.0.0 Safari/537.36"
    private static let componentVersion = "26.10.0.1796"
    private static let hmacKey = SymmetricKey(data: Data("bt8xH3VOlb4mqf0nqAibnDOoiPlXsisf".utf8))

    private let session: URLSession
    private var yandexSession: (uuid: String, secretKey: String, expiresAt: Date)?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Requests (or polls) the translation of a YouTube video.
    /// - Parameter oauthToken: Yandex account token; sent only together with the lively-voice flag.
    public func translate(
        videoId: String, duration: TimeInterval, sourceLanguage: String, targetLanguage: String,
        livelyVoiceToken oauthToken: String?
    ) async throws -> Translation {
        var body = ProtoWriter()
        body.string(3, Self.videoURL(videoId))
        body.bool(5, true)  // firstRequest — vot.js always sends true; false is rejected with HTTP 400
        body.double(6, duration)
        body.bool(7, true)
        body.string(8, sourceLanguage)
        body.string(14, targetLanguage)
        body.bool(15, true)
        body.int(16, 2)  // configVersion
        body.bool(18, oauthToken != nil)  // useLivelyVoice
        var extraHeaders: [String: String] = [:]
        if let oauthToken { extraHeaders["Authorization"] = "OAuth \(oauthToken)" }

        let fields = try await signedRequest(
            path: "/video-translation/translate", method: "POST", body: body.data, extraHeaders: extraHeaders)
        // proto3 omits default values, so a missing status is FAILED (0).
        let rawStatus = fields[4]?.int ?? Status.failed.rawValue
        guard let status = Status(rawValue: rawStatus) else { throw VOTError.unknownStatus(rawStatus) }
        let translation = Translation(
            status: status,
            audioURL: fields[1]?.string.flatMap(URL.init(string:)),
            remainingTime: fields[5]?.int,
            translationId: fields[7]?.string ?? "",
            isLivelyVoice: (fields[10]?.int ?? 0) != 0,
            message: fields[9]?.string
        )
        votLog.notice(
            "translate \(videoId, privacy: .public) \(sourceLanguage, privacy: .public)→\(targetLanguage, privacy: .public) status=\(rawStatus) remaining=\(translation.remainingTime ?? -1) lively=\(translation.isLivelyVoice)"
        )
        return translation
    }

    /// Uploads the original audio track after an AUDIO_REQUESTED status, in vot.js-sized chunks.
    public func uploadAudio(videoId: String, translationId: String, audio: Data) async throws {
        let chunks = Self.audioChunks(audio)
        let fileId = "random-web_abr-\(UUID().uuidString.lowercased())"
        for (index, chunk) in chunks.enumerated() {
            var buffer = ProtoWriter()
            buffer.int(1, index)  // chunkId
            buffer.bytes(2, chunk)
            var partial = ProtoWriter()
            partial.message(1, buffer)
            partial.int(2, chunks.count)  // audioPartsLength
            partial.string(3, fileId)
            partial.int(4, 1)  // version
            var body = ProtoWriter()
            body.string(1, translationId)
            body.string(2, Self.videoURL(videoId))
            body.message(4, partial)
            _ = try await signedRequest(path: "/video-translation/audio", method: "PUT", body: body.data)
        }
        votLog.notice(
            "uploaded \(audio.count) bytes of audio in \(chunks.count) chunk(s) for \(videoId, privacy: .public)")
    }

    // MARK: - Internals

    static func videoURL(_ videoId: String) -> String { "https://youtu.be/\(videoId)" }

    /// Splits `audio` into chunks of at least `audioChunkSize` bytes (a short tail joins the previous chunk).
    static func audioChunks(_ audio: Data) -> [Data] {
        var chunks = stride(from: 0, to: audio.count, by: audioChunkSize).map {
            audio.subdata(in: $0..<min($0 + audioChunkSize, audio.count))
        }
        if chunks.count > 1, let tail = chunks.last, tail.count < audioChunkSize {
            chunks.removeLast()
            chunks[chunks.count - 1].append(tail)
        }
        return chunks
    }

    static func signature(_ data: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: data, using: hmacKey).map { String(format: "%02x", $0) }.joined()
    }

    private func currentSession() async throws -> (uuid: String, secretKey: String) {
        if let s = yandexSession, s.expiresAt > Date() { return (s.uuid, s.secretKey) }
        let uuid = (0..<32).map { _ in String("0123456789ABCDEF".randomElement()!) }.joined()
        var body = ProtoWriter()
        body.string(1, uuid)
        body.string(2, "video-translation")
        let fields = try await send(
            path: "/session/create", method: "POST", body: body.data,
            headers: ["Vtrans-Signature": Self.signature(body.data)])
        guard let secretKey = fields[1]?.string else { throw VOTError.malformedResponse }
        let expires = TimeInterval(fields[2]?.int ?? 3600)
        yandexSession = (uuid, secretKey, Date().addingTimeInterval(expires - 60))
        return (uuid, secretKey)
    }

    private func signedRequest(
        path: String, method: String, body: Data, extraHeaders: [String: String] = [:]
    ) async throws -> [Int: ProtoValue] {
        let (uuid, secretKey) = try await currentSession()
        let token = "\(uuid):\(path):\(Self.componentVersion)"
        var headers = extraHeaders
        headers["Vtrans-Signature"] = Self.signature(body)
        headers["Sec-Vtrans-Sk"] = secretKey
        headers["Sec-Vtrans-Token"] = "\(Self.signature(Data(token.utf8))):\(token)"
        return try await send(path: path, method: method, body: body, headers: headers)
    }

    private func send(
        path: String, method: String, body: Data, headers: [String: String]
    ) async throws
        -> [Int: ProtoValue]
    {
        var request = URLRequest(url: URL(string: Self.host + path)!, timeoutInterval: 60)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            votLog.error("\(method, privacy: .public) \(path, privacy: .public) HTTP \(status)")
            throw VOTError.http(status)
        }
        return try ProtoReader.decode(data)
    }
}

// MARK: - Minimal protobuf wire format

enum ProtoValue: Equatable, Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case bytes(Data)

    var int: Int? {
        if case .varint(let v) = self { return Int(truncatingIfNeeded: v) }
        return nil
    }
    var string: String? {
        if case .bytes(let d) = self { return String(data: d, encoding: .utf8) }
        return nil
    }
    var double: Double? {
        if case .fixed64(let v) = self { return Double(bitPattern: v) }
        return nil
    }
}

/// Writes proto3 fields; default values (false/0/"") are omitted like protobufjs does.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func bool(_ field: Int, _ value: Bool) { if value { int(field, 1) } }
    mutating func int(_ field: Int, _ value: Int) {
        guard value != 0 else { return }
        key(field, wireType: 0)
        varint(UInt64(bitPattern: Int64(value)))
    }
    mutating func double(_ field: Int, _ value: Double) {
        key(field, wireType: 1)
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }
    mutating func string(_ field: Int, _ value: String) {
        guard !value.isEmpty else { return }
        bytes(field, Data(value.utf8))
    }
    mutating func bytes(_ field: Int, _ value: Data) {
        key(field, wireType: 2)
        varint(UInt64(value.count))
        data.append(value)
    }
    mutating func message(_ field: Int, _ value: ProtoWriter) { bytes(field, value.data) }

    private mutating func key(_ field: Int, wireType: UInt64) { varint(UInt64(field) << 3 | wireType) }
    private mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }
}

/// Decodes the top level of a protobuf message into `[fieldNumber: lastValue]`.
enum ProtoReader {
    static func decode(_ data: Data) throws -> [Int: ProtoValue] {
        let bytes = [UInt8](data)
        var fields: [Int: ProtoValue] = [:]
        var i = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard i < bytes.count, shift < 64 else { throw YandexVOTClient.VOTError.malformedResponse }
                let b = bytes[i]
                i += 1
                result |= UInt64(b & 0x7F) << shift
                if b < 0x80 { return result }
                shift += 7
            }
        }
        func fixed(_ count: Int) throws -> UInt64 {
            guard i + count <= bytes.count else { throw YandexVOTClient.VOTError.malformedResponse }
            let value = bytes[i..<i + count].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            i += count
            return value
        }
        while i < bytes.count {
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: fields[field] = .varint(try varint())
            case 1: fields[field] = .fixed64(try fixed(8))
            case 5: fields[field] = .fixed32(UInt32(try fixed(4)))
            case 2:
                guard let length = Int(exactly: try varint()), length <= bytes.count - i else {
                    throw YandexVOTClient.VOTError.malformedResponse
                }
                fields[field] = .bytes(Data(bytes[i..<i + length]))
                i += length
            default: throw YandexVOTClient.VOTError.malformedResponse
            }
        }
        return fields
    }
}
