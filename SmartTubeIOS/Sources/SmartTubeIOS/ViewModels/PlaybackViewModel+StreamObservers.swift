import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = CrashlyticsLogger(category: "Player")

// MARK: - Playback Item Observers

extension PlaybackViewModel {

    func observeInitialPlayerItem(_ item: AVPlayerItem, info: PlayerInfo, isHLS: Bool) {
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream {
                guard let self, !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    self.initialPlayerItemBecameReady(item, info: info, isHLS: isHLS)
                case .failed:
                    let err = item.error.map { "\($0)" } ?? "nil"
                    playerLog.error("❌ AVPlayerItem failed: \(err)")
                    // Retry the video that owned this item; a stale item is ignored.
                    if self.player.currentItem === item {
                        self.startExhaustiveRetry(video: info.video, item: item, originalError: item.error)
                    }
                case .unknown:
                    playerLog.notice("AVPlayerItem status: unknown (loading)")
                @unknown default:
                    break
                }
            }
        }

    }

    private func initialPlayerItemBecameReady(_ item: AVPlayerItem, info: PlayerInfo, isHLS: Bool) {
        let elapsedMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
        self.timeToPlayMs = elapsedMs
        playerLog.notice(
            "✅ AVPlayerItem readyToPlay — video=\(self.currentVideo?.id ?? "nil") rate=\(self.player.rate) timeControlStatus=\(self.player.timeControlStatus.rawValue) isAudioOnlyMode=\(self.isAudioOnlyMode)"
        )
        playerLog.notice(
            "[benchmark] readyToPlay in \(elapsedMs) ms since load() — videoId=\(self.currentVideo?.id ?? "nil") title=\(self.currentVideo?.title ?? "nil")"
        )
        // Only set the stream type here if a fallback path hasn't already set it
        // (fallback paths set it in attemptURL/tryWebViewHLS readyToPlay handlers).
        if self.lastSuccessfulStreamType == "unknown" {
            self.lastSuccessfulStreamType = isHLS ? "primaryHLS" : "primaryDirect"
        }
        if elapsedMs > PlaybackTuning.slowVideoLoadMilliseconds {
            CrashlyticsLogger.recordSlowVideoLoad(
                videoId: self.currentVideo?.id ?? "unknown",
                elapsedMs: elapsedMs,
                streamType: self.lastSuccessfulStreamType,
                hasError: item.error != nil,
                errorDescription: item.error?.localizedDescription
            )
        }
        // Refresh duration from the AVPlayerItem now that it is
        // ready — the API metadata may have been absent (nil) or
        // inaccurate, which would leave duration=0 and break scrubbing
        // (every seekBar drag computes fraction*0 = 0).
        updateInitialItemDuration(item)

        if let pos = self.savedPositionToRestore, pos > 0 {
            self.savedPositionToRestore = nil
            self.seek(to: pos)
        }
        // Load alternate audio renditions (dubbed / translated tracks).
        self.loadAudioTracks(from: item)  // Dismiss the spinner: the first frame is ready to display.
        // Previously this was done after player.rate was set, which
        // dismissed the spinner before buffering completed on slow
        // networks (GitHub issue #53).
        self.isLoading = false
        // Fast-start quality ramp: first frame is visible now. Upgrade
        // ABR hints to the user's preferred quality so AVPlayer switches
        // to a higher-quality variant during continued playback. This is
        // a hint update only — no item replacement, no stutter.
        if info.hlsURL != nil {
            let targetMaxH = self.settings.preferredQuality.maxHeight
            Task { [weak self, weak item] in
                try? await Task.sleep(for: PlaybackTuning.qualityRampDelay)
                guard let self, !Task.isCancelled else { return }
                self.timeToHighQualityMs = Int(Date().timeIntervalSince(self.videoLoadStartedAt) * 1000)
                // Reset to system default so scrubbing has a comfortable
                // forward buffer after the first frame is on screen.
                item?.preferredForwardBufferDuration = 0
                if let height = targetMaxH {
                    let hf = CGFloat(height)
                    item?.preferredMaximumResolution = CGSize(width: hf * 4, height: hf)
                    item?.preferredPeakBitRate = self.peakBitRate(for: height)
                    playerLog.notice("[fast-start] ABR ramp → \(height)p + buffer unconstrained")
                } else {
                    item?.preferredMaximumResolution = .zero
                    item?.preferredPeakBitRate = 0
                    playerLog.notice(
                        "[fast-start] ABR ramp → Auto (unconstrained) + buffer unconstrained")
                }
            }
        }
    }

    private func updateInitialItemDuration(_ item: AVPlayerItem) {
        let itemDur = item.duration.seconds
        if itemDur.isFinite && itemDur > 0 {
            let prevDur = self.duration
            self.duration = itemDur
            playerLog.notice(
                "[duration] updated from AVPlayerItem: \(String(format: "%.1f", itemDur))s (was \(String(format: "%.1f", prevDur))s from metadata)"
            )
        } else if self.duration == 0 {
            // Some HLS streams report .invalid duration at readyToPlay and
            // deliver it later via KVO once playlist segments are parsed.
            // Watch for the first valid value so the scrubber is not
            // permanently greyed out (#183).
            self.durationObserverTask?.cancel()
            self.durationObserverTask = Task { [weak self, weak item] in
                guard let item else { return }
                for await seconds in item.firstValidDurationStream {
                    guard let self, !Task.isCancelled else { return }
                    let prev = self.duration
                    self.duration = seconds
                    playerLog.notice(
                        "[duration] deferred KVO update: \(String(format: "%.1f", seconds))s (was \(String(format: "%.1f", prev))s)"
                    )
                    break
                }
            }
        }
    }

    func observePlaybackEndAndStalls(for item: AVPlayerItem) {
        // Observe end-of-item using NotificationCenter async sequence
        endObserverTask?.cancel()
        endObserverTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.handlePlaybackEnd()
            }
        }

        // Observe playback stalls and record them as Crashlytics non-fatals (bug #193).
        stallObserverTask?.cancel()
        stallObserverTask = Task { @MainActor [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVPlayerItem.playbackStalledNotification,
                object: item
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.registerStall(on: item)
                let stallTime = Int(self.currentTime)
                playerLog.notice(
                    "[stall] AVPlayerItemPlaybackStalled at t=\(stallTime)s stall#\(self.stallCount) video=\(self.currentVideo?.id ?? "unknown")"
                )
                let stallError = NSError(
                    domain: "SmartTube.PlaybackStall",
                    code: 0,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "AVPlayerItemPlaybackStalled at t=\(stallTime)s (stall #\(self.stallCount))"
                    ]
                )
                playerLog.recordNonFatal(
                    stallError,
                    userInfo: [
                        "video_id": self.currentVideo?.id ?? "unknown",
                        "stall_at_time": String(stallTime),
                        "stall_count": String(self.stallCount),
                        "video_duration": String(Int(self.duration)),
                        "stall_trigger": "AVPlayerItemPlaybackStalled",
                    ])
                // Stall recovery (#193): wait 2 s for AVPlayer to self-heal;
                // if still stalled, nudge the pipeline with a near-zero seek
                // + explicit rate restore. Capped at 3 attempts per item.
                let recoveryCount = self.stallCount
                if recoveryCount <= 3 {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: PlaybackTuning.stallRecoveryDelayNanoseconds)
                        guard let self, self.isPlaying, self.player.rate == 0,
                            !self.isQualityChangePending
                        else { return }
                        let seekT = self.currentTime
                        playerLog.notice(
                            "[stall] recovery#\(recoveryCount): seeking to \(seekT)s to flush pipeline")
                        self.player.seek(
                            to: CMTime(seconds: seekT, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                        ) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.isPlaying else { return }
                                self.player.rate = Float(self.settings.playbackSpeed)
                                playerLog.notice("[stall] recovery#\(recoveryCount): rate restored")
                            }
                        }
                    }
                }
            }
        }

    }
}
