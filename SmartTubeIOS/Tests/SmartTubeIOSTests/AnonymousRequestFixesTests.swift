import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - AnonymousRequestFixesTests (PLAN-0047)
//
// iPad logs and probes (2026-11-09): the WEB `/next` lists related videos as `lockupViewModel`s, which the related
// parser skipped (0 related in 265 loads), and the category browse IDs (`FEmusic_home`, `FEgaming`, `FElive_home`,
// `FEsportsau`) answer HTTP 400 with or without the token, so those sections always showed a search. The
// `FEtopics_*` IDs answer with video tiles.

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    // Every read, write and reset is protected by the static NSLock above.
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    // Guarded by the same lock: set by reset(), read once per request.
    nonisolated(unsafe) private static var responseBody = Data("{}".utf8)

    static func reset(responseBody body: Data = Data("{}".utf8)) {
        lock.withLock {
            recorded = []
            responseBody = body
        }
    }

    static func requests() -> [Recorded] { lock.withLock { recorded } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let reply = Self.lock.withLock {
            Self.recorded.append(Recorded(url: url, headers: request.allHTTPHeaderFields ?? [:], body: body))
            return Self.responseBody
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite("Anonymous request fixes", .serialized)
struct AnonymousRequestFixesTests {
    private func makeAPI(authToken: String?) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return InnerTubeAPI(authToken: authToken, session: URLSession(configuration: config))
    }

    private static func lockup(id: String, contentType: String) -> [String: Any] {
        [
            "lockupViewModel": [
                "contentId": id,
                "contentType": contentType,
                "rendererContext": [
                    "commandContext": ["onTap": ["innertubeCommand": ["watchEndpoint": ["videoId": id]]]]
                ],
                "metadata": ["lockupMetadataViewModel": ["title": ["content": "Title \(id)"]]],
            ]
        ]
    }

    @Test("related videos are read from the video lockups of the WEB /next response")
    func relatedVideosFromLockups() async throws {
        let next: [String: Any] = [
            "contents": [
                "twoColumnWatchNextResults": [
                    "secondaryResults": [
                        "secondaryResults": [
                            "results": [
                                Self.lockup(id: "related0001", contentType: "LOCKUP_CONTENT_TYPE_VIDEO"),
                                Self.lockup(id: "mixplaylist", contentType: "LOCKUP_CONTENT_TYPE_PLAYLIST"),
                            ]
                        ]
                    ]
                ]
            ]
        ]
        RecordingURLProtocol.reset(responseBody: try JSONSerialization.data(withJSONObject: next))
        let info = try await makeAPI(authToken: nil).fetchNextInfo(videoId: "current0001")
        #expect(info.relatedVideos.map(\.id) == ["related0001"])
        #expect(info.relatedVideos.first?.title == "Title related0001")
    }

    private static func tileResponse(id: String, overlayStyle: String?) -> [String: Any] {
        var header: [String: Any] = [
            "thumbnail": ["thumbnails": [["url": "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"]]]
        ]
        if let overlayStyle {
            header["thumbnailOverlays"] = [["thumbnailOverlayTimeStatusRenderer": ["style": overlayStyle]]]
        }
        let tile: [String: Any] = [
            "contentType": "TILE_CONTENT_TYPE_VIDEO",
            "onSelectCommand": ["watchEndpoint": ["videoId": id, "ustreamerConfig": "GgIIBQ=="]],
            "metadata": ["tileMetadataRenderer": ["title": ["simpleText": "Tile \(id)"]]],
            "header": ["tileHeaderRenderer": header],
        ]
        return [
            "contents": [
                "sectionListRenderer": [
                    "contents": [["itemSectionRenderer": ["contents": [["tileRenderer": tile]]]]]
                ]
            ]
        ]
    }

    @Test(
        "a live or upcoming tile with the Shorts ustreamer config is not a Short",
        arguments: [("LIVE", false), ("UPCOMING", false), (nil, true)] as [(String?, Bool)])
    func streamTilesAreNotShorts(overlayStyle: String?, expectedShort: Bool) async throws {
        let response = Self.tileResponse(id: "streamtile1", overlayStyle: overlayStyle)
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(response, title: nil)
        let video = try #require(group.videos.first)
        #expect(video.isShort == expectedShort)
    }

    @Test("a signed-in account browses a category with the TV client and its token on googleapis")
    func signedInCategoryUsesAccount() async throws {
        RecordingURLProtocol.reset()
        _ = try? await makeAPI(authToken: "token").fetchGaming(continuationToken: nil)
        let browse = try #require(RecordingURLProtocol.requests().first)
        #expect(browse.url.host == "youtubei.googleapis.com")
        #expect(browse.url.path.hasSuffix("/browse"))
        #expect(browse.headers["Authorization"] == "Bearer token")
        #expect(browse.url.query?.contains("key=") != true)
        let body = try #require(try JSONSerialization.jsonObject(with: browse.body) as? [String: Any])
        #expect(body["browseId"] as? String == "FEtopics_gaming")
    }

    @Test("without an account a category keeps the anonymous TV browse on www.youtube.com")
    func anonymousCategoryStaysOnWWW() async throws {
        RecordingURLProtocol.reset()
        _ = try? await makeAPI(authToken: nil).fetchMusic(continuationToken: nil)
        let browse = try #require(RecordingURLProtocol.requests().first)
        #expect(browse.url.host == "www.youtube.com")
        #expect(browse.headers["Authorization"] == nil)
        #expect(browse.url.query?.contains("key=") == true)
    }

    @Test("News loads the news topic page instead of searching")
    func newsBrowsesDestination() async throws {
        RecordingURLProtocol.reset()
        _ = try? await makeAPI(authToken: "token").fetchNews(continuationToken: nil)
        let browse = try #require(RecordingURLProtocol.requests().first)
        let body = try #require(try JSONSerialization.jsonObject(with: browse.body) as? [String: Any])
        #expect(body["browseId"] as? String == "FEtopics_news")
    }

    @Test("a category continuation sends the token, and a failed one ends the section without a search")
    func categoryContinuation() async throws {
        RecordingURLProtocol.reset(responseBody: Data("not json".utf8))
        let group = try await makeAPI(authToken: "token").fetchSports(continuationToken: "next-page")
        let requests = RecordingURLProtocol.requests()
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["continuation"] as? String == "next-page")
        #expect(body["browseId"] == nil)
        #expect(group.videos.isEmpty)
        #expect(group.nextPageToken == nil)
    }
}
