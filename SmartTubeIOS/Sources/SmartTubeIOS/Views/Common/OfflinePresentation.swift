import Foundation
import SmartTubeIOSCore

/// How the offline screens describe `OfflineCoordinator` state. Mapping only: it adds no state or behaviour
/// (PLAN-0027, "Stage 6 basis").
enum OfflinePresentation {
    /// Keep the chosen video through snapshot updates; deletion leaves the detail empty, without choosing a neighbour.
    static func retainedSelection(_ videoID: String?, entries: [OfflineEntry]) -> String? {
        guard let videoID, entries.contains(where: { $0.id == videoID }) else { return nil }
        return videoID
    }

    /// A job's visible status. Waiting for translation is a queued job whose resolution was deferred.
    enum JobStatus: Equatable {
        case queued, waitingForTranslation, resolving, downloading(Double), completed, failed, cancelled
    }

    /// The one action a job row offers besides Delete task and files, which every job has.
    enum JobAction: Equatable { case cancel, retry, open }

    /// Badge of a library row: what this video's jobs are doing, otherwise whether it can play.
    enum EntryStatus: Equatable { case downloading(Double), preparing, queued, failed, ready, notReady }

    /// A kind of saved file, in display order.
    enum Part: CaseIterable { case video, audio, translation }

    enum PageState: Equatable { case loading, storageError(String), empty, content }

    struct JobGroup: Identifiable {
        let videoID: String
        let title: String
        let jobs: [OfflineJob]
        var id: String { videoID }
    }

    static func status(_ job: OfflineJob) -> JobStatus {
        switch job.state {
        case .queued: job.nextResolutionAt == nil ? .queued : .waitingForTranslation
        case .resolving: .resolving
        case .downloading: .downloading(job.progress)
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    static func action(_ job: OfflineJob) -> JobAction {
        switch job.state {
        case .queued, .resolving, .downloading: .cancel
        case .failed, .cancelled: .retry
        case .completed: .open
        }
    }

    /// Jobs under their video, in the order each video first appears in the queue.
    static func groups(jobs: [OfflineJob], entries: [OfflineEntry]) -> [JobGroup] {
        var order: [String] = []
        var byVideo: [String: [OfflineJob]] = [:]
        for job in jobs {
            if byVideo[job.videoID] == nil { order.append(job.videoID) }
            byVideo[job.videoID, default: []].append(job)
        }
        return order.map { id in
            JobGroup(videoID: id, title: title(of: id, in: entries), jobs: byVideo[id] ?? [])
        }
    }

    /// The video title, or its ID when the title is unknown (a deep link opens a video without one).
    static func title(of videoID: String, in entries: [OfflineEntry]) -> String {
        guard let title = entries.first(where: { $0.id == videoID })?.video.title, !title.isEmpty else {
            return videoID
        }
        return title
    }

    /// A storage error replaces the empty state; loading lasts until the library is ready.
    /// With saved content the error is shown above it instead, so working files stay reachable.
    static func pageState(ready: Bool, error: String?, isEmpty: Bool) -> PageState {
        if let error, isEmpty { return .storageError(error) }
        if !ready, error == nil { return .loading }
        return isEmpty ? .empty : .content
    }

    /// `OfflineCoordinator` ignores changes while storage is blocked and does not reject a second removal
    /// while one is pending, so every change, including an already open confirmation, waits for both to clear.
    /// `persistenceBlocked` is not observed and a storage failure may leave the snapshot unchanged; its observed
    /// `error` is set in the same step, so passing it makes a view re-render and lock on the failure.
    static func isLocked(storageError: String?, persistenceBlocked: Bool, pendingRemovals: [OfflineRemoval]?) -> Bool {
        storageError != nil || persistenceBlocked || !(pendingRemovals ?? []).isEmpty
    }

    /// The player only takes the network while it starts or rebuffers; say so only when a download is waiting.
    static func showsYieldNotice(isYielding: Bool, jobs: [OfflineJob]) -> Bool {
        isYielding && jobs.contains { [.queued, .resolving, .downloading].contains($0.state) }
    }

    static func entryStatus(_ entry: OfflineEntry, jobs: [OfflineJob]) -> EntryStatus {
        let own = jobs.filter { $0.videoID == entry.id }
        if let job = own.first(where: { $0.state == .downloading }) { return .downloading(job.progress) }
        if own.contains(where: { $0.state == .resolving }) { return .preparing }
        if own.contains(where: { $0.state == .queued }) { return .queued }
        if own.contains(where: { $0.state == .failed }) { return .failed }
        return isPlayable(entry) ? .ready : .notReady
    }

    /// Mirrors `OfflineCoordinator.playbackVideo`: a package, a file with sound, or a file plus a saved audio track.
    static func isPlayable(_ entry: OfflineEntry) -> Bool {
        let hasAudio = entry.assets.contains { $0.track.kind == .audio }
        return entry.assets.contains { asset in
            asset.track.kind == .hls || asset.track.kind == .video && (asset.track.hasAudio || hasAudio)
        }
    }

    static func parts(_ entry: OfflineEntry) -> [Part] {
        Part.allCases.filter { part in entry.assets.contains { self.part(of: $0.track) == part } }
    }

    static func part(of track: OfflineTrack) -> Part {
        switch track.kind {
        case .video, .hls: .video
        case .audio: .audio
        case .translation: .translation
        }
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// A localized prefix and the reason exactly as the transport or store reported it (HTTP status, error domain and code).
    static func failureText(_ reason: String) -> String {
        String(localized: "Not saved: \(reason)", bundle: .module)
    }
}
