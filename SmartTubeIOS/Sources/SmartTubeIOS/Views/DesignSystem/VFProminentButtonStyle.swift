import SmartTubeIOSCore
import SwiftUI

// MARK: - vfProminent
//
// The one primary action in a context. On iPhone and iPad: a capsule filled with the accent and a label that stays
// readable on it (`AccentColorChoice.onColor`). tvOS keeps `.borderedProminent` for the system focus effect, and macOS
// keeps it with the user's system accent.

#if os(iOS)
extension ButtonStyle where Self == VFProminentButtonStyle {
    static var vfProminent: VFProminentButtonStyle { VFProminentButtonStyle() }
}

/// Fill and label come from the accent setting, not `.tint`: the system draws white on the prominent tint,
/// which fails on the dark accents, and a UIKit-hosted cover does not inherit `.tint`.
struct VFProminentButtonStyle: ButtonStyle {
    @Environment(SettingsStore.self) private var store
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let accent = store.settings.accentColor
        // A capsule at one line; a label wrapped by Dynamic Type keeps this radius instead of becoming an oval.
        let shape = RoundedRectangle(cornerRadius: VFTarget.touch / 2, style: .continuous)
        let (font, inset): (Font, CGSize) =
            switch controlSize {
            case .mini, .small: (.subheadline.weight(.semibold), CGSize(width: VFSpace.s12, height: VFSpace.s4))
            case .large, .extraLarge: (.headline, CGSize(width: VFSpace.s24, height: VFSpace.s12))
            default: (.body.weight(.semibold), CGSize(width: VFSpace.s20, height: VFSpace.s8))
            }
        configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(accent.onColor)
            .padding(.horizontal, inset.width)
            .padding(.vertical, inset.height)
            .frame(minHeight: VFTarget.touch)
            .background {
                // Pressed darkens the fill in light and lightens it in dark, which raises label contrast.
                shape.fill(accent.color ?? .accentColor)
                    .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.15 : 0)))
            }
            .overlay {
                // No high-contrast colour values yet (OQ-0019): a strong edge instead.
                if contrast == .increased {
                    shape.strokeBorder(Color.primary, lineWidth: 2)
                }
            }
            .contentShape(shape)
            // Disabled is 40 % (design); the shrink on press is motion, so Reduce Motion drops it.
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .vfAnimation(VFMotion.fast, value: configuration.isPressed)
    }
}
#else
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    static var vfProminent: BorderedProminentButtonStyle { .borderedProminent }
}
#endif
