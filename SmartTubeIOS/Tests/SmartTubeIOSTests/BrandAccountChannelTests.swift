import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// Brand Accounts (PLAN-0049, upstream #172): the OAuth token stays the primary account's and the
// selected channel travels as `X-Goog-Pageid`, as in SmartTube Android.

private final class PageIDStubURLProtocol: URLProtocol, @unchecked Sendable {
    // The only suite that uses this protocol is serialized, and each test resets the list before its requests.
    nonisolated(unsafe) static var capturedHeaders: [[String: String]] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedHeaders.append(request.allHTTPHeaderFields ?? [:])
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func accountItem(
    name: String, pageId: String?, avatar: String? = nil, nameAsRuns: Bool = false
)
    -> [String: Any]
{
    var item: [String: Any] = ["accountName": nameAsRuns ? ["runs": [["text": name]]] : ["simpleText": name]]
    if let avatar { item["accountPhoto"] = ["thumbnails": [["url": "//small"], ["url": avatar]]] }
    if let pageId {
        item["serviceEndpoint"] = [
            "selectActiveIdentityEndpoint": ["supportedTokens": [["pageIdToken": ["pageId": pageId]]]]
        ]
    }
    return ["accountItem": item]
}

private func accountsList(_ items: [[String: Any]]) -> [String: Any] {
    ["contents": [["accountSectionListRenderer": ["contents": [["accountItemSectionRenderer": ["contents": items]]]]]]]
}

@Suite("Brand Account accounts_list parsing")
struct BrandAccountParsingTests {

    @Test("Lists the primary account and Brand Accounts; only the primary has no page ID")
    func listsPrimaryAndBrandAccounts() {
        let channels = YouTubeChannel.list(
            fromAccountsList: accountsList([
                accountItem(name: "Brand Channel", pageId: "100000000000000000001"),
                accountItem(name: "Primary User", pageId: nil),
            ]))

        #expect(channels.map(\.name) == ["Brand Channel", "Primary User"])
        #expect(channels.map(\.pageId) == ["100000000000000000001", nil])
        #expect(channels.map(\.isPrimary) == [false, true])
    }

    @Test("Reads a name from runs and makes a protocol-relative avatar https")
    func readsRunsNameAndNormalizesAvatar() {
        let channel = YouTubeChannel.list(
            fromAccountsList: accountsList([
                accountItem(name: "Cooking", pageId: "1", avatar: "//yt3.ggpht.com/a.jpg", nameAsRuns: true)
            ])
        ).first

        #expect(channel?.name == "Cooking")
        #expect(channel?.avatarURL == URL(string: "https://yt3.ggpht.com/a.jpg"))
    }

    @Test("An unexpected response shape gives no channels, and a nameless item is skipped")
    func malformedInput() {
        #expect(YouTubeChannel.list(fromAccountsList: [:]).isEmpty)
        #expect(YouTubeChannel.list(fromAccountsList: ["contents": "unexpected"]).isEmpty)
        let json = accountsList([["accountItem": ["isSelected": true]], accountItem(name: "Watch", pageId: "2")])
        #expect(YouTubeChannel.list(fromAccountsList: json).map(\.name) == ["Watch"])
    }
}

@Suite("Brand Account page ID on requests", .serialized)
struct BrandAccountRequestHeaderTests {

    private func makeAPI(authToken: String?, channel: ActiveChannel) -> InnerTubeAPI {
        PageIDStubURLProtocol.capturedHeaders = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PageIDStubURLProtocol.self]
        return InnerTubeAPI(authToken: authToken, session: URLSession(configuration: config), activeChannel: channel)
    }

    @Test("A selected Brand Account travels with the Bearer token")
    func sendsPageIdWithBearer() async {
        let channel = ActiveChannel()
        channel.set(pageId: "100000000000000000001")
        let api = makeAPI(authToken: "fake-token", channel: channel)

        _ = try? await api.fetchSubscriptions()

        let headers = PageIDStubURLProtocol.capturedHeaders.first
        #expect(headers?["Authorization"] == "Bearer fake-token")
        #expect(headers?[ActiveChannel.headerField] == "100000000000000000001")
    }

