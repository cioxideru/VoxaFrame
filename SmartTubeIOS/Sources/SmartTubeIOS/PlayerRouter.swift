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
    private let settingsStore: SettingsStore

    public init(playerState: PlayerStateStore, settingsStore: SettingsStore) {
        self.playerState = playerState
        self.settingsStore = settingsStore
    }

    /// Open `video` in the AVPlayer pipeline. `incognito` (#94) skips history,
    /// watchtime and resume-position recording for this video only.
    public func open(video: Video, api: InnerTubeAPI, incognito: Bool = false) {
        playerState.play(video: video, settings: settingsStore.settings, incognito: incognito)
    }
}
#endif  // os(iOS)
