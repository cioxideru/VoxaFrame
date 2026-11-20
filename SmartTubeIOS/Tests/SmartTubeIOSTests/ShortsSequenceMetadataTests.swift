import Foundation
import Testing
import os

@testable import SmartTubeIOSCore

// PLAN-0052: sequence entries carry only an ID; Core fills each Short's title and channel from its
// `reel/reel_item_watch` overlay before the page reaches the feed.

/// TVHTML5 `reel/reel_item_watch` overlays in the shape captured for upstream #189, trimmed to the fields read.
private enum OverlayFixture {
    static let capture = """
        {"overlay": {"reelPlayerOverlayRenderer": {
          "reelPlayerHeaderSupportedRenderers": {"reelPlayerHeaderRenderer": {
            "reelTitleText": {"runs": [{"text": "Physics "}, {"text": "#sports"}]},
            "timestampText": {"simpleText": "5 days ago"},
            "channelNavigationEndpoint": {"browseEndpoint": {"browseId": "UC123"}},
            "channelTitleText": {"runs": [{"text": "@Chan"}]}}},
          "subscribeButtonRenderer": {"subscribeButtonRenderer": {"subscribed": true, "channelId": "UC123"}}}}}
        """

    static let subscribeOnly = """
        {"overlay": {"reelPlayerOverlayRenderer": {
          "reelPlayerHeaderSupportedRenderers": {"reelPlayerHeaderRenderer": {
            "reelTitleText": {"simpleText": "Plain title"}, "channelTitleText": {"simpleText": "Plain channel"}}},
          "subscribeButtonRenderer": {"subscribeButtonRenderer": {"channelId": "UCsub"}}}}}
        """

    static func answer(videoId: String) -> String {
        """
        {"overlay": {"reelPlayerOverlayRenderer": {"reelPlayerHeaderSupportedRenderers": {"reelPlayerHeaderRenderer": {
          "reelTitleText": {"runs": [{"text": "Title "}, {"text": "\(videoId)"}]},
          "channelTitleText": {"runs": [{"text": "@Channel \(videoId)"}]},
          "channelNavigationEndpoint": {"browseEndpoint": {"browseId": "UC-\(videoId)"}}}}}}}
        """
    }

    static let sequence = """
        {"responseContext": {"serviceTrackingParams": [
           {"service": "GFEEDBACK", "params": [{"key": "logged_in", "value": "1"}]}]},
         "entries": [{"command": {"reelWatchEndpoint": {"videoId": "m-1"}}},
                     {"command": {"reelWatchEndpoint": {"videoId": "m-2"}}},
                     {"command": {"reelWatchEndpoint": {"videoId": "m-3"}}}],
         "continuation": "NEXT"}
        """

    static func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

@Suite("Shorts overlay metadata parser (PLAN-0052)")
struct ShortsOverlayMetadataParserTests {

    @Test("The captured overlay gives the joined title, the channel name and the browse channel ID")
    func parsesCapturedOverlay() throws {
        let metadata = try #require(ShortsSequence.metadata(from: try OverlayFixture.json(OverlayFixture.capture)))
        #expect(
            metadata == ShortsSequence.Metadata(title: "Physics #sports", channelTitle: "@Chan", channelId: "UC123"))
    }

