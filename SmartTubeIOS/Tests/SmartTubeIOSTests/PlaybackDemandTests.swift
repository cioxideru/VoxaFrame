import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
private final class DemandGate {
    var waits: [CheckedContinuation<Void, Never>] = []
    var completed = 0
    func wait() async {
        await withCheckedContinuation { waits.append($0) }
        completed += 1
    }
    func fire() { waits.removeFirst().resume() }
    func drain() { while !waits.isEmpty { fire() } }
}

private final class DemandPlayer: AVPlayer {
    private let lock = NSLock()
    private var storedTransport: AVPlayer.TimeControlStatus = .paused
    var transport: AVPlayer.TimeControlStatus {
        get { lock.withLock { storedTransport } }
        set { lock.withLock { storedTransport = newValue } }
    }
    override var timeControlStatus: AVPlayer.TimeControlStatus { transport }
}

@Suite("Playback demand (PLAN-0020)")
@MainActor
struct PlaybackDemandTests {
    private func eventually(
        sourceLocation: SourceLocation = #_sourceLocation, _ predicate: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(predicate(), sourceLocation: sourceLocation)
    }

    @Test func intentionalPauseReleasesStartupAndResumeReacquiresIt() async throws {
        let recovery = DemandGate()
        let budget = DemandGate()
        let demand = PlaybackDemandCoordinator(
            waitForRecovery: { await recovery.wait() }, waitForBudget: { await budget.wait() })
        let adapter = PlaybackDemandAdapter(coordinator: demand)
        let player = DemandPlayer()
        adapter.update(player: player, videoID: "startup", isLoading: true, isEnabled: true)
        player.transport = .waitingToPlayAtSpecifiedRate
        adapter.update(player: player, videoID: "startup", isLoading: false, isEnabled: true)
        #expect(demand.isYielding)
        // Translation/stream preparation may pause before the first frame without a user pause.
        player.transport = .paused
        adapter.update(player: player, videoID: "startup", isLoading: false, isEnabled: true)
        #expect(demand.isYielding)
        adapter.pause()
        player.transport = .waitingToPlayAtSpecifiedRate
        adapter.update(player: player, videoID: "startup", isLoading: true, isEnabled: true)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
        adapter.update(player: player, videoID: "startup", isLoading: false, isEnabled: true)
        #expect(!demand.isYielding)
        adapter.resume()
        adapter.update(player: player, videoID: "startup", isLoading: false, isEnabled: true)
        #expect(demand.isYielding)
        #expect(budget.waits.isEmpty)
        adapter.stop()
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
    }

    @Test(arguments: [
        "toggle", "pendingToggle", "background", "suspend", "outputLost", "voiceOver", "backgroundEnabled",
    ])
    func viewModelDistinguishesIntentionalAndTechnicalPauses(path: String) {
        var settings = AppSettings()
        settings.backgroundPlaybackEnabled = path == "backgroundEnabled"
        let vm = PlaybackViewModel(settings: settings)
        vm.isIncognito = true
        vm.beginPlaybackAudioSession()
        vm.currentVideo = Video(id: "startup", title: "Fixture", channelTitle: "Test")
        vm.isLoading = true
        vm.isPlaying = true
        switch path {
        case "toggle": vm.togglePlayPause()
        case "pendingToggle":
            vm.isPlaying = false
            vm.audioPlaybackTask = Task {}
            vm.togglePlayPause()
        case "background", "backgroundEnabled": vm.handleBackground()
        case "suspend": vm.suspend()
        case "outputLost": vm.handleAudioOutputLost()
        default: vm.setPlayingForVoiceOver(false)
        }
        #expect(vm.playbackDemand.isPaused == (path != "voiceOver" && path != "backgroundEnabled"))
        vm.beginPlaybackAudioSession()
        #expect(!vm.playbackDemand.isPaused)
        vm.stop()
    }

