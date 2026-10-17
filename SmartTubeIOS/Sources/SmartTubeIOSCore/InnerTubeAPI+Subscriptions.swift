import Foundation

extension InnerTubeAPI {
    func parseSubscriptionNavigation(_ response: [String: Any]) throws -> (channels: [Channel], continuation: String?) {
        var sections: [[String: Any]] = []
        func collect(_ value: Any, depth: Int = 0) {
            guard depth < 50 else { return }
            if let object = value as? [String: Any] {
                for key in ["tvSecondaryNavSectionRenderer", "tvSecondaryNavSectionContinuation"] {
                    if let section = object[key] as? [String: Any] {
                        sections.append(section)
                        return
                    }
                }
                for child in object.values { collect(child, depth: depth + 1) }
            } else if let array = value as? [Any] {
                for child in array { collect(child, depth: depth + 1) }
            }
        }
        collect(response)
        guard !sections.isEmpty else { throw APIError.decodingError("Missing subscriptions navigation.") }
        var channels: [Channel] = []
        var continuation: String?
        for section in sections {
            guard let tabs = section["tabs"] as? [[String: Any]] else {
                throw APIError.decodingError("Missing subscription channel tabs.")
            }
            for item in tabs {
                guard let tab = item["tabRenderer"] as? [String: Any],
                    let endpoint = (tab["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
                    let browseID = endpoint["browseId"] as? String
                else { continue }
                let id: String?
                if browseID.hasPrefix("UC") {
                    id = browseID
                } else if browseID == "FEsubscriptions", let params = endpoint["params"] as? String {
                    id = try subscriptionChannelID(params)
                } else {
                    continue  // The unfiltered All tab has no channel parameter.
                }
                guard let id else { continue }
                let thumbnails = (tab["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
                let thumbnailURL = (thumbnails?.last?["url"] as? String).flatMap {
                    URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0)
                }
                channels.append(
                    Channel(
                        id: id, title: tab["title"] as? String ?? "", thumbnailURL: thumbnailURL, isSubscribed: true))
            }
            // Video continuations inside the selected tab do not paginate the channel list.
            for item in section["continuations"] as? [[String: Any]] ?? [] {
                if let next = (item["nextContinuationData"] as? [String: Any])?["continuation"] as? String {
                    guard continuation == nil || continuation == next else {
                        throw APIError.decodingError("Ambiguous subscription channel continuation.")
                    }
                    continuation = next
                }
            }
        }
        return (channels, continuation)
    }

    private func subscriptionChannelID(_ params: String) throws -> String? {
        let encoded = (params.removingPercentEncoding ?? params)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else {
            throw APIError.decodingError("Invalid subscription channel parameter.")
        }
        let bytes = Array(data)
        // TV FEsubscriptions: length-delimited field 49 contains field 1 (the channel ID).
        if bytes == [0x8A, 0x03, 0x00] { return nil }  // Older All tab.
        guard bytes.count >= 5, bytes[0] == 0x8A, bytes[1] == 0x03,
            Int(bytes[2]) == bytes.count - 3, bytes[3] == 0x0A, Int(bytes[4]) == bytes.count - 5,
            let id = String(data: data.dropFirst(5), encoding: .utf8), id.hasPrefix("UC"),
            id.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            })
        else { throw APIError.decodingError("Unsupported subscription channel parameter.") }
        return id
    }

    public func setSubscribed(channelId: String, subscribed: Bool) async throws {
        guard let token = authToken else { throw APIError.notAuthenticated }
        let id = channelId.hasPrefix("@") ? try await fetchChannel(channelId: channelId).channel.id : channelId
        guard id.hasPrefix("UC") else { throw APIError.unavailable("Could not identify this channel.") }
        var body = makeBody(client: tvClientContext)
        body["channelIds"] = [id]
        let response = try await postTV(
            endpoint: subscribed ? "subscription/subscribe" : "subscription/unsubscribe", body: body,
            explicitBearerToken: token)
        try checkSubscriptionResponse(response)
    }

    func checkSubscriptionResponse(_ response: [String: Any]) throws {
        if let error = response["error"] as? [String: Any] {
            throw APIError.unavailable(error["message"] as? String ?? "Could not update subscriptions.")
        }
        for alert in response["alerts"] as? [[String: Any]] ?? [] {
            if let renderer = alert["alertRenderer"] as? [String: Any], renderer["type"] as? String == "ERROR" {
                throw APIError.unavailable(
                    (renderer["text"] as? [String: Any]).flatMap { extractText($0) }
                        ?? "Could not update subscriptions.")
            }
        }
    }
}

public extension InnerTubeAPIProtocol {
    /// Account and local subscriptions are separate; publish a change only after its owner saves it.
    @MainActor
    func changeSubscription(
        channel: Channel, subscribed: Bool, signedIn: Bool,
        localStore: LocalSubscriptionStore = .shared
    ) async throws {
        if signedIn {
            try await setSubscribed(channelId: channel.id, subscribed: subscribed)
        } else if subscribed {
            await localStore.follow(
                LocalChannel(id: channel.id, title: channel.title, thumbnailURL: channel.thumbnailURL))
        } else {
            await localStore.unfollow(channelId: channel.id)
            await LocalSubscriptionFeedCache.shared.invalidate(channelId: channel.id)
        }
        NotificationCenter.default.post(
            name: .subscriptionsDidChange, object: nil,
            userInfo: ["channel": channel, "subscribed": subscribed, "signedIn": signedIn])
    }
}
