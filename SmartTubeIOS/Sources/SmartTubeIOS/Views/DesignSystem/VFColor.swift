import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - VFColorPair
//
// Brand and status colours that have no system equivalent, written once as light/dark hex.
// Values come from docs/design/voxaframe-redesign/design-system/tokens.json; tests check their contrast.

struct VFColorPair: Sendable, Equatable {
    let light: UInt32
    let dark: UInt32

    static let action = VFColorPair(light: 0xB83829, dark: 0xFF9988)
    static let onAction = VFColorPair(light: 0xFFFFFF, dark: 0x260724)
    static let focus = VFColorPair(light: 0xB83829, dark: 0xFFD9D2)
    static let success = VFColorPair(light: 0x236A3C, dark: 0x82D99E)
    static let warning = VFColorPair(light: 0x805300, dark: 0xF7CE7D)
    static let danger = VFColorPair(light: 0xB42318, dark: 0xFFB4A9)
}

// MARK: - VFColor

enum VFColor {
    /// Fill of the primary button, selected navigation, enabled toggles and progress.
    static let action = Color(VFColorPair.action)
    /// Text and icons on an `action` fill.
    static let onAction = Color(VFColorPair.onAction)
    /// Keyboard focus ring. Draw it with a 3–4 pt gap; the gap is what separates it from an `action` fill.
    /// tvOS focus stays system-owned.
    static let focus = Color(VFColorPair.focus)
    /// Status colours always come with a label and a symbol, never alone.
    static let success = Color(VFColorPair.success)
    static let warning = Color(VFColorPair.warning)
    static let danger = Color(VFColorPair.danger)

    /// Black at 72 %: only under white controls drawn over an arbitrary video frame.
    /// Over glass and video use `onMedia` or system label styles, not the colours above.
    static let scrim = Color.black.opacity(0.72)
    /// Text and transport icons on `scrim`.
    static let onMedia = Color.white

    #if os(tvOS)
    // tvOS has no grouped-background roles, so these two use the reference values from tokens.json.
    static let surface = Color(VFColorPair(light: 0xF2F2F7, dark: 0x1C1C1E))
    static let elevated = Color(VFColorPair(light: 0xFFFFFF, dark: 0x2C2C2E))
    static let border = Color(uiColor: .opaqueSeparator)
    #elseif canImport(UIKit)
    /// Groups, chips and secondary buttons.
    static let surface = Color(uiColor: .secondarySystemBackground)
    /// Content raised above the page: mini-player, bottom navigation, the opaque stand-in for glass.
    static let elevated = Color(uiColor: .tertiarySystemBackground)
    /// Decorative separator; never the only sign that something is a control.
    static let border = Color(uiColor: .opaqueSeparator)
    #else
    static let surface = Color(nsColor: .quaternarySystemFill)
    static let elevated = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    #endif
}

extension Color {
    fileprivate init(_ pair: VFColorPair) {
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
            })
        #else
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? pair.dark : pair.light)
            })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
#else
extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
#endif
