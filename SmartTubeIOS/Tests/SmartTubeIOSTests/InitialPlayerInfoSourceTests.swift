import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Initial metadata source parity (PLAN-0022)")
@MainActor
struct InitialPlayerInfoSourceTests {
    private enum Failure: Error, Equatable { case visionOS, legacy }

    private func info(_ id: String = "video", hls: Bool = true) -> PlayerInfo {
        PlayerInfo(
            video: Video(id: id, title: id, channelTitle: "Channel"),
            formats: [], hlsURL: hls ? URL(string: "https://example.com/\(id).m3u8") : nil,
            dashURL: nil, captionTracks: [], trackingURLs: nil, endCards: []
        )
    }

    @Test("Cache and coalesced responses bypass direct requests even without HLS", arguments: [true, false])
    func cachedAndCoalesced(useCache: Bool) async throws {
        let expected = info(hls: false)
        var calls: [String] = []
        let source = InitialPlayerInfoSource(
            inFlight: { id in
                calls.append("inFlight:\(id)")
                return Task { expected }
            },
            visionOS: { _ in
                Issue.record("Unexpected direct request")
                return expected
            },
            legacy: { _ in
                Issue.record("Unexpected fallback")
                return expected
            },
            store: { _, _ in Issue.record("Already cached response must not be stored again") }
        )
        let result = try await source.resolve(videoId: "video", cached: useCache ? expected : nil)
        #expect(result.info.video.id == "video")
        #expect(result.info.hlsURL == nil)
        #expect(result.origin == (useCache ? .cache : .inFlight))
        #expect(result.directVisionOSHLS == nil)
        #expect(calls == (useCache ? [] : ["inFlight:video"]))
    }

    @Test("Missing or empty in-flight request proceeds to VISIONOS and stores its HLS", arguments: [true, false])
    func directHLS(emptyTask: Bool) async throws {
        var calls: [String] = []
        let expected = info()
        let source = InitialPlayerInfoSource(
            inFlight: { id in
                calls.append("inFlight:\(id)")
                return emptyTask ? Task { nil } : nil
            },
            visionOS: { id in
                calls.append("visionOS:\(id)")
                return expected
            },
            legacy: { _ in
                Issue.record("Unexpected fallback")
                return expected
            },
            store: { value, id in
                calls.append("store:\(id)")
                #expect(value.hlsURL == expected.hlsURL)
            }
        )
        let result = try await source.resolve(videoId: "video", cached: nil)
        #expect(result.origin == .visionOS)
        #expect(result.directVisionOSHLS?.hlsURL == expected.hlsURL)
        #expect(calls == ["inFlight:video", "visionOS:video", "store:video"])
    }

    @Test("No HLS and direct errors enter the unchanged legacy path", arguments: [true, false])
    func fallback(noHLS: Bool) async throws {
        var calls: [String] = []
        let expected = info(hls: false)
        let source = InitialPlayerInfoSource(
            inFlight: { _ in
                calls.append("inFlight")
                return nil
            },
            visionOS: { _ in
                calls.append("visionOS")
                if noHLS { return expected }
                throw Failure.visionOS
            },
            legacy: { _ in
                calls.append("legacy")
                return expected
            },
            store: { _, _ in calls.append("store") }
        )
        let result = try await source.resolve(videoId: "video", cached: nil)
        #expect(result.origin == .legacy)
        #expect(result.directVisionOSHLS == nil)
        #expect(result.info.hlsURL == nil)
        #expect(calls == ["inFlight", "visionOS", "legacy", "store"])
    }

    @Test("Legacy errors propagate without storing a failed result")
    func legacyError() async {
        let source = InitialPlayerInfoSource(
            inFlight: { _ in nil },
            visionOS: { _ in throw Failure.visionOS },
            legacy: { _ in throw Failure.legacy },
            store: { _, _ in Issue.record("Failed metadata must not be stored") }
        )
        await #expect(throws: Failure.legacy) {
            try await source.resolve(videoId: "video", cached: nil)
        }
    }

    @Test("Cancellation after direct failure prevents legacy preparation")
    func cancellationBeforeFallback() async {
        let expected = info()
        let source = InitialPlayerInfoSource(
            inFlight: { _ in nil },
            visionOS: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            },
            legacy: { _ in
                Issue.record("Cancelled request must not enter legacy")
                return expected
            },
            store: { _, _ in Issue.record("No result to store") }
        )
        let consumer = Task { try await source.resolve(videoId: "video", cached: nil) }
        await #expect(throws: CancellationError.self) { try await consumer.value }
    }

    @Test("Cancelling one consumer leaves shared metadata available to other consumers")
    func sharedFetchSurvivesCancellation() async throws {
        let response = AsyncStream<PlayerInfo>.makeStream()
        let joined = AsyncStream<Void>.makeStream()
        let shared = Task<PlayerInfo?, Never> {
            for await value in response.stream { return value }
            return nil
        }
        let source = InitialPlayerInfoSource(
            inFlight: { _ in
                joined.continuation.yield(())
                return shared
            },
            visionOS: { _ in
                Issue.record("Unexpected direct request")
                throw Failure.visionOS
            },
            legacy: { _ in
                Issue.record("Unexpected fallback")
                throw Failure.legacy
            },
            store: { _, _ in Issue.record("Shared result is already owned by cache") }
        )
        let consumer = Task { try await source.resolve(videoId: "old-video", cached: nil) }
        var iterator = joined.stream.makeAsyncIterator()
        await iterator.next()
        consumer.cancel()
        response.continuation.yield(info("old-video"))
        response.continuation.finish()
        joined.continuation.finish()
        let result = try await consumer.value
        #expect(!shared.isCancelled)
        #expect(await shared.value?.video.id == "old-video")
        #expect(result.info.video.id == "old-video")
        #expect(result.origin == .inFlight)
        // Existing VM cancellation/identity guards reject this result before applying it.
    }

    @Test("Independent video requests retain their requested identity")
    func requestIdentity() async throws {
        let source = InitialPlayerInfoSource(
            inFlight: { _ in nil }, visionOS: { id in info(id) },
            legacy: { _ in throw Failure.legacy },
            store: { value, id in #expect(value.video.id == id) }
        )
        let first = try await source.resolve(videoId: "old-video", cached: nil)
        let second = try await source.resolve(videoId: "new-video", cached: nil)
        #expect(first.info.video.id == "old-video")
        #expect(second.info.video.id == "new-video")
    }
}
