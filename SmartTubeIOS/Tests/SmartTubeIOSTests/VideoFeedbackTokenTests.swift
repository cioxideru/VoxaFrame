import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - VideoFeedbackTokenTests (PLAN-0039, PLAN-0045)
//
// Card feedback hides a video or blocks a channel only after YouTube got the request. TV feed menus have no icon
// types: tokens are recognised by what their command does, inline (older tiles) or from `get_panel` (2026-09 tiles).
// The menu shapes below follow the TV responses recorded by Android SmartTube (MediaServiceCore test resources
// `2025.07.30_home_continuation.json`, `history_25.01.2023.json`, `2026.09.20_engagementPanel.json`).

private final class FeedbackStubProtocol: URLProtocol, @unchecked Sendable {
    struct Request {
        let path: String
        let body: [String: Any]
    }

    // The serialized suite sets the responses before awaiting requests; callbacks only read them.
    nonisolated(unsafe) static var responses: [String: Data] = [:]
    // Written by URLSession callbacks before each request completes; the suite reads only after await.
    nonisolated(unsafe) static var requests: [Request] = []

    static func reset(_ responses: [String: [String: Any]] = [:]) {
        self.responses = responses.compactMapValues { try? JSONSerialization.data(withJSONObject: $0) }
        requests = []
    }

