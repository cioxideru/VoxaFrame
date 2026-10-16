#if os(iOS)
import SwiftUI
import UIKit

/// Reject vertical movement before recognition so the parent feed can scroll.
struct HomeSectionSwipe: ViewModifier {
    let onSwipe: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(HorizontalPan(onEnded: finish))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { finish($0.translation) })
        }
    }

    private func finish(_ translation: CGSize) {
        guard abs(translation.width) > 80,
            Self.isHorizontal(x: translation.width, y: translation.height)
        else { return }
        onSwipe(translation.width)
    }

    private static func isHorizontal(x: CGFloat, y: CGFloat) -> Bool {
        abs(x) > abs(y) * 2
    }

    @available(iOS 18, *)
    private struct HorizontalPan: UIGestureRecognizerRepresentable {
        let onEnded: (CGSize) -> Void

        func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer()
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = context.coordinator
            return recognizer
        }

        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            onEnded(CGSize(width: translation.x, height: translation.y))
        }

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
                let velocity = pan.velocity(in: pan.view)
                return HomeSectionSwipe.isHorizontal(x: velocity.x, y: velocity.y)
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool { true }
        }
    }
}
#endif
