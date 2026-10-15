import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - PlaylistMoveCopyTests (#8)
//
// There was previously no way to add a video to (or move it between) arbitrary user
// playlists — only the Watch Later-specific add/remove existed. addToPlaylist/
// removeFromPlaylist generalize that same browse/edit_playlist mechanism to any
// playlistId (from fetchUserPlaylists()), which the new PlaylistPickerSheet UI drives.

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (statusCode: Int, body: Data)] = [:]
    nonisolated(unsafe) static var capturedBodies: [String: Data] = [:]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        for key in Self.responses.keys where url.contains(key) {
            if let body = request.httpBodyOrAccumulated() {
                Self.capturedBodies[key] = body
            }
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

extension URLRequest {
    fileprivate func httpBodyOrAccumulated() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}

@Suite("Playlist add/remove — generalized beyond Watch Later (#8)", .serialized)
struct PlaylistMoveCopyTests {

    private func makeAPI() -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return InnerTubeAPI(authToken: "fake-token", session: session)
    }

    @Test("addToPlaylist sends addedVideoId under ACTION_ADD_VIDEO for the given playlistId")
    func addToPlaylistSendsCorrectShape() async throws {
        StubURLProtocol.responses = ["browse/edit_playlist": (200, Data("{}".utf8))]
        StubURLProtocol.capturedBodies = [:]
        let api = makeAPI()
        try await api.addToPlaylist(playlistId: "PLxyz123", videoId: "VID1")

        guard let bodyData = StubURLProtocol.capturedBodies["browse/edit_playlist"],
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let actions = body["actions"] as? [[String: Any]],
            let action = actions.first
        else {
            Issue.record("No request body captured for browse/edit_playlist")
            return
        }
        #expect(body["playlistId"] as? String == "PLxyz123")
        #expect(action["action"] as? String == "ACTION_ADD_VIDEO")
        #expect(action["addedVideoId"] as? String == "VID1")
    }

    @Test("removeFromPlaylist sends setVideoId under ACTION_REMOVE_VIDEO for the given playlistId")
    func removeFromPlaylistSendsCorrectShape() async throws {
        StubURLProtocol.responses = ["browse/edit_playlist": (200, Data("{}".utf8))]
        StubURLProtocol.capturedBodies = [:]
        let api = makeAPI()
        try await api.removeFromPlaylist(playlistId: "PLxyz123", setVideoId: "SET_TOKEN_1")

        guard let bodyData = StubURLProtocol.capturedBodies["browse/edit_playlist"],
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let actions = body["actions"] as? [[String: Any]],
            let action = actions.first
        else {
            Issue.record("No request body captured for browse/edit_playlist")
            return
        }
        #expect(body["playlistId"] as? String == "PLxyz123")
        #expect(action["action"] as? String == "ACTION_REMOVE_VIDEO")
        #expect(action["setVideoId"] as? String == "SET_TOKEN_1")
        #expect(action["removedVideoId"] == nil)
    }
}