    static var paths: [String] { requests.map(\.path) }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        let endpoint = url.path.replacingOccurrences(of: "/youtubei/v1/", with: "")
        let body = (try? JSONSerialization.jsonObject(with: requestBody())) as? [String: Any] ?? [:]
        Self.requests.append(Request(path: endpoint, body: body))
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responses[endpoint] ?? Data(#"{"responseContext":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func requestBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

// MARK: - Menu shapes

private enum Menu {
    static var dismissal: [[String: Any]] {
        [
            ["openClientOverlayAction": ["type": "CLIENT_OVERLAY_TYPE_DISMISSAL_FOLLOW_UP", "context": "v1"]]
        ]
    }

    /// "Don't recommend channel": the token sits in the popup's Confirm command.
    static func channelPopup(_ token: String) -> [String: Any] {
        let confirm: [String: Any] = [
            "compactLinkRenderer": [
                "title": ["runs": [["text": "Confirm"]]],
                "serviceEndpoint": [
                    "commandExecutorCommand": [
                        "commands": [
                            [
                                "feedbackEndpoint": [
                                    "feedbackToken": token, "actions": [["removeItemAction": ["childId": "v1"]]],
                                ]
                            ],
                            ["signalAction": ["signal": "CLOSE_POPUP"]],
                        ]
                    ]
                ],
            ]
        ]
        let panel: [String: Any] = ["content": ["overlayPanelItemListRenderer": ["items": [confirm]]]]
        return [
            "openPopupAction": [
                "popup": [
                    "overlaySectionRenderer": [
                        "overlay": ["overlayTwoPanelRenderer": ["actionPanel": ["overlayPanelRenderer": panel]]]
                    ]
                ]
            ]
        ]
    }

    /// An older TV tile menu item (`menuServiceItemRenderer`).
    static func service(
        _ title: String, serviceEndpoint: [String: Any]? = nil, command: [String: Any]? = nil
    )
        -> [String: Any]
    {
        var renderer: [String: Any] = ["text": ["runs": [["text": title]]]]
        renderer["serviceEndpoint"] = serviceEndpoint
        renderer["command"] = command
        return ["menuServiceItemRenderer": renderer]
    }

    /// A `get_panel` list item (`listItemViewModel`).
    static func listItem(_ title: String, _ command: [String: Any]) -> [String: Any] {
        [
            "listItemViewModel": [
                "title": ["content": title],
                "rendererContext": ["commandContext": ["onTap": ["innertubeCommand": command]]],
            ]
        ]
    }

    static func panelResponse(_ items: [[String: Any]]) -> [String: Any] {
        ["content": ["engagementPanelSectionListRenderer": ["content": ["listViewModel": ["listItems": items]]]]]
    }

    static var homePanel: [String: Any] {
        panelResponse([
            listItem("Play", ["watchEndpoint": ["videoId": "v1"]]),
            listItem(
                "Save to Watch later",
                ["playlistEditEndpoint": ["playlistId": "WL", "actions": [["addedVideoId": "v1"]]]]),
            listItem("Not interested", ["feedbackEndpoint": ["feedbackToken": "panel-video", "actions": dismissal]]),
            listItem("Don't recommend channel", channelPopup("panel-channel")),
        ])
    }

    static func tile(longPress: [String: Any], menu: [String: Any]? = nil) -> [String: Any] {
        var tile: [String: Any] = [
            "contentType": "TILE_CONTENT_TYPE_VIDEO",
            "onSelectCommand": ["watchEndpoint": ["videoId": "v1"]],
            "metadata": ["tileMetadataRenderer": ["title": ["simpleText": "Tile"]]],
            "onLongPressCommand": longPress,
        ]
        tile["menu"] = menu
        return tile
    }

    static func feed(_ tile: [String: Any]) -> [String: Any] {
        [
            "contents": [
                "sectionListRenderer": [
                    "contents": [["itemSectionRenderer": ["contents": [["tileRenderer": tile]]]]]
                ]
            ]
        ]
    }
}

// MARK: - Parsing

@Suite("TV menu feedback tokens")
struct TVMenuFeedbackTokenParsingTests {
    @Test("An inline tile menu yields the video and channel tokens")
    func inlineTileMenu() async throws {
        let items: [[String: Any]] = [
            Menu.service("Save to Watch later", serviceEndpoint: ["playlistEditEndpoint": ["playlistId": "WL"]]),
            Menu.service(
                "Not interested",
                serviceEndpoint: ["feedbackEndpoint": ["feedbackToken": "inline-video", "actions": Menu.dismissal]]),
            Menu.service("Don't recommend channel", command: Menu.channelPopup("inline-channel")),
        ]
        let tile = Menu.tile(longPress: ["showMenuCommand": ["menu": ["menuRenderer": ["items": items]]]])
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(Menu.feed(tile), title: "Home")
        let video = try #require(group.videos.first)
        #expect(video.notInterestedToken == "inline-video")
        #expect(video.hideChannelToken == "inline-channel")
        #expect(video.feedbackPanel == nil)
    }

    @Test("A 2026 tile carries its menu panel and no tokens")
    func panelTile() async throws {
        let endpoint: [String: Any] = [
            "identifier": ["tag": "PAcontext_menu"],
            "globalConfiguration": ["params": "-golCgtOTzZaQjlpRjhrYyCeAUITCAISD0ZFd2hhdF90b193YXRjaA%3D%3D"],
        ]
        let tile = Menu.tile(longPress: ["showEngagementPanelEndpoint": endpoint])
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(Menu.feed(tile), title: "Home")
        let video = try #require(group.videos.first)
        #expect(
            video.feedbackPanel
                == FeedbackPanel(
                    id: "PAcontext_menu", params: "-golCgtOTzZaQjlpRjhrYyCeAUITCAISD0ZFd2hhdF90b193YXRjaA%3D%3D"))
        #expect(video.notInterestedToken == nil)
        #expect(video.hideChannelToken == nil)
    }

    @Test("Subscriptions' Hide counts as Not Interested")
    func subscriptionsHide() {
        let hide: [String: Any] = [
            "feedbackToken": "hide", "actions": [["replaceEnclosingAction": ["item": [:]]]],
        ]
        let tokens = TVMenuFeedbackTokens(menuItems: [Menu.service("Hide", serviceEndpoint: ["feedbackEndpoint": hide])]
        )
        #expect(tokens == TVMenuFeedbackTokens(notInterested: "hide"))
    }

    @Test("Remove from watch history is never taken for Not Interested")
    func historyRemoval() {
        let remove: [String: Any] = [
            "feedbackToken": "history", "uiActions": ["hideEnclosingContainer": true],
            "actions": [["openPopupAction": ["popupType": "TOAST"]]],
        ]
        let tokens = TVMenuFeedbackTokens(menuItems: [
            Menu.service("Remove from watch history", serviceEndpoint: ["feedbackEndpoint": remove])
        ])
        #expect(tokens == TVMenuFeedbackTokens())
    }

    @Test("A get_panel list yields the video and channel tokens")
    func panelList() throws {
        let items = try #require(
            ((((Menu.homePanel["content"] as? [String: Any])?["engagementPanelSectionListRenderer"] as? [String: Any])?[
                "content"] as? [String: Any])?["listViewModel"] as? [String: Any])?["listItems"] as? [[String: Any]])
        #expect(
            TVMenuFeedbackTokens(menuItems: items)
                == TVMenuFeedbackTokens(notInterested: "panel-video", dontRecommendChannel: "panel-channel"))
    }
}

// MARK: - Sending

@Suite("Video feedback token", .serialized)
struct VideoFeedbackTokenTests {
    private let panel = FeedbackPanel(id: "PAcontext_menu", params: "params-1")

