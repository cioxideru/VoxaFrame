import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor @Suite("Parallel offline downloads (PLAN-0029)")
struct OfflineParallelDownloadTests {
    @Test("Resolving reserves slots before suspension", arguments: AppSettings.availableConcurrentDownloadCounts)
    func startsAtMostTheLimitIncludingResolution(limit: Int) async throws {
        let resolver = OfflineParallelResolverGate()
        let fixture = OfflineParallelFixture(limit: limit, resolver: resolver)
        defer { fixture.close() }
        let jobs = try await fixture.seed(6)
        fixture.coordinator.start()
        try #require(await fixture.wait { await resolver.attempts.count == limit })
        #expect(Set(await resolver.attempts) == Set(jobs.prefix(limit).map(\.attempt)))
        #expect(fixture.transport.startOrder.isEmpty)
        for _ in 0..<6 { fixture.coordinator.setDownloadLimit(limit) }
        await resolver.releaseAll()
        try #require(await fixture.wait { fixture.transport.startOrder.count == limit })
        #expect(fixture.activeJobs.count == limit)
        #expect(fixture.coordinator.snapshot.jobs.filter { $0.state == .queued }.count == jobs.count - limit)
        #expect(Set(fixture.transport.startOrder) == Set(jobs.prefix(limit).map(\.attempt)))
    }