    @Test("simpleText is read, and the subscribe button gives the channel ID without a browse endpoint")
    func readsSimpleTextAndSubscribeChannel() throws {
        let metadata = try #require(
            ShortsSequence.metadata(from: try OverlayFixture.json(OverlayFixture.subscribeOnly)))
        #expect(
            metadata == ShortsSequence.Metadata(title: "Plain title", channelTitle: "Plain channel", channelId: "UCsub")
        )
    }

    @Test("An answer without the overlay has no metadata")
    func missingOverlay() throws {
        #expect(ShortsSequence.metadata(from: [:]) == nil)
        #expect(ShortsSequence.metadata(from: try OverlayFixture.json(OverlayFixture.sequence)) == nil)
    }

    @Test("Filling keeps known values and takes only empty ones")
    func fillingKeepsKnownValues() {
        let metadata = ShortsSequence.Metadata(title: "New", channelTitle: "New channel", channelId: "UCnew")
        let partial = Video(id: "p", title: "Own", channelTitle: "", channelId: "UCown", isShort: true)
        let filled = ShortsSequence.filling(partial, with: metadata)
        #expect(filled.title == "Own")
        #expect(filled.channelTitle == "New channel")
        #expect(filled.channelId == "UCown")
        #expect(
            ShortsSequence.filling(Video(id: "e", title: "", channelTitle: ""), with: metadata).channelId == "UCnew")
    }
}

// MARK: - Lookups at the API seam

/// Answers the sequence with three Shorts (running `onSequence` first, as if the answer came late) and each
/// `reel/reel_item_watch` with its own overlay, unless the Short is set to fail or every lookup is set to hang. With
/// `holding` each lookup's answer waits for `releaseOne()`. It counts the lookups in flight: from their start until
/// answered or stopped. Unchecked Sendable: every stored property is used only under `lock`.
private final class OverlayRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(URLRequest, [String: Any])] = []
    private var failing: Set<String> = []
    private var hanging = false
    private var holding = false
    private var held: [(lookup: ObjectIdentifier, respond: @Sendable () -> Void)] = []
    private var onSequence: (@Sendable () -> Void)?
    private var active: Set<ObjectIdentifier> = []
    private var started = 0
    private var mostActive = 0

    func reset(
        failing: Set<String> = [], hanging: Bool = false, holding: Bool = false,
        onSequence: (@Sendable () -> Void)? = nil
    ) {
        lock.withLock {
            requests = []
            self.failing = failing
            self.hanging = hanging
            self.holding = holding
            held = []
            self.onSequence = onSequence
            active = []
            started = 0
            mostActive = 0
        }
    }

    /// Keeps a lookup's `respond` until `releaseOne()`; false when lookups are not held.
    func hold(_ lookup: ObjectIdentifier, respond: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            guard holding else { return false }
            held.append((lookup, respond))
            return true
        }
    }

    /// Answers the oldest held lookup.
    func releaseOne() {
        let respond = lock.withLock { held.isEmpty ? nil : held.removeFirst().respond }
        respond?()
    }

    /// A stopped lookup is never answered.
    func drop(_ lookup: ObjectIdentifier) { lock.withLock { held.removeAll { $0.lookup == lookup } } }

    /// The status and body to answer with; nil leaves the request unanswered until it is cancelled.
    func answer(_ request: URLRequest, body: Data) -> (Int, Data)? {
        lock.withLock {
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            requests.append((request, json))
            let path = request.url?.path ?? ""
            if path.hasSuffix("/reel/reel_watch_sequence") {
                onSequence?()
                return (200, Data(OverlayFixture.sequence.utf8))
            }
            guard path.hasSuffix("/reel/reel_item_watch") else { return (404, Data()) }
            if hanging { return nil }
            let videoId = (json["playerRequest"] as? [String: Any])?["videoId"] as? String ?? ""
            if failing.contains(videoId) { return (500, Data()) }
            return (200, Data(OverlayFixture.answer(videoId: videoId).utf8))
        }
    }

    func lookupStarted(_ lookup: ObjectIdentifier) {
        lock.withLock {
            active.insert(lookup)
            started += 1
            mostActive = max(mostActive, active.count)
        }
    }

    func lookupEnded(_ lookup: ObjectIdentifier) { lock.withLock { _ = active.remove(lookup) } }

    var inFlight: Int { lock.withLock { active.count } }
    var lookupsStarted: Int { lock.withLock { started } }
    var maxInFlight: Int { lock.withLock { mostActive } }

    func requests(path: String) -> [(URLRequest, [String: Any])] {
        lock.withLock { requests.filter { $0.0.url?.path.hasSuffix(path) == true } }
    }

    var lookups: [(URLRequest, [String: Any])] { requests(path: "/reel/reel_item_watch") }
}

