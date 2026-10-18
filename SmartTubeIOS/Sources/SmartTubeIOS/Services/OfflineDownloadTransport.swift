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
    func start(_ source: OfflineSource, attempt: UUID) async throws
    func cancel(_ attempt: UUID) async
    func acknowledge(_ attempt: UUID)
    func setYielding(_ yielding: Bool) async
    func setForeground(_ foreground: Bool)
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
    private var expectedHLS: [UUID: OfflineSource] = [:]
    #endif
    private var finished: [UUID: (URL, Bool)] = [:]
    private var videoSizes: [UUID: [OfflineVideoSize]] = [:]
    private var lastProgress: [UUID: Int] = [:]
    private let completionLock = NSLock()
    private var retainedAttempts: Set<UUID> = []
    private var cancelledAttempts: Set<UUID> = []
    private var nextChunks: [UUID: (OfflineDownloadChunk, URLRequest)] = [:]
    #if os(iOS)
    private var allowsChunking = false
    #else
    private var allowsChunking = true
    #endif
    private var pressureYielding = false
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
        configuration.httpMaximumConnectionsPerHost = AppSettings.availableConcurrentDownloadCounts.upperBound
        files = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        #if os(iOS)
        let assetConfiguration = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID)
        assetConfiguration.isDiscretionary = false
        assetConfiguration.httpMaximumConnectionsPerHost = AppSettings.availableConcurrentDownloadCounts.upperBound
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
        return active.union(completionLock.withLock { retainedAttempts })
    }

    func start(_ source: OfflineSource, attempt: UUID) async throws {
        try Task.checkCancellation()
        #if DEBUG
        let allowed = source.url.scheme == "https" || OfflineUITestFixture.allows(source.url)
        #else
        let allowed = source.url.scheme == "https"
        #endif
        guard allowed else { throw Self.unavailable("source URL is not HTTPS track=\(source.track.id)") }
        let task: URLSessionTask
        if source.track.kind == .hls {
            #if os(iOS)
            let configuration = try await Self.hlsConfiguration(source)
            try Task.checkCancellation()
            completionLock.withLock { expectedHLS[attempt] = source }
            task = hls.makeAssetDownloadTask(downloadConfiguration: configuration)
            #else
            throw Self.unavailable("HLS downloads need iOS track=\(source.track.id)")
            #endif
        } else {
            var request = URLRequest(url: source.url)
            request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
            task = completionLock.withLock {
                files.downloadTask(with: OfflineDownloadChunk.prepare(request, bounded: allowsChunking))
            }
        }
        completionLock.withLock {
            retainedAttempts.insert(attempt)
            task.taskDescription = attempt.uuidString
            task.priority = URLSessionTask.lowPriority
            if cancelledAttempts.contains(attempt) {
                task.cancel()
            } else if !pressureYielding {
                task.resume()
            }
        }
    }

    #if os(iOS)
    private static func hlsConfiguration(_ source: OfflineSource) async throws -> AVAssetDownloadConfiguration {
        let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPUserAgentKey": source.userAgent])
        let variants = try await asset.load(.variants)
        let audible = try await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try await asset.loadMediaSelectionGroup(for: .legible)
        let preferred = try await asset.load(.preferredMediaSelection)
        try Task.checkCancellation()
        let track = source.track.id
        // Variant URLs carry per-request tokens, so a fresh load rarely repeats them; fall back to attributes.
        var matches = variants.filter { matchesVariant($0, source: source, byURL: true) }
        if matches.isEmpty { matches = variants.filter { matchesVariant($0, source: source, byURL: false) } }
        guard matches.count == 1, let variant = matches.first else {
            if matches.isEmpty { logVariantMismatch(variants, source: source) }
            throw unavailable("HLS variant matches=\(matches.count) of \(variants.count) track=\(track)")
        }
        guard let selection = preferred.mutableCopy() as? AVMutableMediaSelection else {
            throw unavailable("HLS media selection is not mutable track=\(track)")
        }
        if let name = source.track.hlsAudioName {
            guard let audible else {
                offlineTransportLog.error(
                    "Offline unavailable: HLS has no audible group track=\(track, privacy: .public)")
                throw OfflineLibraryError.missingAudio
            }
            // Prefer options this variant's audio group carries; equivalent renditions repeat per group.
            let carried = audible.options.filter {
                variant.audioAttributes?.renditionSpecificAttributes(for: $0) != nil
            }
            let options = carried.isEmpty ? audible.options : carried
            guard
                let audio = hlsAudioOption(
                    options, name: name, language: source.track.language, displayName: \.displayName,
                    languageTag: \.extendedLanguageTag)
            else {
                let offered = audible.options.map { "\($0.displayName)|\($0.extendedLanguageTag ?? "-")" }
                throw unavailable(
                    "HLS audio \(name)|\(source.track.language ?? "-") not unique among \(offered) carried=\(carried.count) track=\(track)"
                )
            }
            selection.select(audio, in: audible)
        }
        if let legible, legible.allowsEmptySelection { selection.select(nil, in: legible) }
        let configuration = AVAssetDownloadConfiguration(asset: asset, title: source.track.label)
        configuration.auxiliaryContentConfigurations = []
        // Match one rendition; willDownloadVariants also rejects the system's automatic fallback.
        // A unique peak keeps the proven predicate qualifier; dubbed variants sharing it need the variant itself.
        let qualifier: AVAssetVariantQualifier
        if let peak = variant.peakBitRate, peak > 0, variants.filter({ $0.peakBitRate == peak }).count == 1 {
            qualifier = AVAssetVariantQualifier(
                predicate: NSPredicate(format: "peakBitRate == %@", NSNumber(value: peak)))
        } else {
            offlineTransportLog.notice(
                "HLS peak bit rate is shared; qualifying the variant track=\(track, privacy: .public)")
            qualifier = AVAssetVariantQualifier(variant: variant)
        }
        configuration.primaryContentConfiguration.variantQualifiers = [qualifier]
        configuration.primaryContentConfiguration.mediaSelections = [selection]
        return configuration
    }
    /// Lists what each variant offers against the catalog choice; no URLs, only whether they match.
    private static func logVariantMismatch(_ variants: [AVAssetVariant], source: OfflineSource) {
        let expected = source.track
        offlineTransportLog.error(
            "HLS expected size=\(expected.videoSize.map { "\($0.width)x\($0.height)" } ?? "-", privacy: .public) codec=\(expected.codec?.rawValue ?? "-", privacy: .public) fps=\(expected.fps ?? 0, privacy: .public) peak=\(expected.hlsPeakBitRate ?? 0, privacy: .public) hasURL=\(source.hlsVariantURL != nil, privacy: .public)"
        )
        for variant in variants {
            var sameURL = "n/a"
            if let url = source.hlsVariantURL, #available(iOS 26, *) {
                sameURL = variant.url.absoluteURL == url.absoluteURL ? "yes" : "no"
                if sameURL == "no", variant.url.path == url.path { sameURL = "path-only" }
            }
            let video = variant.videoAttributes
            let size = video.map { "\(Int($0.presentationSize.width))x\(Int($0.presentationSize.height))" } ?? "-"
            let codecs =
                video?.codecTypes.map { code in
                    String(bytes: (0..<4).map { UInt8((code >> (24 - $0 * 8)) & 0xFF) }, encoding: .ascii) ?? "?"
                } ?? []
            offlineTransportLog.error(
                "HLS variant size=\(size, privacy: .public) codecs=\(codecs, privacy: .public) fps=\(video?.nominalFrameRate ?? 0, privacy: .public) peak=\(variant.peakBitRate ?? 0, privacy: .public) url=\(sameURL, privacy: .public)"
            )
        }
    }

    private static func matchesVariant(_ variant: AVAssetVariant, source: OfflineSource, byURL: Bool) -> Bool {
        let matchesURL: Bool
        if byURL, let url = source.hlsVariantURL, #available(iOS 26, *) {
            guard variant.url.absoluteURL == url.absoluteURL else { return false }
            matchesURL = true
        } else {
            matchesURL = false
        }
        if let size = source.track.videoSize {
            guard variant.videoAttributes?.presentationSize == CGSize(width: size.width, height: size.height) else {
                return false
            }
        }
        // AVFoundation omits codecTypes for some VP9 variants; their exact playlist URL is authoritative.
        if let codec = source.track.codec, !matchesURL {
            let fourCC = codec.rawValue.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard variant.videoAttributes?.codecTypes.contains(fourCC) == true else { return false }
        }
        if let fps = source.track.fps, let attributes = variant.videoAttributes,
            let frameRate = attributes.nominalFrameRate, frameRate > 0, frameRate.rounded() != Double(fps)
        {
            return false
        }
        if let peak = source.track.hlsPeakBitRate, variant.peakBitRate != peak { return false }
        return true
    }
    #endif

    /// Logs why a variant cannot be saved; reasons carry track IDs and counts, never URLs.
    static func unavailable(_ reason: String) -> OfflineLibraryError {
        offlineTransportLog.error("Offline unavailable: \(reason, privacy: .public)")
        return .unavailable
    }

    /// The one audio option named like the catalog choice, else the one in its language.
    /// Several equally named options are the same rendition repeated across audio groups.
    static func hlsAudioOption<Option>(
        _ options: [Option], name: String, language: String?,
        displayName: (Option) -> String, languageTag: (Option) -> String?
    ) -> Option? {
        let named = options.filter { displayName($0) == name }
        let localized = options.filter { option in
            guard let language, let tag = languageTag(option) else { return false }
            return tag.caseInsensitiveCompare(language) == .orderedSame
        }
        let candidates = named.isEmpty ? localized : named
        let renditions = Set(candidates.map { "\(displayName($0))|\(languageTag($0)?.lowercased() ?? "")" })
        guard renditions.count == 1 else { return nil }
        return candidates.first
    }

    func setForeground(_ foreground: Bool) {
        #if os(iOS)
        completionLock.withLock { allowsChunking = foreground }
        #endif
    }

    func acknowledge(_ attempt: UUID) {
        completionLock.withLock {
            retainedAttempts.remove(attempt)
            cancelledAttempts.remove(attempt)
        }
    }

    func cancel(_ attempt: UUID) async {
        completionLock.withLock { _ = cancelledAttempts.insert(attempt) }
        let tasks = await allTasks().filter { $0.taskDescription == attempt.uuidString }
        for task in tasks { task.cancel() }
        completionLock.withLock {
            // An unstarted queued job has no terminal callback; active ranges keep cancellation until it arrives.
            if tasks.isEmpty, !retainedAttempts.contains(attempt) { cancelledAttempts.remove(attempt) }
        }
    }

    func setYielding(_ yielding: Bool) async {
        let revision = completionLock.withLock {
            pressureYielding = yielding
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
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)),
            let progress = OfflineDownloadChunk.progress(
                request: downloadTask.originalRequest, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        else { return }
        publishProgress(id, progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            guard !completionLock.withLock({ cancelledAttempts.contains(id) }) else { throw CancellationError() }
            let size = (try location.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            try Self.validateDownload(response: downloadTask.response, fileSize: size)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = downloadTask.response?.mimeType?.contains("audio/mpeg") == true ? "mp3" : "mp4"
            let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
            finished[id] = (destination, false)
            if let request = downloadTask.originalRequest, request.value(forHTTPHeaderField: "Range") != nil,
                let response = downloadTask.response as? HTTPURLResponse
            {
                let chunk = try OfflineDownloadChunk(response: response, request: request, fileSize: Int64(size))
                try OfflineTransferReceipt(attempt: id, url: destination, systemPackage: false, isPartial: true)
                    .persist(in: directory)
                try chunk.append(location, to: destination)
                nextChunks[id] = (chunk, request)
            } else {
                try FileManager.default.moveItem(at: location, to: destination)
            }
        } catch { stagingErrors[id] = error.localizedDescription }
    }

    static func validateDownload(response: URLResponse?, fileSize: Int) throws {
        guard let response = response as? HTTPURLResponse else { throw OfflineLibraryError.invalidFile }
        guard (200..<300).contains(response.statusCode) else {
            offlineTransportLog.error("Download rejected: HTTP \(response.statusCode)")
            throw APIError.httpError(response.statusCode)
        }
        guard fileSize > 0 else { throw OfflineLibraryError.invalidFile }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let next = nextChunks.removeValue(forKey: id)
        if error == nil, stagingErrors[id] == nil, let next {
            let continued = completionLock.withLock {
                guard !cancelledAttempts.contains(id),
                    let request = next.0.nextRequest(after: next.1, bounded: allowsChunking)
                else { return false }
                // iOS rate-limits background wakes; keep one remainder request, even after returning to the app.
                retainedAttempts.insert(id)
                let chunk = files.downloadTask(with: request)
                chunk.taskDescription = id.uuidString
                chunk.priority = URLSessionTask.lowPriority
                if !pressureYielding { chunk.resume() }
                return true
            }
            if continued { return }
        }
        let cancelled = completionLock.withLock { cancelledAttempts.contains(id) }
        completionLock.withLock {
            _ = retainedAttempts.insert(id)
            #if os(iOS)
            expectedHLS[id] = nil
            #endif
        }
        lastProgress[id] = nil
        var staged = finished.removeValue(forKey: id)
        if staged == nil, error != nil || stagingErrors[id] != nil || cancelled {
            let partial = directory.appendingPathComponent("\(id.uuidString).mp4")
            if FileManager.default.fileExists(atPath: partial.path) { staged = (partial, false) }
        }
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
        let failure =
            stagingErrors.removeValue(forKey: id) ?? diagnostic
            ?? (cancelled ? "Download cancelled." : nil)
        if let failure {
            if let staged { discardStaged(staged, attempt: id) }
            continuation.yield(.failed(id, failure))
        } else if let staged {
            do {
                try OfflineTransferReceipt(attempt: id, url: staged.0, systemPackage: staged.1, savedVideoSizes: sizes)
                    .persist(in: directory)
                continuation.yield(.finished(id, staged.0, systemPackage: staged.1, savedVideoSizes: sizes))
            } catch {
                discardStaged(staged, attempt: id)
                continuation.yield(.failed(id, "Could not save download completion: \(error.localizedDescription)"))
            }
        } else {
            continuation.yield(.failed(id, "The system did not provide a completed file."))
        }
    }

    /// Only URLs obtained from this adapter's transfer callbacks enter this method.
    /// They are unpublished, so deleting them cannot invalidate a committed library variant.
    private func discardStaged(_ staged: (URL, Bool), attempt: UUID) {
        do {
            do { try FileManager.default.removeItem(at: staged.0) } catch CocoaError.fileNoSuchFile {}
            try? FileManager.default.removeItem(at: OfflineTransferReceipt.location(attempt, in: directory))
        } catch {
            // Keep cleanup retryable after a temporary filesystem failure.
            try? OfflineTransferReceipt(attempt: attempt, url: staged.0, systemPackage: staged.1, isPartial: true)
                .persist(in: directory)
            offlineTransportLog.error(
                "Could not remove unfinished download: \(error.localizedDescription, privacy: .public)")
        }
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
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let normalized = location.absoluteURL.standardizedFileURL
        finished[id] = (normalized, true)
        do {
            // Keep a durable reference to partially written packages so cancellation/relaunch can remove their cache.
            try OfflineTransferReceipt(attempt: id, url: normalized, systemPackage: true, isPartial: true)
                .persist(in: directory)
        } catch {
            stagingErrors[id] = error.localizedDescription
            assetDownloadTask.cancel()
        }
    }
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
        if let expected = completionLock.withLock({ expectedHLS[id] }),
            variants.count != 1
                || !variants.allSatisfy({
                    Self.matchesVariant($0, source: expected, byURL: true)
                        || Self.matchesVariant($0, source: expected, byURL: false)
                })
        {
            offlineTransportLog.error(
                "Offline unavailable: system chose \(variants.count) HLS variants not matching track=\(expected.track.id, privacy: .public)"
            )
            stagingErrors[id] = OfflineLibraryError.unavailable.localizedDescription
            assetDownloadTask.cancel()
            return
        }
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
