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

    func startLocalPlayback(video: Video) -> Bool {
        guard video.localFileURL != nil else { return false }
        relatedVideos = []
        hasNext = false
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            do {
                let item = try await OfflineMedia.item(video: video)
                let localDuration = try await item.asset.load(.duration).seconds
                guard let self, !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else {
                    return
                }
                if localDuration.isFinite, localDuration > 0 { duration = localDuration }
                item.audioTimePitchAlgorithm = .spectral
                itemObserverTask = nil
                observeLocalPlayerItem(item, video: video)
                player.replaceCurrentItem(with: item)
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
        // A local request never falls through to a remote stream, even if its file is gone.
        return true
    }

    private func observeLocalPlayerItem(_ item: AVPlayerItem, video: Video) {
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
                guard let self, !Task.isCancelled, self.player.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    playerLog.notice(
                        "[benchmark] readyToPlay — local-file — videoId=\(video.id) title=\(video.title)")
                    self.loadAudioTracks(from: item)
                    if let translation = video.localTranslationFileURL {
                        self.voiceOver.keepsOriginalAudio = self.settings.yandexVOTKeepOriginalAudio
                        self.voiceOver.startLocal(
                            url: translation, videoID: video.id, mainPlayer: self.player,
                            setVideoPlaying: { [weak self] playing in self?.setPlayingForVoiceOver(playing) })
                    }
                    self.isLoading = false
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
