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
        #if DEBUG
        var video = video
        video.localFileURL = video.localFileURL ?? ShortsPlaybackUITestFixture.localFileURL
        #endif
        playerState.play(video: video, settings: settingsStore.settings, incognito: incognito)
    }

    /// Current Queue position of the video the app player is playing; `nil` when it plays nothing from the queue.
    /// Card menus pass it to `CurrentQueueStore.playNext(_:playingIndex:)`.
    var playingQueueIndex: Int? {
        CurrentQueueStore.queueIndex(of: playerState.currentVideo)
    }
}
#endif  // os(iOS)