    @Test("The primary account sends no page ID")
    func omitsPageIdForPrimary() async {
        let api = makeAPI(authToken: "fake-token", channel: ActiveChannel())

        _ = try? await api.fetchSubscriptions()

        #expect(PageIDStubURLProtocol.capturedHeaders.first?["Authorization"] == "Bearer fake-token")
        #expect(PageIDStubURLProtocol.capturedHeaders.first?[ActiveChannel.headerField] == nil)
    }

    @Test("An unauthenticated request sends no page ID")
    func omitsPageIdWhenUnauthenticated() async {
        let channel = ActiveChannel()
        channel.set(pageId: "100000000000000000001")
        let api = makeAPI(authToken: nil, channel: channel)

        _ = try? await api.fetchHome()

        let headers = PageIDStubURLProtocol.capturedHeaders.first
        #expect(headers != nil)
        #expect(headers?["Authorization"] == nil)
        #expect(headers?[ActiveChannel.headerField] == nil)
    }

    @Test("The next request uses a newly selected channel without a new API instance")
    func appliesSwitchOnNextRequest() async {
        let channel = ActiveChannel()
        channel.set(pageId: "111")
        let api = makeAPI(authToken: "fake-token", channel: channel)

        _ = try? await api.fetchSubscriptions()
        channel.set(pageId: "222")
        _ = try? await api.fetchSubscriptions()
        channel.set(pageId: nil)
        _ = try? await api.fetchSubscriptions()

        #expect(PageIDStubURLProtocol.capturedHeaders.map { $0[ActiveChannel.headerField] } == ["111", "222", nil])
    }
}

@MainActor
@Suite("Brand Account switch in AuthService")
struct BrandAccountAuthServiceTests {

    private let primary = YouTubeChannel(name: "Primary User", avatarURL: nil, pageId: nil)
    private let brand = YouTubeChannel(name: "Brand Channel", avatarURL: nil, pageId: "100000000000000000001")

    // Written only by an observer with a nil queue, which runs synchronously inside `post` on the main actor.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    /// A signed-in AuthService with its own Keychain service, channel state and notification center.
    private func signedInAuth() -> (auth: AuthService, channel: ActiveChannel) {
        let channel = ActiveChannel()
        let auth = AuthService(
            tokenManager: TokenManager(keychainService: "test-brand-\(UUID().uuidString)"),
            activeChannel: channel, notificationCenter: NotificationCenter())
        auth.evictAccountPlayerData = {}
        auth.isSignedIn = true
        auth.applyChannels([primary, brand])
        return (auth, channel)
    }

    private func changes(on auth: AuthService, during action: () -> Void) -> Int {
        let counter = Counter()
        let count: @Sendable (Notification) -> Void = { _ in counter.value += 1 }
        let center = auth.notificationCenter
        let token = center.addObserver(forName: .activeChannelDidChange, object: nil, queue: nil, using: count)
        action()
        auth.notificationCenter.removeObserver(token)
        return counter.value
    }

    @Test("Switching selects the channel for requests, starts a new session and announces it once")
    func switchStartsNewSession() {
        let (auth, channel) = signedInAuth()
        let session = auth.sessionGeneration

        #expect(changes(on: auth) { auth.selectChannel(brand) } == 1)
        #expect(auth.activePageId == brand.pageId)
        #expect(channel.pageId == brand.pageId)
        #expect(auth.accountName == "Brand Channel")
        #expect(auth.sessionGeneration == session + 1)

        #expect(changes(on: auth) { auth.selectChannel(brand) } == 0)
        #expect(auth.sessionGeneration == session + 1)
    }

    @Test("A stored channel the account no longer has falls back to the primary account")
    func missingChannelFallsBack() {
        let (auth, channel) = signedInAuth()
        auth.selectChannel(brand)

        auth.applyChannels([primary])

        #expect(auth.activePageId == nil)
        #expect(channel.pageId == nil)
    }

    @Test("Signing out clears the channels and the selected page ID")
    func signOutClearsSelection() {
        let (auth, channel) = signedInAuth()
        auth.selectChannel(brand)

        auth.signOut()

        #expect(auth.activePageId == nil)
        #expect(auth.channels.isEmpty)
        #expect(channel.pageId == nil)
    }

    @Test("A signed-out service does not switch")
    func signedOutDoesNotSwitch() {
        let (auth, channel) = signedInAuth()
        auth.isSignedIn = false

        #expect(changes(on: auth) { auth.selectChannel(brand) } == 0)
        #expect(channel.pageId == nil)
    }
}
