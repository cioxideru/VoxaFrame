import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - LocalWatchHistoryStoreTests (#150)

@MainActor
@Suite("LocalWatchHistoryStore (#150)")
struct LocalWatchHistoryStoreTests {

    private struct StoreContext {
        let store: LocalWatchHistoryStore
        let defaults: UserDefaults
        let suite: String
    }

    private func makeStore() throws -> StoreContext {
        let suite = "LocalWatchHistoryStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return StoreContext(store: LocalWatchHistoryStore(defaults: defaults), defaults: defaults, suite: suite)
    }

    private func video(_ id: String) -> Video {
        Video(id: id, title: "Title \(id)", channelTitle: "Chan", channelId: "UC1")
    }

    @Test("records most recent first")
    func mostRecentFirst() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        context.store.record(video("a"), at: Date(timeIntervalSince1970: 1))
        context.store.record(video("b"), at: Date(timeIntervalSince1970: 2))
        #expect(context.store.videos.map(\.id) == ["b", "a"])
    }

    @Test("re-watching a video moves it to the front without duplicating")
    func dedupeMovesToFront() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        context.store.record(video("a"))
        context.store.record(video("b"))
        context.store.record(video("a"))
        #expect(context.store.videos.map(\.id) == ["a", "b"])
    }

    @Test("caps at maxEntries, evicting the oldest")
    func capsEntries() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        for index in 0..<(LocalWatchHistoryStore.maxEntries + 5) { context.store.record(video("v\(index)")) }
        #expect(context.store.entries.count == LocalWatchHistoryStore.maxEntries)
        #expect(context.store.videos.first?.id == "v\(LocalWatchHistoryStore.maxEntries + 4)")
        #expect(!context.store.videos.contains { $0.id == "v0" })
    }

    @Test("persists across instances sharing the same defaults")
    func persists() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        context.store.record(video("a"))
        let reloaded = LocalWatchHistoryStore(defaults: context.defaults)
        #expect(reloaded.videos.map(\.id) == ["a"])
    }

    @Test("clear removes everything, including from disk")
    func clearEmpties() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        context.store.record(video("a"))
        context.store.clear()
        #expect(context.store.videos.isEmpty)
        #expect(LocalWatchHistoryStore(defaults: context.defaults).videos.isEmpty)
    }

    @Test("stored entries keep display fields but drop per-fetch tokens")
    func slimsVideo() throws {
        let context = try makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        var storedVideo = video("a")
        storedVideo.notInterestedToken = "secret-token"
        context.store.record(storedVideo)
        #expect(context.store.videos.first?.title == "Title a")
        #expect(context.store.videos.first?.notInterestedToken == nil)
    }
}
