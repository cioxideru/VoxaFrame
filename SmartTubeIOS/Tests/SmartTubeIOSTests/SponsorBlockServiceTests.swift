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
}
