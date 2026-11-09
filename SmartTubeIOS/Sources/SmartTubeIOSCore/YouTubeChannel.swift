import Foundation

// MARK: - YouTubeChannel
//
// One identity of the signed-in Google account: the primary channel or a Brand Account.
// The OAuth token always belongs to the primary account; a Brand Account is selected per
// request via `X-Goog-Pageid` (see ActiveChannel), mirroring SmartTube Android.

public struct YouTubeChannel: Sendable, Hashable, Identifiable {
    public let name: String
    public let avatarURL: URL?
    /// nil for the primary account.
    public let pageId: String?

    public var id: String { pageId ?? "primary" }
    public var isPrimary: Bool { pageId == nil }

    public init(name: String, avatarURL: URL?, pageId: String?) {
        self.name = name
        self.avatarURL = avatarURL
        self.pageId = pageId
    }

    /// Parses every account of an `account/accounts_list` response (requested with
    /// `returnBrandAccounts: true`). Same JSON path as Android's AccountInt.java.
    public static func list(fromAccountsList json: [String: Any]) -> [YouTubeChannel] {
        guard let contents = json["contents"] as? [[String: Any]],
            let sectionListRenderer = contents.first?["accountSectionListRenderer"] as? [String: Any],
            let sectionContents = sectionListRenderer["contents"] as? [[String: Any]],
            let itemSectionRenderer = sectionContents.first?["accountItemSectionRenderer"] as? [String: Any],
            let items = itemSectionRenderer["contents"] as? [[String: Any]]
        else { return [] }
        return items.compactMap { ($0["accountItem"] as? [String: Any]).flatMap(channel(fromAccountItem:)) }
    }

    static func channel(fromAccountItem item: [String: Any]) -> YouTubeChannel? {
        let nameDict = item["accountName"] as? [String: Any]
        guard
            let name = (nameDict?["runs"] as? [[String: Any]])?.compactMap({ $0["text"] as? String }).joined()
                ?? nameDict?["simpleText"] as? String
        else { return nil }
        let thumbnails = (item["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let avatar = thumbnails?.last?["url"] as? String
        let endpoint = (item["serviceEndpoint"] as? [String: Any])?["selectActiveIdentityEndpoint"] as? [String: Any]
        let pageId = (endpoint?["supportedTokens"] as? [[String: Any]])?
            .compactMap { ($0["pageIdToken"] as? [String: Any])?["pageId"] as? String }.first
        return YouTubeChannel(
            name: name,
            avatarURL: avatar.flatMap { URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0) },
            pageId: pageId
        )
    }
}
