import Foundation

/// Bytes on disk per saved kind, bytes already fetched by active downloads, and what they still have to fetch.
public struct OfflineTotals: Equatable, Sendable {
    public var video: Int64 = 0
    public var audio: Int64 = 0
    public var translation: Int64 = 0
    public var downloading: Int64 = 0
    public var remaining: Int64 = 0
    public var saved: Int64 { video + audio + translation }
    /// Everything this feature holds on disk, including unfinished transfers.
    public var onDisk: Int64 { saved + downloading }
    public init() {}
}

/// Measured sizes: committed assets by `OfflineSizes.key`, unfinished transfers by job attempt.
public struct OfflineDiskSizes: Equatable, Sendable {
    public var assets: [String: Int64] = [:]
    public var partials: [UUID: Int64] = [:]
    public init() {}
}

/// Size of an unfinished job. `done` is nil until anything is known; `isEstimate` marks a size from the variant list.
public struct OfflineTransfer: Equatable, Sendable {
    public let done: Int64?
    public let expected: Int64
    public let isEstimate: Bool
}

public enum OfflineSizes {
    /// Key of a saved asset in `OfflineDiskSizes.assets`.
    public static func key(videoID: String, trackID: String) -> String { "\(videoID)|\(trackID)" }

    public static func isActive(_ job: OfflineJob) -> Bool { [.queued, .resolving, .downloading].contains(job.state) }

    /// Allocated bytes of a file, or of everything inside a package directory; symlinks count themselves and are not
    /// followed. Nil when any part cannot be read, so a partly unreadable package never shows a smaller total.
    public static func diskBytes(at url: URL) throws -> Int64? {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
        ]
        func size(_ url: URL) -> (bytes: Int64, isDirectory: Bool)? {
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            // Allocated size is what the disk holds; the logical size is the fallback for volumes without it.
            guard
                let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize
            else { return isDirectory ? (0, true) : nil }
            return (Int64(bytes), isDirectory)
        }
        guard let root = size(url), (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        else { return nil }
        guard root.isDirectory else { return root.bytes }
        var failed = false
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(keys),
                errorHandler: { _, _ in
                    failed = true
                    return false
                })
        else { return nil }
        var total: Int64 = 0
        for case let file as URL in walker {
            try Task.checkCancellation()
            guard let child = size(file) else { return nil }
            if !child.isDirectory { total += child.bytes }
        }
        return failed ? nil : total
    }

    /// Size of one saved asset; nil when unknown or empty.
    public static func savedBytes(of job: OfflineJob, sizes: OfflineDiskSizes) -> Int64? {
        sizes.assets[key(videoID: job.videoID, trackID: job.track.id)].flatMap { $0 > 0 ? $0 : nil }
    }

    /// Byte counters of the transport first, then a measured partial package (HLS), then the variant-list estimate.
    public static func transfer(of job: OfflineJob, sizes: OfflineDiskSizes) -> OfflineTransfer? {
        let done = job.bytes?.done ?? sizes.partials[job.attempt]
        if let total = job.bytes?.total, total > 0 {
            return OfflineTransfer(done: done, expected: total, isEstimate: false)
        }
        guard let estimate = job.track.estimatedBytes, estimate > 0 else { return nil }
        return OfflineTransfer(done: done, expected: estimate, isEstimate: true)
    }

    public static func totals(entries: [OfflineEntry], jobs: [OfflineJob], sizes: OfflineDiskSizes) -> OfflineTotals {
        var totals = OfflineTotals()
        for entry in entries {
            for asset in entry.assets {
                let bytes = max(0, sizes.assets[key(videoID: entry.id, trackID: asset.track.id)] ?? 0)
                switch asset.track.kind {
                case .video, .hls: totals.video += bytes
                case .audio: totals.audio += bytes
                case .translation: totals.translation += bytes
                }
            }
        }
        for job in jobs where isActive(job) {
            let transfer = transfer(of: job, sizes: sizes)
            let done = transfer?.done ?? job.bytes?.done ?? sizes.partials[job.attempt] ?? 0
            totals.downloading += done
            if let transfer { totals.remaining += max(0, transfer.expected - done) }
        }
        return totals
    }
}

/// Measures saved files and unfinished transfers off the store, so a long scan never delays a library change.
/// Committed assets are measured once per commit; unfinished transfers at most once per `partialInterval`.
public actor OfflineSizeScanner {
    private let store: OfflineLibraryStore
    private let partialInterval: Duration
    private var committed: [String: (token: String, bytes: Int64)] = [:]
    private var partialScan: (at: ContinuousClock.Instant, sizes: [UUID: Int64])?

    public init(store: OfflineLibraryStore, partialInterval: Duration = .seconds(1)) {
        self.store = store
        self.partialInterval = partialInterval
    }

    public func sizes() async throws -> OfflineDiskSizes {
        let snapshot = try await store.snapshot()
        var result = OfflineDiskSizes()
        var live: Set<String> = []
        for entry in snapshot.entries {
            for asset in entry.assets {
                try Task.checkCancellation()
                let key = OfflineSizes.key(videoID: entry.id, trackID: asset.track.id)
                // A commit gets a new attempt, so a replaced file is measured again.
                let token = asset.attempt?.uuidString ?? asset.filename
                live.insert(key)
                if let hit = committed[key], hit.token == token {
                    result.assets[key] = hit.bytes
                } else if let url = try? await store.fileURL(asset), let bytes = try OfflineSizes.diskBytes(at: url) {
                    committed[key] = (token, bytes)
                    result.assets[key] = bytes
                }
            }
        }
        committed = committed.filter { live.contains($0.key) }
        result.partials = try await partials(active: Set(snapshot.jobs.filter(OfflineSizes.isActive).map(\.attempt)))
        return result
    }

    private func partials(active: Set<UUID>) async throws -> [UUID: Int64] {
        guard !active.isEmpty else {
            partialScan = nil
            return [:]
        }
        let now = ContinuousClock.now
        if let scan = partialScan, now - scan.at < partialInterval {
            return scan.sizes.filter { active.contains($0.key) }
        }
        var sizes: [UUID: Int64] = [:]
        for receipt in try await store.pendingReceipts()
        where receipt.isPartial == true && active.contains(receipt.attempt) {
            try Task.checkCancellation()
            // Only locations the downloader owns, the same rule the store applies before it removes them.
            let owned =
                receipt.systemPackage
                ? OfflineLibraryStore.isSystemPackage(receipt.url)
                : OfflineLibraryStore.contains(receipt.url, in: store.directory)
                    && receipt.url.deletingPathExtension().lastPathComponent == receipt.attempt.uuidString
            if owned, let bytes = try OfflineSizes.diskBytes(at: receipt.url) { sizes[receipt.attempt] = bytes }
        }
        partialScan = (now, sizes)
        return sizes
    }
}
