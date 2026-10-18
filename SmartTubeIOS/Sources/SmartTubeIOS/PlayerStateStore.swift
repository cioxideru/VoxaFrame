#if os(iOS)
import AVFoundation
import AVKit
import UIKit
import Observation
import SmartTubeIOSCore
import OSLog

private let storeLog = Logger(subsystem: "com.void.smarttube.app", category: "PlayerStateStore")

// MARK: - PersistentPlayerHostView

/// A UIView that owns an AVPlayerLayer for the lifetime of the app.
/// Its reference lives in PlayerStateStore, so the layer — and the AVPlayer
/// connection — survive PlayerView dismiss/re-present cycles (mini-player).
///
/// Embed it as a subview in full-screen and mini-player contexts.
/// UIView.addSubview automatically removes it from the previous parent,
/// so no explicit removeFromSuperview is needed when transplanting.
final class PersistentPlayerHostView: UIView {

    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            fatalError("layerClass must create an AVPlayerLayer")
        }
        return playerLayer
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

}

// MARK: - PlayerStateStore

/// Centralised iOS playback state for the in-app mini-player.
///
/// Owns the single `PlaybackViewModel` and `PersistentPlayerHostView` so they
/// survive PlayerView presentation/dismiss cycles. Injected as an environment
/// object at the `AppEntry` level; accessed via `@Environment(PlayerStateStore.self)`.
@MainActor
@Observable
public final class PlayerStateStore {

    // MARK: - Presentation state

    public enum Presentation: Equatable {
        case hidden
        case miniPlayer
        case fullScreen
        case pictureInPicture
    }

    public internal(set) var presentation: Presentation = .hidden

    /// The active playback request; stop keeps the item parked but ends its presentation.
    var currentVideo: Video? {
        vm.parkedVideoId == nil ? vm.currentVideo : nil
    }

    /// Loading a different video clears the old item; recovery can retain a ready item.
    var playingVideo: Video? {
        currentVideo == nil ? nil : vm.displayedVideo
    }

    // MARK: - Imperative dismiss hook

    /// Set by LandscapePresenter's coordinator when a full-screen player is presented.
    /// Fired imperatively by minimize() / stop() to bypass the SwiftUI update-propagation
    /// pause that occurs when the presenting VC's view is removed from the window by
    /// UIKit's .fullScreen presentation style (so updateUIViewController never fires).
    var dismissPlayerAction: (() -> Void)?

    // MARK: - Owned objects

    /// The single PlaybackViewModel for the app. Lives for the app's lifetime.
    public let vm: PlaybackViewModel

    /// The UIView that owns the AVPlayerLayer. Never deallocated; transplanted
    /// between full-screen and mini-player containers via UIView.addSubview.
    let playerHostView: PersistentPlayerHostView

    var pipController: AVPictureInPictureController?
    var isPiPActive = false
    @ObservationIgnored var pipDelegate: PiPDelegate?
    @ObservationIgnored var pipRestoreCompletion: ((Bool) -> Void)?

    // MARK: - Init

    public init(api: InnerTubeAPI) {
        let vm = PlaybackViewModel(api: api)
        self.vm = vm
        let hostView = PersistentPlayerHostView()
        hostView.playerLayer.player = vm.player
        self.playerHostView = hostView
    }

    // MARK: - Actions

