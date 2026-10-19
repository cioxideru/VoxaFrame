import AVFoundation
import SmartTubeIOSCore
import os

@MainActor
protocol OfflineSponsorSegmentProviding {
    func sponsorSegmentsForPlayback(videoID: String) async -> OfflineSponsorSegments?
}

extension OfflineCoordinator: OfflineSponsorSegmentProviding {}

// MARK: - SponsorBlock (thin wrapper — logic lives in SponsorBlockSkipManager)

extension PlaybackViewModel {

    @discardableResult
    public func checkSponsorSkip(at time: TimeInterval) -> Bool {
        sponsorBlockManager.checkSponsorSkip(at: time)
    }

    public func skipToastSegment() {
        sponsorBlockManager.skipToastSegment()
    }

    /// Saved videos use the segments stored with the entry, filtered by the current SponsorBlock settings,
    /// so skipping, toasts and timeline marks behave as for streamed videos without a network.
    /// Runs beside item preparation and never delays it.
    func applyOfflineSponsorSegments(for video: Video) async {
        offlineSponsorStored = nil
        sponsorSegments = []
        offlineSponsorLookupID = nil
        let excluded = video.channelId.map { settings.sponsorBlockExcludedChannels.keys.contains($0) } ?? false
        guard settings.sponsorBlockEnabled, !excluded else { return }
        offlineSponsorLookupID = video.id
        let stored = await offlineSponsor.sponsorSegmentsForPlayback(videoID: video.id)
        guard !Task.isCancelled, currentVideo?.hasSamePlaybackSource(as: video) == true, let stored else { return }
        offlineSponsorStored = (video.id, stored)
        refilterOfflineSponsorSegments()
    }

    /// Settings now allow SponsorBlock for the saved video on screen but nothing was looked up (it was off or
    /// excluded when playback started): start the lookup once, without reloading the player.
    func startOfflineSponsorLookupIfNeeded() {
        guard let video = currentVideo, video.isDownloaded, offlineSponsorStored?.id != video.id,
            offlineSponsorLookupID != video.id, settings.sponsorBlockEnabled,
            !(video.channelId.map { settings.sponsorBlockExcludedChannels.keys.contains($0) } ?? false)
        else { return }
        Task { [weak self] in await self?.applyOfflineSponsorSegments(for: video) }
    }

    /// A parked saved item comes back: re-filter what is stored, or look it up if nothing was (SponsorBlock was off).
    func reuseOfflineSponsorSegments() {
        guard let video = currentVideo, video.isDownloaded else { return }
        refilterOfflineSponsorSegments()
        startOfflineSponsorLookupIfNeeded()
    }

    /// Re-applies the current settings (enabled, categories, minimum length, channel exclusion) to the stored
    /// segments of the saved video on screen. Called after the lookup, when settings change and when a parked
    /// item is reused.
    func refilterOfflineSponsorSegments() {
        guard let video = currentVideo, video.isDownloaded, let stored = offlineSponsorStored, stored.id == video.id
        else { return }
        let excluded = video.channelId.map { settings.sponsorBlockExcludedChannels.keys.contains($0) } ?? false
        sponsorSegments =
            settings.sponsorBlockEnabled && !excluded
            ? stored.segments.active(
                categories: settings.activeSponsorCategories, minDuration: settings.sponsorBlockMinSegmentDuration)
            : []
        // A toast whose segment is no longer eligible must not leave a skip button behind.
        if let toast = currentToastSegment, !sponsorSegments.contains(where: { $0.id == toast.id }) {
            currentToastSegment = nil
        }
    }
}
