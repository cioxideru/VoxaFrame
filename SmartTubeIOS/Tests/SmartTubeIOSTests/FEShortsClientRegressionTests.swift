import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Each request and reply is protected because URLSession callbacks use another thread.
private final class ShortsRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(URLRequest, Data)] = []
    private var status = 200
    private var response = Data()
    private var pages: [String: Data] = [:]

    func reset(status: Int = 200, response: Data = Data(), pages: [String: Data] = [:]) {
        lock.withLock {
            requests = []
            self.status = status
            self.response = response
            self.pages = pages
        }
    }

    func record(_ request: URLRequest, body: Data) -> (Int, Data) {
        lock.withLock {
            requests.append((request, body))
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            return (status, pages[json?["continuation"] as? String ?? "initial"] ?? response)
        }
    }

    var snapshot: [(URLRequest, Data)] { lock.withLock { requests } }
}

// URLProtocol owns per-request callbacks; shared mutable state lives in the locked probe.
private final class ShortsURLProtocol: URLProtocol, @unchecked Sendable {
    static let probe = ShortsRequestProbe()
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let (status, data) = Self.probe.record(request, body: body)
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Account Shorts source and continuation (PLAN-0012)", .serialized)
struct FEShortsClientRegressionTests {
    private func api(token: String? = "test-account") -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ShortsURLProtocol.self]
        return InnerTubeAPI(authToken: token, session: URLSession(configuration: config))
    }

    private func response() throws -> Data {
        let contents: [[String: Any]] = [
            [
                "videoRenderer": [
                    "videoId": "account-short", "title": ["simpleText": "Short"],
                    "lengthText": ["simpleText": "0:45"],
                    "navigationEndpoint": ["reelWatchEndpoint": ["videoId": "account-short"]],
                ]
            ],
            [
                "videoRenderer": [
                    "videoId": "regular-short-video", "title": ["simpleText": "Regular"],
                    "lengthText": ["simpleText": "0:45"],
                ]
            ],
            [
                "continuationItemRenderer": [
                    "continuationEndpoint": ["continuationCommand": ["token": "next-account-page"]]
                ]
            ],
        ]
        return try JSONSerialization.data(withJSONObject: [
            "contents": [
                "sectionListRenderer": [
                    "contents": [["itemSectionRenderer": ["contents": contents]]]
                ]
            ]
        ])
    }

    @Test func accountFeedAndContinuationStayAuthenticated() async throws {
        ShortsURLProtocol.probe.reset(response: try response())
        let api = api()
        let first = try await api.fetchShorts()
        #expect(first.videos.map(\.id) == ["account-short"])
        let token = try #require(first.nextPageToken)
        _ = try await api.fetchShortsMore(continuationToken: token)
        let requests = ShortsURLProtocol.probe.snapshot
        #expect(requests.count == 2)
        for (index, entry) in requests.enumerated() {
            let (request, body) = entry
            #expect(request.url?.host == "youtubei.googleapis.com")
            #expect(request.url?.path == "/youtubei/v1/browse")
            #expect(request.url?.query?.contains("key=") != true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let context = json["context"] as? [String: Any]
            #expect((context?["client"] as? [String: Any])?["clientName"] as? String == "TVHTML5")
            if index == 0 {
                #expect(json["browseId"] as? String == "FEsubscriptions")
            } else {
                #expect(json["continuation"] as? String == "next-account-page")
            }
        }
    }

    @Test("Three account pages never follow nested shelf cursors", arguments: ["home", "homeRows", "shorts"])
    func laterPagesRetainAccountSource(source: String) async throws {
        func page(_ number: Int) throws -> Data {
            var list: [String: Any] = [
                "contents": [
                    [
                        "shelfRenderer": [
                            "content": [
                                "horizontalListRenderer": [
                                    "items": [
                                        [
                                            "reelItemRenderer": [
                                                "videoId": "account-\(number)", "headline": ["simpleText": "Account"],
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ],
                    [
                        "shelfRenderer": [
                            "content": [
                                "horizontalListRenderer": [
                                    "items": [],
                                    "continuations": [["nextContinuationData": ["continuation": "unrelated-shelf"]]],
                                ]
                            ]
                        ]
                    ],
                ]
            ]
            if number < 3 {
                list["continuations"] = [["nextContinuationData": ["continuation": "account-page-\(number + 1)"]]]
            }
            let response =
                number == 1
                ? ["contents": ["sectionListRenderer": list]]
                : ["continuationContents": ["sectionListContinuation": list]]
            return try JSONSerialization.data(withJSONObject: response)
        }
        ShortsURLProtocol.probe.reset(
            response: try response(),
            pages: [
                "initial": try page(1), "account-page-2": try page(2), "account-page-3": try page(3),
            ])
        let api = api()
        var token: String?
        for number in 1...3 {
            let groups: [VideoGroup]
            switch source {
            case "home": groups = [try await api.fetchHome(continuationToken: token)]
            case "homeRows": groups = try await api.fetchHomeRows(continuationToken: token)
            default:
                groups =
                    if let token {
                        [try await api.fetchShortsMore(continuationToken: token)]
                    } else {
                        [try await api.fetchShorts()]
                    }
            }
            #expect(groups.flatMap(\.videos).map(\.id) == ["account-\(number)"])
            token = groups.last?.nextPageToken
            if number < 3 { #expect(token != nil) }
        }
        #expect(token == nil)
        let requests = ShortsURLProtocol.probe.snapshot
        #expect(requests.count == 3)
        for (index, entry) in requests.enumerated() {
            let (request, body) = entry
            #expect(request.url?.host == "youtubei.googleapis.com")
            #expect(request.url?.path == "/youtubei/v1/browse")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            if index == 0 {
                #expect(json["browseId"] as? String == (source == "shorts" ? "FEsubscriptions" : "FEwhat_to_watch"))
            } else {
                #expect(json["continuation"] as? String == "account-page-\(index + 1)")
            }
        }
    }

    @Test func accountFailureNeverFallsBackToGlobalSearch() async {
        ShortsURLProtocol.probe.reset(status: 401)
        await #expect(throws: APIError.self) { try await api().fetchShorts() }
        #expect(ShortsURLProtocol.probe.snapshot.count == 1)
        #expect(ShortsURLProtocol.probe.snapshot.first?.0.url?.path == "/youtubei/v1/browse")
    }

    @Test func continuationCannotCrossAuthenticationBoundary() async {
        ShortsURLProtocol.probe.reset()
        await #expect(throws: APIError.self) {
            try await api(token: nil).fetchShortsMore(continuationToken: "subs:account-page")
        }
        await #expect(throws: APIError.self) {
            try await api().fetchShortsMore(continuationToken: "srch:anonymous-page")
        }
        await #expect(throws: APIError.self) {
            try await api().fetchShortsMore(continuationToken: "unknown-source")
        }
        #expect(ShortsURLProtocol.probe.snapshot.isEmpty)
    }

    @Test func signedOutDiscoveryRetainsSearchContinuation() async throws {
        ShortsURLProtocol.probe.reset(response: try response())
        let api = api(token: nil)
        let first = try await api.fetchShorts()
        _ = try await api.fetchShortsMore(continuationToken: #require(first.nextPageToken))
        let requests = ShortsURLProtocol.probe.snapshot
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.0.url?.path == "/youtubei/v1/search" })
        #expect(requests.allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == nil })
    }
}
