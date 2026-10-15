#if !os(tvOS)
import Foundation
import Testing

@testable import SmartTubeIOSCore
@testable import SmartTubeIOS

// MARK: - TOSPlayerChaptersTests (#10, closes #68/#105)
//
// fetchRelatedVideos() already does the one fetchNextInfo round trip TOSPlayerViewModel
// needs for swipe navigation; NextInfo also carries chapters (parsed by
// InnerTubeAPI+Social.swift's parseChapters from the same /next response), so
// fetchRelatedVideos() was extended to also stash them on vm.chapters — no extra
// network cost. This proves that wiring, not the parser itself (see
// InnerTubeAPI+VideoRenderers.swift's own chapter-parsing tests for that).

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let match = Self.responses.filter { url.contains($0.key) }.max(by: { $0.key.count < $1.key.count })
        let (statusCode, body) = match.map { ($0.value.statusCode, $0.value.body) } ?? (200, Data("{}".utf8))
        guard let requestURL = request.url,
            let httpResponse = HTTPURLResponse(
                url: requestURL, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("TOS player chapters wiring (#10)", .serialized)
@MainActor
struct TOSPlayerChaptersTests {

    private func nextResponseWithChapters() throws -> Data {
        let json: [String: Any] = [
            "engagementPanels": [
                [
                    "engagementPanelSectionListRenderer": [
                        "content": [
                            "macroMarkersListRenderer": [
                                "contents": [
                                    [
                                        "macroMarkersListItemRenderer": [
                                            "title": ["simpleText": "Intro"],
                                            "onTap": ["watchEndpoint": ["startTimeSeconds": 0]],
                                        ]
                                    ],
                                    [
                                        "macroMarkersListItemRenderer": [
                                            "title": ["simpleText": "The main part"],
                                            "onTap": ["watchEndpoint": ["startTimeSeconds": 90]],
                                        ]
                                    ],
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("fetchRelatedVideos populates vm.chapters from the same /next response")
    func fetchRelatedVideosPopulatesChapters() async throws {
        StubURLProtocol.responses = ["next": (200, try nextResponseWithChapters())]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = InnerTubeAPI(authToken: nil, session: session)

        let vm = TOSPlayerViewModel(videoId: "test_chapters_video", api: api)
        await vm.fetchRelatedVideos()

        #expect(vm.chapters.count == 2)
        #expect(vm.chapters.first?.title == "Intro")
        #expect(vm.chapters.first?.startTime == 0)
        #expect(vm.chapters.last?.title == "The main part")
        #expect(vm.chapters.last?.startTime == 90)
    }

    @Test("vm.chapters is empty by default (before fetchRelatedVideos completes)")
    func chaptersEmptyByDefault() {
        let vm = TOSPlayerViewModel(videoId: "test_chapters_default", api: InnerTubeAPI())
        #expect(vm.chapters.isEmpty)
    }
}
#endif