    /// Load `video` (if not already loaded) and present the full-screen player.
    /// `settings` is applied before `load` so the first stream request uses the current
    /// preferences (codecs, speed, audio-only). `incognito` (#94) skips history,
    /// watchtime and resume-position recording for this video.
    public func play(video: Video, settings: AppSettings, incognito: Bool = false) {
        storeLog.notice(
            "[PlayerStateStore] play — id=\(video.id) currentPresentation=\(String(describing: self.presentation))")
        vm.updateSettings(settings)
        successorCheck?.cancel()
        // Also reload when:
        //   1. Different video — always load
        //   2. No current item — item was cleared by stop() (legacy path)
        //   3. Not playing — item is parked (fix12 park path): stop() keeps the
        //      AVPlayerItem alive but pauses and sets isPlaying=false. On re-tap,
        //      call load() so the park fast-path in PlaybackViewModel resumes it.
        // A privacy-mode change needs a fresh tracking session even for the same video.
        let sameSource = vm.currentVideo?.hasSamePlaybackSource(as: video) == true
        // Before `load`: its duplicate-loading guard keeps the item it is still loading, with the old position.
        if sameSource { adoptQueueContext(of: video) }
        if !sameSource || vm.isIncognito != incognito || vm.player.currentItem == nil || !vm.isPlaying {
            vm.load(video: video, incognito: incognito)
        }
        expand()
        storeLog.notice("[PlayerStateStore] play — presentation set to .fullScreen")
    }

    /// The Current Queue checked for a successor (`.shared` in the app; tests give the store their own).
    @ObservationIgnored var queue = CurrentQueueStore.shared

    /// The playing video picked again from another list keeps playing but takes that list's position, so Play Next
    /// and auto-advance follow the queue the user started it from last. A successor in that queue enables Next
    /// (button, swipe, remote command) as `load` would.
    private func adoptQueueContext(of video: Video) {
        guard var current = vm.currentVideo,
            current.playlistId != video.playlistId || current.playlistIndex != video.playlistIndex
                || current.setVideoId != video.setVideoId
        else { return }
        current.playlistId = video.playlistId
        current.playlistIndex = video.playlistIndex
        current.setVideoId = video.setVideoId
        vm.currentVideo = current
        guard let index = CurrentQueueStore.queueIndex(of: current) else { return }
        // Cancelled by stop() and by the next play(); stop() keeps currentVideo, so the checks after the await
        // also require the same video, still at `index`, not parked.
        successorCheck = Task { [vm, queue] in
            let hasSuccessor = await queue.videoAt(index: index + 1) != nil
            guard hasSuccessor, !Task.isCancelled, vm.parkedVideoId == nil,
                vm.currentVideo?.hasSamePlaybackSource(as: current) == true,
                CurrentQueueStore.queueIndex(of: vm.currentVideo) == index, !vm.hasNext
            else { return }
            vm.hasNext = true
            vm.updateNowPlayingInfo()
        }
    }

    @ObservationIgnored private(set) var successorCheck: Task<Void, Never>?

    /// Collapse the full-screen player to the mini-player bar. Playback continues.
    public func minimize() {
        storeLog.notice("[PlayerStateStore] minimize — currentPresentation=\(String(describing: self.presentation))")
        presentation = isPiPActive ? .pictureInPicture : .miniPlayer
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        storeLog.notice(
            "[PlayerStateStore] minimize — presentation set to .miniPlayer, dismissPlayerAction=\(action != nil)")
        action?()
    }

    /// Expand the mini-player back to full-screen.
    func expand() {
        storeLog.notice("[PlayerStateStore] expand — currentPresentation=\(String(describing: self.presentation))")
        if isPiPActive, pipRestoreCompletion == nil {
            pipRestoreCompletion = { [weak controller = pipController] restored in
                if restored { controller?.stopPictureInPicture() }
            }
        }
        presentation = .fullScreen
        storeLog.notice("[PlayerStateStore] expand — presentation set to .fullScreen")
    }

    /// Stop playback completely and hide the player UI.
    func stop() {
        storeLog.notice("[PlayerStateStore] stop — currentPresentation=\(String(describing: self.presentation))")
        pipRestoreCompletion?(false)
        pipRestoreCompletion = nil
        pipController?.stopPictureInPicture()
        successorCheck?.cancel()
        vm.stop()
        presentation = .hidden
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        storeLog.notice("[PlayerStateStore] stop — presentation set to .hidden, dismissPlayerAction=\(action != nil)")
        action?()
    }
}
#endif
