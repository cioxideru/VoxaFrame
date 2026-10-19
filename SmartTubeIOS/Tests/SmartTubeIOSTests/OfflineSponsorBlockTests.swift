import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

private protocol RecordingSponsorSource: SponsorSegmentSource {
    func hasRequested(_ id: String) async -> Bool
}

/// Holds every request until `release()`, to prove nothing else waits on a pending fetch.
private actor GatedSponsorSource: RecordingSponsorSource {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var requests: [String] = []
    func hasRequested(_ id: String) -> Bool { requests.contains(id) }
    func segments(videoId: String, categories: Set<SponsorSegment.Category>) async throws -> [SponsorSegment] {
        requests.append(videoId)
        if !open { await withCheckedContinuation { waiters.append($0) } }
        return [SponsorSegment(start: 1, end: 10, category: .sponsor)]
    }
    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

private actor FakeSponsorSource: RecordingSponsorSource {
    var failing: Bool
    private(set) var requests: [String] = []
    private(set) var categories: Set<SponsorSegment.Category> = []
    init(failing: Bool = false) { self.failing = failing }
    func setFailing(_ value: Bool) { failing = value }
    func hasRequested(_ id: String) -> Bool { requests.contains(id) }
    // swiftlint:disable:next async_without_await
    func segments(videoId: String, categories: Set<SponsorSegment.Category>) async throws -> [SponsorSegment] {
        requests.append(videoId)
        self.categories = categories
        if failing { throw URLError(.notConnectedToInternet) }
        return [
            SponsorSegment(start: 1, end: 10, category: .sponsor),
            SponsorSegment(start: 20, end: 21, category: .intro),
            SponsorSegment(start: 30, end: 50, category: .outro),
        ]
    }
}

@Suite("Offline SponsorBlock storage")
struct OfflineSponsorBlockStorageTests {
    private let stamp = Date(timeIntervalSince1970: 1_000_000)

    @Test func segmentsRoundTripThroughTheManifest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineLibraryStore(directory: directory)
        try await store.enqueue(video: Video(id: "v1", title: "T", channelTitle: "C"), tracks: [.automatic])
        let segment = SponsorSegment(start: 1, end: 2, category: .sponsor, apiUUID: "abc")
        try await store.setSponsorSegments(videoID: "v1", segments: [segment], fetchedAt: stamp)
        try await store.markSponsorRefresh(at: stamp)
        let reloaded = try await OfflineLibraryStore(directory: directory).snapshot()
        #expect(reloaded.entries[0].sponsor == OfflineSponsorSegments(segments: [segment], fetchedAt: stamp))
        #expect(reloaded.sponsorRefreshedAt == stamp)
        // A removed video is ignored.
        try await store.setSponsorSegments(videoID: "gone", segments: [segment], fetchedAt: stamp)
        #expect(try await store.snapshot().entries.count == 1)
    }

    @Test func manifestWithoutSponsorFieldsStillDecodes() throws {
        var current = OfflineSnapshot()
        var entry = OfflineEntry(video: Video(id: "old", title: "Old", channelTitle: "C"))
        entry.sponsor = OfflineSponsorSegments(segments: [], fetchedAt: stamp)
        current.entries = [entry]
        current.sponsorRefreshedAt = stamp
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "sponsor")
        object["entries"] = entries
        object.removeValue(forKey: "sponsorRefreshedAt")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(!(String(bytes: legacy, encoding: .utf8) ?? "").contains("sponsor"))
        let snapshot = try JSONDecoder().decode(OfflineSnapshot.self, from: legacy)
        #expect(snapshot.entries[0].id == "old")
        #expect(snapshot.entries[0].sponsor == nil)
        #expect(snapshot.sponsorRefreshedAt == nil)
    }

    @Test func playbackFiltersStoredSegmentsByCurrentCategoriesAndMinimumLength() {
        let stored = OfflineSponsorSegments(
            segments: [
                SponsorSegment(start: 1, end: 10, category: .sponsor),
                SponsorSegment(start: 20, end: 21, category: .intro),
                SponsorSegment(start: 30, end: 50, category: .outro),
            ], fetchedAt: stamp)
        #expect(stored.active(categories: [.sponsor, .intro], minDuration: 0).map(\.category) == [.sponsor, .intro])
        #expect(stored.active(categories: [.sponsor, .intro], minDuration: 2).map(\.category) == [.sponsor])
        // Enabling another category later needs no refetch.
        #expect(stored.active(categories: [.outro], minDuration: 0).count == 1)
        #expect(stored.active(categories: [], minDuration: 0).isEmpty)
    }

    @Test func dailyThrottle() {
        let day = OfflineSponsorSegments.refreshInterval
        #expect(OfflineSponsorSegments.isRefreshDue(lastRefresh: nil, now: stamp))
        #expect(!OfflineSponsorSegments.isRefreshDue(lastRefresh: stamp, now: stamp.addingTimeInterval(day - 1)))
        #expect(OfflineSponsorSegments.isRefreshDue(lastRefresh: stamp, now: stamp.addingTimeInterval(day)))
        // A clock set back must not block refreshes for days.
        #expect(OfflineSponsorSegments.isRefreshDue(lastRefresh: stamp.addingTimeInterval(10), now: stamp))
    }

    @Test func autoUpdateSettingDefaultsOnAndDecodesSafely() throws {
        #expect(AppSettings().offlineSponsorBlockAutoUpdate)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"playbackSpeed":1.5}"#.utf8))
        #expect(old.offlineSponsorBlockAutoUpdate)
        let bad = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"offlineSponsorBlockAutoUpdate":"yes","playbackSpeed":1.5}"#.utf8))
        #expect(bad.offlineSponsorBlockAutoUpdate && bad.playbackSpeed == 1.5)
        var off = AppSettings()
        off.offlineSponsorBlockAutoUpdate = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off))
        #expect(!decoded.offlineSponsorBlockAutoUpdate)
    }
}

