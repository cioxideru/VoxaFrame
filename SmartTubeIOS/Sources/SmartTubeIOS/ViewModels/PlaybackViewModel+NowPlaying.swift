import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = ViewModelLogger(category: "Player")

// File-scope factory — deliberately nonisolated so MPMediaItemArtwork can invoke the
// returned closure from MediaPlayer's internal serial queue without triggering the
// Swift 6 actor-isolation assertion (_swift_task_checkIsolatedSwift → EXC_BREAKPOINT).
// An inline closure defined inside a @MainActor method inherits @MainActor isolation
// even when it only captures a value-type snapshot; extracting it here breaks that.
#if canImport(UIKit)
private func makeNonisolatedArtworkProvider(image: UIImage) -> (CGSize) -> UIImage {
    { _ in image }
}
#endif

// MARK: - Now Playing (lock screen + Dynamic Island)

#if canImport(UIKit)
extension PlaybackViewModel {

    func setupAudioSessionObserver() {
        audioSessionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }
            switch type {
            case .began:
                // System (phone call, Siri, etc.) took the audio session — note we
                // were playing so we can resume when it ends.
                playerLog.notice("[interruption] began — pausing player")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.wasPlayingBeforeInterruption = self.isPlaying
                    self.isHandlingAudioInterruption = true
                    self.player.pause()
                    self.isPlaying = false
                    self.updateNowPlayingPlayback()
                }
            case .ended:
                let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                playerLog.notice("[interruption] ended — shouldResume=\(options.contains(.shouldResume))")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        playerLog.error("[interruption] setActive failed: \(error.localizedDescription)")
                    }
                    if options.contains(.shouldResume) && self.wasPlayingBeforeInterruption {
                        self.player.rate = Float(self.settings.playbackSpeed)
                        self.isPlaying = true
                        self.updateNowPlayingPlayback()
                    }
                    self.isHandlingAudioInterruption = false
                    self.wasPlayingBeforeInterruption = false
                }
            @unknown default:
                break
            }
        }
    }

    func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        // Remove any existing targets first so this function is safe to call
        // multiple times (e.g. early in loadAsync AND at readyToPlay) without
        // accumulating duplicate handlers.
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                player.rate = Float(settings.playbackSpeed)
                isPlaying = true
                updateNowPlayingPlayback()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player.pause()
                self?.isPlaying = false
                self?.updateNowPlayingPlayback()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor [weak self] in self?.seekRelative(seconds: interval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor [weak self] in self?.seekRelative(seconds: -interval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playPrevious() }
            return .success
        }
    }

    func updateNowPlayingInfo() {
        let video = playerInfo?.video ?? currentVideo
        guard let video else {
            nowPlayingInfoCache = [:]
            setNowPlayingInfo(nil)
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.channelTitle,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.video.rawValue),
            MPNowPlayingInfoPropertyIsLiveStream: NSNumber(value: video.isLive),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: currentTime),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: isPlaying ? Double(player.rate) : 0.0),
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        nowPlayingInfoCache = info

        // Artwork — capture the current image by value so the MPMediaItemArtwork closure
        // never captures self. MediaPlayer calls the closure on its private serial queue;
        // capturing self (a @MainActor-isolated type) causes Swift 6 to assert actor
        // isolation via dispatch_assert_queue and throw EXC_BREAKPOINT (fix238).
        if let thumbURL = video.thumbnailURL {
            let snapshot: UIImage = cachedArtwork ?? UIImage()
            let artwork = MPMediaItemArtwork(
                boundsSize: CGSize(width: 600, height: 600),
                requestHandler: makeNonisolatedArtworkProvider(image: snapshot))
            nowPlayingInfoCache[MPMediaItemPropertyArtwork] = artwork

            // Kick off fetch only when the video changes to avoid redundant network hits.
            if cachedArtworkVideoID != video.id {
                cachedArtworkVideoID = video.id
                cachedArtwork = nil
                Task { [weak self, url = thumbURL, videoID = video.id] in
                    guard let (data, _) = try? await URLSession.shared.data(from: url),
                        let image = UIImage(data: data)
                    else { return }
                    await MainActor.run { [weak self] in
                        guard let self, self.cachedArtworkVideoID == videoID else { return }
                        self.cachedArtwork = image
                        // Update the artwork key in the cache with the real image. Use the
                        // nonisolated factory so MediaPlayer can call the closure from its
                        // internal background queue without hitting the Swift 6 actor-isolation
                        // assertion (same fix as the initial artwork registration above).
                        self.nowPlayingInfoCache[MPMediaItemPropertyArtwork] =
                            MPMediaItemArtwork(
                                boundsSize: image.size,
                                requestHandler: makeNonisolatedArtworkProvider(image: image))
                        self.setNowPlayingInfo(self.nowPlayingInfoCache)
                    }
                }
            }
        }

        // Update next/previous button enabled state.
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = hasPrevious

        setNowPlayingInfo(nowPlayingInfoCache)
    }

    func updateNowPlayingPlayback() {
        nowPlayingInfoCache[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: currentTime)
        nowPlayingInfoCache[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(
            value: isPlaying ? Double(player.rate) : 0.0)
        setNowPlayingInfo(nowPlayingInfoCache)
    }

    func clearNowPlayingInfo() {
        cachedArtwork = nil
        cachedArtworkVideoID = nil
        nowPlayingInfoCache = [:]
        setNowPlayingInfo(nil)
    }

    /// Writes to `MPNowPlayingInfoCenter` directly on `@MainActor` (= main thread).
    /// Do NOT use DispatchQueue.main.async here — dispatching async from @MainActor
    /// creates a new GCD block that may lack the proper queue-specific context that
    /// MediaPlayer's internal accessQueue asserts, causing EXC_BREAKPOINT.
    /// Since every caller is already @MainActor-isolated this call is always
    /// synchronous on the main thread.
    private func setNowPlayingInfo(_ info: [String: Any]?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
#endif
