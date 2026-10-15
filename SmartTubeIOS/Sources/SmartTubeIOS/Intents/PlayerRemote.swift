#if os(iOS)
import Foundation

// MARK: - PlayerRemote (App Intents)
//
// Lets the player-control App Intents (play/pause, skip, next video) act on whichever
// player is open without bringing the app forward. AppEntry attaches the player
// store at launch; each call returns false when nothing is playing.

@MainActor
public enum PlayerRemote {
    private static weak var playerState: PlayerStateStore?

    public static func attach(playerState: PlayerStateStore) {
        self.playerState = playerState
    }

    private static var playbackVM: PlaybackViewModel? {
        guard let playerState, playerState.presentation != .hidden else { return nil }
        return playerState.vm
    }

    @discardableResult
    public static func togglePlayPause() -> Bool {
        if let vm = playbackVM {
            vm.togglePlayPause()
            return true
        }
        return false
    }

    @discardableResult
    public static func skip(by seconds: TimeInterval) -> Bool {
        if let vm = playbackVM {
            vm.seekRelative(seconds: seconds)
            return true
        }
        return false
    }

    @discardableResult
    public static func playNext() -> Bool {
        if let vm = playbackVM {
            vm.playNext()
            return true
        }
        return false
    }
}
#endif
