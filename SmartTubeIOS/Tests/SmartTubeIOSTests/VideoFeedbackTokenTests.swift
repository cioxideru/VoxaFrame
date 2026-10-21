import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - VideoFeedbackTokenTests (PLAN-0039)
//
// Card feedback hides a video or blocks a channel only after YouTube got the request, so
// `sendFeedbackForVideo` must throw when `/next` offers no token instead of returning as if it had sent one.

private final class FeedbackStubProtocol: URLProtocol, @unchecked Sendable {
    // The serialized suite sets the response before awaiting requests; callbacks only read it.
    nonisolated(unsafe) static var nextBody = Data("{}".utf8)
    // Written by URLSession callbacks before each request completes; the suite reads only after await.
    nonisolated(unsafe) static var paths: [String] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        Self.paths.append(url.path)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: url.path.hasSuffix("/next") ? Self.nextBody : Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Video feedback token", .serialized)
struct VideoFeedbackTokenTests {
    private func makeAPI() -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedbackStubProtocol.self]
        return InnerTubeAPI(authToken: "fake-token", session: URLSession(configuration: config))
    }

    @Test("A missing token throws and sends no feedback")
    func missingTokenThrows() async {
        FeedbackStubProtocol.nextBody = Data(#"{"contents":{}}"#.utf8)
        FeedbackStubProtocol.paths = []
        await #expect(throws: InnerTubeAPI.VideoFeedbackError.tokenUnavailable) {
            try await makeAPI().sendFeedbackForVideo(videoId: "abc", iconType: "NOT_INTERESTED")
        }
        #expect(!FeedbackStubProtocol.paths.contains { $0.hasSuffix("/feedback") })
    }

    @Test("A matching token is sent")
    func matchingTokenIsSent() async throws {
        FeedbackStubProtocol.nextBody = Data(
            #"{"items":[{"menuServiceItemRenderer":{"icon":{"iconType":"NOT_INTERESTED"},"serviceEndpoint":{"feedbackEndpoint":{"feedbackToken":"t1"}}}}]}"#
                .utf8)
        FeedbackStubProtocol.paths = []
        try await makeAPI().sendFeedbackForVideo(videoId: "abc", iconType: "NOT_INTERESTED")
        #expect(FeedbackStubProtocol.paths.contains { $0.hasSuffix("/feedback") })
    }
}
