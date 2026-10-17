import SwiftUI

// MARK: - vfGlass
//
// The only place that decides between Liquid Glass and an opaque surface.
// Use it on navigation and control layers, never on content (lists, cards, descriptions, captions).

private struct VFGlassDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the user turned Liquid Glass off; set by `vfGlassScope()`.
    var vfGlassDisabled: Bool {
        get { self[VFGlassDisabledKey.self] }
        set { self[VFGlassDisabledKey.self] = newValue }
    }
}

extension View {
    /// Puts `AppSettings.disableLiquidGlass` into the environment. Apply it on every root that hosts glass, inside the
    /// `SettingsStore` injection: `RootView` and each UIKit-hosted cover, because the environment does not cross a hosting controller.
    func vfGlassScope() -> some View {
        modifier(VFGlassScope())
    }
}

private struct VFGlassScope: ViewModifier {
    @Environment(SettingsStore.self) private var store

    func body(content: Content) -> some View {
        content.environment(\.vfGlassDisabled, store.settings.disableLiquidGlass)
    }
}

extension View {
    /// Liquid Glass on iOS/iPadOS/macOS/tvOS 26+; an opaque `elevated` surface everywhere else,
    /// and also when Reduce Transparency or the Disable Liquid Glass setting is on.
    /// Pass a rounded rectangle for anything that can wrap onto several lines; the default capsule is for single-line chrome.
    func vfGlass<S: Shape>(in shape: S) -> some View {
        modifier(VFGlassModifier(shape: shape))
    }

    func vfGlass() -> some View {
        vfGlass(in: Capsule())
    }
}

private struct VFGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.vfGlassDisabled) private var glassDisabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *), !reduceTransparency, !glassDisabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(VFColor.elevated, in: shape)
                .overlay {
                    shape.stroke(VFColor.border, lineWidth: contrast == .increased ? 2 : 1)
                        .allowsHitTesting(false)
                }
        }
    }
}
