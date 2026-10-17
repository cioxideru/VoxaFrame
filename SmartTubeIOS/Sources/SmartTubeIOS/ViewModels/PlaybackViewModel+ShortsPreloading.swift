import AVFoundation
import SmartTubeIOSCore

extension PlaybackViewModel {
    /// Called only after the outgoing session's tasks, translation and item have been cleared.
    func adoptPreparedShortPlayer(_ preparedPlayer: AVPlayer) {
        precondition(isShortsPlayer)
        let wasMuted = player.isMuted
        if let timeObserver { timeObserver.player.removeTimeObserver(timeObserver.token) }
        timeObserver = nil
        rateObserver?.invalidate()
        airPlayObserver?.invalidate()
        player = preparedPlayer
        updatePlaybackDemand()
        player.isMuted = wasMuted
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        qualityManager.player = player
        audioManager.player = player
        sponsorBlockManager.player = player
        shortsPreloader?.player = player
        setupTimeObserver()
        setupRateObserver()
        #if canImport(UIKit)
        setupAirPlayObserver()
        #endif
    }

    func preloadNextShort(_ video: Video?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-disable-shorts-preload") { return }
        #endif
        guard !isLoading, isPlaying, error == nil else { return }
        shortsPreloader?.prepare(video, settings: settings)
    }

    func startPreparedShort(_ prepared: PreparedShort, video: Video) async -> Bool {
        guard player.currentItem === prepared.item else { return false }
        playerInfo = prepared.info
        availableFormats = prepared.formats
        availableCaptions = prepared.info.captionTracks
        autoApplyCaptionPreference(tracks: availableCaptions)
        hlsVariantURLs = prepared.variants
        let policy = prepared.preference.policy
        qualityManager.configureHLSPlayback(
            userAgent: policy.userAgent,
            maximumHeight: policy.maximumHeight, videoCodecs: policy.videoCodecs)
        qualityManager.setSelectedFormatForCurrentPreference()
        qualityManager.nativeHLSProxyLoader = prepared.proxy
        if let height = policy.cappedHeight(requested: qualityManager.resolvedHeight(for: effectiveQuality)) {
            prepared.item.preferredMaximumResolution = CGSize(width: height * 4, height: height)
            prepared.item.preferredPeakBitRate = peakBitRate(for: height)
        } else {
            prepared.item.preferredMaximumResolution = .zero
            prepared.item.preferredPeakBitRate = 0
        }
        lastAttemptedStreamURL = prepared.info.hlsURL
        observePlaybackEndAndStalls(for: prepared.item)
        for await status in prepared.item.statusStream(timeout: PlaybackTuning.itemReadinessTimeout) {
            guard !Task.isCancelled, currentVideo?.id == video.id,
                player.currentItem === prepared.item
            else { return false }
            switch status {
            case .readyToPlay:
                cacheStatusSummary = "shorts:prepared"
                attemptItemBecameReady(
                    prepared.item, video: video, info: prepared.info,
                    label: "VisionOS/HLS-preloaded", isMuxedFallback: false)
                return true
            case .failed: return false
            default: continue
            }
        }
        return false
    }
}
