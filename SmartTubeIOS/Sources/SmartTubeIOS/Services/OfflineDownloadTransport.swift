import AVFoundation
import Foundation
import SmartTubeIOSCore
import os

private let offlineTransportLog = Logger(subsystem: appSubsystem, category: "OfflineTransport")

enum OfflineTransferEvent: Sendable {
    case progress(UUID, Double)
    case finished(UUID, URL, systemPackage: Bool, savedVideoSizes: [OfflineVideoSize]? = nil)
    case failed(UUID, String)
    case drained(String)
}

protocol OfflineTransporting: Sendable {
    var events: AsyncStream<OfflineTransferEvent> { get }
    func activeAttempts() async -> Set<UUID>
    func start(_ source: OfflineSource, attempt: UUID, yielding: Bool) throws
    func cancel(_ attempt: UUID) async
    func acknowledge(_ attempt: UUID)
    func setYielding(_ yielding: Bool) async
}

/// Sessions are immutable after init; delegate bookkeeping runs on one serial OperationQueue.
final class OfflineDownloadTransport: NSObject, OfflineTransporting, URLSessionDownloadDelegate, @unchecked Sendable {
    static let fileSessionID = "com.void.smarttube.offline.files.v1"
    static let hlsSessionID = "com.void.smarttube.offline.hls.v1"
    let events: AsyncStream<OfflineTransferEvent>
    private let continuation: AsyncStream<OfflineTransferEvent>.Continuation
    private let directory: URL
    private var files: URLSession!
    #if os(iOS)
    private var hls: AVAssetDownloadURLSession!
    #endif
    private var finished: [UUID: (URL, Bool)] = [:]
    private var videoSizes: [UUID: [OfflineVideoSize]] = [:]
    private var lastProgress: [UUID: Int] = [:]
    private let completionLock = NSLock()
    private var completedAttempts: Set<UUID> = []
    private var pressureRevision: UInt64 = 0
    private var stagingErrors: [UUID: String] = [:]

