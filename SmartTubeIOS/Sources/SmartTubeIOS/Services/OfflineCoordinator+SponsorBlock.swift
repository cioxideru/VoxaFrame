import Foundation
import Observation
import SmartTubeIOSCore
import os

private let sponsorLog = Logger(subsystem: appSubsystem, category: "OfflineSponsorBlock")

public enum OfflineSponsorUpdateState: Equatable, Sendable {
    case idle
    case running(done: Int, total: Int)
    case finished(updated: Int, failed: Int)
}

/// Used until `configure` installs the real service, so a coordinator built outside the app never
/// reaches the network.
private struct InertSponsorSource: SponsorSegmentSource {
    // swiftlint:disable:next async_without_await
    func segments(videoId: String, categories: Set<SponsorSegment.Category>) async throws -> [SponsorSegment] {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor @Observable
final class OfflineSponsorState {
    @ObservationIgnored var source: any SponsorSegmentSource = InertSponsorSource()
    /// Reads the current global SponsorBlock switch; checked before every request.
    @ObservationIgnored var isEnabled: () -> Bool = { true }
    /// Reads the live "update automatically" preference; checked before every automatic request.
    @ObservationIgnored var isAutoUpdateEnabled: () -> Bool = { true }
    /// Pending request per video: callers asking for the same video share its result.
    @ObservationIgnored var pending: [String: Task<Bool, Never>] = [:]
    /// Last queued request; the next one waits for it, so requests run one at a time.
    @ObservationIgnored var tail: Task<Bool, Never>?
    /// Held from the due check to the timestamp commit of an automatic run.
    @ObservationIgnored var automaticRunning = false
    /// Progress and outcome of the bulk "Update SponsorBlock" action.
    var update = OfflineSponsorUpdateState.idle
}

/// SponsorBlock segments for saved videos: fetched best effort, stored with the entry, used offline.
extension OfflineCoordinator {
    func configureSponsor(settings: SettingsStore) {
        #if DEBUG
        sponsor.source = OfflineUITestFixture.sponsorSource() ?? SponsorBlockService()
        #else
        sponsor.source = SponsorBlockService()
        #endif
        sponsor.isEnabled = { settings.settings.sponsorBlockEnabled }
        sponsor.isAutoUpdateEnabled = { settings.settings.offlineSponsorBlockAutoUpdate }
    }

    /// After a download. Best effort and never awaited: a SponsorBlock failure must not affect the download.
    func fetchSponsorSegmentsIfMissing(videoID: String) {
        guard snapshot.entries.first(where: { $0.id == videoID })?.sponsor == nil else { return }
        Task { await refreshSponsorSegments(videoID: videoID) }
    }

    /// Fetches every supported category (category settings are applied at playback) and stores the
    /// result. Returns false on any failure or when SponsorBlock is off; nothing is stored then, so the
    /// next refresh retries. One request runs at a time; callers for the same video share its result.
    @discardableResult func refreshSponsorSegments(videoID: String, automatic: Bool = false) async -> Bool {
        if let shared = sponsor.pending[videoID] { return await shared.value }
        guard sponsor.isEnabled(), !persistenceBlocked else { return false }
        let previous = sponsor.tail
        let task = Task { [self] () -> Bool in
            _ = await previous?.value
            defer { sponsor.pending[videoID] = nil }
            return await fetchAndStoreSponsorSegments(videoID: videoID, automatic: automatic)
        }
        sponsor.pending[videoID] = task
        sponsor.tail = task
        return await task.value
    }

    private func fetchAndStoreSponsorSegments(videoID: String, automatic: Bool) async -> Bool {
        // The settings may have changed while this request waited in line.
        guard sponsor.isEnabled(), !automatic || sponsor.isAutoUpdateEnabled(), !persistenceBlocked else {
            return false
        }
        do {
            let segments = try await sponsor.source.segments(
                videoId: videoID, categories: Set(SponsorSegment.Category.allCases))
            apply(try await store.setSponsorSegments(videoID: videoID, segments: segments, fetchedAt: now()))
            return true
        } catch {
            sponsorLog.notice("SponsorBlock refresh failed: \(ViewModelLogger.errorSummary(error), privacy: .public)")
            return false
        }
    }

    /// Sequential refresh of every saved video. `stopOnError` is for the background run.
    @discardableResult func refreshAllSponsorSegments(stopOnError: Bool = false) async -> OfflineSponsorUpdateState {
        if case .running = sponsor.update { return sponsor.update }
        let ids = snapshot.entries.filter { !$0.assets.isEmpty }.map(\.id)
        var updated = 0
        var failed = 0
        for id in ids {
            guard sponsor.isEnabled(), !stopOnError || sponsor.isAutoUpdateEnabled() else {
                failed = ids.count - updated
                break
            }
            sponsor.update = .running(done: updated + failed, total: ids.count)
            if await refreshSponsorSegments(videoID: id, automatic: stopOnError) {
                updated += 1
            } else {
                failed += 1
                if stopOnError { break }
            }
        }
        sponsor.update = .finished(updated: updated, failed: failed)
        return sponsor.update
    }

    /// Called when the app becomes active; throttled to once a day. No timers, one request at a time.
    /// Makes no request while the automatic setting or SponsorBlock itself is off.
    public func appBecameActive(_ settings: AppSettings) {
        Task { await refreshSponsorSegmentsOnActivation(settings) }
    }

    func refreshSponsorSegmentsOnActivation(_ settings: AppSettings) async {
        guard settings.sponsorBlockEnabled, settings.offlineSponsorBlockAutoUpdate, !sponsor.automaticRunning
        else { return }
        sponsor.automaticRunning = true
        defer { sponsor.automaticRunning = false }
        start()
        await startup?.value
        // Re-read the live preferences: they may have changed while the library was loading.
        guard sponsor.isEnabled(), sponsor.isAutoUpdateEnabled(), ready, !persistenceBlocked,
            OfflineSponsorSegments.isRefreshDue(lastRefresh: snapshot.sponsorRefreshedAt, now: now())
        else { return }
        guard case .finished(_, let failed) = await refreshAllSponsorSegments(stopOnError: true), failed == 0 else {
            return
        }
        do { apply(try await store.markSponsorRefresh(at: now())) } catch { blockPersistence(error) }
    }

    /// Stored segments, filling in once for videos saved before this feature (or adopting a refresh that is
    /// already running). Offline, the fetch fails and playback simply goes without segments.
    func sponsorSegmentsForPlayback(videoID: String) async -> OfflineSponsorSegments? {
        func stored() async -> OfflineSponsorSegments? {
            try? await store.snapshot().entries.first(where: { $0.id == videoID })?.sponsor
        }
        if let existing = await stored() { return existing }
        guard await refreshSponsorSegments(videoID: videoID) else { return nil }
        return await stored()
    }
}
