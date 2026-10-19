#if os(iOS)
import AVFoundation
import AVKit
import UIKit
import Observation
import SmartTubeIOSCore
import OSLog

let storeLog = Logger(subsystem: appSubsystem, category: "PlayerStateStore")

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
    /// A dismissal from an older cover must not collapse a newly opened video.
    private(set) var fullScreenRequestID = UUID()

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
    @ObservationIgnored private var firstFrameObserver: NSKeyValueObservation?
    @ObservationIgnored private weak var firstDisplayedItem: AVPlayerItem?

    var pipController: AVPictureInPictureController?
    var isPiPActive = false
    @ObservationIgnored var pipDelegate: PiPDelegate?
    @ObservationIgnored var pipRestoreCompletion: ((Bool) -> Void)?
    @ObservationIgnored var pipStartRequestID: UUID?

    // MARK: - Init

    public init(api: InnerTubeAPI) {
        let vm = PlaybackViewModel(api: api)
        self.vm = vm
        let hostView = PersistentPlayerHostView()
        hostView.playerLayer.player = vm.player
        self.playerHostView = hostView
        firstFrameObserver = hostView.playerLayer.observe(
            \.isReadyForDisplay, options: [.new]
        ) { [weak self] layer, _ in
            guard layer.isReadyForDisplay, let item = layer.player?.currentItem else { return }
            Task { @MainActor [weak self] in
                guard let self, self.playerHostView.playerLayer.isReadyForDisplay,
                    self.vm.player.currentItem === item, self.firstDisplayedItem !== item
                else { return }
                self.firstDisplayedItem = item
                self.vm.logLocalPlaybackStep("first frame displayable")
            }
        }
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
        if sameSource, video.isDownloaded {
            // A library tap explicitly chooses its saved track (including Without translation).
            vm.voiceOverOverride = nil
            vm.restartVoiceOver()
        }
        expand()
        storeLog.notice("[PlayerStateStore] play — presentation set to .fullScreen")
    }

    /// Adoption, loading and navigation must use the same queue (`.shared` in the app).
    var queue: any PlaybackQueue {
        get { vm.queue }
        set { vm.queue = newValue }
    }

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

    /// A channel the shell should push once the full-screen player is gone (see `MainTabView`).
    var pendingChannelId: String?

    /// Leaves the full-screen player the way Back does (mini-player when enabled, otherwise stop) and asks the
    /// shell to open the channel page.
    func openChannel(_ channelId: String, miniPlayerEnabled: Bool) {
        pendingChannelId = channelId
        if miniPlayerEnabled {
            minimize(reason: "open-channel")
        } else {
            stop()
        }
    }

    /// Collapse the full-screen player to the mini-player bar. Playback continues.
    public func minimize(reason: String) {
        storeLog.notice(
            "[PlayerStateStore] minimize reason=\(reason, privacy: .public) videoId=\(self.currentVideo?.id ?? "nil", privacy: .public) from=\(String(describing: self.presentation), privacy: .public) pip=\(self.isPiPActive)"
        )
        presentation = isPiPActive ? .pictureInPicture : .miniPlayer
        let action = dismissPlayerAction
        dismissPlayerAction = nil
        storeLog.notice(
            "[PlayerStateStore] minimize — presentation=\(String(describing: self.presentation), privacy: .public), dismissPlayerAction=\(action != nil)"
        )
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
        if presentation != .fullScreen {
            fullScreenRequestID = UUID()
        }
        presentation = .fullScreen
        storeLog.notice("[PlayerStateStore] expand — presentation set to .fullScreen")
    }

    func fullScreenCoverDismissed(requestID: UUID) {
        guard requestID == fullScreenRequestID, presentation == .fullScreen else { return }
        minimize(reason: "cover-dismissed")
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
