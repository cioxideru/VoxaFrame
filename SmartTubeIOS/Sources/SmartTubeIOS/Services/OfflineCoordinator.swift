import Foundation
import Observation
import SmartTubeIOSCore

#if !os(tvOS)
import UserNotifications
#endif

protocol OfflineNotifying: Sendable {
    func requestPermission() async
    func completed(id: UUID, title: String) async
}
struct OfflineNotifications: OfflineNotifying {
    func requestPermission() async {
        #if !os(tvOS)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        #endif
    }
    func completed(id: UUID, title: String) async {
        #if !os(tvOS)
        let content = UNMutableNotificationContent()
        content.title = "Ready to watch offline"
        content.body = title
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        #endif
    }
}

@MainActor @Observable
public final class OfflineCoordinator {
    public static let shared = OfflineCoordinator()
    public private(set) var snapshot = OfflineSnapshot()
    public private(set) var error: String?
    public private(set) var isYielding = false
    public private(set) var ready = false
    @ObservationIgnored let store: OfflineLibraryStore
    @ObservationIgnored private let transport: any OfflineTransporting
    @ObservationIgnored private var resolver: any OfflineResolving
    @ObservationIgnored private let notifications: any OfflineNotifying
    @ObservationIgnored private let validate: @Sendable (URL, OfflineTrack, Bool) async throws -> Void
    @ObservationIgnored private(set) var persistenceBlocked = false
    @ObservationIgnored private let demand: PlaybackDemandCoordinator
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let waitUntil: @Sendable (Date) async throws -> Void
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var deferredEvents: [OfflineTransferEvent] = []
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var demandTask: Task<Void, Never>?
    @ObservationIgnored private var resolverTask: Task<Void, Never>?
    @ObservationIgnored private var resolvingAttempt: UUID?
    @ObservationIgnored private var backgroundHandlers: [String: () -> Void] = [:]
    @ObservationIgnored private var drainedSessions: Set<String> = []

