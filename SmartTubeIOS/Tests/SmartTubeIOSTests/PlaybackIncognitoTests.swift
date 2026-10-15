import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - PlaybackIncognitoTests (#94)
//
// "Play Incognito" must not record the video to on-device history, and the flag
// applies only to the load that requested it.

@Suite("Playback incognito (#94)")
@MainActor
struct PlaybackIncognitoTests {
    private func makeVM() throws -> PlaybackViewModel {
        let vm = PlaybackViewModel()
        vm.settings.historyState = .enabled
        vm.localHistory = LocalWatchHistoryStore(
            defaults: try #require(UserDefaults(suiteName: "incognito-\(UUID().uuidString)")))
        return vm
    }

    @Test("Incognito load is not recorded to local history")
    func incognitoSkipsHistory() throws {
        let vm = try makeVM()
        vm.resetPlaybackForLoad(video: Video(id: "secret", title: "S", channelTitle: "C"), incognito: true)
        #expect(vm.isIncognito)
        #expect(!vm.recordsHistory)
        #expect(vm.localHistory.videos.isEmpty)
    }

    @Test("A normal load after an incognito one records again")
    func normalLoadRevertsIncognito() throws {
        let vm = try makeVM()
        vm.resetPlaybackForLoad(video: Video(id: "secret", title: "S", channelTitle: "C"), incognito: true)
        vm.resetPlaybackForLoad(video: Video(id: "next", title: "N", channelTitle: "C"), incognito: false)
        #expect(!vm.isIncognito)
        #expect(vm.recordsHistory)
        #expect(vm.localHistory.videos.map(\.id) == ["next"])
    }
}
