import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

/// All fake task state is protected by its lock; AsyncStream continuation is Sendable.
private final class OfflineFakeTransport: OfflineTransporting, @unchecked Sendable {
    let events: AsyncStream<OfflineTransferEvent>
    let continuation: AsyncStream<OfflineTransferEvent>.Continuation
    private let lock = NSLock()
    private var started: [UUID] = []
    private var cancelled: Set<UUID> = []
    private var acknowledged: Set<UUID> = []
    init() {
        let stream = AsyncStream<OfflineTransferEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }
    func activeAttempts() -> Set<UUID> { lock.withLock { Set(started).subtracting(cancelled) } }
    func start(_ source: OfflineSource, attempt: UUID, yielding: Bool) throws {
        lock.withLock { started.append(attempt) }
    }
    func cancel(_ attempt: UUID) { lock.withLock { _ = cancelled.insert(attempt) } }
    func acknowledge(_ attempt: UUID) { lock.withLock { _ = acknowledged.insert(attempt) } }
    func isAcknowledged(_ attempt: UUID) -> Bool { lock.withLock { acknowledged.contains(attempt) } }
    func setYielding(_ yielding: Bool) {}
}
private struct OfflineFakeResolver: OfflineResolving {
    let track = OfflineTrack(id: "test-muxed", kind: .video, label: "360p H.264", hasAudio: true)
    func catalog(video: Video) throws -> [OfflineSource] { [try resolve(video: video, track: track)] }
    func resolve(video: Video, track: OfflineTrack) throws -> OfflineSource {
        OfflineSource(
            track: track.id == "automatic" ? self.track : track,
            url: try #require(URL(string: "https://example.invalid/media")),
            userAgent: "Test")
    }
}
private actor OfflineFakeNotifications: OfflineNotifying {
    var completedIDs: [UUID] = []
    func requestPermission() {}
    func completed(id: UUID, title: String) { completedIDs.append(id) }
}

