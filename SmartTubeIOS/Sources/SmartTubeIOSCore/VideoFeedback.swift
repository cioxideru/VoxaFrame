import Foundation

// MARK: - Card feedback (PLAN-0045)
//
// TV feed menus carry no icon types, so a token is identified by what its command does. Home's "Not interested" and
// Subscriptions' "Hide" send their `feedbackEndpoint` directly and dismiss the card with a follow-up; "Don't recommend
// channel" sends it from the confirmation of an `openPopupAction`; History's "Remove from watch history" sends it
// directly with only a toast, so it is never taken for "Not interested". Newer tiles (2026-09) carry no menu at all,
// only a `showEngagementPanelEndpoint` whose `get_panel` response holds the same items as `listItemViewModel`s.

/// A feedback command in a video card menu.
public enum VideoFeedbackAction: Sendable, CaseIterable {
    case notInterested
    case dontLike
    case dontRecommendChannel
}

/// The TV menu panel that holds a card's feedback tokens. `InnerTubeAPI.sendFeedback(_:for:)` loads it with
/// `get_panel` when the feed sent no tokens inline.
public struct FeedbackPanel: Hashable, Codable, Sendable {
    public let id: String
    public let params: String

    public init(id: String, params: String) {
        self.id = id
        self.params = params
    }

    /// `tileRenderer.onLongPressCommand.showEngagementPanelEndpoint` — `identifier.tag` and `globalConfiguration.params`.
    init?(tile: [String: Any]) {
        let endpoint = (tile["onLongPressCommand"] as? [String: Any])?["showEngagementPanelEndpoint"] as? [String: Any]
        guard let id = (endpoint?["identifier"] as? [String: Any])?["tag"] as? String, !id.isEmpty,
            let params = (endpoint?["globalConfiguration"] as? [String: Any])?["params"] as? String, !params.isEmpty
        else { return nil }
        self.init(id: id, params: params)
    }
}

extension Video {
    /// The card feedback a TV tile offers: inline menu tokens (older tiles) or its menu panel (2026-09 tiles).
    func addingTVMenuFeedback(of tile: [String: Any]) -> Video {
        var video = self
        let tokens = TVMenuFeedbackTokens(tile: tile)
        video.notInterestedToken = tokens.notInterested
        video.hideChannelToken = tokens.dontRecommendChannel
        video.feedbackPanel = FeedbackPanel(tile: tile)
        return video
    }
}

/// The feedback tokens of one TV card menu: inline `menuServiceItemRenderer`s or `get_panel` `listItemViewModel`s.
struct TVMenuFeedbackTokens: Equatable {
    var notInterested: String?
    var dontRecommendChannel: String?

    init(notInterested: String? = nil, dontRecommendChannel: String? = nil) {
        self.notInterested = notInterested
        self.dontRecommendChannel = dontRecommendChannel
    }

    /// Tokens from a tile's own menu: `menu` and `onLongPressCommand.showMenuCommand.menu`.
    init(tile: [String: Any]) {
        let showMenu = (tile["onLongPressCommand"] as? [String: Any])?["showMenuCommand"] as? [String: Any]
        let menus = [tile["menu"], showMenu?["menu"]].compactMap { $0 as? [String: Any] }
        self.init(
            menuItems: menus.flatMap { ($0["menuRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? [] })
    }

    init(menuItems: [[String: Any]]) {
        for command in menuItems.flatMap(Self.commands(of:)) {
            if let endpoint = command["feedbackEndpoint"] as? [String: Any] {
                if notInterested == nil, Self.dismissesCard(endpoint) {
                    notInterested = endpoint["feedbackToken"] as? String
                }
            } else if dontRecommendChannel == nil, let popup = command["openPopupAction"] {
                dontRecommendChannel = Self.firstFeedbackToken(in: popup)
            }
        }
    }

    /// The commands one menu item runs.
    private static func commands(of item: [String: Any]) -> [[String: Any]] {
        if let service = item["menuServiceItemRenderer"] as? [String: Any] {
            return ["serviceEndpoint", "command"].compactMap { service[$0] as? [String: Any] }
        }
        let context = (item["listItemViewModel"] as? [String: Any])?["rendererContext"] as? [String: Any]
        let onTap = (context?["commandContext"] as? [String: Any])?["onTap"] as? [String: Any]
        return [onTap?["innertubeCommand"]].compactMap { $0 as? [String: Any] }
    }

    /// "Not interested" opens the dismissal follow-up, "Hide" replaces the card; a toast alone is a history removal.
    private static func dismissesCard(_ endpoint: [String: Any]) -> Bool {
        (endpoint["actions"] as? [[String: Any]] ?? []).contains {
            $0["openClientOverlayAction"] != nil || $0["replaceEnclosingAction"] != nil
        }
    }

    private static func firstFeedbackToken(in value: Any, depth: Int = 0) -> String? {
        guard depth < 20 else { return nil }
        if let dict = value as? [String: Any] {
            if let token = (dict["feedbackEndpoint"] as? [String: Any])?["feedbackToken"] as? String { return token }
            return dict.values.lazy.compactMap { firstFeedbackToken(in: $0, depth: depth + 1) }.first
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { firstFeedbackToken(in: $0, depth: depth + 1) }.first
        }
        return nil
    }
}
