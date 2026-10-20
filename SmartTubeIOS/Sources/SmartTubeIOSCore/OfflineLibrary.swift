import Foundation

/// Durable selection, never a signed CDN URL or account credential.
public struct OfflineTrack: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case video, audio, translation, hls }
    public let id: String
    public let kind: Kind
    public var label: String
    public let language: String?
    public let hasAudio: Bool
    public var videoSize: OfflineVideoSize?
    public var fps: Int?
    public var codec: VideoCodec?
    public var audioLabel: String?
    public var estimatedBytes: Int64?
    public var isOriginalAudio: Bool?
    public var hlsAudioName: String?
    public var hlsPeakBitRate: Double?
    public init(id: String, kind: Kind, label: String, language: String? = nil, hasAudio: Bool = false) {
        self.id = id
        self.kind = kind
        self.label = label
        self.language = language
        self.hasAudio = hasAudio
    }
    public static let automatic = OfflineTrack(id: "automatic", kind: .video, label: "Video + original audio")
    public static func translation(_ language: String) -> Self {
        Self(id: "vot-\(language)", kind: .translation, label: "Yandex translation · \(language)", language: language)
    }
}
public struct OfflineVideoSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
/// Bytes the transport has fetched of a download and how many it expects, when it knows.
public struct OfflineByteCounts: Codable, Hashable, Sendable {
    public let done: Int64
    public let total: Int64
    public init(done: Int64, total: Int64) {
        self.done = done
        self.total = total
    }
}
public struct OfflineAsset: Codable, Sendable, Identifiable {
    public var id: String { track.id }
    public let track: OfflineTrack
    public let filename: String
    public let systemRelativePath: String?
    public var savedVideoSizes: [OfflineVideoSize]?
    public var systemNoFollow: Bool?
    public var attempt: UUID?
}
/// SponsorBlock segments saved with a video. All supported categories are kept; the user's
/// current category settings are applied at playback, so changing them needs no refetch.
public struct OfflineSponsorSegments: Codable, Sendable, Equatable {
    public var segments: [SponsorSegment]
    public var fetchedAt: Date
    public init(segments: [SponsorSegment], fetchedAt: Date) {
        self.segments = segments
        self.fetchedAt = fetchedAt
    }
    /// Segments of the enabled categories that are at least `minDuration` seconds long.
    public func active(categories: Set<SponsorSegment.Category>, minDuration: Double) -> [SponsorSegment] {
        segments.filter { categories.contains($0.category) && ($0.end - $0.start) >= minDuration }
    }
    /// Automatic refresh runs at most once per day.
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    public static func isRefreshDue(lastRefresh: Date?, now: Date) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= refreshInterval || lastRefresh > now
    }
}
public struct OfflineEntry: Codable, Sendable, Identifiable {
    public var id: String { video.id }
    public var video: Video
    public var assets: [OfflineAsset] = []
    /// Absent in manifests written before offline SponsorBlock support.
    public var sponsor: OfflineSponsorSegments?
}
public struct OfflineJob: Codable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case queued, resolving, downloading, completed, failed, cancelled }
    public let id: UUID
    public let batch: UUID
    public var attempt: UUID
    public let videoID: String
    public var track: OfflineTrack
    public var state: State
    public var progress: Double
    public var bytes: OfflineByteCounts?
    public var error: String?
    public var nextResolutionAt: Date?
    public var resolutionAttempts: Int = 0
}
public struct OfflineRemoval: Codable, Sendable {
    public let videoID: String?
    public let jobIDs: Set<UUID>
    let assetIDs: Set<String>
}
public struct OfflineSnapshot: Codable, Sendable {
    public var revision: UInt64 = 0
    public var entries: [OfflineEntry] = []
    public var jobs: [OfflineJob] = []
    public var notifiedBatches: Set<UUID> = []
    public var pendingRemovals: [OfflineRemoval]?
    /// When the automatic SponsorBlock refresh last completed; nil in manifests written before it existed.
    public var sponsorRefreshedAt: Date?
    public init() {}
}
public struct OfflineTransferReceipt: Codable, Sendable {
    public let attempt: UUID
    public let url: URL
    public let systemPackage: Bool
    public let savedVideoSizes: [OfflineVideoSize]?
    public let isPartial: Bool?
    public init(
        attempt: UUID, url: URL, systemPackage: Bool, savedVideoSizes: [OfflineVideoSize]? = nil, isPartial: Bool? = nil
    ) {
        self.attempt = attempt
        self.url = url
        self.systemPackage = systemPackage
        self.savedVideoSizes = savedVideoSizes
        self.isPartial = isPartial
    }
    public func persist(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.location(attempt, in: directory), options: .atomic)
    }
    public static func location(_ attempt: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("receipt-\(attempt.uuidString).json")
    }
}
public enum OfflineLibraryError: Error, LocalizedError {
    case invalidFile, unavailable, missingAudio
    public var errorDescription: String? {
        switch self {
        case .invalidFile: "The downloaded file is missing or invalid. Retry the download."
        case .unavailable: "This variant is unavailable for offline download. Refresh the available variants."
        case .missingAudio: "Download an original audio track before playing this video variant."
        }
    }
}
/// Serializes disk work; UI state is published only after an atomic manifest write.
public actor OfflineLibraryStore {
    public let directory: URL
    private let homeDirectory: URL
    private let fileExists: @Sendable (URL) -> Bool
    private var value = OfflineSnapshot()
    private var loaded = false
    private let writeManifest: @Sendable (Data, URL) throws -> Void
    public init(
        directory: URL,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        writeManifest: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.directory = directory
        self.homeDirectory = homeDirectory
        self.fileExists = fileExists
        self.writeManifest = writeManifest
    }
    public func snapshot() throws -> OfflineSnapshot {
        if !loaded {
            let manifest = directory.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                value = try JSONDecoder().decode(OfflineSnapshot.self, from: Data(contentsOf: manifest))
            }
            loaded = true
        }
        return value
    }
    @discardableResult private func commit(_ proposed: OfflineSnapshot) throws -> OfflineSnapshot {
        var next = proposed
        next.revision = value.revision + 1
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeManifest(JSONEncoder().encode(next), directory.appendingPathComponent("manifest.json"))
        value = next
        return next
    }
    @discardableResult public func enqueue(
        video: Video, tracks: [OfflineTrack], batch: UUID = UUID()
    ) throws -> OfflineSnapshot {
        var next = try snapshot()
        guard !(next.pendingRemovals ?? []).contains(where: { $0.videoID == nil || $0.videoID == video.id }) else {
            throw OfflineLibraryError.unavailable
        }
        if !next.entries.contains(where: { $0.id == video.id }) {
            let metadata = Video(
                id: video.id, title: video.title, channelTitle: video.channelTitle, channelId: video.channelId,
                thumbnailURL: video.thumbnailURL, duration: video.duration)
            next.entries.append(OfflineEntry(video: metadata))
        }
        for track in tracks {
            guard
                !next.jobs.contains(where: {
                    $0.videoID == video.id
                        && ($0.track.id == track.id
                            || track.id == OfflineTrack.automatic.id && [.video, .hls].contains($0.track.kind))
                        && [.queued, .resolving, .downloading].contains($0.state)
                })
            else { continue }
            next.jobs.append(
                OfflineJob(
                    id: UUID(), batch: batch, attempt: UUID(), videoID: video.id,
                    track: track, state: .queued, progress: 0))
        }
        return try commit(next)
    }
    /// No-op when the video was removed meanwhile.
    @discardableResult public func setSponsorSegments(
        videoID: String, segments: [SponsorSegment], fetchedAt: Date
    ) throws -> OfflineSnapshot {
        var next = try snapshot()
        guard let index = next.entries.firstIndex(where: { $0.id == videoID }) else { return next }
        next.entries[index].sponsor = OfflineSponsorSegments(segments: segments, fetchedAt: fetchedAt)
        return try commit(next)
    }
    @discardableResult public func markSponsorRefresh(at date: Date) throws -> OfflineSnapshot {
        var next = try snapshot()
        next.sponsorRefreshedAt = date
        return try commit(next)
    }
    @discardableResult public func update(
        attempt: UUID, state: OfflineJob.State, progress: Double? = nil,
        track: OfflineTrack? = nil, error: String? = nil, bytes: OfflineByteCounts? = nil
    ) throws -> OfflineSnapshot {
        var next = try snapshot()
        guard let index = next.jobs.firstIndex(where: { $0.attempt == attempt }),
            ![.cancelled, .completed, .failed].contains(next.jobs[index].state)
        else { return next }
        next.jobs[index].state = state
        if let progress { next.jobs[index].progress = min(1, max(0, progress)) }
        if let track { next.jobs[index].track = track }
        if let bytes { next.jobs[index].bytes = bytes }
        next.jobs[index].error = error
        return try commit(next)
    }
    @discardableResult public func retry(id: UUID) throws -> OfflineSnapshot {
        var next = try snapshot()
        guard let index = next.jobs.firstIndex(where: { $0.id == id }),
            [.cancelled, .failed].contains(next.jobs[index].state)
        else { return next }
        var job = next.jobs.remove(at: index)
        job.attempt = UUID()
        job.state = .queued
        job.progress = 0
        job.bytes = nil
        job.error = nil
        job.nextResolutionAt = nil
        job.resolutionAttempts = 0
        next.jobs.append(job)
        return try commit(next)
    }
    public func deferResolution(attempt: UUID, until date: Date) throws -> OfflineSnapshot {
        var next = try snapshot()
        guard let index = next.jobs.firstIndex(where: { $0.attempt == attempt && $0.state == .resolving }) else {
            return next
        }
        next.jobs[index].resolutionAttempts += 1
        if next.jobs[index].resolutionAttempts >= 120 {
            next.jobs[index].state = .failed
            next.jobs[index].error = "Translation is still unavailable. Retry later."
        } else {
            next.jobs[index].state = .queued
            next.jobs[index].nextResolutionAt = date
        }
        return try commit(next)
    }
    /// Late completion cannot overwrite a working variant or finish a newer attempt.
    @discardableResult public func finish(
        attempt: UUID, staged: URL, systemPackage: Bool = false, savedVideoSizes: [OfflineVideoSize]? = nil
    ) throws -> OfflineSnapshot {
        let staged = staged.absoluteURL.standardizedFileURL
        var next = try snapshot()
        guard let jobIndex = next.jobs.firstIndex(where: { $0.attempt == attempt }),
            next.jobs[jobIndex].state == .downloading,
            let entryIndex = next.entries.firstIndex(where: { $0.id == next.jobs[jobIndex].videoID })
        else {
            discard(attempt: attempt, url: staged, systemPackage: systemPackage)
            return next
        }
        guard
            systemPackage
                ? Self.isSystemPackage(staged, homeDirectory: homeDirectory)
                : Self.contains(staged, in: directory)
                    && staged.deletingPathExtension().lastPathComponent == attempt.uuidString,
            fileExists(staged)
        else {
            throw OfflineLibraryError.invalidFile
        }
        let asset = OfflineAsset(
            track: next.jobs[jobIndex].track, filename: staged.lastPathComponent,
            systemRelativePath: systemPackage
                ? String(Self.comparisonURL(staged).path.dropFirst(Self.comparisonURL(homeDirectory).path.count + 1))
                : nil,
            savedVideoSizes: savedVideoSizes,
            systemNoFollow: systemPackage && Self.hasNoFollow(staged) ? true : nil, attempt: attempt)

        let replaced = next.entries[entryIndex].assets.first { $0.id == asset.id }
        next.entries[entryIndex].assets.removeAll { $0.id == asset.id }
        next.entries[entryIndex].assets.append(asset)
        next.jobs[jobIndex].state = .completed
        next.jobs[jobIndex].progress = 1
        let committed = try commit(next)
        try? FileManager.default.removeItem(at: OfflineTransferReceipt.location(attempt, in: directory))
        if let replaced, let old = try? fileURL(replaced), !Self.sameLocalFile(old, staged) {
            try? FileManager.default.removeItem(at: old)
        }
        return committed
    }
    public func pendingReceipts() throws -> [OfflineTransferReceipt] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("receipt-") && $0.pathExtension == "json" }
            .compactMap { url in
                do {
                    return try JSONDecoder().decode(OfflineTransferReceipt.self, from: Data(contentsOf: url))
                } catch CocoaError.fileReadNoSuchFile { return nil }
            }
    }
    public func discard(attempt: UUID, url: URL, systemPackage: Bool) {
        let valid =
            systemPackage
            ? Self.isSystemPackage(url, homeDirectory: homeDirectory)
            : Self.contains(url, in: directory)
                && url.deletingPathExtension().lastPathComponent == attempt.uuidString
        let isPublished = value.entries.flatMap(\.assets).contains { asset in
            guard let published = try? fileURL(asset) else { return false }
            return Self.sameLocalFile(published, url)
        }
        guard valid else { return }
        if !isPublished {
            do { try removeIfPresent(url) } catch { return }
        }
        try? FileManager.default.removeItem(at: OfflineTransferReceipt.location(attempt, in: directory))
    }
    public func recover(activeAttempts: Set<UUID>) throws -> OfflineSnapshot {
        var next = try snapshot()
        let received = Set(try pendingReceipts().filter { $0.isPartial != true }.map(\.attempt))
        for index in next.jobs.indices where [.resolving, .downloading].contains(next.jobs[index].state) {
            if !activeAttempts.union(received).contains(next.jobs[index].attempt) {
                next.jobs[index].attempt = UUID()
                next.jobs[index].state = .queued
                next.jobs[index].progress = 0
                next.jobs[index].bytes = nil
            }
        }
        return try commit(next)
    }
    public func takeCompletedBatches() throws -> [(UUID, String)] {
        var next = try snapshot()
        var result: [(UUID, String)] = []
        for batch in Set(next.jobs.map(\.batch)) where !next.notifiedBatches.contains(batch) {
            let jobs = next.jobs.filter { $0.batch == batch }
            if jobs.allSatisfy({ $0.state == .completed }), let first = jobs.first {
                result.append((batch, next.entries.first(where: { $0.id == first.videoID })?.video.title ?? "Video"))
                next.notifiedBatches.insert(batch)
            }
        }
        if !result.isEmpty { try commit(next) }
        return result
    }
    /// Invalidate attempts durably before cancellation; nil videoID includes all videos and orphaned transfer cache.
    public func beginRemoval(videoID: String?, jobID: UUID? = nil) throws -> OfflineSnapshot {
        var next = try snapshot()
        let jobs = next.jobs.filter { (videoID == nil || $0.videoID == videoID) && (jobID == nil || $0.id == jobID) }
        let assets = next.entries.filter { videoID == nil || $0.id == videoID }.flatMap(\.assets)
        let selected = assets.filter { asset in
            guard let jobID else { return true }
            guard let job = jobs.first(where: { $0.id == jobID }) else { return false }
            if let attempt = asset.attempt { return attempt == job.attempt }
            // Manifests before PLAN-0025 did not record asset ownership by attempt.
            return asset.id == job.track.id
                && next.jobs.last(where: {
                    $0.videoID == videoID && $0.track.id == asset.id && $0.state == .completed
                })?.id == jobID
        }
        let removal = OfflineRemoval(
            videoID: videoID, jobIDs: Set(jobs.map(\.id)), assetIDs: Set(selected.map(\.id)))
        for index in next.jobs.indices where removal.jobIDs.contains(next.jobs[index].id) {
            next.jobs[index].state = .cancelled
        }
        next.pendingRemovals = (next.pendingRemovals ?? []) + [removal]
        return try commit(next)
    }

    public func completeRemovals() throws -> OfflineSnapshot {
        var next = try snapshot()
        for removal in next.pendingRemovals ?? [] {
            let attempts = Set(next.jobs.filter { removal.jobIDs.contains($0.id) }.map(\.attempt))
            let removesAll = removal.videoID == nil
            let assets = next.entries.filter { removesAll || $0.id == removal.videoID }.flatMap(\.assets)
            let preserved = try next.entries.flatMap { entry in
                try entry.assets.filter {
                    (!removesAll && entry.id != removal.videoID) || !removal.assetIDs.contains($0.id)
                }.map { try assetURL($0) }
            }
            func removeOwned(_ url: URL) throws {
                if !preserved.contains(where: { Self.sameLocalFile($0, url) }) { try removeIfPresent(url) }
            }
            for asset in assets where removal.assetIDs.contains(asset.id) {
                try removeOwned(try assetURL(asset))
            }
            for receipt in try pendingReceipts() where removesAll || attempts.contains(receipt.attempt) {
                let owned =
                    receipt.systemPackage
                    ? Self.isSystemPackage(receipt.url, homeDirectory: homeDirectory)
                    : Self.contains(receipt.url, in: directory)
                        && receipt.url.deletingPathExtension().lastPathComponent == receipt.attempt.uuidString
                guard owned else { throw OfflineLibraryError.invalidFile }
                try removeOwned(receipt.url)
                try removeIfPresent(OfflineTransferReceipt.location(receipt.attempt, in: directory))
            }
            // A process can exit between staging a direct file and writing its receipt.
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where UUID(uuidString: url.deletingPathExtension().lastPathComponent).map({
                removesAll || attempts.contains($0)
            }) == true {
                guard Self.contains(url, in: directory) else { throw OfflineLibraryError.invalidFile }
                try removeOwned(url)
            }
            next.jobs.removeAll { removal.jobIDs.contains($0.id) }
            for index in next.entries.indices where removesAll || next.entries[index].id == removal.videoID {
                next.entries[index].assets.removeAll { removal.assetIDs.contains($0.id) }
            }
            next.entries.removeAll { entry in
                (removesAll || entry.id == removal.videoID) && entry.assets.isEmpty
                    && !next.jobs.contains(where: { $0.videoID == entry.id })
            }
        }
        guard !(next.pendingRemovals ?? []).isEmpty else { return next }
        next.pendingRemovals = nil
        next.notifiedBatches.formIntersection(Set(next.jobs.map(\.batch)))
        return try commit(next)
    }

    private func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile
        { /* Already removed by an earlier cleanup attempt. */  }
    }

    public func fileURL(_ asset: OfflineAsset) throws -> URL {
        let url = try assetURL(asset)
        guard fileExists(url) else { throw OfflineLibraryError.invalidFile }
        return url
    }
    private func assetURL(_ asset: OfflineAsset) throws -> URL {
        let url: URL
        if let relative = asset.systemRelativePath {
            guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
                throw OfflineLibraryError.invalidFile
            }
            let home = Self.comparisonURL(homeDirectory)
            let base: URL
            if asset.systemNoFollow == true {
                // Foundation may shorten /private/var to the /var symlink, which /.nofollow rejects.
                guard let physicalHome = realpath(home.path, nil) else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                defer { free(physicalHome) }
                base = URL(fileURLWithPath: Self.noFollowPrefix + String(cString: physicalHome), isDirectory: true)
            } else {
                base = home
            }
            url = base.appendingPathComponent(relative)
        } else {
            url = directory.appendingPathComponent(asset.filename)
        }
        guard
            asset.systemRelativePath != nil
                ? Self.isSystemPackage(url, homeDirectory: homeDirectory) : Self.contains(url, in: directory)
        else {
            throw OfflineLibraryError.invalidFile
        }
        return url
    }
    private static func sameLocalFile(_ first: URL, _ second: URL) -> Bool {
        first.isFileURL && second.isFileURL && comparisonURL(first).path == comparisonURL(second).path
    }
    private static let noFollowPrefix = "/.nofollow"
    private static func hasNoFollow(_ url: URL) -> Bool {
        url.absoluteURL.path.hasPrefix(noFollowPrefix + "/")
    }
    /// Apple's /.nofollow is a protected view of the same filesystem root. Strip it ONLY
    /// for ownership comparison; actual I/O and restored references retain the protection.
    /// Resolve the comparison path to reject symlink escapes from the owned Library.
    private static func comparisonURL(_ url: URL) -> URL {
        let path = url.absoluteURL.path
        let ordinaryPath = hasNoFollow(url) ? String(path.dropFirst(noFollowPrefix.count)) : path
        return URL(fileURLWithPath: ordinaryPath).resolvingSymlinksInPath().standardizedFileURL
    }
    public static func isSystemPackage(
        _ url: URL, homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> Bool {
        guard url.isFileURL, url.pathExtension == "movpkg" else { return false }
        let library = comparisonURL(homeDirectory).appendingPathComponent("Library")
        return comparisonURL(url).path.hasPrefix(library.path + "/")
    }
    public static func contains(_ url: URL, in directory: URL) -> Bool {
        url.isFileURL
            && url.absoluteURL.resolvingSymlinksInPath().standardizedFileURL.path
                .hasPrefix(directory.absoluteURL.resolvingSymlinksInPath().standardizedFileURL.path + "/")
    }
}