@MainActor @Suite("Offline coordinator", .serialized)
struct OfflineCoordinatorTests {
    private func wait(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        return predicate()
    }
    @Test func cancelRetryRejectsOldCompletionAndNotifiesNewAttempt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let notifier = OfflineFakeNotifications()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport,
            resolver: OfflineFakeResolver(), notifications: notifier,
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        let video = Video(id: "one", title: "One", channelTitle: "Test")
        coordinator.enqueue(video: video)
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        let old = try #require(coordinator.snapshot.jobs.first)
        coordinator.cancel(old)
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .cancelled })
        coordinator.retry(old)
        #expect(
            await wait {
                coordinator.snapshot.jobs.first?.state == .downloading
                    && coordinator.snapshot.jobs.first?.attempt != old.attempt
            })
        let retry = try #require(coordinator.snapshot.jobs.first)
        let staleURL = directory.appendingPathComponent(old.attempt.uuidString + ".mp4")
        try Data([1]).write(to: staleURL)
        transport.continuation.yield(.finished(old.attempt, staleURL, systemPackage: false))
        #expect(await wait { !FileManager.default.fileExists(atPath: staleURL.path) })
        #expect(coordinator.snapshot.entries[0].assets.isEmpty)
        let url = directory.appendingPathComponent(retry.attempt.uuidString + ".mp4")
        try Data([2]).write(to: url)
        transport.continuation.yield(.finished(retry.attempt, url, systemPackage: false))
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .completed })
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await notifier.completedIDs.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await notifier.completedIDs.count == 1)
    }
    @Test func explicitSelectionDoesNotFetchOrEnqueueDefaultAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let resolver = OfflineCatalogGate()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport, resolver: resolver,
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        let video = Video(id: "explicit", title: "Explicit", channelTitle: "Test")
        coordinator.enqueue(
            video: video,
            tracks: [
                OfflineTrack(id: "video", kind: .video, label: "Video"),
                OfflineTrack(id: "chosen-audio", kind: .audio, label: "Chosen audio"),
            ])
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        #expect(coordinator.snapshot.jobs.map(\.track.id) == ["video", "chosen-audio"])
        #expect(await !resolver.entered)
    }

    @Test func deletionCancelsActiveTransferAndLateCompletionCannotRestoreIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport, resolver: OfflineFakeResolver(),
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.enqueue(video: Video(id: "delete", title: "Delete", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        let job = try #require(coordinator.snapshot.jobs.first)
        coordinator.remove(videoID: job.videoID, jobID: job.id)
        #expect(await wait { coordinator.snapshot.jobs.isEmpty })
        #expect(!transport.activeAttempts().contains(job.attempt))
        #expect(!transport.isAcknowledged(job.attempt))
        let late = directory.appendingPathComponent(job.attempt.uuidString + ".mp4")
        try Data([1]).write(to: late)
        transport.continuation.yield(.finished(job.attempt, late, systemPackage: false))
        #expect(await wait { !FileManager.default.fileExists(atPath: late.path) })
        #expect(await wait { transport.isAcknowledged(job.attempt) })
        #expect(coordinator.snapshot.entries.isEmpty)
    }

    @Test func deleteAllCancelsQueuedAndActiveTransfersAndRejectsLateCompletions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let resolver = OfflineFakeResolver()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport, resolver: resolver,
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        let first = Video(id: "first", title: "First", channelTitle: "Test")
        coordinator.enqueue(video: first)
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        coordinator.enqueue(video: Video(id: "second", title: "Second", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.count == 2 })
        let attempts = coordinator.snapshot.jobs.map(\.attempt)
        let orphan = UUID()
        try transport.start(resolver.resolve(video: first, track: .automatic), attempt: orphan, yielding: false)
        coordinator.remove(videoID: nil)
        #expect(await wait { coordinator.snapshot.jobs.isEmpty })
        #expect(coordinator.snapshot.entries.isEmpty)
        #expect(transport.activeAttempts().isEmpty)
        for attempt in attempts + [orphan] {
            let late = directory.appendingPathComponent(attempt.uuidString + ".mp4")
            try Data([1]).write(to: late)
            transport.continuation.yield(.finished(attempt, late, systemPackage: false))
            #expect(await wait { !FileManager.default.fileExists(atPath: late.path) })
        }
        #expect(coordinator.snapshot.entries.isEmpty)
        coordinator.enqueue(video: first)
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
    }

    @Test func failureAllowsNextVideoToDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport,
            resolver: OfflineFakeResolver(), notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.enqueue(video: Video(id: "one", title: "One", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        coordinator.enqueue(video: Video(id: "two", title: "Two", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.count == 2 })
        let first = try #require(coordinator.snapshot.jobs.first)
        transport.continuation.yield(.failed(first.attempt, "Connection lost"))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .downloading })
        #expect(coordinator.snapshot.jobs[0].state == .failed)
    }
    @Test func ignoresOlderSnapshotAndCanRetryStartupDiskFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport,
            resolver: OfflineFakeResolver(), notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.start()
        #expect(await wait { coordinator.persistenceBlocked })
        #expect(!coordinator.ready)
        coordinator.enqueue(video: Video(id: "blocked", title: "Blocked", channelTitle: "Test"))
        #expect(coordinator.snapshot.jobs.isEmpty)
        try FileManager.default.removeItem(at: directory)
        coordinator.retryStorage()
        #expect(await wait { coordinator.ready && !coordinator.persistenceBlocked })
        let old = coordinator.snapshot
        coordinator.enqueue(video: Video(id: "accepted", title: "Accepted", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .downloading })
        let revision = coordinator.snapshot.revision
        coordinator.apply(old)
        #expect(coordinator.snapshot.revision == revision)
        #expect(coordinator.snapshot.jobs.first?.state == .downloading)
    }
    @Test func cancellationWhileFindingCompanionAudioDoesNotEnqueueIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let resolver = OfflineCatalogGate()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport, resolver: resolver,
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.enqueue(video: Video(id: "video-only", title: "Video", channelTitle: "Test"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await resolver.entered), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await resolver.entered)
        let job = try #require(coordinator.snapshot.jobs.first)
        coordinator.cancel(job)
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .cancelled })
        await resolver.release()
        while !(await resolver.returned), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await resolver.returned)
        #expect(coordinator.snapshot.jobs.count == 1)
        #expect(coordinator.snapshot.jobs.first?.state == .cancelled)
    }

    @Test func storageRecoveryReleasesOldResolverBeforeItsLateResponse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failures = OfflineManifestFailure()
        let store = OfflineLibraryStore(directory: directory, writeManifest: { try failures.write($0, to: $1) })
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let resolver = OfflineUncooperativeResolver()
        let coordinator = OfflineCoordinator(
            store: store, transport: transport, resolver: resolver, notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.enqueue(video: Video(id: "held", title: "Held", channelTitle: "Test"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await resolver.entered), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await resolver.entered)
        let old = try #require(coordinator.snapshot.jobs.first)
        failures.failAll = true
        coordinator.enqueue(video: Video(id: "error", title: "Error", channelTitle: "Test"))
        #expect(await wait { coordinator.persistenceBlocked })
        failures.failAll = false
        coordinator.retryStorage()
        #expect(
            await wait {
                coordinator.snapshot.jobs.first?.state == .downloading
                    && coordinator.snapshot.jobs.first?.attempt != old.attempt
            })
        let current = try #require(coordinator.snapshot.jobs.first)
        await resolver.release()
        while !(await resolver.returned), ContinuousClock.now < deadline { await Task.yield() }
        #expect(coordinator.snapshot.jobs.first?.attempt == current.attempt)
        #expect(!transport.activeAttempts().contains(old.attempt))
    }

    @Test func storageRetryRequeuesDownloadingStateWithoutSystemTask() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failures = OfflineManifestFailure()
        let store = OfflineLibraryStore(directory: directory, writeManifest: { try failures.write($0, to: $1) })
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let coordinator = OfflineCoordinator(
            store: store, transport: transport, resolver: OfflineFakeResolver(),
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.start()
        #expect(await wait { coordinator.ready })
        let queued = try await store.enqueue(
            video: Video(id: "orphan", title: "Orphan", channelTitle: "Test"), tracks: [.automatic])
        let orphan = try #require(queued.jobs.first)
        coordinator.apply(try await store.update(attempt: orphan.attempt, state: .downloading))
        failures.failAll = true
        coordinator.enqueue(video: Video(id: "disk-error", title: "Error", channelTitle: "Test"))
        #expect(await wait { coordinator.persistenceBlocked })
        failures.failAll = false
        coordinator.retryStorage()
        #expect(
            await wait {
                !coordinator.persistenceBlocked && coordinator.snapshot.jobs.first?.state == .downloading
                    && coordinator.snapshot.jobs.first?.attempt != orphan.attempt
            })
        #expect(transport.activeAttempts().contains(try #require(coordinator.snapshot.jobs.first).attempt))
    }

    @Test func notificationMarkerFailureRetriesCompleteStartupAndReceivesEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failures = OfflineManifestFailure()
        let store = OfflineLibraryStore(directory: directory, writeManifest: { try failures.write($0, to: $1) })
        let video = Video(id: "completed", title: "Completed", channelTitle: "Test")
        let queued = try await store.enqueue(video: video, tracks: [.automatic])
        let job = try #require(queued.jobs.first)
        try await store.update(attempt: job.attempt, state: .downloading)
        let file = directory.appendingPathComponent(job.attempt.uuidString + ".mp4")
        try Data([1]).write(to: file)
        try await store.finish(attempt: job.attempt, staged: file, systemPackage: false)
        failures.failMarker = true
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let coordinator = OfflineCoordinator(
            store: store, transport: transport, resolver: OfflineFakeResolver(),
            notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), validate: { _, _, _ in })
        coordinator.start()
        #expect(await wait { coordinator.persistenceBlocked })
        #expect(!coordinator.ready)
        failures.failMarker = false
        coordinator.retryStorage()
        #expect(await wait { coordinator.ready && !coordinator.persistenceBlocked })
        coordinator.enqueue(video: Video(id: "next", title: "Next", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .downloading })
        let next = try #require(coordinator.snapshot.jobs.last)
        transport.continuation.yield(.failed(next.attempt, "Observed after restored startup"))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .failed })
    }

    @Test func deferredTranslationDoesNotBlockAnotherVideo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = OfflineFakeTransport()
        defer { transport.continuation.finish() }
        let timer = OfflineTestClock()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport,
            resolver: OfflineDeferredResolver(), notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}),
            now: { timer.now }, waitUntil: { try await timer.wait(until: $0) }, validate: { _, _, _ in })
        coordinator.enqueue(
            video: Video(id: "translated", title: "Translated", channelTitle: "Test"), tracks: [.translation("ru")])
        #expect(await wait { coordinator.snapshot.jobs.first?.resolutionAttempts == 1 })
        coordinator.enqueue(video: Video(id: "next", title: "Next", channelTitle: "Test"))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .downloading })
        #expect(coordinator.snapshot.jobs[0].state == .queued)
        #expect(coordinator.snapshot.jobs[0].nextResolutionAt == timer.now.addingTimeInterval(30))
        let next = try #require(coordinator.snapshot.jobs.last)
        timer.advance(seconds: 31)
        transport.continuation.yield(.failed(next.attempt, "Fixture finished"))
        #expect(await wait { coordinator.snapshot.jobs.first?.resolutionAttempts == 2 })
        coordinator.cancel(coordinator.snapshot.jobs[0])
        #expect(await wait { coordinator.snapshot.jobs.first?.state == .cancelled })
    }

}

