import AVFoundation
import SmartTubeIOSCore
import os

#if canImport(UIKit)
import UIKit
import MediaPlayer
#endif

private let playerLog = ViewModelLogger(category: "Player")

// MARK: - Load Video Lifecycle

extension PlaybackViewModel {

    public func load(video: Video, incognito: Bool = false) {
        parkedResourceCleanup.cancel()
        playerLog.notice(
            "[load] load() called — id=\(video.id) currentVideo=\(self.currentVideo?.id ?? "nil") isLoading=\(self.isLoading) player.item=\(self.player.currentItem != nil)"
        )
        playerLog.notice("[benchmark] load started — videoId=\(video.id) title=\(video.title)")
        videoLoadStartedAt = Date()
        lastSuccessfulStreamType = "unknown"
        timeToPlayMs = 0
        timeToHighQualityMs = 0
        cacheStatusSummary = ""
        if currentVideo?.id == video.id, !isLoading {
            playerLog.notice("[load] re-opening same video \(video.id) — stop() may have deactivated AVAudioSession")
        } else if let prev = currentVideo, prev.id != video.id, !isLoading {
            playerLog.notice("[load] switching from \(prev.id) to \(video.id) after stop()")
        }
        // If the exact same video is already being loaded, ignore the duplicate call.
        // SwiftUI can trigger load() multiple times during a single navigation (e.g.
        // selectedVideo binding re-evaluated while a queue autoplay is in flight).
        // Each duplicate spawns its own loadAsync → its own duplicate request storm.
        if currentVideo?.hasSamePlaybackSource(as: video) == true, isIncognito == incognito, isLoading {
            playerLog.notice("[load] already loading \(video.id) — ignoring duplicate call")
            return
        }
        // Cancel any previous in-flight load so we never have two concurrent API
        // fetches for the same (or different) video running at the same time.
        loadTask?.cancel()
        #if canImport(WebKit)
        if wkHLSEarlyTaskVideoId != video.id {
            cancelEarlyWebViewExtraction()
            wkHLSPermissionDenied = false
        }
        #endif

        // fix12: Same-video re-open fast path — if stop() parked the AVPlayerItem and it is
        // still .readyToPlay, bypass the entire exhaustiveRetry race (~1.27s saved per hot
        // cycle). Re-activates AVAudioSession, wires end/stall observers, and resumes.
        // Expected: <0.1s in-app → ~0.5s reported (XCTest polling overhead only).
        // Changing privacy mode must reset tracking and history through the full load path.
        if isIncognito == incognito, resumeParkedItem(for: video) {
            return
        }
        sponsorBlockManager.reset()
        // Different video or parked item expired — clear parked state and tear down old item.
        if parkedVideoId != nil {
            player.replaceCurrentItem(with: nil)
            parkedVideoId = nil
        }

        let prepared = shortsPreloader?.take(video: video, settings: settings)
        resetPlaybackForLoad(video: video, incognito: incognito)
        if let prepared { adoptPreparedShortPlayer(prepared.warmingPlayer) }

        // UI-testing synchronous inject for related videos.
        // Checked here (before the Task is created) so that hasNext = true is set
        // before the first XCTest accessibility-tree snapshot.  The async path in
        // loadAsync contains the same check and is kept as a belt-and-suspenders
        // guard in case load() is ever called without going through this entry point.
        if let relArg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-related-video-ids=")
        }) {
            let raw = String(relArg.dropFirst("--uitesting-inject-related-video-ids=".count))
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            if !ids.isEmpty {
                relatedVideos = ids.map { Video(id: $0, title: $0, channelTitle: "Test Channel") }
                hasNext = true
                playerLog.notice("UI-testing sync inject: set \(ids.count) related videos before Task")
            }
        }

        // Show the loading spinner synchronously — set before the Task starts so the
        // first frame of PlayerView already has isLoading=true. Without this, there is a
        // one-frame gap (one run-loop cycle) where the PlayerView renders with isLoading=false,
        // making the spinner invisible until the Task runs and sets it inside loadAsync().
        isLoading = true
        // UI-testing: re-show controls after load() resets controlsVisible=false.
        // Mirrors the onAppear --uitesting-show-controls handling so controls remain
        // visible across queue advances without relying on a second onAppear trigger.
        #if !os(iOS)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-show-controls") {
            showControls()
            cancelControlsHide()
        }
        #endif
        loadTask = Task {
            guard !Task.isCancelled else { return }
            await loadAsync(video: video, prepared: prepared)
        }

        // Kick off a background prefetch for the next video in the queue
        // so its PlayerInfo is warm in VideoPreloadCache before it is needed.
        // This fires immediately on load() so the full video duration is
        // available as warm-up time, rather than waiting until playback ends.
        if video.isDownloaded {
            hasNext = false
        } else if video.playlistId == CurrentQueueStore.playlistID,
            let nextIndex = video.playlistIndex.map({ $0 + 1 })
        {
            prefetchQueueVideo(at: nextIndex)
            // The queue has a next item — enable the next button immediately so
            // the user can advance before related videos finish loading.
            hasNext = true
        }
    }

    private func resumeParkedItem(for video: Video) -> Bool {
        guard let parked = parkedVideoId, parked == video.id, currentVideo?.hasSamePlaybackSource(as: video) == true,
            let parkedItem = player.currentItem, parkedItem.status == .readyToPlay
        else { return false }
        playerLog.notice("[fix12] same-video re-open — reusing parked AVPlayerItem for \(video.id)")
        parkedVideoId = nil
        logLocalPlaybackStep("parked item reused")
        #if canImport(WebKit)
        cancelEarlyWebViewExtraction()
        #endif
        currentVideo = video
        isLoading = false
        isPlaying = false
        videoEnded = false
        error = nil
        wasPlayingBeforeSuspend = false
        observePlaybackEndAndStalls(for: parkedItem)
        #if canImport(UIKit)
        setupRemoteCommandCenter()
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        requestAudioPlayback()
        return true
    }

    func resetPlaybackForLoad(video: Video, incognito: Bool) {
        beginPlaybackAudioSession()
        cancelBackgroundQualityUpgrade()
        audioOnlySwapTask?.cancel()
        // Report watchtime for the video being replaced before tearing it down.
        // This is the only opportunity when switching via load() directly (e.g. autoplay),
        // since stop()/suspend() are not called in that path. Uses the outgoing video's
        // incognito flag; an incognito video gets no tracker session (empty id), so
        // nothing is flushed or checkpointed for it later.
        let flushPrevious = recordsHistory && duration > 0
        isIncognito = incognito
        let flush = tracker.transition(
            to: incognito ? "" : video.id, cpn: InnerTubeAPI.generateCPN(),
            flushPosition: flushPrevious ? currentTime : 0,
            flushDuration: flushPrevious ? duration : 0)
        if flushPrevious { Task { await flush() } }

        // #150: on-device history, kept alongside the account reporting (which YouTube
        // doesn't always credit for device-code sign-in).
        if recordsHistory {
            localHistory.record(video)
        }

        // Stop and clear the current item immediately so the previous frame
        // is not visible while the next video is loading.
        player.pause()
        shortsPreloader?.cancel()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        videoEnded = false
        wasPlayingBeforeSuspend = false
        currentTime = 0
        duration = 0
        savedPositionToRestore = nil
        itemObserverTask?.cancel()
        durationObserverTask?.cancel()
        error = nil
        playerInfo = nil
        controlsVisible = false
        controlsTimer?.cancel()
        seekDebounceTask?.cancel()
        isScrubbing = false
        chapters = []
        captionsManager.reset()
        audioManager.reset()
        offlineTranslationTask?.cancel()
        offlineTranslationTask = nil
        voiceOver.stop()
        voiceOverOverride = nil
        endCards = []

        // Push the currently playing video onto the history stack before switching
        if !isShortsPlayer, let prev = currentVideo, prev.id != video.id {
            history.append(prev)
        }
        playbackDemand.stop()
        currentVideo = video
        // fix236: Record the intended video at load() time so checkWrongVideoOnFirstPlay()
        // can detect if a stale task swaps currentVideo before readyToPlay fires.
        intendedVideoId = video.id
        pendingWrongVideoCheck = true
        hasPrevious = !history.isEmpty
        retryAttempts = 0
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        cancelStallRecovery()
        stallEscalationCount = 0
        #if os(tvOS)
        tvEmbeddedEarlyTask?.cancel()
        tvEmbeddedEarlyTask = nil
        #endif
        qualityManager.reset()
        phase2Task?.cancel()
        phase2Task = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        AVAssetTrackCache.shared.clear()
    }

    /// User-initiated retry after all automatic fallbacks have been exhausted.
    /// Resets the retry guard and reloads the current video from scratch.
    public func retryLoad() {
        guard let video = currentVideo else { return }
        loadTask?.cancel()
        resetPlaybackForLoad(video: video, incognito: isIncognito)
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            await VideoPreloadCache.shared.invalidatePlayerInfo(for: video.id)
            guard !Task.isCancelled, self.currentVideo?.id == video.id else { return }
            await self.loadAsync(video: video)
        }
    }

    /// Call when the app returns to the foreground and this PlayerView is the visible one.
    /// Reactivates the AVAudioSession and resumes the player if it was playing
    /// before the interruption/background transition.
    public func handleForeground() {
        guard player.currentItem != nil else { return }
        // Resume only if we consider ourselves to be in playing state.
        // isPlaying is kept in sync with player.rate via KVO, so this only fires
        // when the player was paused while still intending to play (e.g. background transition).
        if isPlaying && player.rate == 0 {
            requestAudioPlayback()
            playerLog.notice("[handleForeground] resumed player after foreground transition")
        }
    }

    /// Call when the app enters the background.
    /// Pauses playback when the user has disabled background audio.
    public func handleBackground() {
        shortsPreloader?.cancel()
        guard !settings.backgroundPlaybackEnabled else { return }
        playbackDemand.pause()
        cancelPendingAudioPlayback()
        cancelBackgroundQualityUpgrade()
        // A pending stall recovery would otherwise resume playback in the background.
        cancelStallRecovery()
        guard isPlaying else { return }
        // Clear isPlaying before pausing so the rate observer doesn't treat this as a stall.
        isPlaying = false
        player.pause()
        playerLog.notice("[handleBackground] background playback disabled — paused")
    }

    /// Pauses playback and saves the watch position without tearing down the AVPlayerItem.
    /// Called when the PlayerView temporarily disappears (e.g. a sheet slides over it).
    /// Use `resume()` to restart playback, or `load(video:)` to switch videos.
    public func suspend() {
        playbackDemand.pause()
        cancelPendingAudioPlayback()
        cancelBackgroundQualityUpgrade()
        audioOnlySwapTask?.cancel()
        playerLog.notice(
            "[suspend] suspend() called — currentVideo=\(self.currentVideo?.id ?? "nil") currentTime=\(Int(self.currentTime))s"
        )
        if recordsHistory, duration > 0 {
            let pos = self.currentTime
            let dur = self.duration
            Task {
                await self.tracker.checkpoint(position: pos, duration: dur)
                playerLog.notice("Saved position \(Int(pos))s for suspend")
            }
        }
        wasPlayingBeforeSuspend = isPlaying
        cancelStallRecovery()
        player.pause()
        isPlaying = false
        // Suspension retains the system session, as before (the voice-over player
        // follows the video pause). Revoke intent so delayed work cannot restart it.
        if let audioSessionID { audioSession.invalidate(audioSessionID) }
        controlsTimer?.cancel()
        // Cancel in-flight load tasks so their @Observable state mutations do not
        // fire after the PlayerView has been removed from the SwiftUI hierarchy.
        // Without this, exhaustiveRetry callbacks crash with "No Observable object of
        // type SettingsStore found" when a sub-view rebuilds after dismiss.
        // Reported issue: a013be1c (EXC_BREAKPOINT in EnvironmentValues.subscript.getter).
        loadTask?.cancel()
        loadTask = nil
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        // rateObserver's KVO closure can independently re-spawn a brand-new
        // exhaustiveRetryTask (see setupRateObserver()'s "rapid stall loop"
        // escalation) — it was never invalidated outside deinit, so it kept firing
        // after suspend() and undoing the cancellation above, recreating the same
        // crash task-190 was supposed to have fixed. Re-established in resume().
        // Reported issue: a013be1c, regressed June 8 in 4.4(2) — still happening in 4.6.
        rateObserver?.invalidate()
        rateObserver = nil
        #if canImport(WebKit)
        cancelEarlyWebViewExtraction()
        #endif
        isLoading = false
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        updateNowPlayingPlayback()
        // Deregister from the global command center so a suspended VM never
        // handles lock screen Play while another VM is the active player.
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        #endif
    }

    /// Resumes playback after a `suspend()`. If the player has no current item
    /// (e.g. `stop()` was called), this is a no-op — use `load(video:)` instead.
    /// `stop()` keeps its item parked (fix12), so a parked item also means stopped.
    public func resume() {
        guard player.currentItem != nil, parkedVideoId == nil else {
            playerLog.notice("[resume] no item or stopped (parked) — skipping resume")
            return
        }
        playerLog.notice("[resume] resume() called — currentVideo=\(self.currentVideo?.id ?? "nil")")
        wasPlayingBeforeSuspend = false
        #if canImport(UIKit)
        // Re-register lock screen commands (removed in suspend()).
        setupRemoteCommandCenter()
        #endif
        // Re-establish the rate KVO observer (invalidated in suspend()) so isPlaying
        // stays in sync with the player again for this resumed session.
        setupRateObserver()
        requestAudioPlayback()
        showControls()
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        updateNowPlayingPlayback()
        #endif
    }

    // MARK: - Cleanup

    public func stop() {
        playbackDemand.stop()
        shortsPreloader?.cancel()
        qualityManager.cancel()
        sponsorBlockManager.cancelPendingSkip()
        cancelBackgroundQualityUpgrade()
        audioOnlySwapTask?.cancel()
        // Release the presenting view before teardown; suspend() keeps its handler.
        onPlaybackEnd = nil
        playerLog.notice(
            "[stop] stop() called — currentVideo=\(self.currentVideo?.id ?? "nil") currentTime=\(Int(self.currentTime))s isLoading=\(self.isLoading)"
        )
        // Save watch position before stopping (mirrors VideoStateController)
        if recordsHistory, duration > 0 {
            let pos = self.currentTime
            let dur = self.duration
            Task {
                await self.tracker.checkpoint(position: pos, duration: dur)
                playerLog.notice("Saved position \(Int(pos))s for stop")
            }
        }
        player.pause()
        // Keep the item briefly for same-video reopen; pressure or idle timeout releases it.
        parkedVideoId = currentVideo?.id
        offlineTranslationTask?.cancel()
        offlineTranslationTask = nil
        voiceOver.stop()
        isPlaying = false
        wasPlayingBeforeSuspend = false
        wasPlayingBeforeInterruption = false
        endPlaybackAudioSession()
        loadTask?.cancel()
        loadTask = nil
        // fix235: Cancel any in-flight exhaustiveRetry so it cannot call replaceCurrentItem
        // with a stale video after stop() returns. stop() does not spawn a new load so
        // exhaustiveRetryTask is left dangling otherwise.
        exhaustiveRetryTask?.cancel()
        exhaustiveRetryTask = nil
        cancelStallRecovery()
        // Reset isLoading immediately so a same-video re-open via play() does not hit
        // the early-return guard in load() before the cancelled task cleans up.
        isLoading = false
        phase2Task?.cancel()
        phase2Task = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        AVAssetTrackCache.shared.clear()
        #if canImport(WebKit)
        cancelEarlyWebViewExtraction()
        #endif
        // Browser CDN sessions are single-use; refresh only if playback needs the fallback again.
        if let stoppedVideoId = currentVideo?.id {
            Task { await VideoPreloadCache.shared.invalidateWKHLSURL(for: stoppedVideoId) }
        }
        itemObserverTask?.cancel()
        itemObserverTask = nil
        endObserverTask?.cancel()
        endObserverTask = nil
        stallObserverTask?.cancel()
        stallObserverTask = nil
        durationObserverTask?.cancel()
        durationObserverTask = nil
        // Defense-in-depth, same reasoning as suspend(): a live rateObserver's KVO
        // closure can independently spawn a new exhaustiveRetryTask after this
        // function returns. stop()'s synchronous pause()/isPlaying=false ordering
        // happens to make that unreachable today, but invalidating here removes the
        // dependency on that ordering. Re-established defensively in loadAsync().
        rateObserver?.invalidate()
        rateObserver = nil
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        clearNowPlayingInfo()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        #endif
        if let audioSessionObserver { audioSessionNotificationCenter.removeObserver(audioSessionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
        audioSessionObserver = nil
        routeChangeObserver = nil
        if isShortsPlayer {
            player.replaceCurrentItem(with: nil)
            qualityManager.reset()
        } else {
            scheduleParkedItemCleanup()
        }
    }

    private func scheduleParkedItemCleanup() {
        let parkedItem = player.currentItem
        parkedResourceCleanup.schedule { [weak self, weak parkedItem] in
            guard let self, self.parkedVideoId != nil, !self.isPlaying,
                let parkedItem, self.player.currentItem === parkedItem
            else { return }
            self.player.replaceCurrentItem(with: nil)
            self.qualityManager.reset()
            // Keep the stopped marker: PlayerStateStore must not expose this video again.
        }
    }

    // MARK: - Phase 2: Background enrichment

    /// Runs concurrently with playback after Phase 1 completes.
    /// Fetches data that is not needed to start AVPlayer: related videos, end cards,
    /// SponsorBlock segments (cache miss only), tracking URLs, and neighbour prefetch.
    /// All property assignments happen on @MainActor because PlaybackViewModel is @MainActor.
    func loadAsyncPhase2(
        video: Video,
        cached: CachedVideoData,
        info: PlayerInfo,
        cachedTrackingURLs: PlaybackTrackingURLs?,
        authTrackingTask: Task<PlaybackTrackingURLs?, Never>?,
        sponsorCached: Bool
    ) async {
        guard !Task.isCancelled else { return }

        await loadPhase2SponsorSegments(video: video, cached: cached, sponsorCached: sponsorCached)

        guard !Task.isCancelled else { return }

        if isShortsPlayer {
            // Shorts has its own feed; /next and end cards are unused here.
            let tracking = recordsHistory ? await api.fetchAuthenticatedTrackingURLs(videoId: video.id) : nil
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            tracker.setTrackingURLs(tracking ?? info.trackingURLs)
            return
        }

        await loadPhase2RelatedVideos(video: video, cached: cached)

        guard !Task.isCancelled else { return }

        // --- End cards ---
        if let cachedCards = cached.endCards, !cached.staleFields.contains(.endCards) {
            playerLog.notice("cache HIT: endCards (skipping network)")
            endCards = cachedCards
        } else if let staleCards = cached.endCards, cached.staleFields.contains(.endCards) {
            playerLog.notice("SWR: endCards stale — using cached, revalidating in background")
            endCards = staleCards
            let videoId = video.id
            Task(priority: .background) { [api = self.api] in
                if let fresh = try? await api.fetchEndCards(videoId: videoId) {
                    await VideoPreloadCache.shared.store(endCards: fresh, for: videoId)
                }
            }
        } else if !info.endCards.isEmpty {
            endCards = info.endCards
            playerLog.notice("endCards: \(info.endCards.count) from primary response")
            await VideoPreloadCache.shared.store(endCards: info.endCards, for: video.id)
        } else {
            do {
                let webCards = try await api.fetchEndCards(videoId: video.id)
                guard !Task.isCancelled else { return }
                endCards = webCards
                playerLog.notice("endCards: \(webCards.count) from web client fallback")
                await VideoPreloadCache.shared.store(endCards: webCards, for: video.id)
            } catch {
                playerLog.error("endCards fetch failed: \(ViewModelLogger.errorSummary(error))")
                endCards = []
            }
        }

        guard !Task.isCancelled else { return }

        // --- Tracking URLs ---
        let resolvedTrackingURLs: PlaybackTrackingURLs?
        if let cachedTracking = cachedTrackingURLs {
            resolvedTrackingURLs = cachedTracking
            playerLog.notice("cache HIT: trackingURLs")
        } else {
            resolvedTrackingURLs = await authTrackingTask?.value ?? info.trackingURLs
            await VideoPreloadCache.shared.store(trackingURLs: resolvedTrackingURLs, for: video.id)
        }
        guard !Task.isCancelled else { return }
        tracker.setTrackingURLs(resolvedTrackingURLs)  // incognito: session id is empty, never flushed
        playerLog.notice("activeTrackingURLs resolved: \(resolvedTrackingURLs != nil ? "account-bound" : "none")")

        prefetchNeighboursIfNeeded(info: info)
    }

    private func loadPhase2SponsorSegments(video: Video, cached: CachedVideoData, sponsorCached: Bool) async {
        // --- SponsorBlock cache miss or stale ---
        if !sponsorCached, settings.sponsorBlockEnabled {
            let channelIsExcluded =
                video.channelId.map {
                    settings.sponsorBlockExcludedChannels.keys.contains($0)
                } ?? false
            if !channelIsExcluded {
                let videoId = video.id
                let cats = settings.activeSponsorCategories
                let minDur = settings.sponsorBlockMinSegmentDuration
                if cached.staleFields.contains(.sponsorSegments) {
                    // Stale data was already applied in Phase 1 — revalidate silently.
                    Task(priority: .background) { [weak self] in
                        guard let self else { return }
                        let segments = await self.sponsorBlock.fetchSegments(videoId: videoId, categories: cats)
                        await VideoPreloadCache.shared.store(sponsorSegments: segments, for: videoId)
                    }
                } else {
                    // Full miss — fetch now and apply.
                    var segments = await sponsorBlock.fetchSegments(videoId: videoId, categories: cats)
                    await VideoPreloadCache.shared.store(sponsorSegments: segments, for: videoId)
                    guard !Task.isCancelled else { return }
                    if minDur > 0 { segments = segments.filter { ($0.end - $0.start) >= minDur } }
                    sponsorSegments = segments
                    playerLog.notice("[sponsorBlock] phase2 applied \(segments.count) segments for \(videoId)")
                }
            }
        }
    }

    private func loadPhase2RelatedVideos(video: Video, cached: CachedVideoData) async {
        // --- Related videos + like status ---
        // UI testing inject: bypass all network fetches for related videos.
        // Used by testPlayerSwipeRightWorksWhenControlsAreVisible which runs on
        // clone simulators that may lack network access for playerInfo.
        if let relArg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--uitesting-inject-related-video-ids=")
        }) {
            let raw = String(relArg.dropFirst("--uitesting-inject-related-video-ids=".count))
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            if !ids.isEmpty {
                relatedVideos = ids.map { Video(id: $0, title: $0, channelTitle: "Test Channel") }
                hasNext = true
                playerLog.notice("UI-testing inject: set \(ids.count) related videos synchronously")
                // fall through to remainder of loading (chapters, endCards, etc.)
            }
        } else {

            // Fresh cache hit: use immediately (no network).
            // Stale cache hit: stale data was already returned by consume() — revalidate silently in background.
            // Full miss: live blocking fetch so relatedVideos is populated before the panel opens.
            let nextInfo: NextInfo?
            if let cachedNext = cached.nextInfo, !cached.staleFields.contains(.nextInfo) {
                playerLog.notice("cache HIT: nextInfo chapters=\(cachedNext.chapters.count) (skipping network)")
                nextInfo = cachedNext
            } else if let staleNext = cached.nextInfo, cached.staleFields.contains(.nextInfo) {
                playerLog.notice(
                    "SWR: nextInfo stale chapters=\(staleNext.chapters.count) — using cached, revalidating in background"
                )
                nextInfo = staleNext
                let videoId = video.id
                Task(priority: .background) { [api = self.api] in
                    if let fresh = try? await api.fetchNextInfo(videoId: videoId) {
                        await VideoPreloadCache.shared.store(nextInfo: fresh, for: videoId)
                    }
                }
            } else {
                nextInfo = try? await api.fetchNextInfo(videoId: video.id)
                if let nextInfo { await VideoPreloadCache.shared.store(nextInfo: nextInfo, for: video.id) }
            }

            guard !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else { return }

            if let nextInfo, !nextInfo.relatedVideos.isEmpty {
                relatedVideos = nextInfo.relatedVideos.filter { $0.id != video.id }
            } else {
                let fallbackQuery = video.title.isEmpty ? nil : video.title
                if let query = fallbackQuery {
                    let searched = try? await api.search(query: query)
                    guard !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else { return }
                    relatedVideos =
                        searched?.videos.filter { $0.id != video.id }.prefix(InnerTubeClients.maxVideoResults).map {
                            $0
                        } ?? []
                } else {
                    relatedVideos = []
                }
            }
            await updateNextAvailability(for: video)
            guard !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true else { return }
            if let status = nextInfo?.likeStatus { likeDislike.setLikeStatus(status) }
            if let ch = nextInfo?.chapters, !ch.isEmpty {
                chapters = ch
                playerLog.notice("[chapters] applied \(ch.count) chapters for \(video.id)")
            } else {
                playerLog.notice(
                    "[chapters] none for \(video.id) (nextInfo chapters=\(nextInfo?.chapters.count ?? -1))")
            }

            // hasNext is now fully resolved (related videos + queue fallback). Update the
            // lock-screen now-playing info so nextTrackCommand.isEnabled reflects the real
            // state. Without this call the next/prev buttons only appear if hasNext was
            // already true during phase-1 (playlist videos); for home-feed autoplay the
            // buttons are permanently missing.
            #if canImport(UIKit)
            updateNowPlayingInfo()
            #endif

        }  // end of non-inject related-videos branch
    }

    func updateNextAvailability(for video: Video) async {
        // A same-source selection can adopt another queue while either the API or queue lookup is suspended.
        for _ in 0..<PlaybackTuning.maxQueueContextAttempts {
            guard !Task.isCancelled, parkedVideoId == nil,
                let current = currentVideo, current.hasSamePlaybackSource(as: video)
            else { return }
            var canAdvance = !relatedVideos.isEmpty
            if !canAdvance, let index = CurrentQueueStore.queueIndex(of: current) {
                canAdvance = await queue.videoAt(index: index + 1) != nil
            }
            guard !Task.isCancelled, parkedVideoId == nil else { return }
            guard hasCurrentQueueContext(current) else { continue }
            hasNext = canAdvance
            return
        }
        playerLog.notice("Next availability kept after repeated queue changes")
    }

    private func prefetchNeighboursIfNeeded(info: PlayerInfo) {
        // Shorts owns its next-video list and already prefetches that list on navigation.
        guard onPlaybackEnd == nil else { return }

        #if canImport(WebKit)
        if !info.isFromVisionOSClient, let firstNeighbour = relatedVideos.first?.id {
            Task(priority: .background) { [weak self] in
                await self?.preExtractWKHLSForVideo(firstNeighbour)
            }
        }
        #endif

        // BUG-015 fix: read currentAuthToken per-prefetch-call so a token refresh mid-loop
        // uses the fresh token rather than a stale snapshot captured before the loop starts.
        let neighbourIds = Array(relatedVideos.prefix(3).map(\.id))
        let sponsorCats = settings.activeSponsorCategories
        playerLog.notice("[prefetch] scheduling \(neighbourIds.count) neighbours")
        Task(priority: .background) { [weak self] in
            for videoId in neighbourIds {
                let token = await MainActor.run { self?.currentAuthToken }
                await VideoPreloadCache.shared.prefetch(
                    videoId: videoId,
                    sponsorCategories: sponsorCats,
                    authToken: token,
                    priority: .speculative
                )
            }
        }

    }
}

extension PlaybackViewModel {
    #if canImport(WebKit)
    func cancelEarlyWebViewExtraction() {
        wkHLSEarlyTask?.cancel()
        wkHLSEarlyTask = nil
        if let videoId = wkHLSEarlyTaskVideoId {
            YouTubeWebViewHLSExtractor.shared.cancelCurrentExtraction(for: videoId)
        }
        wkHLSEarlyTaskVideoId = nil
    }
    #endif
}
