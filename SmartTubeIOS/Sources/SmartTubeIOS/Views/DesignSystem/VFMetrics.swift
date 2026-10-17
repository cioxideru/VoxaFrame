import SwiftUI

// MARK: - Metrics
//
// Spacing, radii, targets and margins from docs/design/voxaframe-redesign/design-system/tokens.json.
// Real safe areas and layout margins win over these numbers.

enum VFSpace {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
    static let s64: CGFloat = 64
}

/// Radii for content only, drawn with `RoundedRectangle(cornerRadius:style: .continuous)`.
/// Sheets, windows and system buttons keep the OS geometry; pills are `Capsule()`.
enum VFRadius {
    static let small: CGFloat = 8
    static let card: CGFloat = 16
    static let panel: CGFloat = 24
}

/// Default interactive size per input model, used as a minimum (`minWidth`/`minHeight`), never a fixed frame.
/// The visible glyph may be smaller. HIG floors: 20 on macOS, 56 on tvOS.
enum VFTarget {
    static let touch: CGFloat = 44
    static let pointer: CGFloat = 28
    static let tv: CGFloat = 66
}

enum VFMargin {
    static let iphone: CGFloat = 16
    static let ipad: CGFloat = 20
    static let mac: CGFloat = 24
    static let tvHorizontal: CGFloat = 80
    static let tvVertical: CGFloat = 60
    /// Narrowest video card on iPad and Mac; drop a column instead of going below it.
    static let cardMinWidth: CGFloat = 240
}

// MARK: - Motion

enum VFMotion {
    static let fast: TimeInterval = 0.12
    static let standard: TimeInterval = 0.22
    static let layout: TimeInterval = 0.32
}

extension View {
    /// Animates changes of `value`; with Reduce Motion the change is applied at once.
    func vfAnimation<Value: Equatable>(
        _ duration: TimeInterval = VFMotion.standard, value: Value
    ) -> some View {
        modifier(VFAnimationModifier(duration: duration, value: value))
    }
}

private struct VFAnimationModifier<Value: Equatable>: ViewModifier {
    let duration: TimeInterval
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: duration), value: value)
    }
}
