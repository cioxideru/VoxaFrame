import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - FEShortsClientRegressionTests
//
// Regression tests for task #96: fetchShorts and fetchShortsMore must use the
// TVHTML5 client context, not the WEB client context, when making authenticated
// InnerTube browse requests.
//
// Root cause: the device-code OAuth token is bound to TVHTML5. When the WEB
// client body is sent with this token, YouTube returns HTTP 400. All other auth
// endpoints correctly use tvClientContext; fetchShorts and fetchShortsMore had
// a regression that switched them to webClientContext, causing Shorts to show
// no videos on cold launch.
//
// These tests intercept the outgoing URLRequest via URLProtocol and verify the
// JSON body contains `"clientName": "TVHTML5"` — not `"WEB"`.

// MARK: - URLProtocol helper

/// Intercepts the first outgoing POST request and captures its JSON body.
/// Returns HTTP 400 so the caller's network path fails fast.
private final class BodyCapturingURLProtocol: URLProtocol, @unchecked Sendable {

    // The serialized suite resets before the request and reads after await; sequential callbacks capture only the first body.
    nonisolated(unsafe) static var capturedBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        request.httpMethod == "POST"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession converts httpBody to httpBodyStream before handing the request
        // to URLProtocol; httpBody is always nil here.
        // Only capture the FIRST request — fetchShorts falls back to a second search
        // request when the primary browse fails, and we must not let it overwrite
        // the FEshorts browse body we already captured.
        if BodyCapturingURLProtocol.capturedBody == nil {
            if let stream = request.httpBodyStream {
                stream.open()
                var body = Data()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer {
                    buffer.deallocate()
                    stream.close()
                }
                // Use read-until-zero rather than hasBytesAvailable; the latter
                // can return false prematurely for in-memory streams.
                while true {
                    let count = stream.read(buffer, maxLength: bufferSize)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
                BodyCapturingURLProtocol.capturedBody = body
            } else if let bodyData = request.httpBody {
                // Fallback: some configurations pass the body directly in httpBody.
                BodyCapturingURLProtocol.capturedBody = bodyData
            }
        }

        // Reply with a minimal HTTP 400 response so the API call fails fast.
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite("FEshorts uses TV client — Regression #96", .serialized)
struct FEShortsClientRegressionTests {

    // MARK: - Helpers

    /// Returns an `InnerTubeAPI` wired to `BodyCapturingURLProtocol` via an ephemeral
    /// `URLSession`. This avoids polluting the global URLProtocol registry.
    private func makeTestAPI(authToken: String) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BodyCapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: authToken, session: session)
    }

    // fetchShorts no longer browses FEshorts (YouTube deprecated it, see InnerTubeAPI+Browse):
    // it searches "#shorts", so only the continuation path still needs the TV client.

    // MARK: - fetchShortsMore

    /// Continuation tokens must use their source client, with the routing prefix removed.
    @Test(
        "fetchShortsMore preserves legacy and tagged client routing",
        arguments: ["", "stv:", "stvc:", "web:", "srch:"]
    )
    func fetchShortsMoreRoutesClient(prefix: String) async throws {
        BodyCapturingURLProtocol.capturedBody = nil
        let api = makeTestAPI(authToken: "fake-tv-oauth-token")

        _ = try? await api.fetchShortsMore(continuationToken: prefix + "test-continuation-token-12345")

        let bodyData = try #require(
            BodyCapturingURLProtocol.capturedBody,
            "URLProtocol should have captured the POST body"
        )
        let json = try #require(
            try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            "Request body must be valid JSON"
        )

        let context = json["context"] as? [String: Any]
        let clientDict = context?["client"] as? [String: Any]

        let expectedClient = prefix == "web:" || prefix == "srch:" ? "WEB" : "TVHTML5"
        #expect(
            clientDict?["clientName"] as? String == expectedClient,
            """
            fetchShortsMore must use the source client for prefix \(prefix).
            Found clientName=\(String(describing: clientDict?["clientName"]))
            """
        )
        #expect(
            json["continuation"] as? String == "test-continuation-token-12345",
            "fetchShortsMore must forward the continuation token in the body"
        )
    }
}
