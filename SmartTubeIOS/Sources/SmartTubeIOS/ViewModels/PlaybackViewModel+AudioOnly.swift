import AVFoundation
import SmartTubeIOSCore
import os

private let audioOnlyLog = ViewModelLogger(category: "AudioOnly")

// MARK: - Audio-Only Playback Mode

extension PlaybackViewModel {

    /// Toggles audio-only mode on the **currently playing video** immediately.
    /// - Turning ON: overlay appears immediately; attempts to swap to an audio-only
    ///   stream in the background. If the swap fails, the overlay stays visible with
    ///   HLS audio playing underneath — the setting is NOT reverted.
    /// - Turning OFF: overlay hides; reloads HLS only if an audio-only stream was
    ///   successfully loaded (tracked by `audioOnlyItemActive`).
    /// The caller is responsible for persisting `store.settings.audioOnlyMode`.
    @MainActor
    func toggleAudioOnlyLive() {
        let savedTime = currentTime
        isAudioOnlyMode.toggle()
        settings.audioOnlyMode = isAudioOnlyMode
        toastMessage =
            isAudioOnlyMode
            ? String(localized: "Audio-Only Mode", bundle: .module)
            : String(localized: "Video Mode", bundle: .module)

        // A previous on/off swap may still be in flight; only the latest toggle wins.
        audioOnlySwapTask?.cancel()
        audioOnlySwapTask = nil
        if isAudioOnlyMode {
            // Overlay shows immediately via isAudioOnlyMode = true.
            // Attempt stream swap in background; failure does NOT revert the overlay.
            audioOnlySwapTask = Task { [weak self] in
                guard let self else { return }
                await self.loadAudioOnlyItemIfEnabled(seekTo: savedTime, liveToggle: true)
            }
        } else {
            // Only reload HLS if we actually swapped to an audio-only stream;
            // otherwise HLS is already playing and no reload is needed.
            if audioOnlyItemActive {
                audioOnlySwapTask = Task { [weak self] in
                    guard let self, !Task.isCancelled, !self.isAudioOnlyMode else { return }
                    self.audioOnlyItemActive = false
                    // Restore the user's quality preference (fixes W6: passing nil dropped the preference).
                    self.reloadHLSItem(seekTo: savedTime, quality: effectiveQuality)
                }
            }
        }
    }

    /// Whether a started stream still needs the audio-only swap. Only the iOS-client path swaps before it
    /// plays; VisionOS HLS, adaptive composition and the fallback start their own item (OQ-0024).
    nonisolated static func needsAudioOnlySwapAfterStart(
        isAudioOnlyMode: Bool, audioOnlyItemActive: Bool, hasError: Bool, isCurrentVideo: Bool, hasItem: Bool
    ) -> Bool {
        isAudioOnlyMode && !audioOnlyItemActive && !hasError && isCurrentVideo && hasItem
    }

    /// Applies audio-only after any successful start, at the position the stream reached.
    func applyAudioOnlyAfterStart(video: Video) async {
        guard !Task.isCancelled,
            Self.needsAudioOnlySwapAfterStart(
                isAudioOnlyMode: isAudioOnlyMode, audioOnlyItemActive: audioOnlyItemActive, hasError: error != nil,
                isCurrentVideo: currentVideo?.id == video.id, hasItem: player.currentItem != nil)
        else { return }
        audioOnlyLog.notice("Audio-only: applying after the stream started")
        await loadAudioOnlyItemIfEnabled(seekTo: currentTime)
    }

    /// `false` once the user turned audio-only off, toggled again or moved to another video
    /// while a swap was awaiting.
    private func audioOnlySwapStillWanted(for videoId: String) -> Bool {
        isAudioOnlyMode && !Task.isCancelled && currentVideo?.id == videoId
    }

    /// Entry point called before the iOS-client stream plays, and by `applyAudioOnlyAfterStart` after
    /// any other start, when `isAudioOnlyMode == true` and `playerInfo` is populated.
    ///
    /// The existing HLS item is already loaded when this runs. If every audio-only
    /// attempt fails the HLS item remains active — the user gets video silently.
    /// - Parameter liveToggle: When `true` (called from `toggleAudioOnlyLive`), audio
    ///   load failures do NOT revert `isAudioOnlyMode` — the overlay stays visible with
    ///   HLS audio playing underneath. When `false` (new video load), failures silently
    ///   fall back to HLS and reset the flag.
    func loadAudioOnlyItemIfEnabled(seekTo seekTime: TimeInterval = 0, liveToggle: Bool = false) async {
        guard isAudioOnlyMode else { return }
        guard let info = playerInfo else { return }

        // Live streams have no adaptive audio-only URL. Leave HLS path untouched.
        guard !info.video.isLive else {
            audioOnlyLog.notice("Audio-only: skipped for live stream id=\(info.video.id)")
            return
        }

        // Attempt 1: iOS client URL (already in memory, zero extra network cost).
        if let url = info.bestAdaptiveAudioURL {
            let success = await tryLoadAudioURL(
                url, userAgent: InnerTubeClients.iOS.userAgent, videoId: info.video.id, seekTo: seekTime,
                liveToggle: liveToggle)
            if success { return }
        }
        // No second client: android_vr audio answers 403 past the first megabytes (PLAN-0049).
        audioOnlyAttemptsFailed(videoId: info.video.id, liveToggle: liveToggle)
    }