@MainActor @Suite("Offline SponsorBlock coordinator", .serialized)
struct OfflineSponsorBlockCoordinatorTests {
    private func wait(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        return predicate()
    }

    struct Harness {
        let coordinator: OfflineCoordinator
        let transport: OfflineFakeTransport
        let dir: URL
    }

    private func makeCoordinator(
        _ source: any SponsorSegmentSource, now: @escaping @Sendable () -> Date = { Date() }
    ) -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = OfflineFakeTransport()
        let coordinator = OfflineCoordinator(
            store: OfflineLibraryStore(directory: directory), transport: transport,
            resolver: OfflineFakeResolver(), notifications: OfflineFakeNotifications(),
            demand: PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {}), now: now,
            validate: { _, _, _ in })
        coordinator.sponsor.source = source
        return Harness(coordinator: coordinator, transport: transport, dir: directory)
    }

    private func download(
        _ id: String, _ coordinator: OfflineCoordinator, _ transport: OfflineFakeTransport, _ dir: URL,
        _ source: any RecordingSponsorSource, settle: Bool = true
    ) async throws {
        coordinator.enqueue(video: Video(id: id, title: id, channelTitle: "C"))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .downloading })
        let attempt = try #require(coordinator.snapshot.jobs.last?.attempt)
        let url = dir.appendingPathComponent(attempt.uuidString + ".mp4")
        try Data([1]).write(to: url)
        transport.continuation.yield(.finished(attempt, url, systemPackage: false))
        #expect(await wait { coordinator.snapshot.jobs.last?.state == .completed })
        // The best-effort fetch runs after completion; wait for it to finish either way.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !source.hasRequested(id), ContinuousClock.now < deadline { await Task.yield() }
        if settle { #expect(await wait { coordinator.sponsor.pending.isEmpty }) }
    }

    @Test func failedFetchNeverFailsTheDownloadAndRefreshRetriesIt() async throws {
        let source = FakeSponsorSource(failing: true)
        let harness = makeCoordinator(source)
        let (coordinator, transport, dir) = (harness.coordinator, harness.transport, harness.dir)
        defer {
            transport.continuation.finish()
            try? FileManager.default.removeItem(at: dir)
        }
        try await download("v1", coordinator, transport, dir, source)
        #expect(coordinator.snapshot.entries[0].assets.count == 1)
        #expect(coordinator.snapshot.entries[0].sponsor == nil)
        #expect(await source.requests == ["v1"])
        // Next refresh retries; segments of every category are requested.
        await source.setFailing(false)
        #expect(await coordinator.refreshSponsorSegments(videoID: "v1"))
        #expect(coordinator.snapshot.entries[0].sponsor?.segments.count == 3)
        #expect(await source.categories == Set(SponsorSegment.Category.allCases))
    }

    @Test func successfulDownloadStoresSegmentsWithFetchDate() async throws {
        let source = FakeSponsorSource()
        let fixed = Date(timeIntervalSince1970: 5_000)
        let harness = makeCoordinator(source, now: { fixed })
        let (coordinator, transport, dir) = (harness.coordinator, harness.transport, harness.dir)
        defer {
            transport.continuation.finish()
            try? FileManager.default.removeItem(at: dir)
        }
        try await download("v1", coordinator, transport, dir, source)
        #expect(await wait { coordinator.snapshot.entries[0].sponsor != nil })
        #expect(coordinator.snapshot.entries[0].sponsor?.fetchedAt == fixed)
    }

    @Test func bulkUpdateCountsResultsAndAutoUpdateStopsOnFirstError() async throws {
        let source = FakeSponsorSource()
        let clock = Date(timeIntervalSince1970: 10_000_000)
        let harness = makeCoordinator(source, now: { clock })
        let (coordinator, transport, dir) = (harness.coordinator, harness.transport, harness.dir)
        defer {
            transport.continuation.finish()
            try? FileManager.default.removeItem(at: dir)
        }
        try await download("a", coordinator, transport, dir, source)
        try await download("b", coordinator, transport, dir, source)
        await source.setFailing(true)
        #expect(await coordinator.refreshAllSponsorSegments() == .finished(updated: 0, failed: 2))
        let before = await source.requests.count
        await coordinator.refreshSponsorSegmentsOnActivation(AppSettings())
        #expect(await source.requests.count == before + 1)  // stopped after one error
        #expect(coordinator.snapshot.sponsorRefreshedAt == nil)  // retried at the next foreground
        await source.setFailing(false)
        await coordinator.refreshSponsorSegmentsOnActivation(AppSettings())
        #expect(coordinator.snapshot.sponsorRefreshedAt == clock)
        // Throttled: no more requests within a day; disabled: never.
        let after = await source.requests.count
        await coordinator.refreshSponsorSegmentsOnActivation(AppSettings())
        #expect(await source.requests.count == after)
    }

    @Test func disabledAutoUpdateMakesNoRequests() async throws {
        let source = FakeSponsorSource()
        let harness = makeCoordinator(source)
        let (coordinator, transport, dir) = (harness.coordinator, harness.transport, harness.dir)
        defer {
            transport.continuation.finish()
            try? FileManager.default.removeItem(at: dir)
        }
        try await download("a", coordinator, transport, dir, source)
        var autoOff = AppSettings()
        autoOff.offlineSponsorBlockAutoUpdate = false
        let before = await source.requests.count
        await coordinator.refreshSponsorSegmentsOnActivation(autoOff)
        #expect(await source.requests.count == before)
    }

    @Test func playbackFillsMissingSegmentsOnceAndOfflineReturnsNil() async throws {
        let source = FakeSponsorSource(failing: true)
        let harness = makeCoordinator(source)
        let (coordinator, transport, dir) = (harness.coordinator, harness.transport, harness.dir)
        defer {
            transport.continuation.finish()
            try? FileManager.default.removeItem(at: dir)
        }
        try await download("a", coordinator, transport, dir, source)
        #expect(await coordinator.sponsorSegmentsForPlayback(videoID: "a") == nil)  // offline: no segments
        await source.setFailing(false)
        let filled = await coordinator.sponsorSegmentsForPlayback(videoID: "a")
        #expect(filled?.segments.count == 3)
        let count = await source.requests.count
        #expect(await coordinator.sponsorSegmentsForPlayback(videoID: "a") == filled)
        #expect(await source.requests.count == count)  // stored: no further request
    }

    private func harness(_ source: any SponsorSegmentSource) -> Harness { makeCoordinator(source) }

    @Test func switchingSponsorBlockOffMakesNoRequestAnywhere() async throws {
        let source = FakeSponsorSource()
        let rig = harness(source)
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        await source.setFailing(false)
        let before = await source.requests.count
        coordinator.sponsor.isEnabled = { false }
        #expect(!(await coordinator.refreshSponsorSegments(videoID: "a")))
        #expect(await coordinator.refreshAllSponsorSegments() == .finished(updated: 0, failed: 1))
        coordinator.fetchSponsorSegmentsIfMissing(videoID: "a")
        _ = await coordinator.sponsorSegmentsForPlayback(videoID: "never-saved")
        var off = AppSettings()
        off.sponsorBlockEnabled = false
        await coordinator.refreshSponsorSegmentsOnActivation(off)
        var autoOff = AppSettings()
        autoOff.offlineSponsorBlockAutoUpdate = false
        await coordinator.refreshSponsorSegmentsOnActivation(autoOff)
        for _ in 0..<20 { await Task.yield() }
        #expect(await source.requests.count == before)
    }

    @Test func pendingFetchDoesNotBlockDownloadCompletionAndPlaybackAdoptsItsResult() async throws {
        let source = GatedSponsorSource()
        let rig = harness(source)
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        // The download completes while its SponsorBlock request is still suspended.
        try await download("a", coordinator, rig.transport, rig.dir, source, settle: false)
        #expect(coordinator.snapshot.entries[0].sponsor == nil)
        let playback = Task { await coordinator.sponsorSegmentsForPlayback(videoID: "a") }
        for _ in 0..<20 { await Task.yield() }
        await source.release()
        #expect(await playback.value?.segments.count == 1)
        #expect(await source.requests == ["a"])  // shared, not requested twice
    }

    @Test func requestsRunOneAtATimeAcrossVideos() async throws {
        let source = GatedSponsorSource()
        let rig = harness(source)
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source, settle: false)
        try await download("b", coordinator, rig.transport, rig.dir, source, settle: false)
        for _ in 0..<20 { await Task.yield() }
        #expect(await source.requests == ["a"])  // "b" waits for "a"
        await source.release()
        #expect(await wait { coordinator.sponsor.pending.isEmpty })
        #expect(await source.requests == ["a", "b"])
    }

    @Test func concurrentActivationsRunTheAutomaticBatchOnce() async throws {
        let source = FakeSponsorSource()
        let clock = Date(timeIntervalSince1970: 10_000_000)
        let rig = makeCoordinator(source, now: { clock })
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        let before = await source.requests.count
        let first = Task { @MainActor in await coordinator.refreshSponsorSegmentsOnActivation(AppSettings()) }
        let second = Task { @MainActor in await coordinator.refreshSponsorSegmentsOnActivation(AppSettings()) }
        await first.value
        await second.value
        #expect(await source.requests.count == before + 1)
        #expect(coordinator.snapshot.sponsorRefreshedAt == clock)
    }

    @Test func failedRefreshKeepsStoredSegments() async throws {
        let source = FakeSponsorSource()
        let first = Date(timeIntervalSince1970: 1_000)
        let rig = makeCoordinator(source, now: { first })
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        let saved = try #require(coordinator.snapshot.entries[0].sponsor)
        await source.setFailing(true)
        #expect(!(await coordinator.refreshSponsorSegments(videoID: "a")))
        #expect(coordinator.snapshot.entries[0].sponsor == saved)
        #expect(try await coordinator.store.snapshot().entries[0].sponsor == saved)
    }

    @Test func turningTheAutomaticPreferenceOffMidRunStopsWithoutStamping() async throws {
        let source = FakeSponsorSource()
        let rig = makeCoordinator(source)
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        try await download("b", coordinator, rig.transport, rig.dir, source)
        let gated = GatedSponsorSource()
        coordinator.sponsor.source = gated
        let run = Task { @MainActor in await coordinator.refreshSponsorSegmentsOnActivation(AppSettings()) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await gated.requests.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        coordinator.sponsor.isAutoUpdateEnabled = { false }  // while the first request waits
        await gated.release()
        await run.value
        #expect(await gated.requests.count == 1)
        #expect(coordinator.snapshot.sponsorRefreshedAt == nil)
    }

    @Test func queueRecoversAfterAFailedRequestAndAfterACancelledWaiter() async throws {
        let source = FakeSponsorSource(failing: true)
        let rig = makeCoordinator(source)
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        try await download("b", coordinator, rig.transport, rig.dir, source)
        #expect(!(await coordinator.refreshSponsorSegments(videoID: "a")))  // a failed (timed-out) request
        await source.setFailing(false)
        #expect(await coordinator.refreshSponsorSegments(videoID: "b"))

        let gated = GatedSponsorSource()
        coordinator.sponsor.source = gated
        let first = Task { @MainActor in await coordinator.refreshSponsorSegments(videoID: "a") }
        let second = Task { @MainActor in await coordinator.refreshSponsorSegments(videoID: "a") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await gated.requests.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        first.cancel()  // one waiter of the shared request goes away
        await gated.release()
        #expect(await second.value)
        _ = await first.value
        #expect(await coordinator.refreshSponsorSegments(videoID: "b"))  // the queue is not stuck
        #expect(await gated.requests == ["a", "b"])
    }

    @Test func malformedRecordsKeepSavedSegmentsAndDoNotStampTheThrottle() async throws {
        let source = FakeSponsorSource()
        let clock = Date(timeIntervalSince1970: 10_000_000)
        let rig = makeCoordinator(source, now: { clock })
        defer {
            rig.transport.continuation.finish()
            try? FileManager.default.removeItem(at: rig.dir)
        }
        let coordinator = rig.coordinator
        try await download("a", coordinator, rig.transport, rig.dir, source)
        let saved = try #require(coordinator.snapshot.entries[0].sponsor)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedRecordsProtocol.self]
        coordinator.sponsor.source = SponsorBlockService(session: URLSession(configuration: config))
        await coordinator.refreshSponsorSegmentsOnActivation(AppSettings())
        #expect(coordinator.snapshot.entries[0].sponsor == saved)
        #expect(coordinator.snapshot.sponsorRefreshedAt == nil)
    }
}

/// Answers every request with a 200 whose only record lacks its required fields.
private final class MalformedRecordsProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[{}]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
