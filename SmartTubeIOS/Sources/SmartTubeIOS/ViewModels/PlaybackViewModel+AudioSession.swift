import AVFoundation
import Foundation

extension PlaybackViewModel {
    var ownsPlaybackAudioSession: Bool {
        audioSessionID.map { audioSession.isCurrent($0) } ?? false
    }

    var canResumeInAudioSession: Bool {
        ownsPlaybackAudioSession && audioPlaybackTask == nil
    }

    /// Ready callbacks still publish metadata while an owned activation is pending.
    /// That task will start the current item once the native session is ready.
    func resumePreparedItem() {
        guard canResumeInAudioSession else { return }
        player.rate = Float(settings.playbackSpeed)
        isPlaying = true
    }

    /// A new intent is issued synchronously, before any task can deliver an old stop.
    func beginPlaybackAudioSession() {
        cancelPendingAudioPlayback()
        audioSessionID = audioSession.begin()
        playbackDemand.resume()
        updatePlaybackDemand()
    }

    func cancelPendingAudioPlayback() {
        if audioPlaybackTask != nil, let audioSessionID { audioSession.invalidate(audioSessionID) }
        audioPlaybackTask?.cancel()
        audioPlaybackTask = nil
        updatePlaybackDemand()
    }

    /// Call after pausing the player and voice-over I/O.
    func endPlaybackAudioSession() {
        cancelPendingAudioPlayback()
        guard let id = audioSessionID else { return }
        audioSession.invalidate(id)
        audioSessionID = nil
        let session = audioSession
        audioPlaybackTask = Task { await session.release(id) }
    }

    func activatePlaybackAudioSession(force: Bool = false) async -> Bool {
        guard !Task.isCancelled, let id = audioSessionID else { return false }
        let activated: Bool
        do {
            activated = try await audioSession.activate(id, force: force)
        } catch {
            if !Task.isCancelled, audioSessionID == id, audioSession.isCurrent(id) {
                self.error = error
                isLoading = false
            }
            return false
        }
        guard activated, !Task.isCancelled, audioSessionID == id, audioSession.isCurrent(id) else {
            if activated { await audioSession.release(id) }
            return false
        }
        return true
    }

    /// Synchronous UI/remote entry points share this one cancellable task owner.
    func requestAudioPlayback() {
        guard player.currentItem != nil else { return }
        player.pause()
        voiceOver.pauseAudio()
        isPlaying = false
        beginPlaybackAudioSession()
        audioPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { audioPlaybackTask = nil } }
            // Quality/audio selection may replace the item within this same intent.
            // Stop, suspend and a new load revoke the intent and cancel this task.
            guard await activatePlaybackAudioSession(force: true), player.currentItem != nil else { return }
            player.rate = Float(settings.playbackSpeed)
            isPlaying = true
            #if canImport(UIKit)
            updateNowPlayingPlayback()
            #endif
        }
    }
}
