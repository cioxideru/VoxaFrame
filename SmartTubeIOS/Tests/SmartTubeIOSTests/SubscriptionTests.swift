import Foundation
import Testing

@testable import SmartTubeIOSCore

private final class SubscriptionURLProtocol: URLProtocol, @unchecked Sendable {
    // The serialized suite sets fixtures before requests and reads captures after completion.
    // Move to per-session transport state if this suite ever gains concurrent requests.
    nonisolated(unsafe) static var replies: [(Int, [String: Any])] = []
    // One in-flight request appends captures; the serialized test reads them only after awaiting completion.
    nonisolated(unsafe) static var requests: [(URLRequest, [String: Any])] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.requests.append((request, body))
        let (status, payload) = Self.replies.isEmpty ? (500, [:]) : Self.replies.removeFirst()
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Subscription API", .serialized)
struct SubscriptionAPITests {
    private func api(token: String? = "test-token", replies: [(Int, [String: Any])]) -> InnerTubeAPI {
        SubscriptionURLProtocol.replies = replies
        SubscriptionURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubscriptionURLProtocol.self]
        return InnerTubeAPI(authToken: token, session: URLSession(configuration: configuration))
    }

    private func navigation(_ ids: [String], token: String? = nil) -> [String: Any] {
        var section: [String: Any] = [
            "tabs": ids.map { id in
                [
                    "tabRenderer": [
                        "endpoint": ["browseEndpoint": ["browseId": id]],
                        "title": id,
                    ]
                ]
            }
        ]
        if let token { section["continuations"] = [["nextContinuationData": ["continuation": token]]] }
        return [
            "contents": [
                "tvBrowseRenderer": [
                    "content": ["tvSecondaryNavRenderer": ["sections": [["tvSecondaryNavSectionRenderer": section]]]]
                ]
            ]
        ]
    }