    @Test func defaultIsTwoAndMixedTracksShareTheSameLimit() async throws {
        let fixture = OfflineParallelFixture()
        defer { fixture.close() }
        let video = OfflineTrack(id: "video", kind: .video, label: "Video", hasAudio: true)
        let audio = OfflineTrack(id: "audio", kind: .audio, label: "Audio")
        try await fixture.store.enqueue(video: Self.video("one"), tracks: [video, audio])
        let jobs = try await fixture.store.enqueue(
            video: Self.video("two"), tracks: [.translation("ru"), audio, video]
        ).jobs
        fixture.coordinator.start()
        try #require(
            await fixture.wait { fixture.transport.startOrder.count == AppSettings.defaultConcurrentDownloads })
        #expect(Set(fixture.transport.startOrder) == Set(jobs.prefix(2).map(\.attempt)))
        fixture.coordinator.setDownloadLimit(4)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 4 })
        #expect(Set(fixture.transport.activeAttempts()) == Set(jobs.prefix(4).map(\.attempt)))
        #expect(Set(fixture.activeJobs.map(\.videoID)) == ["one", "two"])
        #expect(Set(fixture.activeJobs.map(\.track.kind)) == [.video, .audio, .translation])
        #expect(fixture.state(jobs[4]) == .queued)
        fixture.coordinator.remove(videoID: jobs[0].videoID, jobID: jobs[0].id)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 5 })
        #expect(fixture.state(jobs[1]) == .downloading)
        #expect(fixture.transport.cancelledAttempts == [jobs[0].attempt])
        #expect(fixture.transport.activeAttempts() == Set(jobs.dropFirst().map(\.attempt)))
    }

    @Test func singleSlotStartsJobsInFIFOOrder() async throws {
        let fixture = OfflineParallelFixture(limit: 1)
        defer { fixture.close() }
        let jobs = try await fixture.seed(4)
        fixture.coordinator.start()
        for (index, job) in jobs.enumerated() {
            try #require(await fixture.wait { fixture.transport.startOrder.count == index + 1 })
            #expect(fixture.transport.startOrder == jobs.prefix(index + 1).map(\.attempt))
            try fixture.finish(job)
            try #require(await fixture.wait { fixture.state(job) == .completed })
        }
        #expect(fixture.transport.activeAttempts().isEmpty)
    }

    @Test func completionFailureRemovalAndCancellationRefillSlotsAndKeepProgressSeparate() async throws {
        let fixture = OfflineParallelFixture()
        defer { fixture.close() }
        let jobs = try await fixture.seed(6)
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.transport.startOrder.count == 2 })
        try fixture.finish(jobs[0])
        try #require(await fixture.wait { fixture.transport.startOrder.count == 3 })
        #expect(fixture.state(jobs[0]) == .completed)
        fixture.transport.continuation.yield(.failed(jobs[1].attempt, "Connection lost"))
        try #require(await fixture.wait { fixture.transport.startOrder.count == 4 })
        #expect(fixture.state(jobs[1]) == .failed)
        fixture.coordinator.remove(videoID: jobs[2].videoID, jobID: jobs[2].id)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 5 })
        #expect(fixture.state(jobs[2]) == nil)
        #expect(fixture.transport.cancelledAttempts == [jobs[2].attempt])
        fixture.transport.continuation.yield(.progress(jobs[3].attempt, 0.25))
        fixture.transport.continuation.yield(.progress(jobs[4].attempt, 0.75))
        try #require(
            await fixture.wait {
                fixture.coordinator.snapshot.jobs.first { $0.id == jobs[4].id }?.progress == 0.75
            })
        #expect(fixture.coordinator.snapshot.jobs.first { $0.id == jobs[3].id }?.progress == 0.25)
        #expect(Set(fixture.transport.activeAttempts()) == [jobs[3].attempt, jobs[4].attempt])
        fixture.coordinator.cancel(jobs[3])
        try #require(await fixture.wait { fixture.transport.startOrder.count == 6 })
        #expect(fixture.state(jobs[3]) == .cancelled)
        #expect(Set(fixture.transport.activeAttempts()) == [jobs[4].attempt, jobs[5].attempt])
    }

    @Test func raisedLimitFillsSlotsAndLoweredLimitLetsActiveJobsFinish() async throws {
        let fixture = OfflineParallelFixture(limit: 1)
        defer { fixture.close() }
        let jobs = try await fixture.seed(5)
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.transport.startOrder.count == 1 })
        fixture.coordinator.setDownloadLimit(3)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 3 })
        fixture.coordinator.setDownloadLimit(1)
        #expect(fixture.transport.cancelledAttempts.isEmpty)
        try fixture.finish(jobs[0])
        try #require(await fixture.wait { fixture.transport.isAcknowledged(jobs[0].attempt) })
        #expect(fixture.transport.startOrder.count == 3)
        try fixture.finish(jobs[1])
        try #require(await fixture.wait { fixture.transport.isAcknowledged(jobs[1].attempt) })
        #expect(fixture.transport.startOrder.count == 3)
        #expect(fixture.state(jobs[3]) == .queued)
        try fixture.finish(jobs[2])
        try #require(await fixture.wait { fixture.transport.startOrder.count == 4 })
        #expect(fixture.transport.startOrder.last == jobs[3].attempt)
        #expect(fixture.state(jobs[4]) == .queued)
        #expect(fixture.transport.cancelledAttempts.isEmpty)
    }

    @Test func slowResolutionDoesNotBlockAnotherJobAndItsRemovalFreesOnlyItsSlot() async throws {
        let resolver = OfflineParallelResolverGate()
        let fixture = OfflineParallelFixture(resolver: resolver)
        defer { fixture.close() }
        let jobs = try await fixture.seed(4)
        fixture.coordinator.start()
        try #require(await fixture.wait { await resolver.attempts.count == 2 })
        await resolver.release(jobs[1].attempt)
        try #require(await fixture.wait { fixture.transport.startOrder == [jobs[1].attempt] })
        #expect(fixture.state(jobs[0]) == .resolving)
        fixture.coordinator.remove(videoID: jobs[0].videoID, jobID: jobs[0].id)
        try #require(await fixture.wait { await resolver.attempts.count == 3 })
        #expect(fixture.state(jobs[0]) == nil)
        #expect(fixture.state(jobs[1]) == .downloading)
        await resolver.releaseAll()
        try #require(await fixture.wait { fixture.transport.startOrder.count == 2 })
        #expect(Set(fixture.transport.startOrder) == [jobs[1].attempt, jobs[2].attempt])
        #expect(fixture.state(jobs[3]) == .queued)
    }

    @Test func resolutionFailureRefillsTheSlot() async throws {
        let resolver = OfflineParallelResolverGate()
        let fixture = OfflineParallelFixture(resolver: resolver)
        defer { fixture.close() }
        let jobs = try await fixture.seed(3)
        fixture.coordinator.start()
        try #require(await fixture.wait { await resolver.attempts.count == 2 })
        await resolver.fail(jobs[0].attempt)
        try #require(await fixture.wait { await resolver.attempts.count == 3 })
        #expect(fixture.state(jobs[0]) == .failed)
        await resolver.releaseAll()
        try #require(await fixture.wait { fixture.transport.startOrder.count == 2 })
        #expect(Set(fixture.transport.startOrder) == Set(jobs.suffix(2).map(\.attempt)))
    }

    @Test func retriesJoinTheTailAndLateEventsDoNotAffectOtherJobs() async throws {
        let fixture = OfflineParallelFixture()
        defer { fixture.close() }
        let jobs = try await fixture.seed(4)
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.transport.startOrder.count == 2 })
        fixture.transport.continuation.yield(.failed(jobs[0].attempt, "Retry me"))
        try #require(await fixture.wait { fixture.transport.startOrder.count == 3 })
        fixture.coordinator.retry(jobs[0])
        try #require(await fixture.wait { fixture.coordinator.snapshot.jobs.last?.id == jobs[0].id })
        let retry = try #require(fixture.coordinator.snapshot.jobs.last)
        #expect(retry.attempt != jobs[0].attempt)
        try fixture.finish(jobs[1])
        try #require(await fixture.wait { fixture.transport.startOrder.count == 4 })
        #expect(fixture.transport.startOrder.last == jobs[3].attempt)
        try fixture.finish(jobs[2])
        try #require(await fixture.wait { fixture.transport.startOrder.count == 5 })
        #expect(fixture.transport.startOrder.last == retry.attempt)
        let stale = try fixture.finish(jobs[0])
        try #require(await fixture.wait { !FileManager.default.fileExists(atPath: stale.path) })
        fixture.transport.continuation.yield(.progress(jobs[0].attempt, 0.9))
        fixture.transport.continuation.yield(.failed(jobs[0].attempt, "Late failure"))
        fixture.transport.continuation.yield(.progress(retry.attempt, 0.5))
        try #require(
            await fixture.wait {
                fixture.coordinator.snapshot.jobs.first { $0.id == retry.id }?.progress == 0.5
            })
        #expect(fixture.state(retry) == .downloading)
        #expect(fixture.state(jobs[3]) == .downloading)
        #expect(fixture.coordinator.snapshot.entries.first { $0.id == retry.videoID }?.assets.isEmpty == true)
    }

    @Test func playbackDemandPausesAllTransfersAndDefersNewAdmissions() async throws {
        let fixture = OfflineParallelFixture()
        defer { fixture.close() }
        let jobs = try await fixture.seed(5)
        let owner = UUID()
        fixture.demand.update(owner: owner, phase: .preparing)
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.coordinator.ready && fixture.transport.isYielding })
        #expect(fixture.transport.startOrder.isEmpty)
        fixture.demand.remove(owner: owner)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 2 && !fixture.transport.isYielding })
        fixture.demand.update(owner: owner, phase: .preparing)
        try #require(await fixture.wait { fixture.coordinator.isYielding && fixture.transport.isYielding })
        fixture.coordinator.setDownloadLimit(4)
        try fixture.finish(jobs[0])
        try #require(await fixture.wait { fixture.transport.isAcknowledged(jobs[0].attempt) })
        #expect(fixture.transport.startOrder.count == 2)
        #expect(fixture.transport.isYielding)
        #expect(fixture.transport.cancelledAttempts.isEmpty)
        fixture.demand.remove(owner: owner)
        try #require(await fixture.wait { fixture.transport.startOrder.count == 5 && !fixture.transport.isYielding })
        #expect(Set(fixture.transport.activeAttempts()) == Set(jobs.dropFirst().map(\.attempt)))
    }

    @Test func restoredTransfersConsumeSlotsBeforeQueuedJobs() async throws {
        let fixture = OfflineParallelFixture(limit: 1)
        defer { fixture.close() }
        let jobs = try await fixture.seed(3)
        for job in jobs.prefix(2) {
            try await fixture.store.update(attempt: job.attempt, state: .downloading)
            try await fixture.transport.start(
                OfflineFakeResolver().resolve(video: Self.video(job.videoID), track: job.track, attempt: job.attempt),
                attempt: job.attempt)
        }
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.coordinator.ready })
        #expect(fixture.transport.startOrder.count == 2)
        #expect(fixture.state(jobs[2]) == .queued)
        fixture.transport.continuation.yield(.failed(jobs[0].attempt, "First restored job finished"))
        try #require(await fixture.wait { fixture.transport.isAcknowledged(jobs[0].attempt) })
        #expect(fixture.state(jobs[2]) == .queued)
        fixture.transport.continuation.yield(.failed(jobs[1].attempt, "Second restored job finished"))
        try #require(await fixture.wait { fixture.transport.startOrder.count == 3 })
        #expect(fixture.transport.startOrder.last == jobs[2].attempt)
    }

    @Test func playbackDemandDuringAdmissionRequeuesJobsBeforeSourceResolution() async throws {
        let writes = OfflineResolvingWriteGate()
        let fixture = OfflineParallelFixture(limit: 4, writeManifest: { try writes.write($0, to: $1) })
        defer {
            writes.release()
            fixture.close()
        }
        let jobs = try await fixture.seed(4)
        fixture.coordinator.start()
        try #require(await fixture.wait { fixture.coordinator.ready && writes.entered })
        let revision = fixture.coordinator.snapshot.revision
        let owner = UUID()
        fixture.demand.update(owner: owner, phase: .preparing)
        try #require(await fixture.wait { fixture.coordinator.isYielding && fixture.transport.isYielding })
        writes.release()
        try #require(
            await fixture.wait {
                fixture.coordinator.snapshot.revision >= revision + UInt64(jobs.count * 2)
                    && fixture.coordinator.snapshot.jobs.allSatisfy { $0.state == .queued }
            })
        #expect(fixture.transport.startOrder.isEmpty)
        #expect(fixture.coordinator.snapshot.jobs.map(\.attempt) == jobs.map(\.attempt))
        fixture.demand.remove(owner: owner)
        try #require(await fixture.wait { fixture.transport.startOrder.count == jobs.count })
        #expect(Set(fixture.transport.startOrder) == Set(jobs.map(\.attempt)))
    }

    @Test func storageFailureAsTransfersStartPreservesTheirAttemptsThroughRecovery() async throws {
        let starts = OfflineParallelStartGate()
        let failures = OfflineManifestFailure()
        let transport = OfflineFakeTransport(beforeStartReturns: { await starts.wait() })
        let fixture = OfflineParallelFixture(transport: transport, writeManifest: { try failures.write($0, to: $1) })
        defer {
            Task { await starts.releaseAll() }
            fixture.close()
        }
        let jobs = try await fixture.seed(2)
        fixture.coordinator.start()
        try #require(await fixture.wait { await starts.enteredCount == jobs.count })
        failures.failAll = true
        fixture.coordinator.enqueue(video: Self.video("disk-error"))
        try #require(
            await fixture.wait {
                fixture.coordinator.persistenceBlocked && transport.isYielding
                    && transport.startReturnCount == jobs.count
            })
        failures.failAll = false
        fixture.coordinator.retryStorage()
        try #require(
            await fixture.wait {
                !fixture.coordinator.persistenceBlocked && !transport.isYielding
                    && transport.activeAttempts() == Set(jobs.map(\.attempt))
            })
        #expect(fixture.coordinator.snapshot.jobs.map(\.attempt) == jobs.map(\.attempt))
        #expect(transport.startOrder.count == jobs.count)
        for job in jobs {
            try fixture.finish(job)
            try #require(
                await fixture.wait { fixture.state(job) == .completed && transport.isAcknowledged(job.attempt) })
        }
        #expect(transport.cancelledAttempts.isEmpty)
        #expect(transport.activeAttempts().isEmpty)
    }

    @Test func removalWhileTransportStartReturnsStillCancelsOnlyTheRemovedJob() async throws {
        let starts = OfflineParallelStartGate()
        let transport = OfflineFakeTransport(beforeStartReturns: { await starts.wait() })
        let fixture = OfflineParallelFixture(transport: transport)
        defer {
            Task { await starts.releaseAll() }
            fixture.close()
        }
        let jobs = try await fixture.seed(2)
        fixture.coordinator.start()
        try #require(await fixture.wait { await starts.enteredCount == jobs.count })
        fixture.coordinator.remove(videoID: jobs[0].videoID, jobID: jobs[0].id)
        try #require(
            await fixture.wait { fixture.state(jobs[0]) == nil && transport.cancelledAttempts == [jobs[0].attempt] })
        await starts.releaseAll()
        try #require(await fixture.wait { transport.startReturnCount == jobs.count })
        try fixture.finish(jobs[1])
        try #require(await fixture.wait { fixture.state(jobs[1]) == .completed })
        #expect(transport.cancelledAttempts == [jobs[0].attempt])
    }

    private static func video(_ id: String) -> Video { Video(id: id, title: id, channelTitle: "Test") }
}

