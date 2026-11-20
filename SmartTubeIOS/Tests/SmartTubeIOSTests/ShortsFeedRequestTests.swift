import Foundation
import Testing

@testable import SmartTubeIOSCore

// PLAN-0052: the full-screen Shorts feed's requests at the API seam (fixtures: `SequenceFixture`).

/// Replies by path, so a reel answer and the search fallback can differ in one test. With `pagedSearch` each search
/// page n holds `search-n` and continues with `Pn+1`; `searchBody` answers every search. A URLProtocol mock sees no
/// cookies, so each recorded request gets those of `cookieStore` as the HTTP loader adds them, unless it opts out
/// (`httpShouldHandleCookies`). Unchecked Sendable: every stored property is read and written only under `lock`.
private final class SequenceRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(URLRequest, [String: Any])] = []
    private var reel: (status: Int, body: String) = (200, "{}")
    private var pagedSearch = false
    private var searchBody: String?
    private var cookieStore: HTTPCookieStorage?

    func reset(
        reelStatus: Int = 200, reelBody: String, pagedSearch: Bool = false, searchBody: String? = nil,
        cookieStore: HTTPCookieStorage? = nil
    ) {
        lock.withLock {
            requests = []
            reel = (reelStatus, reelBody)
            self.pagedSearch = pagedSearch
            self.searchBody = searchBody
            self.cookieStore = cookieStore
        }
    }

    func record(_ request: URLRequest, body: Data) -> (Int, Data) {
        lock.withLock {
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            var request = request
            if request.httpShouldHandleCookies, let url = request.url, let cookies = cookieStore?.cookies(for: url) {
                for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
            requests.append((request, json))
            guard request.url?.path.hasSuffix("/search") == true else { return (reel.status, Data(reel.body.utf8)) }
            if let searchBody { return (200, Data(searchBody.utf8)) }
            guard pagedSearch else { return (200, Data(SequenceFixture.search.utf8)) }
            let page = (json["continuation"] as? String).flatMap { Int($0.dropFirst()) } ?? 1
            return (200, Data(SequenceFixture.searchPage(page).utf8))
        }
    }

    var snapshot: [(URLRequest, [String: Any])] { lock.withLock { requests } }
}

/// Unchecked Sendable: URLProtocol is not Sendable; this subclass adds no mutable state (the probe locks its own).
private final class SequenceURLProtocol: URLProtocol, @unchecked Sendable {
    static let probe = SequenceRequestProbe()
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

@Suite("Shorts feed request (PLAN-0052)", .serialized)
struct ShortsFeedRequestTests {
    private static let reelPath = "/youtubei/v1/reel/reel_watch_sequence"

    private static let firstPage = "100000000000000000001"
    private static let secondPage = "200000000000000000002"

