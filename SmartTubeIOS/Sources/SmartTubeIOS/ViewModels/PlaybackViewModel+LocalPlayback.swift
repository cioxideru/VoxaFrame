import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = ViewModelLogger(category: "Player")

// MARK: - Local Video Playback

extension PlaybackViewModel {

    func startLocalPlayback(video: Video) async -> Bool {
        guard video.localFileURL != nil else { return false }
        relatedVideos = []
        hasNext = false
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self, offlineMedia] in
            do {
                let item = try await offlineMedia.item(video: video)
                guard let self, !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else {
                    return
                }
                logLocalPlaybackStep("asset prepared")
                if let knownDuration = video.duration, knownDuration.isFinite, knownDuration > 0 {
                    duration = knownDuration
                }
                item.audioTimePitchAlgorithm = .spectral
                itemObserverTask = nil
                observeLocalPlayerItem(item)
                player.replaceCurrentItem(with: item)
                logLocalPlaybackStep("item installed")
                observePlaybackEndAndStalls(for: item)
                #if canImport(UIKit)
                setupRemoteCommandCenter()
                UIApplication.shared.isIdleTimerDisabled = true
                updateNowPlayingInfo()
                #endif
                resumePreparedItem()
            } catch {
                guard let self, !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else {
                    return
                }
                self.error = error
                isLoading = false
            }
        }
        Task { [weak self] in await self?.applyOfflineSponsorSegments(for: video) }
        // Queue availability must not delay local item preparation or use pre-activation context.
        await updateNextAvailability(for: video)
        #if canImport(UIKit)
        if !Task.isCancelled, parkedVideoId == nil, currentVideo?.hasSamePlaybackSource(as: video) == true {
            updateNowPlayingInfo()
        }
        #endif
        // A local request never falls through to a remote stream, even if its file is gone.
        return true
    }

    func logLocalPlaybackStep(_ step: String) {
        guard let video = currentVideo, video.isDownloaded else { return }
        let elapsed = Int(Date().timeIntervalSince(videoLoadStartedAt) * 1_000)
        playerLog.notice("[offline-start] \(step) elapsedMs=\(elapsed) videoId=\(video.id)")
    }

    private func observeLocalPlayerItem(_ item: AVPlayerItem) {
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
                guard let self, !Task.isCancelled, self.player.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    self.timeToPlayMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1_000)
                    self.lastSuccessfulStreamType = "local-file"
                    self.logLocalPlaybackStep("readyToPlay")
                    self.updateInitialItemDuration(item)
                    // OfflineMedia already selected the saved audio; online language preferences must not replace it.
                    self.isLoading = false
                    self.applyOfflineTranslation()
                case .failed:
                    playerLog.error("❌ local-file AVPlayerItem failed: \(ViewModelLogger.errorSummary(item.error))")
                    self.error = item.error
                    self.isLoading = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            guard let self, !Task.isCancelled, self.player.currentItem === item, item.status == .unknown else {
                return
            }
            self.error = URLError(.timedOut)
            self.isLoading = false
        }
    }
}
