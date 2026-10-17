import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Full-screen player gesture arbitration (PLAN-0024)")
struct PlayerPanGestureTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 600)

    @Test(arguments: [CGFloat(-30), 30])
    func slowVerticalDragUsesStartingHalf(_ dy: CGFloat) {
        for (x, level) in [(CGFloat(250), PlayerPanGesture.Level.brightness), (750, .volume)] {
            var drag = PlayerPanGesture(start: CGPoint(x: x, y: 300), bounds: bounds)
            #expect(
                drag.update(translation: CGPoint(x: 2, y: dy / 2), velocity: CGPoint(x: 5, y: dy * 4)) == .undecided)
            #expect(drag.update(translation: CGPoint(x: 2, y: dy), velocity: CGPoint(x: 5, y: dy * 4)) == .level(level))
            #expect(
                drag.update(translation: CGPoint(x: 800, y: dy), velocity: CGPoint(x: 2_000, y: 1_500)) == .level(level)
            )
        }
    }

    @Test func fastDownwardSwipeMinimizesWithoutBecomingALevelAdjustment() {
        var drag = PlayerPanGesture(start: CGPoint(x: 700, y: 200), bounds: bounds)
        #expect(drag.update(translation: CGPoint(x: 1, y: 20), velocity: CGPoint(x: 0, y: 500)) == .undecided)
        #expect(drag.update(translation: CGPoint(x: 1, y: 40), velocity: CGPoint(x: 0, y: 1_000)) == .minimize)
        #expect(drag.update(translation: CGPoint(x: 1, y: 200), velocity: .zero) == .minimize)
    }

    @Test func fastUpwardSwipeDoesNotChangeALevel() {
        var drag = PlayerPanGesture(start: CGPoint(x: 300, y: 300), bounds: bounds)
        #expect(drag.update(translation: CGPoint(x: 1, y: -20), velocity: CGPoint(x: 0, y: -500)) == .undecided)
        #expect(drag.update(translation: CGPoint(x: 1, y: -40), velocity: CGPoint(x: 0, y: -1_000)) == .ignored)
    }

    @Test func horizontalDragCannotTurnIntoMinimizeOrVolume() {
        var drag = PlayerPanGesture(start: CGPoint(x: 700, y: 300), bounds: bounds)
        #expect(drag.update(translation: CGPoint(x: -20, y: 1), velocity: CGPoint(x: -100, y: 0)) == .horizontal)
        #expect(drag.update(translation: CGPoint(x: -21, y: 300), velocity: CGPoint(x: 0, y: 1_000)) == .horizontal)
    }

    @Test func jitterAndAmbiguousDiagonalsWaitForIntent() {
        var drag = PlayerPanGesture(start: CGPoint(x: 250, y: 300), bounds: bounds)
        #expect(drag.update(translation: CGPoint(x: 3, y: 5), velocity: .zero) == .undecided)
        #expect(drag.update(translation: CGPoint(x: 20, y: 20), velocity: .zero) == .undecided)
        #expect(drag.update(translation: CGPoint(x: 20, y: 40), velocity: CGPoint(x: 0, y: 100)) == .undecided)
        #expect(drag.update(translation: CGPoint(x: 20, y: 45), velocity: CGPoint(x: 0, y: 100)) == .level(.brightness))
    }

    @Test(arguments: [CGPoint(x: 5, y: 300), CGPoint(x: 995, y: 300), CGPoint(x: 500, y: 5), CGPoint(x: 500, y: 595)])
    func systemEdgesAreReserved(_ start: CGPoint) {
        var drag = PlayerPanGesture(start: start, bounds: bounds)
        #expect(drag.update(translation: CGPoint(x: 0, y: 80), velocity: CGPoint(x: 0, y: 200)) == .ignored)
    }

    @Test func adjustmentIsRelativeClampedAndIndependentOfWindowHeight() {
        #expect(PlayerPanGesture.adjustedLevel(initial: 0.4, translationY: -180, height: 600) == 0.9)
        #expect(PlayerPanGesture.adjustedLevel(initial: 0.4, translationY: -90, height: 300) == 0.9)
        #expect(PlayerPanGesture.adjustedLevel(initial: 0.4, translationY: -900, height: 600) == 1)
        #expect(PlayerPanGesture.adjustedLevel(initial: 0.4, translationY: 900, height: 600) == 0)
        #expect(PlayerPanGesture.adjustedLevel(initial: 0.4, translationY: 100, height: 0) == 0.4)
    }

    @Test func catalystKeepsItsPreviousDownwardGesture() {
        var drag = PlayerPanGesture(start: CGPoint(x: 250, y: 300), bounds: bounds, allowsLevels: false)
        #expect(drag.update(translation: CGPoint(x: 0, y: 60), velocity: CGPoint(x: 0, y: 100)) == .minimize)
    }
}