/// Unchecked Sendable: URLProtocol is not Sendable; this subclass adds no mutable state (the probe locks its own).
private final class OverlayURLProtocol: URLProtocol, @unchecked Sendable {
    static let probe = OverlayRequestProbe()
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isLookup: Bool { request.url?.path.hasSuffix("/reel/reel_item_watch") == true }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        if isLookup { Self.probe.lookupStarted(ObjectIdentifier(self)) }
        guard let (status, data) = Self.probe.answer(request, body: body) else { return }
        let respond: @Sendable () -> Void = { self.respond(status: status, data: data) }
        if isLookup, Self.probe.hold(ObjectIdentifier(self), respond: respond) { return }
        respond()
    }

    private func respond(status: Int, data: Data) {
        // Ended before the answer is delivered: only then can the next lookup take its slot.
        if isLookup { Self.probe.lookupEnded(ObjectIdentifier(self)) }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard isLookup else { return }
        Self.probe.drop(ObjectIdentifier(self))
        Self.probe.lookupEnded(ObjectIdentifier(self))
    }
}

@Suite("Shorts sequence titles (PLAN-0052)", .serialized)
struct ShortsSequenceTitleTests {
    private let ids = ["m-1", "m-2", "m-3"]

    private func api(channel: ActiveChannel = ActiveChannel()) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OverlayURLProtocol.self]
        return InnerTubeAPI(
            authToken: "test-account", session: URLSession(configuration: config), activeChannel: channel)
    }

    @Test("Each Short of the page gets its title and channel, looked up like the sequence for the Brand Account")
    func fillsThePageWithTheAccount() async throws {
        OverlayURLProtocol.probe.reset()
        let channel = ActiveChannel()
        channel.set(pageId: "100000000000000000001")
        let page = try await api(channel: channel).fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)

        #expect(page.videos.map(\.id) == ids)
        #expect(page.videos.map(\.title) == ids.map { "Title \($0)" })
        #expect(page.videos.map(\.channelTitle) == ids.map { "@Channel \($0)" })
        #expect(page.videos.compactMap(\.channelId) == ids.map { "UC-\($0)" })
        #expect(page.nextPageToken == "reel:0/100000000000000000001:NEXT")

        let lookups = OverlayURLProtocol.probe.lookups
        let lookedUp = lookups.compactMap { ($0.1["playerRequest"] as? [String: Any])?["videoId"] as? String }
        #expect(lookedUp.sorted() == ids)
        for (request, body) in lookups {
            #expect(request.url?.host == "youtubei.googleapis.com")
            #expect(request.url?.query?.contains("key=") != true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
            #expect(request.value(forHTTPHeaderField: ActiveChannel.headerField) == "100000000000000000001")
            let client = (body["context"] as? [String: Any])?["client"] as? [String: Any]
            #expect(client?["clientName"] as? String == "TVHTML5")
            #expect(body["params"] as? String == "CAUwAg%3D%3D")
            #expect(body["disablePlayerResponse"] as? Bool == true)
        }
    }

    @Test("A failed lookup leaves its Short empty, in its place")
    func failedLookupKeepsTheShort() async throws {
        OverlayURLProtocol.probe.reset(failing: ["m-2"])
        let page = try await api().fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)
        #expect(page.videos.map(\.id) == ids)
        #expect(page.videos.map(\.title) == ["Title m-1", "", "Title m-3"])
        #expect(page.videos.map(\.channelTitle) == ["@Channel m-1", "", "@Channel m-3"])
        #expect(page.videos[1].channelId == nil)
    }

    @Test("Lookups that miss the shared deadline leave the Shorts empty and the page still arrives")
    func lateLookupsDoNotHoldThePage() async throws {
        OverlayURLProtocol.probe.reset(hanging: true)
        let page = try await api().fetchShortsFeed(
            seedVideoId: "seed", continuationToken: nil, metadataTimeout: .milliseconds(50))
        #expect(page.videos.map(\.id) == ids)
        #expect(page.videos.allSatisfy { $0.title.isEmpty && $0.channelTitle.isEmpty && $0.channelId == nil })
        #expect(page.nextPageToken == "reel:0/:NEXT")
    }

    @Test("Known fields stay, and a Short with both title and channel is not looked up")
    func knownFieldsStay() async throws {
        OverlayURLProtocol.probe.reset()
        let api = api()
        let partial = Video(id: "m-1", title: "Own title", channelTitle: "", channelId: "UCown", isShort: true)
        let known = Video(id: "m-2", title: "Known", channelTitle: "Known channel", isShort: true)
        let filled = await api.fillingShortsMetadata([partial, known], as: Self.account, until: Self.deadline)

        #expect(filled[0].title == "Own title")
        #expect(filled[0].channelTitle == "@Channel m-1")
        #expect(filled[0].channelId == "UCown")
        #expect(filled[1] == known)
        #expect(lookedUp() == ["m-1"])
    }

    @Test("A Short listed twice is looked up once, and both places get its title")
    func repeatedShortIsLookedUpOnce() async {
        OverlayURLProtocol.probe.reset()
        let api = api()
        let filled = await api.fillingShortsMetadata(
            [bare("m-1"), bare("m-2"), bare("m-1")], as: Self.account, until: Self.deadline)
        #expect(filled.map(\.title) == ["Title m-1", "Title m-2", "Title m-1"])
        #expect(lookedUp().sorted() == ["m-1", "m-2"])
    }

    // MARK: Identity

    @Test("A Brand Account switch while the sequence answer is pending: no lookup goes out, the page still arrives")
    func channelSwitchBeforeTheLookupsStopsThem() async throws {
        let channel = ActiveChannel()
        channel.set(pageId: "100000000000000000001")
        OverlayURLProtocol.probe.reset(onSequence: { channel.set(pageId: "200000000000000000002") })
        let page = try await api(channel: channel).fetchShortsFeed(seedVideoId: "seed", continuationToken: nil)

        #expect(page.videos.map(\.id) == ids)
        #expect(page.videos.allSatisfy { $0.title.isEmpty && $0.channelTitle.isEmpty })
        #expect(OverlayURLProtocol.probe.lookups.isEmpty)
        let sequence = try #require(OverlayURLProtocol.probe.requests(path: "/reel/reel_watch_sequence").first)
        #expect(sequence.0.value(forHTTPHeaderField: ActiveChannel.headerField) == "100000000000000000001")
    }

    @Test("Signed out or into another account after the sequence answer: no lookup goes out")
    func accountChangeBeforeTheLookupsStopsThem() async throws {
        OverlayURLProtocol.probe.reset()
        let api = api()
        let account = try #require(await api.shortsAccountSnapshot)
        await api.setAuthToken("another-account")
        let other = await api.fillingShortsMetadata([bare("m-1")], as: account, until: Self.deadline)
        await api.setAuthToken(nil)
        let signedOut = await api.fillingShortsMetadata([bare("m-1")], as: account, until: Self.deadline)
        #expect(other == [bare("m-1")])
        #expect(signedOut == [bare("m-1")])
        #expect(OverlayURLProtocol.probe.lookups.isEmpty)
    }

    @Test("Another Brand Account after the snapshot, then back before the answer: the whole page goes as the first")
    func switchAndBackKeepsThePageOnTheSnapshot() async throws {
        let channel = ActiveChannel()
        channel.set(pageId: Self.firstPage)
        let api = api(channel: channel)
        let account = try #require(await api.shortsAccountSnapshot)
        // A → B before the sequence request is formed, then B → A while its answer is pending.
        channel.set(pageId: Self.secondPage)
        OverlayURLProtocol.probe.reset(onSequence: { channel.set(pageId: Self.firstPage) })
        let page = try await api.fetchAccountShortsSequence(
            seedVideoId: "seed", continuation: nil, as: account, metadataTimeout: InnerTubeAPI.shortsMetadataTimeout)

        #expect(page.videos.map(\.title) == ids.map { "Title \($0)" })
        let sequence = try #require(OverlayURLProtocol.probe.requests(path: "/reel/reel_watch_sequence").first)
        #expect(sequence.0.value(forHTTPHeaderField: ActiveChannel.headerField) == Self.firstPage)
        let lookups = OverlayURLProtocol.probe.lookups
        #expect(lookups.count == ids.count)
        #expect(lookups.allSatisfy { $0.0.value(forHTTPHeaderField: ActiveChannel.headerField) == Self.firstPage })
    }

    @Test("A token refresh after the snapshot: the sequence still goes with the snapshot's token, no lookup goes out")
    func tokenChangeAfterTheSnapshot() async throws {
        OverlayURLProtocol.probe.reset()
        let api = api()
        let account = try #require(await api.shortsAccountSnapshot)
        await api.setAuthToken("refreshed-account")
        let page = try await api.fetchAccountShortsSequence(
            seedVideoId: "seed", continuation: nil, as: account, metadataTimeout: InnerTubeAPI.shortsMetadataTimeout)

        #expect(page.videos.map(\.id) == ids)
        let sequence = try #require(OverlayURLProtocol.probe.requests(path: "/reel/reel_watch_sequence").first)
        #expect(sequence.0.value(forHTTPHeaderField: "Authorization") == "Bearer test-account")
        #expect(OverlayURLProtocol.probe.lookups.isEmpty)
    }

    // MARK: Concurrency

    @Test("A large page runs at most the limit at once; the deadline cancels them, the queued never start")
    func largePageIsLimitedAndCancelledAtTheDeadline() async throws {
        OverlayURLProtocol.probe.reset(hanging: true)
        let api = api()
        let probe = OverlayURLProtocol.probe
        let limit = InnerTubeAPI.shortsMetadataConcurrency
        let page = (0..<(limit * 3)).map { bare("big-\($0)") }
        // The deadline comes once the first lookups all hang: a queued one could only start in a freed slot.
        let filled = await api.fillingShortsMetadata(
            page, as: Self.account,
            until: deadline {
                let giveUp = ContinuousClock.now + .seconds(5)
                while probe.inFlight < limit, ContinuousClock.now < giveUp, !Task.isCancelled { await Task.yield() }
            })

        #expect(filled == page)
        #expect(probe.maxInFlight == limit)
        #expect(probe.lookupsStarted == limit)
        try await eventually { probe.inFlight == 0 }  // Each running lookup was cancelled.
        #expect(probe.lookupsStarted == limit)
    }

    @Test("A slot freed after the deadline, before its timer wakes: the late title is dropped, no queued lookup starts")
    func slotFreedAfterTheDeadline() async throws {
        OverlayURLProtocol.probe.reset(holding: true)
        let api = api()
        let probe = OverlayURLProtocol.probe
        let limit = InnerTubeAPI.shortsMetadataConcurrency
        let page = (0...limit).map { bare("late-\($0)") }  // One more than the limit waits in the queue.
        let passed = OSAllocatedUnfairLock(initialState: false)
        // Once every slot is taken the deadline passes and one held answer frees its slot; the timer wakes only later.
        let lateTimer = ShortsMetadataDeadline(
            wait: {
                let giveUp = ContinuousClock.now + .seconds(5)
                while probe.inFlight < limit, ContinuousClock.now < giveUp { await Task.yield() }
                passed.withLock { $0 = true }
                probe.releaseOne()
                while ContinuousClock.now < giveUp, !Task.isCancelled { await Task.yield() }
            },
            hasPassed: { passed.withLock { $0 } })
        let filled = await api.fillingShortsMetadata(page, as: Self.account, until: lateTimer)

        #expect(filled == page)
        #expect(probe.lookupsStarted == limit)
        try await eventually { probe.inFlight == 0 }
        #expect(probe.lookupsStarted == limit)
    }

    @Test("A lookup queued before the deadline that would go out after it is not sent")
    func lookupQueuedBeforeTheDeadlineIsNotSentAfterIt() async throws {
        OverlayURLProtocol.probe.reset(holding: true)
        let api = api()
        let probe = OverlayURLProtocol.probe
        let limit = InnerTubeAPI.shortsMetadataConcurrency
        let page = (0...limit).map { bare("due-\($0)") }  // One more than the limit waits in the queue.
        // The first `limit` looks at the deadline come from the lookups before they send, the next from the loop
        // before it queues the waiting lookup once a slot is free. The deadline passes right after that look, so the
        // queued lookup's own look before sending finds it passed.
        let looks = OSAllocatedUnfairLock(initialState: 0)
        let deadline = ShortsMetadataDeadline(
            wait: {
                let giveUp = ContinuousClock.now + .seconds(5)
                while probe.inFlight < limit, ContinuousClock.now < giveUp { await Task.yield() }
                probe.releaseOne()  // A slot frees before the deadline: its title is kept.
                while ContinuousClock.now < giveUp, !Task.isCancelled { await Task.yield() }
            },
            hasPassed: {
                looks.withLock {
                    $0 += 1
                    return $0 > limit + 1
                }
            })
        let filled = await api.fillingShortsMetadata(page, as: Self.account, until: deadline)

        #expect(probe.lookupsStarted == limit)  // The queued lookup never went out.
        #expect(filled.filter { !$0.title.isEmpty }.count == 1)
        #expect(filled.last == page.last)
        try await eventually { probe.inFlight == 0 }
    }

    @Test("Lookups beyond the limit wait for a free slot and all answer within the deadline")
    func queuedLookupsAllAnswer() async {
        OverlayURLProtocol.probe.reset()
        let api = api()
        let page = (0..<(InnerTubeAPI.shortsMetadataConcurrency * 3)).map { bare("q-\($0)") }
        let filled = await api.fillingShortsMetadata(page, as: Self.account, until: Self.deadline)
        #expect(filled.map(\.title) == page.map { "Title \($0.id)" })
        #expect(OverlayURLProtocol.probe.lookupsStarted == page.count)
        #expect(OverlayURLProtocol.probe.maxInFlight <= InnerTubeAPI.shortsMetadataConcurrency)
    }

    // MARK: Helpers

    /// A fresh production deadline, which every lookup here answers well before.
    private static var deadline: ShortsMetadataDeadline { .after(InnerTubeAPI.shortsMetadataTimeout) }
    /// `api()`'s account with no Brand Account, as `shortsAccountSnapshot` reads it.
    private static let account = ShortsAccountSnapshot(token: "test-account", pageId: nil, signIn: 0)
    private static let firstPage = "100000000000000000001"
    private static let secondPage = "200000000000000000002"

    private func bare(_ id: String) -> Video { Video(id: id, title: "", channelTitle: "", isShort: true) }

    /// A deadline that passes once `comes` returns: its timer wakes then, and `hasPassed()` turns true.
    private func deadline(when comes: @escaping @Sendable () async -> Void) -> ShortsMetadataDeadline {
        let passed = OSAllocatedUnfairLock(initialState: false)
        return ShortsMetadataDeadline(
            wait: {
                await comes()
                passed.withLock { $0 = true }
            },
            hasPassed: { passed.withLock { $0 } })
    }

    private func lookedUp() -> [String] {
        OverlayURLProtocol.probe.lookups.compactMap { ($0.1["playerRequest"] as? [String: Any])?["videoId"] as? String }
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let giveUp = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < giveUp { await Task.yield() }
        try #require(condition())
    }
}
