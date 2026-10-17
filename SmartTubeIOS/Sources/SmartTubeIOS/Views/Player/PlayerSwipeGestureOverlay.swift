import SwiftUI

// MARK: - Full-screen player gesture surface

#if os(iOS)
import UIKit
/// Left swipe → `onSwipeLeft`, right swipe → `onSwipeRight`, tap → `onTap`.
/// Set `isEnabled = false` (e.g. while the progress slider is being scrubbed) to
/// temporarily suppress pan recognition so the scrub drag is not mistaken for a swipe.
/// Background controls let this single surface arbitrate taps, navigation and level drags.
struct PlayerSwipeGestureOverlay: UIViewRepresentable {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var onTap: () -> Void
    var onDoubleTap: (CGFloat) -> Void = { _ in }
    var onTwoFingerTap: () -> Void = {}
    var onPanChanged: ((CGFloat) -> Void)?
    var onSwipeCancelled: (() -> Void)?
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?
    var onSwipeDown: (() -> Void)?
    var onLevelChanged: (PlayerPanGesture.Level, CGFloat?) -> Void = { _, _ in }
    var onLevelEnded: () -> Void = {}
    var isActive = true
    var isEnabled: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        #if !targetEnvironment(macCatalyst)
        view.addSubview(context.coordinator.levels.volumeView)
        #endif

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.require(toFail: pan)
        view.addGestureRecognizer(doubleTap)
        context.coordinator.doubleTap = doubleTap

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.require(toFail: pan)
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)
        context.coordinator.tap = tap

        let twoFingerTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = false
        view.addGestureRecognizer(twoFingerTap)
        context.coordinator.twoFingerTap = twoFingerTap
        tap.require(toFail: twoFingerTap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowableMovement = PlayerPanGesture.activationDistance
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        context.coordinator.longPress = longPress

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if !isActive { context.coordinator.levels.restoreBrightness() }
        context.coordinator.twoFingerTap?.isEnabled = isEnabled && isActive
        context.coordinator.pan?.isEnabled = isEnabled && isActive
        context.coordinator.tap?.isEnabled = isEnabled && isActive
        context.coordinator.doubleTap?.isEnabled = isEnabled && isActive
        context.coordinator.longPress?.isEnabled = isEnabled && isActive
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.levels.restoreBrightness()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerSwipeGestureOverlay
        weak var pan: UIPanGestureRecognizer?
        weak var tap: UITapGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?
        weak var longPress: UILongPressGestureRecognizer?
        weak var twoFingerTap: UITapGestureRecognizer?
        let levels = PlayerSystemLevels()
        private var drag: PlayerPanGesture?
        private var initialLevel: CGFloat?

        init(_ parent: PlayerSwipeGestureOverlay) {
            self.parent = parent
            super.init()
            // The custom full-screen hosting controller does not inherit SwiftUI's scene phase.
            NotificationCenter.default.addObserver(
                self, selector: #selector(deactivateScene(_:)), name: UIScene.willDeactivateNotification, object: nil)
        }

        @objc private func deactivateScene(_ notification: Notification) {
            guard let scene = notification.object as? UIWindowScene, scene === pan?.view?.window?.windowScene else {
                return
            }
            levels.restoreBrightness()
            finishPan()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let pan, let view = pan.view else { return true }
            let translation = pan.translation(in: view)
            let location = pan.location(in: view)
            let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            return view.window?.windowScene?.activationState == .foregroundActive
                && !UIAccessibility.isVoiceOverRunning
                && view.bounds.insetBy(
                    dx: PlayerPanGesture.systemEdgeInset, dy: PlayerPanGesture.systemEdgeInset
                ).contains(start)
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view = gr.view else { return }
            let translation = gr.translation(in: view)
            if gr.state == .began {
                let point = gr.location(in: view)
                drag = PlayerPanGesture(
                    start: CGPoint(x: point.x - translation.x, y: point.y - translation.y), bounds: view.bounds,
                    allowsLevels: UIDevice.current.userInterfaceIdiom != .mac)
                #if targetEnvironment(macCatalyst)
                // Catalyst can report the iPad idiom as well as the Mac idiom.
                drag?.allowsLevels = false
                #endif
                initialLevel = nil
            }
            guard var drag else { return }
            if gr.state == .cancelled || gr.state == .failed || drag.bounds != view.bounds {
                finishPan()
                return
            }
            let previousIntent = drag.intent
            let intent = drag.update(translation: translation, velocity: gr.velocity(in: view))
            self.drag = drag
            switch intent {
            case .horizontal:
                if gr.state == .ended {
                    guard abs(translation.x) > PlayerPanGesture.navigationDistance else {
                        finishPan()
                        return
                    }
                    if translation.x < 0 { parent.onSwipeLeft() } else { parent.onSwipeRight() }
                } else {
                    parent.onPanChanged?(translation.x)
                }
            case .minimize:
                if gr.state == .ended, translation.y > PlayerPanGesture.navigationDistance {
                    parent.onSwipeDown?()
                }
            case .level(let level):
                if previousIntent == .undecided { initialLevel = levels.value(for: level, in: view) }
                let value = initialLevel.flatMap {
                    levels.set(
                        PlayerPanGesture.adjustedLevel(
                            initial: $0, translationY: translation.y, height: drag.bounds.height), for: level)
                }
                parent.onLevelChanged(level, value)
            case .undecided, .ignored:
                break
            }
            if gr.state == .ended { finishPan(resetOffset: intent != .horizontal) }
        }

        private func finishPan(resetOffset: Bool = true) {
            if case .level = drag?.intent { parent.onLevelEnded() }
            if resetOffset { parent.onSwipeCancelled?() }
            drag = nil
            initialLevel = nil
        }

        @MainActor @objc func handleTap() { parent.onTap() }
        @MainActor @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            let width = gr.view?.bounds.width ?? 1
            let normalizedX = width > 0 ? gr.location(in: gr.view).x / width : 0.5
            parent.onDoubleTap(normalizedX)
        }
        @MainActor @objc func handleTwoFingerTap() { parent.onTwoFingerTap() }

        @MainActor @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            switch gr.state {
            case .began:
                parent.onLongPressStart?()
            case .ended, .cancelled, .failed:
                parent.onLongPressEnd?()
            default:
                break
            }
        }
    }
}
#endif  // os(iOS)
