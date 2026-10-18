import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Shorts End-of-Video Decision")
struct ShortsEndOfVideoDecisionTests {

    @Test("Loop enabled → replay, even at the last index")
    func loopEnabledReplaysEvenAtEnd() {
        var settings = AppSettings()
        settings.loopEnabled = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 2, count: 3)
        #expect(result == .replay)
    }

    @Test("Loop disabled, not at the end → advance to next index")
    func advancesToNextIndex() {
        var settings = AppSettings()
        settings.loopEnabled = false
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 3)
        #expect(result == .advance(to: 1))
    }

    @Test("Loop disabled, at the last index → freeze")
    func freezesAtLastIndex() {
        var settings = AppSettings()
        settings.loopEnabled = false
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 2, count: 3)
        #expect(result == .freeze)
    }

    @Test("Single-video list, loop disabled → freeze")
    func singleVideoFreezesWithoutLoop() {
        var settings = AppSettings()
        settings.loopEnabled = false
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 1)
        #expect(result == .freeze)
    }

    @Test("Single-video list, loop enabled → replay")
    func singleVideoReplaysWithLoop() {
        var settings = AppSettings()
        settings.loopEnabled = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 1)
        #expect(result == .replay)
    }

    @Test("A panel is open → freeze instead of advancing, so the panel is not closed by the next Short")
    func openPanelFreezesInsteadOfAdvancing() {
        var settings = AppSettings()
        settings.loopEnabled = false
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 3, isPanelOpen: true)
        #expect(result == .freeze)
    }

    @Test("A panel is open, loop enabled → still replay; the Short stays")
    func openPanelStillReplaysWithLoop() {
        var settings = AppSettings()
        settings.loopEnabled = true
        let result = ShortsEndOfVideoDecision.decide(settings: settings, currentIndex: 0, count: 3, isPanelOpen: true)
        #expect(result == .replay)
    }
}