    @Test("Mutations use TV OAuth, the selected channel and the requested operation", arguments: [true, false])
    func mutationRequest(subscribed: Bool) async throws {
        let api = api(replies: [(200, ["responseContext": [:]])])
        try await api.setSubscribed(channelId: "UCtarget", subscribed: subscribed)
        let (request, body) = try #require(SubscriptionURLProtocol.requests.first)
        #expect(request.url?.host == "youtubei.googleapis.com")
        #expect(
            request.url?.path.hasSuffix(subscribed ? "/subscription/subscribe" : "/subscription/unsubscribe") == true)
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(body["channelIds"] as? [String] == ["UCtarget"])
        let client = (body["context"] as? [String: Any])?["client"] as? [String: Any]
        #expect(client?["clientName"] as? String == "TVHTML5")
    }

    @Test("Signed-out account mutations are rejected before any request")
    func requiresAuthentication() async {
        let api = api(token: nil, replies: [])
        await #expect(throws: APIError.self) { try await api.setSubscribed(channelId: "UCtarget", subscribed: true) }
        #expect(SubscriptionURLProtocol.requests.isEmpty)
    }

    @Test("HTTP and application errors never count as a successful mutation", arguments: [0, 1, 2])
    func rejectedMutation(kind: Int) async {
        let replies: [(Int, [String: Any])] = [
            (403, [:]),
            (200, ["error": ["message": "Rejected"]]),
            (200, ["alerts": [["alertRenderer": ["type": "ERROR", "text": ["simpleText": "Rejected"]]]]]),
        ]
        let api = api(replies: [replies[kind]])
        await #expect(throws: APIError.self) { try await api.setSubscribed(channelId: "UCtarget", subscribed: false) }
    }

    @Test("All navigation pages are loaded, deduplicated and marked subscribed")
    func completeNavigation() async throws {
        let api = api(replies: [
            (200, navigation(["UCzeta", "UCbeta", "FEhome"], token: "page-two")),
            (200, navigation(["UCbeta", "UCalpha"])),
        ])
        let channels = try await api.fetchSubscribedChannels()
        #expect(channels.map(\.id) == ["UCalpha", "UCbeta", "UCzeta"])
        #expect(channels.allSatisfy { $0.isSubscribed })
        #expect(SubscriptionURLProtocol.requests.count == 2)
        #expect(SubscriptionURLProtocol.requests[1].1["continuation"] as? String == "page-two")
        #expect(SubscriptionURLProtocol.requests.allSatisfy { $0.0.url?.path.hasSuffix("/browse") == true })
        #expect(SubscriptionURLProtocol.requests[0].1["browseId"] as? String == "FEsubscriptions")
    }

    @Test("An empty channel navigation is empty, not a list guessed from video authors")
    func emptyNavigation() async throws {
        let api = api(replies: [(200, navigation([]))])
        #expect(try await api.fetchSubscribedChannels().isEmpty)
        #expect(SubscriptionURLProtocol.requests.count == 1)
    }

    @Test("Repeated cursors fail visibly instead of looping or returning an incomplete list")
    func repeatedContinuation() async {
        let page = navigation(["UCbeta"], token: "repeat")
        let api = api(replies: [(200, page), (200, page)])
        await #expect(throws: APIError.self) { try await api.fetchSubscribedChannels() }
        #expect(SubscriptionURLProtocol.requests.count == 2)
    }

    @Test("A failed page does not masquerade as an empty or partial list")
    func failedNavigationPage() async {
        let api = api(replies: [(200, navigation(["UCbeta"], token: "next")), (200, ["error": ["message": "Expired"]])])
        await #expect(throws: APIError.self) { try await api.fetchSubscribedChannels() }
    }

    @Test("Malformed navigation fails instead of clearing membership")
    func malformedNavigation() async {
        let api = api(replies: [(200, ["responseContext": [:]])])
        await #expect(throws: APIError.self) { try await api.fetchSubscribedChannels() }
    }

    @Test("Video feed continuations cannot supply the channel-list cursor")
    func unrelatedCursor() async throws {
        var response = navigation(["UCbeta"])
        response["otherSection"] = ["nextContinuationData": ["continuation": "not-subscriptions"]]
        let api = api(replies: [(200, response)])
        #expect(try await api.fetchSubscribedChannels().count == 1)
        #expect(SubscriptionURLProtocol.requests.count == 1)
    }

    @Test(
        "TV tabs decode membership and normalize avatars, independent of recent uploads",
        arguments: ["https://yt3.googleusercontent.com/avatar", "//yt3.googleusercontent.com/avatar"])
    func tvChannelParameters(thumbnail: String) async throws {
        let section: [String: Any] = [
            "tabs": [
                [
                    "tabRenderer": [
                        "title": "All", "endpoint": ["browseEndpoint": ["browseId": "FEsubscriptions"]],
                        "content": ["nextContinuationData": ["continuation": "videos-only"]],
                    ]
                ],
                [
                    "tabRenderer": [
                        "title": "All (older)",
                        "endpoint": ["browseEndpoint": ["browseId": "FEsubscriptions", "params": "igMA"]],
                    ]
                ],
                [
                    "tabRenderer": [
                        "title": "Channel with no uploads",
                        "thumbnail": ["thumbnails": [["url": thumbnail]]],
                        "endpoint": [
                            "browseEndpoint": [
                                "browseId": "FEsubscriptions", "params": "igMaChhVQ1lyeElJbFVzSDJ4cldpUW93T0ZxSHc%3D",
                            ]
                        ],
                    ]
                ],
            ]
        ]
        let api = api(replies: [
            (
                200,
                [
                    "contents": [
                        "tvBrowseRenderer": [
                            "content": [
                                "tvSecondaryNavRenderer": ["sections": [["tvSecondaryNavSectionRenderer": section]]]
                            ]
                        ]
                    ]
                ]
            )
        ])
        let channels = try await api.fetchSubscribedChannels()
        #expect(channels.map(\.id) == ["UCYrxIIlUsH2xrWiQowOFqHw"])
        #expect(channels.first?.title == "Channel with no uploads")
        #expect(channels.first?.thumbnailURL?.absoluteString == "https://yt3.googleusercontent.com/avatar")
        #expect(SubscriptionURLProtocol.requests.count == 1)
    }
}

@Suite("Subscription state")
@MainActor
struct SubscriptionStateTests {
    @Test("A refresh finishing after unsubscribe cannot restore stale membership")
    func refreshDuringMutation() async throws {
        let mock = MockInnerTubeAPI()
        let channel = Channel(id: "UCtarget", title: "Target")
        mock.channelResult = (channel, VideoGroup(videos: []))
        mock.channelsResult = [channel]
        let vm = ChannelViewModel(api: mock)
        await vm.loadAsync(channelId: channel.id, signedIn: true)
        var mutationResponse: CheckedContinuation<Void, Never>?
        var staleResponse: CheckedContinuation<[Channel], Never>?
        defer {
            mutationResponse?.resume()
            staleResponse?.resume(returning: [channel])
        }
        mock.setSubscribedHandler = { _, _ in
            await withCheckedContinuation { mutationResponse = $0 }
        }
        let mutation = Task { await vm.setSubscribed(false) }
        await waitForTasks { mutationResponse != nil }
        let finishMutation = try #require(mutationResponse)
        mock.subscribedChannelsHandler = {
            await withCheckedContinuation { staleResponse = $0 }
        }
        let refresh = Task { await vm.refresh(channelId: channel.id, signedIn: true) }
        await waitForTasks { staleResponse != nil }
        let finishRefresh = try #require(staleResponse)
        mutationResponse = nil
        finishMutation.resume()
        await mutation.value
        staleResponse = nil
        finishRefresh.resume(returning: [channel])
        await refresh.value
        #expect(vm.channel?.isSubscribed == false)
        #expect(vm.isSubscriptionLoaded)
        #expect(!vm.isLoading)
    }

