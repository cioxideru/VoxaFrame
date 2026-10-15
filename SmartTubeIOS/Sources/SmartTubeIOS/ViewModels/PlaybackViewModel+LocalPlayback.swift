import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Local Video Playback

extension PlaybackViewModel {

    func startLocalPlayback(video: Video) -> Bool {
        // Local-file fast path — bypass all network fetches for downloaded videos.
        // The path must be inside Documents/SmartTubeDownloads/ to prevent path-traversal
        // from a crafted Video object.
        if let localURL = video.localFileURL {
            let downloadsDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SmartTubeDownloads").path
            if localURL.path.hasPrefix(downloadsDir),
                FileManager.default.fileExists(atPath: localURL.path)
            {
                let item = AVPlayerItem(url: localURL)
                item.audioTimePitchAlgorithm = .spectral
                // Wire up observers BEFORE replaceCurrentItem (task-80 rule).
                observeLocalPlayerItem(item, video: video)
                player.replaceCurrentItem(with: item)
                observePlaybackEndAndStalls(for: item)
                #if canImport(UIKit)
                setupRemoteCommandCenter()
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    playerLog.error("[loadAsync] local: AVAudioSession setActive failed: \(error.localizedDescription)")
                }
                #endif
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                // Downloaded videos have no related videos — clear any stale state from a
                // previous YouTube session so autoplay does not fire a YouTube video when
                // the download ends. (Bug #224: wrong video played after local file ends.)
                relatedVideos = []
                hasNext = false
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = true
                updateNowPlayingInfo()
                #endif
                playerLog.notice("[loadAsync] local-file fast path: playing \(localURL.lastPathComponent)")
                return true
            }
            // File missing or path invalid — fall through to network re-stream.
            playerLog.notice("[loadAsync] localFileURL set but file not accessible, falling through: \(localURL.path)")
        }

        return false
    }

    private func observeLocalPlayerItem(_ item: AVPlayerItem, video: Video) {
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream {
                guard let self, !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    playerLog.notice(
                        "[benchmark] readyToPlay — local-file — videoId=\(video.id) title=\(video.title)")
                    self.loadAudioTracks(from: item)
                    self.isLoading = false
                case .failed:
                    playerLog.error("❌ local-file AVPlayerItem failed: \(String(describing: item.error))")
                    self.error = item.error
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
