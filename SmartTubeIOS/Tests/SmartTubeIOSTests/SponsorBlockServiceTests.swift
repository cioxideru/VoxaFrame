import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - SponsorBlockServiceTests (#67)
//
// Covers the two pieces #67 needed: fetchSegments parsing the API's own segment
// "UUID" (previously discarded — SponsorSegment.id was always a fresh local UUID(),
// never usable to vote on a segment), and reportIncorrect building the correct
// voteOnSponsorTime request.

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    // The serialized suite installs fixtures before awaiting requests; callbacks only read them.
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]
    // URLSession callbacks write before completing each request; the serialized suite reads only after await.
    nonisolated(unsafe) static var capturedURLs: [String: URL] = [:]
    // URLSession callbacks write before completing each request; the serialized suite reads only after await.
    nonisolated(unsafe) static var capturedMethods: [String: String] = [:]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        for key in Self.responses.keys where url.contains(key) {
            Self.capturedURLs[key] = request.url
            Self.capturedMethods[key] = request.httpMethod
        }
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

@Suite("SponsorBlockService (#67)", .serialized)
struct SponsorBlockServiceTests {

    private func makeService() -> SponsorBlockService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return SponsorBlockService(session: session)
    }

    @Test("fetchSegments parses the API's own segment UUID into apiUUID")
    func fetchSegmentsParsesApiUUID() async throws {
        let responseJSON: [[String: Any]] = [
            ["segment": [10.0, 30.0], "category": "sponsor", "UUID": "abc123def456"]
        ]
        let body = try JSONSerialization.data(withJSONObject: responseJSON)
        StubURLProtocol.responses = ["skipSegments": (200, body)]
        let service = makeService()

        let segments = await service.fetchSegments(videoId: "testvid", categories: [.sponsor])

        #expect(segments.count == 1)
        #expect(segments.first?.apiUUID == "abc123def456")
        #expect(segments.first?.start == 10.0)
        #expect(segments.first?.end == 30.0)
    }

    @Test("fetchSegments leaves apiUUID nil when the API response omits it")
    func fetchSegmentsHandlesMissingUUID() async throws {
        let responseJSON: [[String: Any]] = [
            ["segment": [10.0, 30.0], "category": "sponsor"]
        ]
        let body = try JSONSerialization.data(withJSONObject: responseJSON)
        StubURLProtocol.responses = ["skipSegments": (200, body)]
        let service = makeService()

        let segments = await service.fetchSegments(videoId: "testvid", categories: [.sponsor])

        #expect(segments.count == 1)
        #expect(segments.first?.apiUUID == nil)
    }

    @Test("reportIncorrect sends a downvote (type=0) with the segment's UUID")
    func reportIncorrectSendsCorrectVote() async {
        StubURLProtocol.responses = ["voteOnSponsorTime": (200, Data("{}".utf8))]
        StubURLProtocol.capturedURLs = [:]
        StubURLProtocol.capturedMethods = [:]
        let service = makeService()

        let ok = await service.reportIncorrect(uuid: "abc123def456")

        #expect(ok)
        guard let url = StubURLProtocol.capturedURLs["voteOnSponsorTime"],
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            Issue.record("No request captured for voteOnSponsorTime")
            return
        }
        let queryItems = comps.queryItems ?? []
        #expect(queryItems.contains { $0.name == "UUID" && $0.value == "abc123def456" })
        #expect(queryItems.contains { $0.name == "type" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "userID" })
        #expect(StubURLProtocol.capturedMethods["voteOnSponsorTime"] == "POST")
    }

    @Test("reportIncorrect returns false on an HTTP error")
    func reportIncorrectReturnsFalseOnError() async {
        StubURLProtocol.responses = ["voteOnSponsorTime": (500, Data("{}".utf8))]
        let service = makeService()

        let ok = await service.reportIncorrect(uuid: "abc123def456")

        #expect(!ok)
    }

    @Test("segments: 404 means no segments; failures and wrong shapes throw instead of reading as empty")
    func segmentsDistinguishNoSegmentsFromFailure() async throws {
        let service = makeService()
        StubURLProtocol.responses = ["skipSegments": (404, Data("Not Found".utf8))]
        #expect(try await service.segments(videoId: "v", categories: [.sponsor]).isEmpty)
        StubURLProtocol.responses = ["skipSegments": (200, Data("[]".utf8))]
        #expect(try await service.segments(videoId: "v", categories: [.sponsor]).isEmpty)
        let failures: [(Int, String)] = [
            (500, "[]"), (429, "Too Many Requests"), (200, "not json"), (200, "{}"),
            (200, #"{"error":"rate limited"}"#),
        ]
        for (status, body) in failures {
            StubURLProtocol.responses = ["skipSegments": (status, Data(body.utf8))]
            await #expect(throws: (any Error).self) {
                try await service.segments(videoId: "v", categories: [.sponsor])
            }
            // The best-effort online path keeps reading these as "none".
            #expect(await service.fetchSegments(videoId: "v", categories: [.sponsor]).isEmpty)
        }
    }

    @Test("segments: malformed records of supported categories throw; unsupported categories are ignored")
    func malformedRecordsThrow() async throws {
        let service = makeService()
        let bad = [
            "[{}]", #"[{"category":"sponsor"}]"#, #"[{"category":"sponsor","segment":[1]}]"#,
            #"[{"category":"sponsor","segment":"x"}]"#, #"[{"category":"sponsor","segment":[5,2]}]"#,
        ]
        for body in bad {
            StubURLProtocol.responses = ["skipSegments": (200, Data(body.utf8))]
            await #expect(throws: (any Error).self) {
                try await service.segments(videoId: "v", categories: [.sponsor])
            }
        }
        StubURLProtocol.responses = [
            "skipSegments": (200, Data(#"[{"category":"future_kind","segment":[1,2]}]"#.utf8))
        ]
        #expect(try await service.segments(videoId: "v", categories: [.sponsor]).isEmpty)
        // A point-in-time highlight has start == end and is valid.
        StubURLProtocol.responses = [
            "skipSegments": (200, Data(#"[{"category":"poi_highlight","segment":[7,7]}]"#.utf8))
        ]
        #expect(try await service.segments(videoId: "v", categories: [.poiHighlight]).count == 1)
    }

    #if DEBUG
    @Test("UI-test fixture launches never reach the live SponsorBlock service")
    func fixtureEnvironmentMakesNoRequest() async {
        StubURLProtocol.capturedURLs = [:]
        StubURLProtocol.responses = ["skipSegments": (200, Data("[]".utf8))]
        setenv("OFFLINE_TEST_MEDIA_URL", "http://127.0.0.1:1", 1)
        defer { unsetenv("OFFLINE_TEST_MEDIA_URL") }
        let service = makeService()
        #expect(await service.fetchSegments(videoId: "v", categories: [.sponsor]).isEmpty)
        #expect(StubURLProtocol.capturedURLs["skipSegments"] == nil)
    }
    #endif
}
