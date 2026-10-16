import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private final class PreloadStreamURLProtocol: URLProtocol, @unchecked Sendable {
    // The serialized suite configures before each request and reads after its completion.
    nonisolated(unsafe) static var includesHLS = true
    // One player response per serialized test; read only after the fetch completes.
    nonisolated(unsafe) static var playerClient: String?
    // Visitor and player requests run sequentially; the serialized test awaits both.
    nonisolated(unsafe) static var paths: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.paths.append(url.path)
        let body: String
        if url.path.hasSuffix("/visitor_id") {
            body = #"{"responseContext":{"visitorData":"test-visitor"}}"#
        } else if url.path.hasSuffix("/player") {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(buffer, count: count)
                }
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let context = json?["context"] as? [String: Any]
            Self.playerClient = (context?["client"] as? [String: Any])?["clientName"] as? String
            let hls = Self.includesHLS ? #""hlsManifestUrl":"https://example.test/master.m3u8","# : ""
            body = """
                {"playabilityStatus":{"status":"OK"},
                "videoDetails":{"videoId":"prefetch-test","title":"Short","author":"Test"},
                "streamingData":{\(hls)"adaptiveFormats":[
                {"itag":137,"url":"https://example.test/video?c=VISIONOS","mimeType":"video/mp4","height":1080}]}}
                """
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Playable stream prefetch", .serialized)
struct VideoPreloadStreamTests {
    @Test("Prefetch uses VISIONOS and publishes only playable HLS before metadata", arguments: [true, false])
    func prefetchPublishesPlayableStream(includesHLS: Bool) async {
        PreloadStreamURLProtocol.includesHLS = includesHLS
        PreloadStreamURLProtocol.playerClient = nil
        PreloadStreamURLProtocol.paths = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreloadStreamURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cache = VideoPreloadCache(api: InnerTubeAPI(authToken: nil, session: session))

        let fetch = await cache.getOrFetchPlayerInfo(videoId: "prefetch-test")
        let info = await fetch.value
        let cached = await cache.consume(videoId: "prefetch-test")

        #expect(PreloadStreamURLProtocol.playerClient == "VISIONOS")
        #expect(PreloadStreamURLProtocol.paths == ["/youtubei/v1/visitor_id", "/youtubei/v1/player"])
        #expect((info?.hlsURL != nil) == includesHLS)
        #expect((cached.playerInfo?.isFromVisionOSClient == true) == includesHLS)
        #expect(cached.nextInfo == nil)
        #expect(await cache.inFlightPlayerFetch(videoId: "prefetch-test") == nil)
    }
}
