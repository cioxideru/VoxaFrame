import Foundation

// MARK: - VideoDiskCache
//
// Serial-queue-backed disk cache for Phase J.
// Non-actor — accessed only from VideoPreloadCache actor methods, which provide isolation.
//
// What is stored: nextInfo, endCards, sponsorSegments, deArrowBranding.
// What is NOT stored: playerInfo (CDN URLs are IP-bound) or trackingURLs (auth-sensitive).
//
// Files live at: <Caches>/st-video-cache/<sanitisedVideoId>-<dataType>.json
// LRU eviction fires when directory size exceeds 20 MB.

final class VideoDiskCache: @unchecked Sendable {

    // MARK: - Configuration

    static let maxBytes: Int = 20 * 1024 * 1024  // 20 MB; internal for tests
    private let queue = DispatchQueue(label: "st.disk-cache", qos: .utility)
    let cacheDir: URL  // internal for tests

    // MARK: - In-memory byte estimate
    //
    // evictIfNeeded() used to run a full FileManager.contentsOfDirectory scan on every
    // write, showing up in Apple's energy report as a top CPU hot-spot (5+ event points
    // for VideoDiskCache.evictIfNeeded across 4.8 sessions). The scan is O(n files) and
    // is unnecessary when the cache is well below 20 MB.
    //
    // Fix: track a running estimate here. Store() accounts for replacements; removeAll()
    // resets it to 0. evictIfNeeded() skips the full scan unless the estimate exceeds
    // the threshold — only a scan-and-evict is needed when the cache is actually full.
    // After eviction, the exact count is known from the scan, so the estimate is corrected.
    // Unknown on reopen: reconcile once on the first write, not on the UI's launch path.
    private var estimatedBytes: Int?

    // MARK: - Init

    init(cacheDir: URL? = nil) {
        if let dir = cacheDir {
            self.cacheDir = dir
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.cacheDir = base.appendingPathComponent("st-video-cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Write (fire-and-forget)

    func store<T: Encodable>(_ value: T, videoId: String, dataType: String) {
        let url = fileURL(videoId: videoId, dataType: dataType)
        guard let data = try? JSONEncoder().encode(value) else { return }
        let writtenBytes = data.count
        queue.async { [weak self] in
            guard let self else { return }
            let previousBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            do { try data.write(to: url, options: .atomic) } catch { return }
            if let estimatedBytes {
                self.estimatedBytes = estimatedBytes + writtenBytes - previousBytes
            }
            self.evictIfNeeded()
        }
    }

    // MARK: - Read (synchronous, called from consume() cold path on actor context)

    func load<T: Decodable>(_ type: T.Type, videoId: String, dataType: String) -> T? {
        let url = fileURL(videoId: videoId, dataType: dataType)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Eviction (LRU by modification date)

    func evictIfNeeded() {
        guard estimatedBytes == nil || (estimatedBytes ?? 0) > Self.maxBytes else { return }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys) else { return }
        var totalSize = files.compactMap {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        }.reduce(0, +)
        estimatedBytes = totalSize  // correct the estimate with the real count
        guard totalSize > Self.maxBytes else { return }
        let sorted = files.sorted {
            let d1 =
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let d2 =
                (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            return d1 < d2  // oldest first
        }
        for file in sorted {
            guard totalSize > Self.maxBytes else { break }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            do { try fm.removeItem(at: file) } catch { continue }
            totalSize -= size
        }
        estimatedBytes = totalSize
    }

    // MARK: - Auth eviction (BUG-013 fix)

    /// Removes all cached files from disk. Called by VideoPreloadCache.evictAuthSensitiveData()
    /// on sign-out so nextInfo (which contains likeStatus) cannot be read back after the cache
    /// is cleared in memory.
    /// Uses queue.sync to ensure deletion completes before the caller returns, making this
    /// safe to call synchronously from actor methods that need immediate consistency.
    func removeAll() {
        queue.sync {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.cacheDir, includingPropertiesForKeys: nil) else {
                return
            }
            for file in files {
                try? fm.removeItem(at: file)
            }
            self.estimatedBytes = 0
        }
    }

    // MARK: - Helpers

    func fileURL(videoId: String, dataType: String) -> URL {
        // Sanitise to prevent path traversal: replace '/' and '..' with '_'
        let safeId =
            videoId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        return cacheDir.appendingPathComponent("\(safeId)-\(dataType).json")
    }
}
