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

    /// Two columns open on the first video until a video has filled the detail; after that only the retained
    /// choice counts, so a deletion still leaves the detail empty. A single column selects nothing.
    static func columnSelection(
        _ videoID: String?, entries: [OfflineEntry], showsColumns: Bool, hasShownVideo: Bool
    ) -> String? {
        if let kept = retainedSelection(videoID, entries: entries) { return kept }
        return showsColumns && !hasShownVideo ? entries.first?.id : nil
    }

    /// A job's visible status. Waiting for translation is a queued job whose resolution was deferred.
    enum JobStatus: Equatable {
        case queued, waitingForTranslation, resolving, downloading(Double), completed, failed, cancelled
    }

    /// The one action a job row offers besides Delete task and files, which every job has.
    enum JobAction: Equatable { case cancel, retry, none }

    /// Badge of a library row: what this video's jobs are doing, otherwise whether it can play.
    enum EntryStatus: Equatable { case downloading(Double), preparing, queued, failed, ready, notReady }

    /// A kind of saved file, in display order.
    enum Part: CaseIterable, Hashable { case video, audio, translation }

    enum PageState: Equatable { case loading, storageError(String), empty, content }

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
        case .completed: .none
        }
    }

    enum DownloadFilter: String, CaseIterable, Identifiable {
        case all, active, error, video, audio
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All", bundle: .module)
            case .active: String(localized: "Active", bundle: .module)
            case .error: String(localized: "Error", bundle: .module)
            case .video: String(localized: "Video", bundle: .module)
            case .audio: String(localized: "Audio", bundle: .module)
            }
        }
    }

    /// The manifest appends tasks, so reversing preserves newest-first order without inventing timestamps.
    static func downloadJobs(
        _ jobs: [OfflineJob], videoID: String?, filter: DownloadFilter
    ) -> [OfflineJob] {
        jobs.reversed().filter { job in
            guard videoID == nil || job.videoID == videoID else { return false }
            switch filter {
            case .all: return true
            case .active: return OfflineSizes.isActive(job) || job.state == .failed
            case .error: return job.state == .failed
            case .video: return part(of: job.track) == .video
            case .audio: return part(of: job.track) != .video
            }
        }
    }

    struct TransferSummary {
        let counts: [Part: Int]
        let failures: Int
        /// Equal weight per file in the currently active batches, including their completed files.
        let progress: Double?
        var activeCount: Int { counts.values.reduce(0, +) }
        var isVisible: Bool { activeCount > 0 || failures > 0 }
        var countText: String {
            Part.allCases.compactMap { part in
                guard let count = counts[part], count > 0 else { return nil }
                return String(localized: "offline.partCount \(part.title) \(count)", bundle: .module)
            }.joined(separator: " · ")
        }
    }

    static func transferSummary(_ jobs: [OfflineJob]) -> TransferSummary {
        let active = jobs.filter(OfflineSizes.isActive)
        let batches = Set(active.map(\.batch))
        let current = jobs.filter { batches.contains($0.batch) && $0.state != .cancelled }
        let done = current.reduce(0.0) { sum, job in
            if job.state == .completed { return sum + 1 }
            guard job.state == .downloading, job.progress.isFinite else { return sum }
            return sum + min(1, max(0, job.progress))
        }
        return TransferSummary(
            counts: Dictionary(grouping: active, by: { part(of: $0.track) }).mapValues(\.count),
            failures: jobs.filter { $0.state == .failed }.count,
            progress: current.isEmpty ? nil : done / Double(current.count))
    }

    struct TrackBadge: Identifiable {
        let track: OfflineTrack
        let status: JobStatus
        var id: String { track.id }
        var compactLabel: String {
            switch track.kind {
            case .video, .hls:
                return [track.videoChoiceLabel, track.hasAudio ? languageBadge : nil]
                    .compactMap { $0 }.joined(separator: " · ")
            case .audio:
                return [languageBadge, OfflineDetailPresentation.audioDetail(track)]
                    .compactMap { $0 }.joined(separator: " · ")
            case .translation:
                return ["Yandex", languageBadge].compactMap { $0 }.joined(separator: " ")
            }
        }
        private var languageBadge: String? {
            guard let code = track.language, !code.isEmpty else { return nil }
            return code == "ru" ? "🇷🇺 RU" : code.uppercased()
        }
        var label: String {
            switch track.kind {
            case .video, .hls:
                return [track.videoChoiceLabel, track.hasAudio || track.kind == .hls ? track.audioLabel : nil]
                    .compactMap { $0 }.joined(separator: " · ")
            case .audio: return track.audioLabel ?? track.label
            case .translation:
                guard let language = track.language, !language.isEmpty else { return track.label }
                return String(localized: "Yandex translation · \(languageName(language))", bundle: .module)
            }
        }
    }

    /// Saved variants and the latest attempt for each unsaved variant; never duplicate a saved track's chip.
    static func trackBadges(_ entry: OfflineEntry, jobs: [OfflineJob]) -> [TrackBadge] {
        let own = jobs.filter { $0.videoID == entry.id }
        var seen = Set<String>()
        let tracks = entry.assets.map(\.track) + own.map(\.track)
        return tracks.compactMap { track in
            guard seen.insert(track.id).inserted else { return nil }
            let saved = entry.assets.contains { $0.id == track.id }
            let latest = own.last { $0.track.id == track.id }
            let state = latest.map(status) ?? .completed
            return TrackBadge(track: track, status: saved && latest?.state == .cancelled ? .completed : state)
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

    /// The player's Offline quick button: saved wins (library entry or a local playback source), then queued;
    /// live and upcoming videos cannot be saved.
    enum QuickAction: Equatable {
        case offline, queued, saved, unavailable
        var isEnabled: Bool { self == .offline || self == .queued }
    }

    static func quickAction(video: Video, entries: [OfflineEntry], jobs: [OfflineJob]) -> QuickAction {
        if video.isLive || video.isUpcoming { return .unavailable }
        if video.isDownloaded || entries.contains(where: { $0.id == video.id && isPlayable($0) }) { return .saved }
        let active: [OfflineJob.State] = [.queued, .resolving, .downloading]
        return jobs.contains { $0.videoID == video.id && active.contains($0.state) } ? .queued : .offline
    }

    static func entryStatus(_ entry: OfflineEntry, jobs: [OfflineJob]) -> EntryStatus {
        let own = jobs.filter { $0.videoID == entry.id }
        if let job = own.first(where: { $0.state == .downloading }) { return .downloading(job.progress) }
        if own.contains(where: { $0.state == .resolving }) { return .preparing }
        if own.contains(where: { $0.state == .queued }) { return .queued }
        if own.contains(where: { $0.state == .failed }) { return .failed }
        return isPlayable(entry) ? .ready : .notReady
    }

    static func savedVideoIDs(_ entries: [OfflineEntry]) -> Set<String> {
        Set(entries.filter(isPlayable).map(\.id))
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

    /// The one place bytes become text: localized file-size units ("412 MB").
    static func bytesText(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file)) }

    /// Size shown on a job row: the saved file once completed; while active "fetched of total" (a "~" marks a size
    /// estimated from the variant list) or just the total. Nil when nothing is known, so the row shows no size.
    static func jobSizeText(_ job: OfflineJob, sizes: OfflineDiskSizes) -> String? {
        if job.state == .completed { return OfflineSizes.savedBytes(of: job, sizes: sizes).map(bytesText) }
        guard OfflineSizes.isActive(job), let transfer = OfflineSizes.transfer(of: job, sizes: sizes) else {
            return nil
        }
        let total =
            transfer.isEstimate
            ? String(localized: "offline.estimated \(bytesText(transfer.expected))", bundle: .module)
            : bytesText(transfer.expected)
        guard job.state == .downloading, let done = transfer.done, done > 0 else { return total }
        return String(
            localized: "offline.transfer \(bytesText(min(done, transfer.expected))) \(total)", bundle: .module)
    }

    /// "Video 412 MB · Audio 8 MB" for the saved files of one video; nil when none has a known size.
    static func videoSizeText(_ videoID: String, entries: [OfflineEntry], sizes: OfflineDiskSizes) -> String? {
        guard let entry = entries.first(where: { $0.id == videoID }) else { return nil }
        let lines = Part.allCases.compactMap { part -> String? in
            let bytes = entry.assets.filter { self.part(of: $0.track) == part }
                .reduce(Int64(0)) { $0 + (sizes.assets[OfflineSizes.key(videoID: videoID, trackID: $1.track.id)] ?? 0) }
            guard bytes > 0 else { return nil }
            return String(localized: "offline.partSize \(part.title) \(bytesText(bytes))", bundle: .module)
        }
        return lines.isEmpty ? nil : lines.formatted(.list(type: .and, width: .narrow))
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// A localized prefix and the reason exactly as the transport or store reported it (HTTP status, error domain and code).
    static func failureText(_ reason: String) -> String {
        String(localized: "Not saved: \(reason)", bundle: .module)
    }
}