private struct OfflineDeferredResolver: OfflineResolving {
    func catalog(video: Video) throws -> [OfflineSource] { try OfflineFakeResolver().catalog(video: video) }
    func resolve(video: Video, track: OfflineTrack) throws -> OfflineSource {
        if track.kind == .translation { throw OfflineResolutionDeferred(delay: 30) }
        return try OfflineFakeResolver().resolve(video: video, track: track)
    }
}
/// The lock owns both the simulated time and its independent timer subscribers.
private final class OfflineTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 100)
    private var continuations: [UUID: AsyncStream<Date>.Continuation] = [:]
    var now: Date { lock.withLock { date } }
    func advance(seconds: TimeInterval) {
        lock.withLock {
            date += seconds
            for continuation in continuations.values { continuation.yield(date) }
        }
    }
    func wait(until target: Date) async throws {
        let id = UUID()
        let stream = AsyncStream<Date> { continuation in
            lock.withLock {
                continuations[id] = continuation
                continuation.yield(date)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
            }
        }
        for await date in stream where date >= target { return }
        try Task.checkCancellation()
    }
}

/// The lock protects the injected failure switch; writes happen on the store actor.
private final class OfflineManifestFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var marker = false
    private var all = false
    var failAll: Bool {
        get { lock.withLock { all } }
        set { lock.withLock { all = newValue } }
    }
    var failMarker: Bool {
        get { lock.withLock { marker } }
        set { lock.withLock { marker = newValue } }
    }
    func write(_ data: Data, to url: URL) throws {
        let snapshot = try JSONDecoder().decode(OfflineSnapshot.self, from: data)
        if failAll || (failMarker && !snapshot.notifiedBatches.isEmpty) { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}

private actor OfflineCatalogGate: OfflineResolving {
    var entered = false
    var returned = false
    private let gate = AsyncStream<Void>.makeStream()
    func release() {
        gate.continuation.yield(())
        gate.continuation.finish()
    }
    func catalog(video: Video) async throws -> [OfflineSource] {
        entered = true
        for await _ in gate.stream { break }
        returned = true
        return [
            OfflineSource(
                track: OfflineTrack(id: "audio", kind: .audio, label: "Audio"),
                url: try #require(URL(string: "https://example.invalid/audio")), userAgent: "Test")
        ]
    }
    func resolve(video: Video, track: OfflineTrack) throws -> OfflineSource {
        OfflineSource(
            track: OfflineTrack(id: "video", kind: .video, label: "Video"),
            url: try #require(URL(string: "https://example.invalid/video")), userAgent: "Test")
    }
}

private actor OfflineUncooperativeResolver: OfflineResolving {
    var entered = false
    var returned = false
    private var gate: CheckedContinuation<Void, Never>?
    func release() {
        gate?.resume()
        gate = nil
    }
    func catalog(video: Video) throws -> [OfflineSource] { try OfflineFakeResolver().catalog(video: video) }
    func resolve(video: Video, track: OfflineTrack) async throws -> OfflineSource {
        if !entered {
            entered = true
            await withCheckedContinuation { gate = $0 }
            returned = true
        }
        return try OfflineFakeResolver().resolve(video: video, track: track)
    }
}