    init(directory: URL) {
        self.directory = directory
        let stream = AsyncStream<OfflineTransferEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.fileSessionID)
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 1
        files = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        #if os(iOS)
        let assetConfiguration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID)
        assetConfiguration.isDiscretionary = false
        hls = AVAssetDownloadURLSession(
            configuration: assetConfiguration, assetDownloadDelegate: self, delegateQueue: queue)
        #endif
    }

    private func allTasks() async -> [URLSessionTask] {
        var tasks = await files.allTasks
        #if os(iOS)
        tasks += await hls.allTasks
        #endif
        return tasks
    }

    func activeAttempts() async -> Set<UUID> {
        let active = Set(await allTasks().compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
        return active.union(completionLock.withLock { completedAttempts })
    }

    func start(_ source: OfflineSource, attempt: UUID, yielding: Bool) throws {
        #if DEBUG
        let allowed = source.url.scheme == "https" || OfflineUITestFixture.allows(source.url)
        #else
        let allowed = source.url.scheme == "https"
        #endif
        guard allowed else { throw OfflineLibraryError.unavailable }
        let task: URLSessionTask
        if source.track.kind == .hls {
            #if os(iOS)
            let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPUserAgentKey": source.userAgent])
            guard
                let download = hls.makeAssetDownloadTask(
                    asset: asset, assetTitle: source.track.label,
                    assetArtworkData: nil, options: nil)
            else {
                throw OfflineLibraryError.unavailable
            }
            task = download
            #else
            throw OfflineLibraryError.unavailable
            #endif
        } else {
            var request = URLRequest(url: source.url)
            request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
            task = files.downloadTask(with: request)
        }
        task.taskDescription = attempt.uuidString
        task.priority = URLSessionTask.lowPriority
        if !yielding { task.resume() }
    }

    func acknowledge(_ attempt: UUID) { completionLock.withLock { _ = completedAttempts.remove(attempt) } }

    func cancel(_ attempt: UUID) async {
        for task in await allTasks() where task.taskDescription == attempt.uuidString { task.cancel() }
    }

    func setYielding(_ yielding: Bool) async {
        let revision = completionLock.withLock {
            pressureRevision += 1
            return pressureRevision
        }
        let tasks = await allTasks()
        completionLock.withLock {
            guard revision == pressureRevision else { return }
            for task in tasks {
                if yielding, task.state == .running { task.suspend() }
                if !yielding, task.state == .suspended { task.resume() }
            }
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0, let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:))
        else { return }
        publishProgress(id, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                (try location.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0
            else {
                throw OfflineLibraryError.invalidFile
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = downloadTask.response?.mimeType?.contains("audio/mpeg") == true ? "mp3" : "mp4"
            let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
            try FileManager.default.moveItem(at: location, to: destination)
            finished[id] = (destination, false)
        } catch { stagingErrors[id] = error.localizedDescription }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        completionLock.withLock { _ = completedAttempts.insert(id) }
        lastProgress[id] = nil
        let staged = finished.removeValue(forKey: id)
        let sizes = videoSizes.removeValue(forKey: id)
        let diagnostic = error.map { failure -> String in
            let error = failure as NSError
            offlineTransportLog.error("Download failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                offlineTransportLog.error(
                    "Underlying download failure: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)"
                )
            }
            return "Download failed (\(error.domain), \(error.code)). Retry when connected."
        }
        let failure = stagingErrors.removeValue(forKey: id) ?? diagnostic
        if let failure {
            if let staged { discardStaged(staged) }
            continuation.yield(.failed(id, failure))
        } else if let staged {
            do {
                try OfflineTransferReceipt(attempt: id, url: staged.0, systemPackage: staged.1, savedVideoSizes: sizes)
                    .persist(in: directory)
                continuation.yield(.finished(id, staged.0, systemPackage: staged.1, savedVideoSizes: sizes))
            } catch {
                discardStaged(staged)
                continuation.yield(.failed(id, "Could not save download completion: \(error.localizedDescription)"))
            }
        } else {
            continuation.yield(.failed(id, "The system did not provide a completed file."))
        }
    }

    /// Only URLs obtained from this adapter's completed task callback enter this method.
    /// They are unpublished, so deleting them cannot invalidate a committed library variant.
    private func discardStaged(_ staged: (URL, Bool)) {
        try? FileManager.default.removeItem(at: staged.0)
    }

    private func publishProgress(_ id: UUID, _ progress: Double) {
        guard progress.isFinite else { return }
        let percent = Int(min(1, max(0, progress)) * 100)
        guard percent > (lastProgress[id] ?? -1) else { return }
        lastProgress[id] = percent
        continuation.yield(.progress(id, Double(percent) / 100))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let id = session.configuration.identifier { continuation.yield(.drained(id)) }
    }
}

#if os(iOS)
extension OfflineDownloadTransport: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL)
    {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        // Apple owns this package's location; moving it breaks its persistent reference.
        let normalized = location.absoluteURL.standardizedFileURL
        finished[id] = (normalized, true)
    }
    func urlSession(
        _ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadVariants variants: [AVAssetVariant]
    ) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let selected = variants.compactMap { variant -> OfflineVideoSize? in
            guard let size = variant.videoAttributes?.presentationSize,
                let width = Int(exactly: size.width.rounded()), let height = Int(exactly: size.height.rounded()),
                width > 0, height > 0
            else { return nil }
            return OfflineVideoSize(width: width, height: height)
        }
        let unique = Set((videoSizes[id] ?? []) + selected)
        videoSizes[id] = unique.sorted { $0.height == $1.height ? $0.width < $1.width : $0.height < $1.height }
    }
    func urlSession(
        _ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite, expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        publishProgress(id, min(1, loaded / expected))
    }
}
#endif