    private func makeAPI() -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedbackStubProtocol.self]
        return InnerTubeAPI(authToken: "fake-token", session: URLSession(configuration: config))
    }

    private func sentTokens() -> [String] {
        FeedbackStubProtocol.requests.filter { $0.path == "feedback" }.flatMap {
            $0.body["feedbackTokens"] as? [String] ?? []
        }
    }

    @Test("No token and no panel throws and sends nothing")
    func missingTokenThrows() async {
        FeedbackStubProtocol.reset()
        await #expect(throws: InnerTubeAPI.VideoFeedbackError.tokenUnavailable) {
            try await makeAPI().sendFeedback(.notInterested, for: Video(id: "abc", title: "", channelTitle: ""))
        }
        #expect(FeedbackStubProtocol.requests.isEmpty)
    }

    @Test("An inline token is sent without loading the panel")
    func inlineTokenIsSent() async throws {
        FeedbackStubProtocol.reset()
        let video = Video(
            id: "abc", title: "", channelTitle: "", notInterestedToken: "t1", feedbackPanel: panel)
        try await makeAPI().sendFeedback(.notInterested, for: video)
        #expect(FeedbackStubProtocol.paths == ["feedback"])
        #expect(sentTokens() == ["t1"])
    }

    @Test(
        "Without inline tokens the panel's tokens are sent",
        arguments: [
            (VideoFeedbackAction.notInterested, "panel-video"), (.dontRecommendChannel, "panel-channel"),
        ])
    func panelTokenIsSent(action: VideoFeedbackAction, token: String) async throws {
        FeedbackStubProtocol.reset(["get_panel": Menu.homePanel])
        try await makeAPI().sendFeedback(
            action, for: Video(id: "v1", title: "", channelTitle: "", feedbackPanel: panel))
        #expect(FeedbackStubProtocol.paths == ["get_panel", "feedback"])
        let request = try #require(FeedbackStubProtocol.requests.first)
        #expect(request.body["panelId"] as? String == "PAcontext_menu")
        #expect(request.body["params"] as? String == "params-1")
        let client = (request.body["context"] as? [String: Any])?["client"] as? [String: Any]
        #expect(client?["clientName"] as? String == InnerTubeClients.TV.name)
        #expect(sentTokens() == [token])
    }

    @Test("A panel without the action's token throws and sends nothing")
    func panelWithoutToken() async {
        FeedbackStubProtocol.reset(["get_panel": Menu.panelResponse([Menu.listItem("Play", [:])])])
        await #expect(throws: InnerTubeAPI.VideoFeedbackError.tokenUnavailable) {
            try await makeAPI().sendFeedback(
                .notInterested, for: Video(id: "v1", title: "", channelTitle: "", feedbackPanel: panel))
        }
        #expect(FeedbackStubProtocol.paths == ["get_panel"])
    }

    @Test("Don't Like without a token rates the video down")
    func dontLikeDislikes() async throws {
        FeedbackStubProtocol.reset()
        try await makeAPI().sendFeedback(
            .dontLike, for: Video(id: "v1", title: "", channelTitle: "", feedbackPanel: panel))
        #expect(FeedbackStubProtocol.paths == ["like/dislike"])
        let target = FeedbackStubProtocol.requests.first?.body["target"] as? [String: Any]
        #expect(target?["videoId"] as? String == "v1")
    }

    @Test("Don't Like sends the feed's DISLIKE token when there is one")
    func dontLikeToken() async throws {
        FeedbackStubProtocol.reset()
        try await makeAPI().sendFeedback(
            .dontLike, for: Video(id: "v1", title: "", channelTitle: "", dontLikeToken: "dislike-token"))
        #expect(FeedbackStubProtocol.paths == ["feedback"])
        #expect(sentTokens() == ["dislike-token"])
    }

    @Test("An error answer is not a sent feedback")
    func rejectedFeedback() async {
        FeedbackStubProtocol.reset(["feedback": ["error": ["message": "Request contains an invalid argument."]]])
        await #expect(throws: InnerTubeAPI.VideoFeedbackError.rejected) {
            try await makeAPI().sendFeedback(token: "t1")
        }
    }

    @Test("Unprocessed feedback is not a sent feedback")
    func unprocessedFeedback() async {
        FeedbackStubProtocol.reset(["feedback": ["feedbackResponses": [["isProcessed": false]]]])
        await #expect(throws: InnerTubeAPI.VideoFeedbackError.rejected) {
            try await makeAPI().sendFeedback(token: "t1")
        }
    }

    @Test("A rejected dislike throws")
    func rejectedDislike() async {
        FeedbackStubProtocol.reset(["like/dislike": ["error": ["message": "Login required."]]])
        await #expect(throws: APIError.self) {
            try await makeAPI().sendFeedback(.dontLike, for: Video(id: "v1", title: "", channelTitle: ""))
        }
    }
}