    /// `cookieStore` is the session's, filled as a web sign-in fills the shared one.
    private func api(
        token: String? = "test-account", channel: ActiveChannel = ActiveChannel(), cookieStore: HTTPCookieStorage? = nil
    ) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SequenceURLProtocol.self]
        if let cookieStore { config.httpCookieStorage = cookieStore }
        return InnerTubeAPI(authToken: token, session: URLSession(configuration: config), activeChannel: channel)
    }

    private func clientName(_ body: [String: Any]) -> String? {
        ((body["context"] as? [String: Any])?["client"] as? [String: Any])?["clientName"] as? String
    }

    private func reelRequests() -> [(URLRequest, [String: Any])] {
        SequenceURLProtocol.probe.snapshot.filter { $0.0.url?.path == Self.reelPath }
    }

    @Test("Signed in with a Brand Account: Bearer, its page ID and the TV client, seed first, continuation next")
    func brandAccountSequence() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let channel = ActiveChannel()
        channel.set(pageId: Self.firstPage)
        let api = api(channel: channel)
        let window = ShortsFeedWindow(
            videos: ["a", "b", "c"].map { Video(id: $0, title: $0, channelTitle: "Shelf", isShort: true) },
            startIndex: 1)

        let first = try await api.fetchShortsFeed(seedVideoId: window.seedVideoId, continuationToken: nil)
        #expect(first.videos.map(\.id) == ["seq-1", "seq-2", "seq-3"])
        let token = try #require(first.nextPageToken)
        // Bound to the sign-in and the Brand Account, without the Bearer token.
        #expect(token == "reel:0/\(Self.firstPage):TV-NEXT")
        _ = try await api.fetchShortsFeed(seedVideoId: window.seedVideoId, continuationToken: token)

        // Each page's title lookups (`reel/reel_item_watch`) are covered in ShortsSequenceTitleTests.
        let requests = reelRequests()
        #expect(requests.count == 2)
        for (request, body) in requests {
            #expect(request.url?.host == "youtubei.googleapis.com")
            #expect(request.url?.path == Self.reelPath)
            #expect(request.url?.query?.contains("key=") != true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
            #expect(request.value(forHTTPHeaderField: ActiveChannel.headerField) == Self.firstPage)
            #expect(clientName(body) == "TVHTML5")
        }
        #expect(requests[0].1["sequenceParams"] as? String == ShortsSequence.seedParams(videoId: "b"))
        #expect(requests[0].1["continuation"] == nil)
        #expect(requests[1].1["continuation"] as? String == "TV-NEXT")
        #expect(requests[1].1["sequenceParams"] == nil)
    }

    @Test(
        "A continuation is not sent once another Brand Account or the primary account is selected",
        arguments: [secondPage, nil] as [String?])
    func otherChannelSendsNoContinuation(selected: String?) async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let channel = ActiveChannel()
        channel.set(pageId: Self.firstPage)
        let api = api(channel: channel)
        let token = try #require(
            try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil).nextPageToken)
        channel.set(pageId: selected)
        let sent = SequenceURLProtocol.probe.snapshot.count

        await #expect(throws: APIError.self) {
            try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: token)
        }
        #expect(SequenceURLProtocol.probe.snapshot.count == sent)
        #expect(reelRequests().count == 1)
    }

    @Test("Signed out of one primary account and into another: the first one's continuation is not sent")
    func anotherSignInSendsNoContinuation() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let api = api(token: "account-a")
        let token = try #require(
            try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil).nextPageToken)
        await api.setAuthToken(nil)
        await api.setAuthToken("account-b")
        let sent = SequenceURLProtocol.probe.snapshot.count

        await #expect(throws: APIError.self) {
            try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: token)
        }
        #expect(SequenceURLProtocol.probe.snapshot.count == sent)
        #expect(reelRequests().count == 1)
    }

    @Test("A token refresh of the same account keeps the continuation, sent with the new token")
    func tokenRefreshKeepsTheContinuation() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let channel = ActiveChannel()
        channel.set(pageId: Self.firstPage)
        let api = api(channel: channel)
        let token = try #require(
            try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil).nextPageToken)
        await api.setAuthToken("refreshed-account")
        _ = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: token)

        let continuation = try #require(reelRequests().last)
        #expect(reelRequests().count == 2)
        #expect(continuation.1["continuation"] as? String == "TV-NEXT")
        #expect(continuation.0.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-account")
        #expect(continuation.0.value(forHTTPHeaderField: ActiveChannel.headerField) == Self.firstPage)
    }

    @Test("The primary account sends Bearer without a page ID")
    func primaryAccountSequence() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        _ = try await api().fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)
        let request = try #require(SequenceURLProtocol.probe.snapshot.first?.0)
        #expect(request.url?.path == Self.reelPath)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
        #expect(request.value(forHTTPHeaderField: ActiveChannel.headerField) == nil)
    }

    @Test("Signed out keeps today's anonymous search, with no Bearer or page ID")
    func signedOutUsesSearch() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let channel = ActiveChannel()
        channel.set(pageId: "100000000000000000001")
        let api = api(token: nil, channel: channel)
        let first = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)
        #expect(first.videos.map(\.id) == ["search-short"])
        _ = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: try #require(first.nextPageToken))
        let requests = SequenceURLProtocol.probe.snapshot
        #expect(requests.map { $0.0.url?.path } == ["/youtubei/v1/search", "/youtubei/v1/search"])
        #expect(requests.allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(requests.allSatisfy { $0.0.value(forHTTPHeaderField: ActiveChannel.headerField) == nil })
        #expect(requests[1].1["continuation"] as? String == "search-next")
    }

    @Test(
        "A refused signed-in sequence continues with the anonymous search, page after page",
        arguments: [
            (403, SequenceFixture.errorAnswer), (200, SequenceFixture.errorAnswer), (200, SequenceFixture.signedOut),
            (200, SequenceFixture.signedOutBesideNull), (200, SequenceFixture.empty), (200, SequenceFixture.adsOnly),
        ])
    func refusalFallsBackToSearch(status: Int, body: String) async throws {
        SequenceURLProtocol.probe.reset(reelStatus: status, reelBody: body)
        let api = api()
        let first = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)
        #expect(first.videos.map(\.id) == ["search-short"])
        // The search's token is marked as the end's own (`reel:`), so the feed window keeps it at the end.
        let token = try #require(first.nextPageToken)
        #expect(token == InnerTubeAPI.shortsSequencePrefix + InnerTubeAPI.shortsSearchPrefix + "search-next")
        _ = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: token)

        let requests = SequenceURLProtocol.probe.snapshot
        #expect(requests.map { $0.0.url?.path } == [Self.reelPath, "/youtubei/v1/search", "/youtubei/v1/search"])
        #expect(requests[0].0.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
        #expect(requests.dropFirst().allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(requests[2].1["continuation"] as? String == "search-next")
    }

    @Test("The fallback search sends none of the cookie store's cookies, first page and continuation alike")
    func fallbackSearchSendsNoCookies() async throws {
        let store = try #require(URLSessionConfiguration.ephemeral.httpCookieStorage)
        store.setCookie(
            try #require(
                HTTPCookie(properties: [
                    .domain: ".youtube.com", .path: "/", .name: "SAPISID", .value: "web-session", .secure: "TRUE",
                ])))
        SequenceURLProtocol.probe.reset(reelStatus: 403, reelBody: SequenceFixture.errorAnswer, cookieStore: store)
        let api = api(cookieStore: store)
        let first = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)
        _ = try await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: try #require(first.nextPageToken))
        // Control: a guest's Shorts search outside the feed keeps the shared transport, cookies included.
        _ = try await self.api(token: nil, cookieStore: store).fetchShorts()

        let searches = SequenceURLProtocol.probe.snapshot.filter { $0.0.url?.path == "/youtubei/v1/search" }
        #expect(searches.count == 3)
        #expect(searches.prefix(2).allSatisfy { $0.0.value(forHTTPHeaderField: "Cookie") == nil })
        #expect(searches.last?.0.value(forHTTPHeaderField: "Cookie")?.contains("SAPISID=web-session") == true)
    }

    @Test("A refused continuation also continues with the anonymous search")
    func refusedContinuationFallsBack() async throws {
        SequenceURLProtocol.probe.reset(reelStatus: 401, reelBody: SequenceFixture.errorAnswer)
        let token = InnerTubeAPI.shortsSequenceToken(
            "TV-NEXT", for: ShortsAccountSnapshot(token: "test-account", pageId: nil, signIn: 0))
        let group = try await api().fetchShortsFeed(seedVideoId: "seed", continuationToken: token)
        #expect(group.videos.map(\.id) == ["search-short"])
        let requests = SequenceURLProtocol.probe.snapshot
        #expect(requests.map { $0.0.url?.path } == [Self.reelPath, "/youtubei/v1/search"])
        #expect(requests[0].1["continuation"] as? String == "TV-NEXT")
    }

    @Test("Loading back keeps the earlier source with its cursor and never asks for the sequence")
    func loadingBackKeepsTheEarlierSource() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let api = api()
        _ = try? await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: nil, prepending: true)
        _ = try? await api.fetchShortsFeed(seedVideoId: "seed", continuationToken: "subs:BACK", prepending: true)
        let requests = SequenceURLProtocol.probe.snapshot
        #expect(requests.map { $0.0.url?.path } == ["/youtubei/v1/browse", "/youtubei/v1/browse"])
        #expect(requests[0].1["browseId"] as? String == "FEsubscriptions")
        #expect(requests[1].1["continuation"] as? String == "BACK")
    }

    @Test(
        "A signed-in end with a seed starts the sequence from the presentation's source's token or a bare `reel:`",
        arguments: ["subs:BACK", "srch:P2", "reel:"])
    func endStartsTheSequence(token: String) async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        let page = try await api().fetchShortsFeed(seedVideoId: "seed", continuationToken: token)
        #expect(page.nextPageToken == "reel:0/:TV-NEXT")  // The primary account: no page ID.
        let request = try #require(SequenceURLProtocol.probe.snapshot.first)
        #expect(request.0.url?.path == Self.reelPath)
        #expect(request.1["sequenceParams"] as? String == ShortsSequence.seedParams(videoId: "seed"))
        #expect(request.1["continuation"] == nil)
    }

    @Test("A guest whose search ended while loading back: the end does not ask it again, the trimmed Shorts stay out")
    func endedSearchIsNotRestartedAtTheEnd() async throws {
        let only = (0..<20).map { "search-\($0)" }
        SequenceURLProtocol.probe.reset(
            reelBody: SequenceFixture.page, searchBody: SequenceFixture.searchPage(ids: only, next: nil))
        let api = api(token: nil)
        var window = ShortsFeedWindow(videos: shelf, startIndex: 0)
        #expect(try await load(&window, from: api, prepending: true) == 20)
        #expect(window.videos.first?.id == "search-8")  // The first eight were trimmed at once.
        #expect(!window.canLoadMore(prepending: true))

        window.move(to: window.videos.count - 1)
        #expect(window.canLoadMore(prepending: false))
        #expect(try await load(&window, from: api, prepending: false) == 0)
        #expect(!window.canLoadMore(prepending: false))
        #expect(!window.videos.contains { $0.id == "search-0" })
        #expect(SequenceURLProtocol.probe.snapshot.count == 1)  // The search was not asked again.
    }

    @Test("A guest two pages back, then past the shelf's end: the end goes on with the search's next page")
    func guestBackTwiceThenForwardContinuesTheSearch() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page, pagedSearch: true)
        let api = api(token: nil)
        var window = ShortsFeedWindow(videos: shelf, startIndex: 0)
        for _ in 0..<2 { #expect(try await load(&window, from: api, prepending: true) == 1) }
        #expect(window.videos.map(\.id) == ["search-2", "search-1", "a", "b"])

        window.move(to: window.videos.count - 1)
        #expect(try await load(&window, from: api, prepending: false) == 1)
        #expect(window.videos.last?.id == "search-3")
        #expect(window.canLoadMore(prepending: false))
        #expect(window.cursor(prepending: false) == "srch:P4")
        let continuations = SequenceURLProtocol.probe.snapshot.map { $0.1["continuation"] as? String }
        #expect(continuations == [nil, "P2", "P3"])
    }

    @Test("A token set between two pages: the sequence's `reel:` cursor stays at the end and loading back goes on")
    func tokenSetBetweenPagesKeepsEachSourcesCursor() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page, pagedSearch: true)
        let api = api(token: nil)
        var window = ShortsFeedWindow(videos: shelf, startIndex: 1)
        // An expired token at launch: the end's first page is the presentation's source, the search.
        #expect(try await load(&window, from: api, prepending: false) == 1)
        #expect(window.cursor(prepending: true) == "srch:P2")
        // A refresh sets the token within the same session: the end's next page starts the sequence from the seed.
        await api.setAuthToken("test-account")
        #expect(try await load(&window, from: api, prepending: false) == 3)
        #expect(window.cursor(prepending: false) == "reel:1/:TV-NEXT")  // The token set after none: sign-in 1.
        #expect(window.cursor(prepending: true) == "srch:P2")

        window.move(to: 0)
        #expect(try await load(&window, from: api, prepending: true) == 1)
        #expect(window.videos.first?.id == "search-2")
        #expect(window.cursor(prepending: true) == "srch:P3")
        let pages = SequenceURLProtocol.probe.snapshot.filter { $0.0.url?.path.hasSuffix("reel_item_watch") == false }
        #expect(pages.map { $0.0.url?.path } == ["/youtubei/v1/search", Self.reelPath, "/youtubei/v1/search"])
        #expect(pages[1].1["sequenceParams"] as? String == ShortsSequence.seedParams(videoId: "b"))
        #expect(pages[2].0.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(pages[2].1["continuation"] as? String == "P2")
    }

    private var shelf: [Video] { ["a", "b"].map { Video(id: $0, title: $0, channelTitle: "Shelf", isShort: true) } }

    /// One `loadMore` step: the window's cursor at that end, its page, then `accept`; returns how many were added.
    private func load(_ window: inout ShortsFeedWindow, from api: InnerTubeAPI, prepending: Bool) async throws -> Int {
        let token = window.cursor(prepending: prepending)
        let page = try await api.fetchShortsFeed(
            seedVideoId: window.seedVideoId, continuationToken: token, prepending: prepending)
        return window.accept(page, requestedWith: token, prepending: prepending)
    }

    @Test("Without a seed the signed-in feed keeps today's subscriptions source")
    func noSeedKeepsCurrentSource() async throws {
        SequenceURLProtocol.probe.reset(reelBody: SequenceFixture.page)
        _ = try? await api().fetchShortsFeed(seedVideoId: nil, continuationToken: nil)
        let request = try #require(SequenceURLProtocol.probe.snapshot.first)
        #expect(request.0.url?.path == "/youtubei/v1/browse")
        #expect(request.1["browseId"] as? String == "FEsubscriptions")
    }
}
