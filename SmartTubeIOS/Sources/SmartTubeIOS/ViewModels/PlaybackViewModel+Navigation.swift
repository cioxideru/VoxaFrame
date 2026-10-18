import AVFoundation
import SmartTubeIOSCore
import os

private let playerLog = ViewModelLogger(category: "Player")

protocol PlaybackQueue: Sendable {
    func videoAt(index: Int) async -> Video?
    func remainingVideos(after index: Int) async -> [Video]
    func clear() async
}

extension CurrentQueueStore: PlaybackQueue {}

// MARK: - Queue, History & Chapter Navigation

extension PlaybackViewModel {

    // MARK: - Next-video prefetch

    /// Prefetches the queue video at `index` in the background so its PlayerInfo
    /// is warm in `VideoPreloadCache` before `load(video:)` is called for it.
    /// Uses `.immediate` priority so it jumps ahead of speculative card prefetches.
    /// Safe to call multiple times for the same video — the cache deduplicates.
    func prefetchQueueVideo(at index: Int) {
        let sponsorCats = settings.activeSponsorCategories
        let token = currentAuthToken
        Task(priority: .userInitiated) { [weak self, queue] in
            guard let next = await queue.videoAt(index: index) else { return }
            // Pre-warm only when the queue actually has a video to prepare.
            #if canImport(WebKit)
            if !BotGuardWebViewRunner.shared.isReady {
                Task(priority: .background) {
                    await BotGuardWebViewRunner.shared.prepare()
                }
            }
            #endif
            playerLog.notice("[prefetch] next-queue video index=\(index) id=\(next.id)")
            await VideoPreloadCache.shared.prefetch(
                videoId: next.id,
                sponsorCategories: sponsorCats,
                authToken: token,
                priority: .immediate
            )
            // Also prefetch the one after — avoids a cold start if the user
            // taps "next" quickly before the first prefetch completes.
            guard let _ = self else { return }
            let afterNext = await queue.videoAt(index: index + 1)
            if let afterNext {
                playerLog.notice("[prefetch] next+1 queue video index=\(index + 1) id=\(afterNext.id)")
                await VideoPreloadCache.shared.prefetch(
                    videoId: afterNext.id,
                    sponsorCategories: sponsorCats,
                    authToken: token,
                    priority: .visible  // beats home-feed card prefetches so it finishes before the user taps twice
                )
            }
        }
    }

    // MARK: - Navigation

    func hasCurrentQueueContext(_ video: Video) -> Bool {
        currentVideo?.hasSamePlaybackSource(as: video) == true
            && currentVideo?.playlistId == video.playlistId
            && currentVideo?.playlistIndex == video.playlistIndex
            && currentVideo?.setVideoId == video.setVideoId
    }

    /// Play the next related video. Advances through the Current Queue if one is
    /// active; otherwise falls back to the first related (suggestion) video.
    public func playNext() {
        guard parkedVideoId == nil else { return }
        if let source = currentVideo, CurrentQueueStore.queueIndex(of: source) != nil {
            Task { await advanceQueue(for: source, autoplay: false) }
            return
        }
        playNextFromSuggestions()
    }

    private func advanceQueue(for source: Video, autoplay: Bool) async {
        // Reselection changes queue context without changing the playback source or cancelling this action.
        for _ in 0..<PlaybackTuning.maxQueueContextAttempts {
            guard parkedVideoId == nil, let current = currentVideo, current.hasSamePlaybackSource(as: source)
            else { return }
            guard let index = CurrentQueueStore.queueIndex(of: current) else {
                if autoplay { autoplayFromRecommendations() } else { playNextFromSuggestions() }
                return
            }
            let shuffle = autoplay && settings.queueShuffleEnabled
            let next: Video?
            if shuffle {
                next = await queue.remainingVideos(after: index).randomElement()
            } else {
                next = await queue.videoAt(index: index + 1)
            }
            guard parkedVideoId == nil, currentVideo?.hasSamePlaybackSource(as: source) == true else { return }
            guard hasCurrentQueueContext(current) else { continue }
            if let next {
                playerLog.notice("Queue advance: id=\(next.id) autoplay=\(autoplay) shuffle=\(shuffle)")
                if !shuffle { prefetchQueueVideo(at: index + 2) }
                load(video: next)
                return
            }
            await queue.clear()
            guard parkedVideoId == nil, currentVideo?.hasSamePlaybackSource(as: source) == true else { return }
            guard hasCurrentQueueContext(current) else { continue }
            if autoplay { autoplayFromRecommendations() } else { playNextFromSuggestions() }
            return
        }
        playerLog.notice("Queue advance stopped after repeated queue changes")
        if autoplay { videoEnded = true }
    }

    private func playNextFromSuggestions() {
        guard let next = relatedVideos.first else { return }
        playerLog.notice("playNext: id=\(next.id)")
        load(video: next)
    }

    /// Play the most recently played video from the history stack.
    /// Pops the last entry from history; load() will push the current video back so
    /// the user can navigate forward again with playNext() or via suggestions.
    public func playPrevious() {
        guard !history.isEmpty else { return }
        let prev = history.removeLast()
        hasPrevious = !history.isEmpty
        playerLog.notice("playPrevious: id=\(prev.id)")
        load(video: prev)
    }

    /// Seek to the start of the next chapter.
    public func skipToNextChapter() {
        guard let next = chapters.first(where: { $0.startTime > currentTime }) else { return }
        seek(to: next.startTime)
        showControls()
    }

    /// Seek to the start of the current chapter (if >3 s in) or to the previous chapter.
    public func skipToPreviousChapter() {
        guard let current = currentChapter else { return }
        if currentTime - current.startTime > 3 {
            seek(to: current.startTime)
        } else if let prev = chapters.last(where: { $0.startTime < current.startTime }) {
            seek(to: prev.startTime)
        }
        showControls()
    }

    public func handlePlaybackEnd() {
        guard parkedVideoId == nil else { return }
        if let onPlaybackEnd {
            onPlaybackEnd()
            return
        }
        if settings.loopEnabled {
            player.seek(to: .zero)
            player.rate = Float(settings.playbackSpeed)
            return
        }
        if let source = currentVideo, CurrentQueueStore.queueIndex(of: source) != nil {
            Task { await advanceQueue(for: source, autoplay: true) }
            return
        }
        autoplayFromRecommendations()
    }

    /// Falls back to a recommended video when there's no active queue (or the
    /// queue has just been exhausted): shuffles from `relatedVideos` if shuffle
    /// is enabled, otherwise autoplays the first related video if autoplay is
    /// enabled, otherwise marks the video as ended.
    private func autoplayFromRecommendations() {
        if settings.shuffleEnabled, !relatedVideos.isEmpty {
            let pick = relatedVideos[Int.random(in: 0..<relatedVideos.count)]
            playerLog.notice("Shuffle: loading id=\(pick.id)")
            load(video: pick)
            return
        }
        guard settings.autoplayEnabled, let next = relatedVideos.first else {
            videoEnded = true
            return
        }
        playerLog.notice("Autoplay: loading next video id=\(next.id)")
        load(video: next)
    }
}