    /// Builds an `AVURLAsset` for the given audio URL, checks playability, and replaces
    /// the current player item. Returns `true` on success.
    private func tryLoadAudioURL(
        _ url: URL, userAgent: String, videoId: String, seekTo seekTime: TimeInterval = 0, liveToggle: Bool = false
    ) async -> Bool {
        let opts: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]
        ]
        let asset = AVURLAsset(url: url, options: opts)
        guard (try? await asset.load(.isPlayable)) == true else { return false }
        guard audioOnlySwapStillWanted(for: videoId) else { return false }

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral

        // Set up an item observer before replacing the current item, matching the
        // pattern used by every other load path. Without this the audio item's
        // .failed status is never observed, causing silent playback stalls.
        // BUG-009 fix: replace the current item BEFORE setting up the observer.
        audioOnlyItemActive = true
        player.replaceCurrentItem(with: item)
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
                guard let self, !Task.isCancelled, self.player.currentItem === item,
                    self.ownsPlaybackAudioSession
                else { return }
                switch status {
                case .readyToPlay:
                    audioOnlyLog.notice(
                        "[benchmark] readyToPlay — audio-only — videoId=\(self.currentVideo?.id ?? "nil") title=\(self.currentVideo?.title ?? "nil")"
                    )
                    audioOnlyLog.notice("✅ Audio-only AVPlayerItem readyToPlay")
                    if seekTime > 0 { self.seek(to: seekTime) }
                    self.resumePreparedItem()
                    self.loadAudioTracks(from: item)
                    // Dismiss the spinner — audio item is buffered and playing.
                    self.isLoading = false
                case .failed:
                    let err = ViewModelLogger.errorSummary(item.error)
                    audioOnlyLog.error("❌ Audio-only AVPlayerItem failed: \(err)")
                    self.audioOnlyItemActive = false
                    // BUG-008 fix: only reset isAudioOnlyMode when this is NOT a live toggle.
                    // On liveToggle, the overlay stays visible with HLS audio underneath.
                    if !liveToggle {
                        self.isAudioOnlyMode = false
                    }
                    self.error = item.error
                    self.isLoading = false
                case .unknown:
                    audioOnlyLog.notice("Audio-only: AVPlayerItem status unknown (loading)")
                @unknown default:
                    break
                }
            }
            guard let self, !Task.isCancelled, self.player.currentItem === item, item.status == .unknown else {
                return
            }
            self.audioOnlyItemActive = false
            if !liveToggle { self.isAudioOnlyMode = false }
            self.error = URLError(.timedOut)
            self.isLoading = false
        }

        // BUG-010 fix: restart endObserverTask so autoplay-to-next works in audio-only mode.
        // The main loadAsync sets up endObserverTask for the HLS AVPlayerItem; when we replace
        // that item with an audio-only AVPlayerItem, the old observer watches the wrong object
        // and didPlayToEndTimeNotification is never delivered.
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

        audioOnlyLog.notice("Audio-only: loaded \(ViewModelLogger.urlHost(url))")
        return true
    }

    /// The audio-only URL could not be loaded; the existing HLS item stays in the player.
    private func audioOnlyAttemptsFailed(videoId: String, liveToggle: Bool) {
        guard audioOnlySwapStillWanted(for: videoId) else { return }
        audioOnlyItemActive = false
        if liveToggle {
            // Live toggle: keep overlay showing with HLS audio underneath.
            // Don't reset isAudioOnlyMode — the user's preference stays.
            audioOnlyLog.notice("Audio-only: all attempts failed (live toggle) — overlay stays, HLS audio continues")
            toastMessage = "Audio-only stream unavailable — showing thumbnail"
        } else {
            // New video load: silently fall back to HLS video.
            audioOnlyLog.notice("Audio-only: all attempts failed, falling back to HLS")
            isAudioOnlyMode = false
        }
    }
}
