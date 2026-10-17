import AVFoundation
import SmartTubeIOSCore

/// Owns one speculative task and one muted prepared item for a single Shorts presentation.
@MainActor
final class ShortsPreloader {
    var player: AVPlayer
    private let preparer: any ShortsStreamPreparing
    let deadline: IdleResourceCleanup
    let retention: IdleResourceCleanup
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var requestedID: String?
    private var preference: ShortsStreamPreference?
    private weak var anchor: AVPlayerItem?
    private(set) var prepared: PreparedShort?

    init(player: AVPlayer, preparer: any ShortsStreamPreparing) {
        self.player = player
        self.preparer = preparer
        deadline = IdleResourceCleanup(
            pressureNotification: nil,
            wait: { @MainActor in
                try await Task.sleep(for: .seconds(PlaybackTuning.shortsPreparationSeconds))
            })
        retention = IdleResourceCleanup(
            pressureNotification: IdleResourceCleanup.memoryWarningNotification,
            wait: { @MainActor in try await Task.sleep(for: PlaybackTuning.shortsPreloadRetention) })
    }

    deinit { task?.cancel() }

    func prepare(_ video: Video?, settings: AppSettings) {
        let newPreference = ShortsStreamPreference(settings: settings)
        guard requestedID != video?.id || preference != newPreference || anchor !== player.currentItem else { return }
        cancel()
        guard let video, let currentItem = player.currentItem else { return }
        requestedID = video.id
        preference = newPreference
        anchor = currentItem
        let id = generation
        let preparer = preparer
        deadline.schedule { [weak self] in self?.cancel() }
        retention.schedule { [weak self] in self?.cancel() }
        task = Task(priority: .utility) { [weak self, weak currentItem] in
            do {
                let prepared = try await preparer.prepare(video: video, preference: newPreference)
                guard !Task.isCancelled, let self, self.generation == id,
                    let currentItem, self.player.currentItem === currentItem
                else { return }
                self.prepared = prepared
                self.task = nil
                self.deadline.cancel()
            } catch {
                guard let self, self.generation == id else { return }
                self.task = nil
                // A speculative failure never enters the foreground retry cascade.
            }
        }
    }

    /// Transfer the prepared player intact; AVPlayerItem cannot move between active players.
    func take(video: Video, settings: AppSettings) -> PreparedShort? {
        guard let prepared, prepared.info.video.id == video.id,
            prepared.preference == ShortsStreamPreference(settings: settings),
            prepared.item.status != .failed,
            prepared.warmingPlayer.currentItem === prepared.item
        else {
            cancel()
            return nil
        }
        deadline.cancel()
        retention.cancel()
        task?.cancel()
        task = nil
        generation = UUID()
        self.prepared = nil
        requestedID = nil
        preference = nil
        anchor = nil
        return prepared
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        deadline.cancel()
        retention.cancel()
        requestedID = nil
        preference = nil
        anchor = nil
        prepared?.warmingPlayer.cancelPendingPrerolls()
        prepared?.warmingPlayer.replaceCurrentItem(with: nil)
        prepared = nil
    }
}