    @Test("Channel state comes from account membership and changes only after success")
    func accountMembershipAndMutations() async {
        let mock = MockInnerTubeAPI()
        let channel = Channel(id: "UCtarget", title: "Target")
        mock.channelResult = (channel, VideoGroup(videos: []))
        mock.channelsResult = [channel]
        let vm = ChannelViewModel(api: mock)
        await vm.loadAsync(channelId: channel.id, signedIn: true)
        #expect(vm.isSubscriptionLoaded)
        #expect(vm.channel?.isSubscribed == true)
        await vm.setSubscribed(false)
        #expect(vm.channel?.isSubscribed == false)
        await vm.setSubscribed(true)
        #expect(vm.channel?.isSubscribed == true)
        #expect(
            mock.calls.filter { $0.method == "setSubscribed" }.map(\.args) == [
                ["UCtarget", "false"], ["UCtarget", "true"],
            ])
        mock.errorToThrow = APIError.httpError(403)
        await vm.setSubscribed(false)
        #expect(vm.channel?.isSubscribed == true)
        #expect(vm.error != nil)
        #expect(!vm.isChangingSubscription)
    }

    @Test("Signed-out follow/unfollow persists locally without calling account mutation")
    func localMembership() async {
        let name = "SubscriptionStateTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let local = LocalSubscriptionStore(suiteName: name)
        let mock = MockInnerTubeAPI()
        mock.channelResult = (Channel(id: "UCtarget", title: "Target"), VideoGroup(videos: []))
        let vm = ChannelViewModel(api: mock, localSubscriptions: local)
        await vm.loadAsync(channelId: "UCtarget")
        await vm.setSubscribed(true)
        #expect(await local.isFollowing("UCtarget"))
        await vm.loadAsync(channelId: "UCtarget")
        #expect(vm.channel?.isSubscribed == true)
        await vm.setSubscribed(false)
        #expect(await !local.isFollowing("UCtarget"))
        #expect(!mock.calls.contains { $0.method == "setSubscribed" || $0.method == "fetchSubscribedChannels" })
    }

    @Test("An unknown membership cannot be toggled after a load failure")
    func failedStatusDisablesMutation() async {
        let mock = MockInnerTubeAPI()
        mock.errorToThrow = APIError.httpError(401)
        let vm = ChannelViewModel(api: mock)
        await vm.loadAsync(channelId: "UCtarget", signedIn: true)
        await vm.setSubscribed(true)
        #expect(!vm.isSubscriptionLoaded)
        #expect(!mock.calls.contains { $0.method == "setSubscribed" })
    }

    @Test("Removing one account channel preserves the list on failure and removes only that channel on success")
    func listMutation() async {
        let mock = MockInnerTubeAPI()
        let vm = BrowseViewModel(api: mock, initialSection: BrowseSection(type: .channels))
        await vm.updateAuthToken("test-token", reloadOnSignIn: false)
        let first = Channel(id: "UCfirst", title: "First")
        let second = Channel(id: "UCsecond", title: "Second")
        vm.subscribedChannels = [first, second]
        mock.errorToThrow = APIError.httpError(500)
        await vm.unsubscribe(from: first, signedIn: true)
        #expect(vm.subscribedChannels == [first, second])
        #expect(vm.error != nil)
        mock.errorToThrow = nil
        await vm.unsubscribe(from: first, signedIn: true)
        #expect(vm.subscribedChannels == [second])
        #expect(vm.error == nil)
        #expect(vm.changingSubscriptionIDs.isEmpty)
    }

    @Test("Empty authenticated channels and subscriptions do not request another sign-in")
    func emptyAccountLists() async throws {
        let mock = MockInnerTubeAPI()
        let vm = BrowseViewModel(api: mock)
        await vm.updateAuthToken("test-token", reloadOnSignIn: false)
        try await vm.fetchChannelsSection()
        #expect(vm.subscribedChannels.isEmpty)
        #expect(!vm.isAuthRequired)
        try await vm.fetchSubscriptionsSection()
        #expect(vm.videoGroups.isEmpty)
        #expect(!vm.isAuthRequired)
    }
}