    @Test func startupWaitsForActualPlaybackThenRecoversWithoutFlapping() async throws {
        let recovery = DemandGate()
        let budget = DemandGate()
        let demand = PlaybackDemandCoordinator(
            waitForRecovery: { await recovery.wait() }, waitForBudget: { await budget.wait() })
        let owner = UUID()
        demand.update(owner: owner, phase: .preparing)
        var changes = demand.changes().makeAsyncIterator()
        #expect(await changes.next() == true)
        #expect(budget.waits.isEmpty)
        demand.update(owner: owner, phase: .playing)
        try await eventually { recovery.waits.count == 1 }
        demand.update(owner: owner, phase: .buffering)
        recovery.fire()
        try await eventually { budget.waits.count == 1 }
        #expect(demand.isYielding)
        demand.update(owner: owner, phase: .playing)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
        #expect(await changes.next() == false)
        budget.drain()
    }

    @Test func prolongedBufferingReleasesOnceAndCannotStarveOptionalWork() async throws {
        let recovery = DemandGate()
        let budget = DemandGate()
        let demand = PlaybackDemandCoordinator(
            waitForRecovery: { await recovery.wait() }, waitForBudget: { await budget.wait() })
        let owner = UUID()
        demand.update(owner: owner, phase: .buffering)
        try await eventually { budget.waits.count == 1 }
        budget.fire()
        try await eventually { !demand.isYielding }
        for _ in 0..<100 { demand.update(owner: owner, phase: .buffering) }
        #expect(!demand.isYielding)
        #expect(budget.waits.isEmpty)
        demand.update(owner: owner, phase: .playing)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { recovery.completed == 1 }
        demand.update(owner: owner, phase: .buffering)
        try await eventually { budget.waits.count == 1 }
        #expect(demand.isYielding)
        demand.remove(owner: owner)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        budget.drain()
    }

    @Test func ownerRemovalDoesNotReleaseAnotherStartup() async throws {
        let recovery = DemandGate()
        let budget = DemandGate()
        let demand = PlaybackDemandCoordinator(
            waitForRecovery: { await recovery.wait() }, waitForBudget: { await budget.wait() })
        let regular = UUID()
        let shorts = UUID()
        demand.update(owner: regular, phase: .preparing)
        demand.update(owner: shorts, phase: .preparing)
        demand.remove(owner: regular)
        #expect(demand.isYielding)
        #expect(recovery.waits.isEmpty)
        demand.remove(owner: shorts)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
        #expect(budget.waits.isEmpty)
    }

    @Test(arguments: ["first", "second"])
    func adapterKeepsReadyButNotPlayingUrgentAndHandlesReplacementAndStop(replacementID: String) async throws {
        let recovery = DemandGate()
        let budget = DemandGate()
        let demand = PlaybackDemandCoordinator(
            waitForRecovery: { await recovery.wait() }, waitForBudget: { await budget.wait() })
        var adapter: PlaybackDemandAdapter? = PlaybackDemandAdapter(coordinator: demand)
        let player = DemandPlayer()
        adapter?.update(player: player, videoID: "first", isLoading: true, isEnabled: true)
        adapter?.update(player: player, videoID: "first", isLoading: false, isEnabled: true)
        #expect(demand.isYielding)
        #expect(recovery.waits.isEmpty)
        #expect(budget.waits.isEmpty)
        player.transport = .playing
        adapter?.update(player: player, videoID: "first", isLoading: false, isEnabled: true)
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
        player.transport = .waitingToPlayAtSpecifiedRate
        adapter?.update(player: player, videoID: "first", isLoading: false, isEnabled: true)
        try await eventually { budget.waits.count == 1 }
        let replacement = DemandPlayer()
        adapter?.stop()
        try await eventually { recovery.waits.count == 1 }
        adapter?.update(player: replacement, videoID: replacementID, isLoading: true, isEnabled: true)
        // The fake deliberately ignores cancellation; deliver the old timer before stopping again.
        recovery.fire()
        budget.fire()
        try await eventually { recovery.completed == 2 }
        #expect(demand.isYielding)
        adapter?.stop()
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
        adapter?.update(player: replacement, videoID: "third", isLoading: true, isEnabled: true)
        adapter = nil
        try await eventually { recovery.waits.count == 1 }
        recovery.fire()
        try await eventually { !demand.isYielding }
    }
}
