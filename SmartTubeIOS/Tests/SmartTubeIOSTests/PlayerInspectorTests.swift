import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - Comments follow the playing video (PLAN-0027 stage 2b)

/// The video comment model; `Testing` has its own `Comment`.
private typealias VideoComment = SmartTubeIOSCore.Comment

/// Fake at `CommentsController`'s fetch seam. Each call waits until the test answers or fails it,
/// addressed by call number, so two requests for the same video are told apart.
@MainActor
private final class CommentsFetchGate {
    struct FetchFailed: Error {}

    /// Video IDs in call order; a call is addressed by its index here.
    private(set) var requests: [String] = []
    /// Calls whose result has been handed back to the controller.
    private(set) var returned: [Int] = []
    private var pending: [Int: CheckedContinuation<[VideoComment], any Error>] = [:]

    func fetch(_ videoId: String) async throws -> [VideoComment] {
        let call = requests.count
        requests.append(videoId)
        defer { returned.append(call) }
        return try await withCheckedThrowingContinuation { pending[call] = $0 }
    }

    func isPending(_ call: Int) -> Bool { pending[call] != nil }

    /// Answers `call` with one comment whose `id` is `c-<call>` and whose text is the video ID.
    func answer(_ call: Int) {
        let comment = VideoComment(
            id: "c-\(call)", author: "Author", authorAvatarURL: nil, text: requests[call],
            likeCount: "", publishedTime: "", isLiked: false)
        pending.removeValue(forKey: call)?.resume(returning: [comment])
    }

    func fail(_ call: Int) {
        pending.removeValue(forKey: call)?.resume(throwing: FetchFailed())
    }
}

@Suite("Comments controller")
@MainActor
struct CommentsControllerTests {
    private func eventually(
        sourceLocation: SourceLocation = #_sourceLocation, _ predicate: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(predicate(), sourceLocation: sourceLocation)
    }

    @Test func nextVideoLoadsItsOwnComments() async throws {
        let gate = CommentsFetchGate()
        let controller = CommentsController(fetch: { try await gate.fetch($0) })

        controller.load(videoId: "A")
        try await eventually { gate.isPending(0) }
        gate.answer(0)
        try await eventually { !controller.isLoading }
        #expect(controller.comments.map(\.text) == ["A"])

        controller.load(videoId: "A")  // already loaded: no second request
        controller.load(videoId: "B")
        #expect(controller.comments.isEmpty)
        #expect(controller.isLoading)
        try await eventually { gate.isPending(1) }
        gate.answer(1)
        try await eventually { !controller.isLoading }
        #expect(controller.comments.map(\.text) == ["B"])
        #expect(gate.requests == ["A", "B"])
    }

    @Test func lateResponseForThePreviousVideoIsDropped() async throws {
        let gate = CommentsFetchGate()
        let controller = CommentsController(fetch: { try await gate.fetch($0) })

        controller.load(videoId: "A")
        try await eventually { gate.isPending(0) }
        controller.load(videoId: "B")
        try await eventually { gate.isPending(1) }

        gate.answer(0)
        try await eventually { gate.returned == [0] }
        #expect(controller.comments.isEmpty)
        #expect(controller.isLoading)
        #expect(controller.videoId == "B")

        gate.answer(1)
        try await eventually { !controller.isLoading }
        #expect(controller.comments.map(\.text) == ["B"])
    }

    /// A → B → A: only the second A request may change the state, even though the first one is for the same video.
    @Test func olderRequestForTheSameVideoNeverOverridesTheLatest() async throws {
        let gate = CommentsFetchGate()
        let controller = CommentsController(fetch: { try await gate.fetch($0) })

        controller.load(videoId: "A")
        try await eventually { gate.isPending(0) }
        controller.load(videoId: "B")
        try await eventually { gate.isPending(1) }
        controller.load(videoId: "A")
        try await eventually { gate.isPending(2) }
        #expect(gate.requests == ["A", "B", "A"])

        // A stale B answer while the latest A is pending leaves it loading.
        gate.answer(1)
        try await eventually { gate.returned == [1] }
        #expect(controller.isLoading)
        #expect(controller.comments.isEmpty)

        gate.answer(2)
        try await eventually { !controller.isLoading }
        #expect(controller.comments.map(\.id) == ["c-2"])

        // The first A request fails after the second one succeeded: nothing changes.
        gate.fail(0)
        try await eventually { gate.returned == [1, 2, 0] }
        #expect(!controller.isLoading)
        #expect(controller.comments.map(\.id) == ["c-2"])
        #expect(controller.videoId == "A")
    }
}

// MARK: - Up next follows the queue position

#if os(macOS)
@Suite("Mac inspector Up next")
struct UpNextSourceTests {
    private let videoA = Video(id: "aaa11111111", title: "A", channelTitle: "")
    private let videoB = Video(id: "bbb22222222", title: "B", channelTitle: "")

    @Test func consecutiveDuplicatesFollowPlayNext() async throws {
        let store = CurrentQueueStore(suiteName: "test-\(UUID().uuidString)")
        await store.replaceAll(with: [videoA, videoA, videoB])
        let first = try #require(await store.videoAt(index: 0))
        let second = try #require(await store.videoAt(index: 1))

        #expect(UpNextSource(first) != UpNextSource(second))
        #expect(await UpNextSource(first).remainingQueue(in: store).map(\.playlistIndex) == [1, 2])
        #expect(await UpNextSource(second).remainingQueue(in: store).map(\.id) == [videoB.id])
    }

    @Test func videoOutsideTheQueueOffersNoQueueItems() async {
        let store = CurrentQueueStore(suiteName: "test-\(UUID().uuidString)")
        await store.replaceAll(with: [videoA, videoB])
        var playlistVideo = videoA
        playlistVideo.playlistId = "PL123"
        playlistVideo.playlistIndex = 0

        #expect(UpNextSource(playlistVideo).queueIndex == nil)
        #expect(await UpNextSource(playlistVideo).remainingQueue(in: store).isEmpty)
    }
}
#endif
