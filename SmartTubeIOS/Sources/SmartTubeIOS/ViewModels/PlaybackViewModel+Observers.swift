import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import MediaPlayer
#endif

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - AVPlayer Observers

extension PlaybackViewModel {

    func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Don't overwrite the slider position or trigger SponsorBlock auto-seeks
                // while the user is scrubbing. Auto-seeks call seek() → showControls() →
                // scheduleControlsHide(), which cancels and restarts the 4 s hide-timer
                // every 0.5 s, preventing controls from ever auto-hiding post-scrub.
                guard !self.isScrubbing else { return }
                guard !self.sponsorBlockManager.isSkippingSegment else { return }
                // Suspend time updates during a quality-change transition: the new
                // AVPlayerItem is not yet ready and player.currentTime() may return 0
                // or a stale value. currentTime is restored by qualityItemDidBecomeReady.
                guard !self.isQualityChangePending else { return }
                self.currentTime = seconds
                self.checkSponsorSkip(at: seconds)
                self.updateCaptionCue(for: seconds)
                if self.statsForNerdsVisible { self.updateStatsSnapshot() }
                if self.isPlaying, self.settings.historyState == .enabled, self.duration > 0 {
                    await self.tracker.checkpointIfDue(position: seconds, duration: self.duration)
                }
            }
        }
    }

    func setupRateObserver() {
        // KVO on player.rate so isPlaying stays in sync when the system externally
        // pauses the player (e.g. headphones removed, audio session interruption ends
        // without shouldResume). Without this, isPlaying stays true while the player
        // is actually silent, causing handleForeground() to re-start a ghost session.
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let self, let newRate = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore rate changes that we ourselves triggered (load/pause/resume/stop)
                // by only acting when the player goes silent unexpectedly while we
                // believed it was playing.
                //
                // Also ignore rate→0 when currentTime is within 1 s of the total
                // duration: that's the video naturally reaching its end, not a stall.
                // In that case AVFoundation will post didPlayToEndTimeNotification
                // immediately after, which calls handlePlaybackEnd() correctly.
                // Without this guard the recovery logic seeks back by ~1 s and fights
                // the natural ending, causing repeated spurious stall reports and
                // blocking the end-of-video / autoplay-next flow (crash log confirmed
                // via Crashlytics: stall #1–4 at t=15s for a 15.3 s video).
                let nearEnd = self.duration > 0 && self.currentTime >= self.duration - 1.0
                let playerWentSilent =
                    newRate == 0 && self.isPlaying && !self.isSwappingItem && !self.isHandlingAudioInterruption
                    && !nearEnd
                if playerWentSilent {
                    self.isPlaying = false
                    playerLog.notice("[rateObserver] player.rate→0 while isPlaying=true — syncing isPlaying=false")
                    let stalledItem = self.player.currentItem
                    self.registerStall(on: stalledItem)
                    let t = Int(self.currentTime)
                    let stallError = NSError(
                        domain: "SmartTube.PlaybackStall",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "player.rate→0 while isPlaying=true at t=\(t)s (stall #\(self.stallCount))"
                        ]
                    )
                    playerLog.recordNonFatal(
                        stallError,
                        userInfo: [
                            "video_id": self.currentVideo?.id ?? "unknown",
                            "stall_at_time": String(t),
                            "stall_count": String(self.stallCount),
                            "video_duration": String(Int(self.duration)),
                            "stall_trigger": "rateObserver",
                        ])
                    #if canImport(UIKit)
                    self.updateNowPlayingPlayback()
                    #endif
                    // Stall recovery: mirror the AVPlayerItemPlaybackStalled path (#193).
                    // Wait 2 s for the system to self-heal (audio route change, interruption
                    // resume, etc.), then nudge the pipeline if still stalled. Guard on
                    // !isPlaying (already set above) rather than isPlaying, and also on
                    // !isSwappingItem to avoid interfering with intentional item swaps.
                    // Capped at PlaybackTuning.maxStallRecoveryAttempts per stall sequence, same as
                    // the notification-based path; escalations are capped per video.
                    let recoveryCount = self.stallCount
                    let elapsed = self.firstRapidStallTime.map { Date().timeIntervalSince($0) } ?? 0
                    let isRapidRepeat = elapsed < PlaybackTuning.rapidStallWindow
                    let canEscalate =
                        self.exhaustiveRetryTask == nil
                        && self.stallEscalationCount < PlaybackTuning.maxStallEscalationsPerVideo
                    if recoveryCount >= PlaybackTuning.maxStallRecoveryAttempts && isRapidRepeat && canEscalate {
                        // Rapid stall loop: seeks are re-stalling immediately because the
                        // format URL is expired or rate-limited (CDN returns the same broken
                        // URL after each seek). Escalate to exhaustiveRetry instead of
                        // another wasted seek. Guard on exhaustiveRetryTask == nil to avoid
                        // launching duplicate retries if further stalls fire during retry.
                        if let video = self.currentVideo {
                            playerLog.notice(
                                "[rateObserver] rapid stall loop — \(recoveryCount) stalls in \(Int(elapsed))s — escalating to exhaustiveRetry"
                            )
                            let loopError = NSError(
                                domain: "SmartTube.PlaybackStall",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Stall loop \(recoveryCount)× in \(Int(elapsed))s — format unrecoverable, escalating"
                                ]
                            )
                            self.stallEscalationCount += 1
                            self.startExhaustiveRetry(video: video, item: stalledItem, originalError: loopError)
                        }
                    } else if recoveryCount <= PlaybackTuning.maxStallRecoveryAttempts {
                        self.scheduleStallRecovery(
                            item: stalledItem, recoveryCount: recoveryCount, trigger: "rateObserver")
                    }
                }
            }
        }
    }

    /// After a stall, waits for the system to self-heal, then seeks in place to flush the
    /// pipeline and restores the rate. The single recovery path for both the rate observer
    /// and `AVPlayerItemPlaybackStalled`; a newer stall replaces a pending recovery.
    /// Does nothing if the video, the item or `isPlaying` changed in the meantime. The rate
    /// observer has already set `isPlaying = false`, so a later deliberate pause leaves
    /// `isPlaying` unchanged; every deliberate pause (suspend, background, interruption,
    /// remote/sleep-timer pause, voice-over hold, output-device loss) therefore calls
    /// `cancelStallRecovery()` explicitly. A user resume during the wait still skips the nudge.
    func scheduleStallRecovery(item: AVPlayerItem?, recoveryCount: Int, trigger: String) {
        let videoId = currentVideo?.id
        let expectedIsPlaying = isPlaying
        stallRecoveryTask?.cancel()
        stallRecoveryTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: PlaybackTuning.stallRecoveryDelayNanoseconds)
            guard let self, !Task.isCancelled, let item,
                self.player.currentItem === item, self.currentVideo?.id == videoId,
                self.isPlaying == expectedIsPlaying, self.player.rate == 0,
                !self.isQualityChangePending, !self.isSwappingItem
            else { return }
            let seekT = self.currentTime
            playerLog.notice("[\(trigger)] recovery#\(recoveryCount): seeking to \(seekT)s to flush pipeline")
            self.player.seek(
                to: CMTime(seconds: seekT, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
            ) { [weak self, weak item] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player.currentItem === item,
                        self.isPlaying == expectedIsPlaying, self.player.rate == 0
                    else { return }
                    self.player.rate = Float(self.settings.playbackSpeed)
                    self.isPlaying = true
                    playerLog.notice("[\(trigger)] recovery#\(recoveryCount): rate restored, isPlaying=true")
                }
            }
        }
    }

    /// Counts one stall on `item`. A stall on a different item, or after the rapid-stall
    /// window has elapsed, starts a new sequence so recovery is not capped forever.
    func registerStall(on item: AVPlayerItem?, now: Date = Date()) {
        let windowExpired =
            firstRapidStallTime.map { now.timeIntervalSince($0) >= PlaybackTuning.rapidStallWindow } ?? false
        if item !== stallItem || windowExpired {
            stallCount = 0
            firstRapidStallTime = nil
            stallItem = item
        }
        stallCount += 1
        if firstRapidStallTime == nil { firstRapidStallTime = now }
    }

    /// Starts `exhaustiveRetry` for the video that owned `item`. Skips it when `item` is no
    /// longer current, and clears `exhaustiveRetryTask` when it finishes so later stall loops
    /// can escalate again.
    func startExhaustiveRetry(video: Video, item: AVPlayerItem?, originalError: Error?) {
        cancelStallRecovery()
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = Task { [weak self, weak item] in
            guard let self else { return }
            if let item, self.player.currentItem === item {
                await self.exhaustiveRetry(video: video, originalError: originalError)
            }
            if !Task.isCancelled { self.exhaustiveRetryTask = nil }
        }
    }

    func cancelStallRecovery() {
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil
    }

    /// The audio output went away (e.g. headphones unplugged) and AVPlayer paused itself.
    /// Record it as a deliberate pause so neither stall path resumes on the speaker.
    func handleAudioOutputLost() {
        cancelStallRecovery()
        guard isPlaying else { return }
        isPlaying = false
        player.pause()
        #if canImport(UIKit)
        updateNowPlayingPlayback()
        #endif
    }

    #if canImport(UIKit)
    func setupAirPlayObserver() {
        airPlayObserver = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, change in
            guard let self, let active = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.isAirPlaying = active
            }
        }
    }
    #endif
}