    public static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
            "SmartTubeOffline")
    }
    private convenience init() {
        self.init(
            store: OfflineLibraryStore(directory: Self.directory),
            transport: OfflineDownloadTransport(directory: Self.directory),
            resolver: OfflineSourceResolver(api: InnerTubeAPI()), notifications: OfflineNotifications())
    }
    init(
        store: OfflineLibraryStore, transport: any OfflineTransporting, resolver: any OfflineResolving,
        notifications: any OfflineNotifying,
        demand: PlaybackDemandCoordinator = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        waitUntil: @escaping @Sendable (Date) async throws -> Void = { date in
            try await ContinuousClock().sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
        },
        validate: @escaping @Sendable (URL, OfflineTrack, Bool) async throws -> Void = {
            try await OfflineMedia.validate($0, track: $1, systemPackage: $2)
        }
    ) {
        self.store = store
        self.transport = transport
        self.resolver = resolver
        self.notifications = notifications
        self.validate = validate
        self.demand = demand
        self.now = now
        self.waitUntil = waitUntil
    }
    public func configure(api: InnerTubeAPI) {
        guard startup == nil else { return }
        #if DEBUG
        resolver = OfflineUITestFixture.resolver() ?? OfflineSourceResolver(api: api)
        #else
        resolver = OfflineSourceResolver(api: api)
        #endif
        start()
    }
    public func start() {
        guard startup == nil else { return }
        startup = Task {
            do {
                apply(try await store.snapshot())
                try await finishRemovals()
                try await restoreCompletions()
                let active = await transport.activeAttempts()
                apply(try await store.recover(activeAttempts: active))
                for attempt in active.subtracting(activeIDs) { await transport.cancel(attempt) }
                isYielding = demand.isYielding
                await transport.setYielding(isYielding)
                error = nil
                persistenceBlocked = false
                for (batch, title) in try await store.takeCompletedBatches() {
                    await notifications.completed(id: batch, title: title)
                }
                eventTask = Task { [weak self = self, transport] in
                    for await event in transport.events {
                        guard let self, !Task.isCancelled else { return }
                        await receive(event)
                    }
                }
                demandTask = Task { [weak self = self, demand] in
                    for await yielding in demand.changes() {
                        guard let self, !Task.isCancelled else { return }
                        isYielding = yielding
                        await transport.setYielding(yielding || persistenceBlocked)
                        pump()
                    }
                }
                ready = true
                pump()
            } catch {
                blockPersistence(error)
                startup = nil
            }
        }
    }
    func apply(_ next: OfflineSnapshot) {
        guard next.revision >= snapshot.revision else { return }
        snapshot = next
    }
    private func blockPersistence(_ failure: Error) {
        error = failure.localizedDescription
        persistenceBlocked = true
        resolverTask?.cancel()
        resolverTask = nil
        resolvingAttempt = nil
        wakeTask?.cancel()
        wakeTask = nil
        Task { await transport.setYielding(true) }
    }
    private func restoreCompletions() async throws {
        let active = await transport.activeAttempts()
        for receipt in try await store.pendingReceipts() {
            if receipt.isPartial == true {
                if !active.contains(receipt.attempt) {
                    await store.discard(
                        attempt: receipt.attempt, url: receipt.url, systemPackage: receipt.systemPackage)
                }
                continue
            }
            if let job = snapshot.jobs.first(where: { $0.attempt == receipt.attempt && $0.state == .downloading }) {
                do { try await validate(receipt.url, job.track, receipt.systemPackage) } catch {
                    apply(
                        try await store.update(
                            attempt: receipt.attempt, state: .failed, error: error.localizedDescription))
                    await store.discard(
                        attempt: receipt.attempt, url: receipt.url, systemPackage: receipt.systemPackage)
                    transport.acknowledge(receipt.attempt)
                    continue
                }
            }
            apply(
                try await store.finish(
                    attempt: receipt.attempt, staged: receipt.url, systemPackage: receipt.systemPackage,
                    savedVideoSizes: receipt.savedVideoSizes))
            transport.acknowledge(receipt.attempt)
        }
    }
    func retryStorage() {
        guard persistenceBlocked else { return }
        if !ready {
            persistenceBlocked = false
            start()
            return
        }
        Task {
            do {
                try await finishRemovals()
                try await restoreCompletions()
                let active = await transport.activeAttempts()
                apply(try await store.recover(activeAttempts: active))
                for attempt in active.subtracting(activeIDs) { await transport.cancel(attempt) }
                persistenceBlocked = false
                error = nil
                let events = deferredEvents
                deferredEvents = []
                for event in events { await receive(event) }
                if !persistenceBlocked {
                    for (batch, title) in try await store.takeCompletedBatches() {
                        await notifications.completed(id: batch, title: title)
                    }
                    await transport.setYielding(isYielding)
                    for identifier in Array(drainedSessions) { finishBackgroundEvents(identifier) }
                    pump()
                }
            } catch { blockPersistence(error) }
        }
    }
    private var activeIDs: Set<UUID> {
        Set(snapshot.jobs.filter { [.resolving, .downloading].contains($0.state) }.map(\.attempt))
    }
    public func enqueue(video: Video, translationLanguage: String? = nil) {
        var tracks: [OfflineTrack] = [.automatic]
        if let translationLanguage { tracks.append(.translation(translationLanguage)) }
        enqueue(video: video, tracks: tracks)
    }
    func enqueue(video: Video, tracks: [OfflineTrack]) {
        start()
        Task {
            await startup?.value
            guard ready, !persistenceBlocked else { return }
            do {
                apply(try await store.enqueue(video: video, tracks: tracks))
                error = nil
                pump()
                await notifications.requestPermission()
            } catch { blockPersistence(error) }
        }
    }
    func cancel(_ job: OfflineJob) {
        guard !persistenceBlocked else { return }
        Task {
            do {
                apply(try await store.update(attempt: job.attempt, state: .cancelled))
                if resolvingAttempt == job.attempt {
                    resolverTask?.cancel()
                    resolverTask = nil
                    resolvingAttempt = nil
                }
                await transport.cancel(job.attempt)
                pump()
            } catch { blockPersistence(error) }
        }
    }
    func retry(_ job: OfflineJob) {
        guard !persistenceBlocked else { return }
        Task {
            do {
                apply(try await store.retry(id: job.id))
                pump()
            } catch { blockPersistence(error) }
        }
    }
    func catalog(video: Video) async throws -> [OfflineTrack] {
        try await resolver.catalog(video: video).map(\.track)
    }
    private func pump() {
        guard ready, !persistenceBlocked, !isYielding, (snapshot.pendingRemovals ?? []).isEmpty, resolverTask == nil,
            !snapshot.jobs.contains(where: { $0.state == .downloading })
        else { return }
        guard
            let job = snapshot.jobs.first(where: {
                $0.state == .queued && ($0.nextResolutionAt ?? .distantPast) <= now()
            }),
            let entry = snapshot.entries.first(where: { $0.id == job.videoID })
        else {
            scheduleWake()
            return
        }
        wakeTask?.cancel()
        wakeTask = nil
        resolvingAttempt = job.attempt
        resolverTask = Task {
            defer {
                if resolvingAttempt == job.attempt {
                    resolverTask = nil
                    resolvingAttempt = nil
                }
                pump()
            }
            do {
                apply(try await store.update(attempt: job.attempt, state: .resolving))
                let source = try await resolver.resolve(video: entry.video, track: job.track)
                try Task.checkCancellation()
                guard snapshot.jobs.contains(where: { $0.attempt == job.attempt && $0.state == .resolving }) else {
                    return
                }
                if job.track.id == OfflineTrack.automatic.id, source.track.kind == .video, !source.track.hasAudio,
                    !entry.assets.contains(where: { $0.track.kind == .audio }),
                    !snapshot.jobs.contains(where: {
                        $0.videoID == job.videoID && $0.track.kind == .audio
                            && [.queued, .resolving, .downloading, .completed].contains($0.state)
                    })
                {
                    let catalog = try await resolver.catalog(video: entry.video)
                    try Task.checkCancellation()
                    guard !persistenceBlocked,
                        snapshot.jobs.contains(where: { $0.attempt == job.attempt && $0.state == .resolving })
                    else { return }
                    guard let audio = catalog.first(where: { $0.track.kind == .audio }) else {
                        throw OfflineLibraryError.missingAudio
                    }
                    apply(try await store.enqueue(video: entry.video, tracks: [audio.track], batch: job.batch))
                    try Task.checkCancellation()
                }
                apply(try await store.update(attempt: job.attempt, state: .downloading, track: source.track))
                guard !persistenceBlocked,
                    snapshot.jobs.contains(where: { $0.attempt == job.attempt && $0.state == .downloading })
                else { return }
                try await transport.start(source, attempt: job.attempt, yielding: isYielding)
                guard !Task.isCancelled,
                    snapshot.jobs.contains(where: { $0.attempt == job.attempt && $0.state == .downloading })
                else {
                    await transport.cancel(job.attempt)
                    return
                }
                await transport.setYielding(isYielding)
            } catch let deferred as OfflineResolutionDeferred {
                do {
                    apply(
                        try await store.deferResolution(
                            attempt: job.attempt, until: now().addingTimeInterval(deferred.delay)))
                } catch { blockPersistence(error) }
            } catch {
                if !Task.isCancelled {
                    do {
                        apply(
                            try await store.update(
                                attempt: job.attempt, state: .failed, error: error.localizedDescription))
                    } catch { blockPersistence(error) }
                }
            }
        }
    }
    private func scheduleWake() {
        wakeTask?.cancel()
        guard let date = snapshot.jobs.filter({ $0.state == .queued }).compactMap(\.nextResolutionAt).min() else {
            return
        }
        wakeTask = Task { [weak self, waitUntil] in
            do { try await waitUntil(date) } catch { return }
            guard let self, !Task.isCancelled else { return }
            wakeTask = nil
            pump()
        }
    }
    private func receive(_ event: OfflineTransferEvent) async {
        guard !persistenceBlocked else {
            if case .progress = event { return }
            deferredEvents.append(event)
            return
        }
        do {
            switch event {
            case .progress(let attempt, let progress):
                guard progress.isFinite, let job = snapshot.jobs.first(where: { $0.attempt == attempt }),
                    Int(progress * 100) != Int(job.progress * 100)
                else { return }
                apply(try await store.update(attempt: attempt, state: .downloading, progress: progress))
            case .finished(let attempt, let url, let systemPackage, let savedVideoSizes):
                guard let job = snapshot.jobs.first(where: { $0.attempt == attempt && $0.state == .downloading }) else {
                    await store.discard(attempt: attempt, url: url, systemPackage: systemPackage)
                    transport.acknowledge(attempt)
                    return
                }
                do { try await validate(url, job.track, systemPackage) } catch {
                    apply(try await store.update(attempt: attempt, state: .failed, error: error.localizedDescription))
                    await store.discard(attempt: attempt, url: url, systemPackage: systemPackage)
                    transport.acknowledge(attempt)
                    pump()
                    return
                }
                apply(
                    try await store.finish(
                        attempt: attempt, staged: url, systemPackage: systemPackage, savedVideoSizes: savedVideoSizes))
                transport.acknowledge(attempt)
                for (batch, title) in try await store.takeCompletedBatches() {
                    await notifications.completed(id: batch, title: title)
                }
            case .failed(let attempt, let reason):
                apply(try await store.update(attempt: attempt, state: .failed, error: reason))
                transport.acknowledge(attempt)
            case .drained(let identifier):
                drainedSessions.insert(identifier)
                finishBackgroundEvents(identifier)
            }
            pump()
        } catch {
            blockPersistence(error)
            deferredEvents.append(event)
        }
    }
    public func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard [OfflineDownloadTransport.fileSessionID, OfflineDownloadTransport.hlsSessionID].contains(identifier)
        else {
            completion()
            return
        }
        backgroundHandlers[identifier] = completion
        start()
        finishBackgroundEvents(identifier)
    }
    private func finishBackgroundEvents(_ identifier: String) {
        guard !persistenceBlocked, drainedSessions.contains(identifier),
            let completion = backgroundHandlers.removeValue(forKey: identifier)
        else { return }
        drainedSessions.remove(identifier)
        completion()
    }
    func playbackVideo(
        entry: OfflineEntry, videoAsset: OfflineAsset, audio: OfflineAsset?, translation: OfflineAsset?
    ) async throws -> Video {
        guard videoAsset.track.kind != .hls || audio == nil else { throw OfflineLibraryError.unavailable }
        var video = entry.video
        video.localFileURL = try await store.fileURL(videoAsset)
        if let audio { video.localAudioFileURL = try await store.fileURL(audio) }
        if let translation { video.localTranslationFileURL = try await store.fileURL(translation) }
        guard videoAsset.track.hasAudio || audio != nil else { throw OfflineLibraryError.missingAudio }
        return video
    }
}

extension OfflineCoordinator {
    func remove(videoID: String?, jobID: UUID? = nil) {
        guard !persistenceBlocked else { return }
        Task {
            do {
                apply(try await store.beginRemoval(videoID: videoID, jobID: jobID))
                try await finishRemovals()
                error = nil
                pump()
            } catch { blockPersistence(error) }
        }
    }
    private func finishRemovals() async throws {
        let removals = snapshot.pendingRemovals ?? []
        let ids = Set(removals.flatMap { $0.jobIDs })
        var attempts = Set(snapshot.jobs.filter { ids.contains($0.id) }.map(\.attempt))
        if removals.contains(where: { $0.videoID == nil }) {
            attempts.formUnion(await transport.activeAttempts())
            if let resolvingAttempt { attempts.insert(resolvingAttempt) }
        }
        for attempt in attempts {
            if resolvingAttempt == attempt {
                resolverTask?.cancel()
                resolverTask = nil
                resolvingAttempt = nil
            }
            await transport.cancel(attempt)
            transport.acknowledge(attempt)
        }
        apply(try await store.completeRemovals())
    }
}
