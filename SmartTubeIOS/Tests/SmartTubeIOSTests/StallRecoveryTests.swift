import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS

// Stall counters must restart per item and after the rapid-stall window, otherwise
// recovery is capped for the rest of the session.
@Suite("Stall recovery counters")
@MainActor
struct StallRecoveryTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func makeItem() -> AVPlayerItem {
        AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
    }

    @Test("Stalls on the same item accumulate inside the window")
    func sameItemAccumulates() {
        let vm = PlaybackViewModel()
        let item = makeItem()
        vm.registerStall(on: item, now: t0)
        vm.registerStall(on: item, now: t0.addingTimeInterval(5))
        vm.registerStall(on: item, now: t0.addingTimeInterval(10))
        #expect(vm.stallCount == 3)
        #expect(vm.firstRapidStallTime == t0)
    }

    @Test("A new item starts a new stall sequence")
    func newItemResets() {
        let vm = PlaybackViewModel()
        let first = makeItem()
        let second = makeItem()
        vm.registerStall(on: first, now: t0)
        vm.registerStall(on: first, now: t0.addingTimeInterval(1))
        vm.registerStall(on: second, now: t0.addingTimeInterval(2))
        #expect(vm.stallCount == 1)
        #expect(vm.firstRapidStallTime == t0.addingTimeInterval(2))
    }

    @Test("A stall after the rapid window starts a new sequence")
    func windowExpiryResets() {
        let vm = PlaybackViewModel()
        let item = makeItem()
        vm.registerStall(on: item, now: t0)
        vm.registerStall(on: item, now: t0.addingTimeInterval(1))
        let later = t0.addingTimeInterval(PlaybackTuning.rapidStallWindow + 1)
        vm.registerStall(on: item, now: later)
        #expect(vm.stallCount == 1)
        #expect(vm.firstRapidStallTime == later)
    }
}