@MainActor
private struct OfflineParallelFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store: OfflineLibraryStore
    let transport: OfflineFakeTransport
    let demand = PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {})
    let coordinator: OfflineCoordinator

    init(
        limit: Int = AppSettings.defaultConcurrentDownloads, resolver: any OfflineResolving = OfflineFakeResolver(),
        transport: OfflineFakeTransport = OfflineFakeTransport(),
        writeManifest: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.transport = transport
        store = OfflineLibraryStore(directory: directory, writeManifest: writeManifest)
        coordinator = OfflineCoordinator(
            store: store, transport: transport, resolver: resolver, notifications: OfflineFakeNotifications(),
            demand: demand, validate: { _, _, _ in })
        coordinator.setDownloadLimit(limit)
    }

    var activeJobs: [OfflineJob] {
        coordinator.snapshot.jobs.filter { [.resolving, .downloading].contains($0.state) }
    }

    func state(_ job: OfflineJob) -> OfflineJob.State? {
        coordinator.snapshot.jobs.first { $0.attempt == job.attempt }?.state
    }

    func seed(_ count: Int) async throws -> [OfflineJob] {
        for index in 0..<count {
            try await store.enqueue(
                video: Video(id: "video-\(index)", title: "Video \(index)", channelTitle: "Test"), tracks: [.automatic])
        }
        return try await store.snapshot().jobs
    }

    @discardableResult
    func finish(_ job: OfflineJob) throws -> URL {
        let file = directory.appendingPathComponent(job.attempt.uuidString + ".mp4")
        try Data([1]).write(to: file)
        transport.continuation.yield(.finished(job.attempt, file, systemPackage: false))
        return file
    }

    func wait(_ predicate: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()), ContinuousClock.now < deadline { await Task.yield() }
        return await predicate()
    }

    func close() {
        transport.continuation.finish()
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor OfflineParallelResolverGate: OfflineResolving {
    private(set) var attempts: [UUID] = []
    private var gates: [UUID: AsyncThrowingStream<Void, Error>.Continuation] = [:]

    func catalog(video: Video) throws -> [OfflineSource] { try OfflineFakeResolver().catalog(video: video) }

    func resolve(video: Video, track: OfflineTrack, attempt: UUID) async throws -> OfflineSource {
        let gate = AsyncThrowingStream<Void, Error>.makeStream()
        gates[attempt] = gate.continuation
        attempts.append(attempt)
        defer { gates[attempt] = nil }
        for try await _ in gate.stream { break }
        try Task.checkCancellation()
        return try OfflineFakeResolver().resolve(video: video, track: track, attempt: attempt)
    }

    func release(_ attempt: UUID) {
        gates[attempt]?.yield(())
        gates[attempt]?.finish()
    }

    func releaseAll() {
        for attempt in gates.keys { release(attempt) }
    }

    func fail(_ attempt: UUID) { gates[attempt]?.finish(throwing: OfflineLibraryError.unavailable) }
}

private actor OfflineParallelStartGate {
    private var gates: [AsyncStream<Void>.Continuation] = []
    var enteredCount: Int { gates.count }

    func wait() async {
        let gate = AsyncStream<Void>.makeStream()
        gates.append(gate.continuation)
        // A started system transfer can outlive cancellation of its caller.
        for await _ in gate.stream { break }
    }

    func releaseAll() {
        for gate in gates { gate.finish() }
    }
}

/// Only the first resolving write waits; the condition protects the gate across the store and test actors.
private final class OfflineResolvingWriteGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var blocked = false
    private var released = false
    var entered: Bool { condition.withLock { blocked } }

    func release() {
        condition.withLock {
            released = true
            condition.broadcast()
        }
    }

    func write(_ data: Data, to url: URL) throws {
        let snapshot = try JSONDecoder().decode(OfflineSnapshot.self, from: data)
        if snapshot.jobs.contains(where: { $0.state == .resolving }) {
            try condition.withLock {
                if !blocked {
                    blocked = true
                    let deadline = Date().addingTimeInterval(3)
                    while !released {
                        guard condition.wait(until: deadline) else { throw CocoaError(.fileWriteUnknown) }
                    }
                }
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
