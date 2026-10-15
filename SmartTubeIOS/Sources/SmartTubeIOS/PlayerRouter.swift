#if os(iOS)
import Foundation
import SmartTubeIOSCore

// MARK: - PlayerRouter
//
// Single "open this video" decision point for iOS. Every place in the app that
// lets the user tap a video (Home, Search, Browse, Channel, Playlist, Library,
// RSS, and the deep-link / Share-Extension handlers in RootView) calls
// `open(video:api:)` instead of reaching into `PlayerStateStore` directly.
@MainActor
@Observable
public final class PlayerRouter {
    private let playerState: PlayerStateStore

    public init(playerState: PlayerStateStore) {
        self.playerState = playerState
    }

    /// Open `video` in the AVPlayer pipeline. `incognito` (#94) is accepted for
    /// call-site compatibility but the AVPlayer pipeline's history recording
    /// isn't wired to it yet (see OPEN_QUESTIONS).
    public func open(video: Video, api: InnerTubeAPI, incognito: Bool = false) {
        playerState.play(video: video)
    }
}
#endif  // os(iOS)
