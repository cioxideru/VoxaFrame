import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchHistoryMergeTests (PLAN-0053)

@Suite("WatchHistoryMerge")
struct WatchHistoryMergeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ id: String, minutesAgo: Double) -> LocalWatchHistoryEntry {
        LocalWatchHistoryEntry(video: makeVideo(id), watchedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func merge(_ local: [LocalWatchHistoryEntry], _ remote: [String]) -> [String] {
        WatchHistoryMerge.merge(local: local, remote: remote.map(makeVideo), now: now).map(\.id)
    }

    @Test("Without account history the on-device history is shown as recorded")
    func localOnly() {
        #expect(merge([entry("a", minutesAgo: 1), entry("b", minutesAgo: 600)], []) == ["a", "b"])
    }

    @Test("A video watched in another app leads the list, above older on-device watches")
    func accountOrderLeads() {
        let local = [entry("vf1", minutesAgo: 120), entry("vf2", minutesAgo: 300)]
        #expect(merge(local, ["yt", "vf1", "vf2"]) == ["yt", "vf1", "vf2"])
    }

    @Test("A recent on-device watch the account does not list yet stays at the top")
    func recentUnsyncedOnTop() {
        let local = [entry("new", minutesAgo: 2), entry("vf1", minutesAgo: 120)]
        #expect(merge(local, ["yt", "vf1"]) == ["new", "yt", "vf1"])
    }

    @Test("An older unlisted watch newer than the first anchor goes right before it")
    func olderUnsyncedBeforeFirstAnchor() {
        let local = [entry("old", minutesAgo: 90), entry("vf1", minutesAgo: 120)]
        #expect(merge(local, ["yt", "vf1", "yt2"]) == ["yt", "old", "vf1", "yt2"])
    }

    @Test("An unlisted watch between two anchors goes right after the newer one")
    func betweenAnchors() {
        let local = [entry("vf1", minutesAgo: 120), entry("mid", minutesAgo: 130), entry("vf2", minutesAgo: 140)]
        #expect(merge(local, ["vf1", "yt", "vf2"]) == ["vf1", "mid", "yt", "vf2"])
    }

    @Test("Unlisted watches older than the last anchor follow the account page")
    func trailingAfterPage() {
        let local = [entry("vf1", minutesAgo: 120), entry("old1", minutesAgo: 900), entry("old2", minutesAgo: 1000)]
        #expect(merge(local, ["vf1", "yt1", "yt2"]) == ["vf1", "yt1", "yt2", "old1", "old2"])
    }

    @Test("With no anchor, only recent on-device watches go above the account page")
    func noAnchor() {
        let local = [entry("new", minutesAgo: 5), entry("old", minutesAgo: 600)]
        #expect(merge(local, ["yt1", "yt2"]) == ["new", "yt1", "yt2", "old"])
    }

    @Test("A video listed twice by the account appears once")
    func duplicatesDropped() {
        #expect(merge([entry("vf1", minutesAgo: 120)], ["vf1", "yt", "vf1"]) == ["vf1", "yt"])
    }
}

// MARK: - History refresh (PLAN-0053)

@Suite("BrowseViewModel history refresh")
@MainActor
struct BrowseViewModelHistoryRefreshTests {
    @Test(
        "Returning to the shown History or the app refreshes its top and keeps the loaded pages",
        arguments: [false, true])
    func historyRefreshKeepsLoadedPages(foreground: Bool) async throws {
        let mock = MockInnerTubeAPI()
        let local = LocalWatchHistoryStore(defaults: try #require(UserDefaults(suiteName: "hist-\(UUID().uuidString)")))
        let section = BrowseSection(id: "history", title: "History", type: .history)
        let vm = BrowseViewModel(api: mock, localHistory: local)
        await vm.updateAuthToken("token", reloadOnSignIn: false)
        mock.historyHandler = { token in
            token == nil
                ? VideoGroup(title: "History", videos: [makeVideo("p1")], nextPageToken: "page2")
                : VideoGroup(title: "History", videos: [makeVideo("p2")], nextPageToken: "page3")
        }
        vm.select(section: section)
        await waitForTasks { !vm.isLoading && vm.videoGroups.first?.videos.count == 1 }
        vm.loadMoreIfNeeded(lastVideo: makeVideo("p1"))
        await waitForTasks { !vm.isLoadingMore && vm.videoGroups.first?.videos.count == 2 }

        // A video watched in the official app meanwhile.
        mock.historyHandler = { _ in
            VideoGroup(title: "History", videos: [makeVideo("yt"), makeVideo("p1")], nextPageToken: "page2")
        }
        if foreground { vm.refreshIfStale() } else { vm.select(section: section) }
        await waitForTasks { !vm.isLoading && vm.videoGroups.first?.videos.first?.id == "yt" }

        #expect(vm.videoGroups.first?.videos.map(\.id) == ["yt", "p1", "p2"])
        #expect(vm.videoGroups.first?.nextPageToken == "page3")
        #expect(mock.calls.filter { $0.method == "fetchHistory" }.count == 3)
    }
}
