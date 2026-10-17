import Foundation

/// One decision per drag prevents a level adjustment from turning into navigation.
struct PlayerPanGesture {
    enum Level: Equatable { case brightness, volume }
    enum Intent: Equatable {
        case undecided, horizontal, minimize, ignored
        case level(Level)
    }

    static let activationDistance: CGFloat = 12
    static let navigationDistance: CGFloat = 40
    static let directionBias: CGFloat = 1.25
    static let fastSwipeVelocity: CGFloat = 700
    static let systemEdgeInset: CGFloat = 24
    static let adjustmentHeightFraction: CGFloat = 0.6

    let start: CGPoint
    let bounds: CGRect
    var allowsLevels = true
    private(set) var intent: Intent = .undecided
    private var hasVerticalSample = false

    mutating func update(translation: CGPoint, velocity: CGPoint) -> Intent {
        guard intent == .undecided else { return intent }
        guard bounds.insetBy(dx: Self.systemEdgeInset, dy: Self.systemEdgeInset).contains(start) else {
            intent = .ignored
            return intent
        }
        let dx = abs(translation.x)
        let dy = abs(translation.y)
        guard max(dx, dy) >= Self.activationDistance else { return intent }
        if dx > dy * Self.directionBias {
            intent = .horizontal
        } else if dy > dx * Self.directionBias {
            if !allowsLevels {
                intent = translation.y > 0 ? .minimize : .ignored
                return intent
            }
            // The first pan velocity can include touch-down; wait one sample before classifying speed.
            guard hasVerticalSample else {
                hasVerticalSample = true
                return intent
            }
            if abs(velocity.y) >= Self.fastSwipeVelocity {
                intent = velocity.y > 0 ? .minimize : .ignored
            } else {
                intent = .level(start.x < bounds.midX ? .brightness : .volume)
            }
        }
        return intent
    }

    static func adjustedLevel(initial: CGFloat, translationY: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0, initial.isFinite, translationY.isFinite else { return initial }
        return min(1, max(0, initial - translationY / (height * adjustmentHeightFraction)))
    }
}
