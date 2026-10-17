import AVFoundation
import SmartTubeIOSCore

extension PlaybackDemandCoordinator {
    public static let shared = makeShared()

    private static func makeShared() -> PlaybackDemandCoordinator {
        let coordinator = PlaybackDemandCoordinator(
            waitForRecovery: { try await Task.sleep(for: PlaybackTuning.playbackDemandRecovery) },
            waitForBudget: { try await Task.sleep(for: PlaybackTuning.playbackDemandBufferBudget) })
        Task { await VideoPreloadCache.shared.observePlaybackDemand(coordinator) }
        return coordinator
    }
}

/// Converts the active player's lifecycle and actual transport state into one demand lease.
@MainActor
final class PlaybackDemandAdapter {
    private let coordinator: PlaybackDemandCoordinator
    private let owner = UUID()
    private weak var player: AVPlayer?
    private var observation: NSKeyValueObservation?
    private var videoID: String?
    private var hasStarted = false
    private var preparing = false
    private var isLoading = false
    private var isEnabled = false

    init(coordinator: PlaybackDemandCoordinator = .shared) { self.coordinator = coordinator }

    deinit {
        observation?.invalidate()
        let coordinator = coordinator
        let owner = owner
        Task { @MainActor in coordinator.remove(owner: owner) }
    }

    func update(player: AVPlayer, videoID: String?, isLoading: Bool, isEnabled: Bool) {
        if self.videoID != videoID {
            self.videoID = videoID
            hasStarted = false
            preparing = false
        }
        if isLoading, !hasStarted { preparing = true }
        if !isEnabled { preparing = false }
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        if self.player !== player {
            observation?.invalidate()
            self.player = player
            observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] source, _ in
                Task { @MainActor [weak self, weak source] in
                    guard let self, self.player === source else { return }
                    self.publish()
                }
            }
        }
        publish()
    }

    func stop() {
        isEnabled = false
        hasStarted = false
        preparing = false
        coordinator.remove(owner: owner)
    }

    private func publish() {
        guard isEnabled, videoID != nil, let player else {
            coordinator.remove(owner: owner)
            return
        }
        if player.timeControlStatus == .playing { hasStarted = true }
        let phase: PlaybackDemandCoordinator.Phase
        if !hasStarted, preparing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            phase = .preparing
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate || isLoading {
            phase = .buffering
        } else {
            phase = player.timeControlStatus == .playing ? .playing : .inactive
        }
        coordinator.update(owner: owner, phase: phase)
    }
}
