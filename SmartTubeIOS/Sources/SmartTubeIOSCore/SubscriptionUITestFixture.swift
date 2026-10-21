#if DEBUG
import Foundation

/// Exercises the real request/parsing path without touching an account or the network.
public enum SubscriptionUITestFixture {
    public static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--uitesting-subscriptions")
    }
}

final class SubscriptionUITestProtocol: URLProtocol, @unchecked Sendable {
    // URLProtocol's synchronous callbacks use only immutable request data and the locked State below.
    // Replace this bridge with a checked async transport if URLProtocol is retired from the test seam.
    private final class State: @unchecked Sendable {
        // Every read/write is under lock; an actor cannot serve these synchronous fixture callbacks.
        let lock = NSLock()
        var subscribed = Set(["UCfixtureAlpha", "UCfixtureBeta", "UCfixtureGamma"])
        var failedList = false
    }
    private static let state = State()
    private static let titles = [
        "UCfixtureAlpha": "Alpha Channel", "UCfixtureBeta": "Beta Channel", "UCfixtureGamma": "Gamma Channel",
    ]

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let payload = requestBody()
        let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        let response = fixtureResponse(body: body)
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        guard let url = request.url,
            let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
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

    private func fixtureResponse(body: [String: Any]) -> [String: Any] {
        Self.state.lock.lock()
        defer { Self.state.lock.unlock() }
        let path = request.url?.path ?? ""
        let arguments = ProcessInfo.processInfo.arguments
        let channelList =
            path.hasSuffix("/browse")
            && (body["browseId"] as? String == "FEsubscriptions" || body["continuation"] as? String == "fixture-next")
        if channelList || path.contains("/subscription/") {
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer subscription-fixture" else {
                return ["error": ["message": "Fixture requires account authorization."]]
            }
        }
        if channelList {
            if arguments.contains("--uitesting-subscriptions-load-error"), !Self.state.failedList {
                Self.state.failedList = true
                return ["error": ["message": "Subscription list unavailable."]]
            }
            let ids = arguments.contains("--uitesting-subscriptions-empty") ? [] : Self.state.subscribed.sorted()
            let page = body["continuation"] == nil ? Array(ids.prefix(2)) : Array(ids.dropFirst(2))
            var section: [String: Any] = [
                "tabs": page.map { id in
                    [
                        "tabRenderer": [
                            "title": Self.titles[id] ?? id,
                            "endpoint": ["browseEndpoint": ["browseId": id]],
                        ]
                    ]
                }
            ]
            if body["continuation"] == nil, ids.count > 2 {
                section["continuations"] = [["nextContinuationData": ["continuation": "fixture-next"]]]
            }
            return [
                "contents": [
                    "tvBrowseRenderer": [
                        "content": [
                            "tvSecondaryNavRenderer": ["sections": [["tvSecondaryNavSectionRenderer": section]]]
                        ]
                    ]
                ]
            ]
        }
        if path.contains("/subscription/"), let id = (body["channelIds"] as? [String])?.first {
            if arguments.contains("--uitesting-subscriptions-mutation-error") {
                return ["error": ["message": "Subscription change rejected."]]
            }
            if path.hasSuffix("/subscribe") { Self.state.subscribed.insert(id) }
            if path.hasSuffix("/unsubscribe") { Self.state.subscribed.remove(id) }
            return ["responseContext": [:]]
        }
        if let id = body["browseId"] as? String, let title = Self.titles[id] {
            return [
                "header": ["c4TabbedHeaderRenderer": ["title": title]],
                "metadata": ["channelMetadataRenderer": ["externalId": id, "title": title]],
                "contents": [:],
            ]
        }
        if path.hasSuffix("/next") {
            // The fixture feed has no per-card tokens, so card feedback fetches them here.
            return ["contents": ["NOT_INTERESTED", "DISLIKE", "BLOCK_CHANNEL"].map(Self.feedbackMenuItem)]
        }
        return ["responseContext": [:]]
    }

    private static func feedbackMenuItem(_ iconType: String) -> [String: Any] {
        [
            "menuServiceItemRenderer": [
                "icon": ["iconType": iconType],
                "serviceEndpoint": ["feedbackEndpoint": ["feedbackToken": "fixture-\(iconType)"]],
            ]
        ]
    }
}
#endif
