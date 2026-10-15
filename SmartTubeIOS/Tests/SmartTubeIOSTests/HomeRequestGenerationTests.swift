import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Deliberately ignores cancellation so tests can release obsolete network results.
@MainActor
private final class HomeResponseGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?
    private(set) var started = false

    func value() async -> Value {
        started = true
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: Value) {
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Suite("Home request generations")
@MainActor
struct HomeRequestGenerationTests {
    @Test("An obsolete full load cannot finish a replacement refresh", arguments: [false, true])
    func obsoleteFullLoad(shortsPending: Bool) async {
        let mock = MockInnerTubeAPI()
        let oldHome = HomeResponseGate<[VideoGroup]>()
        let oldShorts = HomeResponseGate<VideoGroup>()
        let freshHome = HomeResponseGate<[VideoGroup]>()
        let freshShorts = HomeResponseGate<VideoGroup>()
        let initialHome = [VideoGroup(title: "Old", videos: [makeVideo("old")])]
        let initialShorts = VideoGroup(title: "Old", videos: [short("old-short")])
        mock.homeRowsHandler = { _ in await oldHome.value() }
        mock.shortsHandler = { await oldShorts.value() }
        let vm = HomeViewModel(api: mock)
        defer { vm.cancel() }
        let oldLoad = Task { await vm.refresh() }
        await waitForTasks { oldHome.started && oldShorts.started }
        if shortsPending {
            oldHome.resolve(initialHome)
            await waitForTasks { !vm.isLoadingAny }
        }

        mock.homeRowsHandler = { _ in await freshHome.value() }
        mock.shortsHandler = { await freshShorts.value() }
        let replacement = Task { await vm.refresh() }
        await waitForTasks { freshHome.started && freshShorts.started }
        let generation = vm.feedGeneration
        let feed = vm.mergedVideos
        oldHome.resolve(initialHome)
        oldShorts.resolve(initialShorts)
        await oldLoad.value

        #expect(vm.isRefreshing)
        #expect(vm.loadedAt == nil)
        #expect(vm.feedGeneration == generation)
        #expect(vm.mergedVideos == feed)
        #expect(vm.shortsVideos.isEmpty)

        freshHome.resolve([VideoGroup(title: "Fresh", videos: [makeVideo("fresh")])])
        freshShorts.resolve(VideoGroup(title: "Fresh", videos: [short("fresh-short")]))
        await replacement.value
        #expect(vm.mergedVideos.map(\.id) == ["fresh"])
        #expect(vm.shortsVideos.map(\.id) == ["fresh-short"])
        #expect(!vm.isRefreshing)
    }

    private func short(_ id: String) -> Video {
        Video(id: id, title: id, channelTitle: "Channel", isShort: true)
    }
}
