import SmartTubeIOSCore
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
    /// Label on a named accent fill (`action(for:)`).
    static let onAccent = VFColorPair(light: 0xFFFFFF, dark: 0x000000)

    /// Fill and text colour of a user accent on iPhone and iPad (Settings › Accent Color; mockups/vf.css):
    /// darkened in light so it reads as text on every surface, lightened in dark under a black label.
    static func action(for accent: AppSettings.AccentColorChoice) -> VFColorPair {
        switch accent {
        case .system: .action
        case .red: VFColorPair(light: 0xD80B00, dark: 0xFF5F56)
        case .orange: VFColorPair(light: 0x9E5C00, dark: 0xFF9F0A)
        case .yellow: VFColorPair(light: 0x826800, dark: 0xFFD60A)
        case .green: VFColorPair(light: 0x207A37, dark: 0x30D158)
        case .mint: VFColorPair(light: 0x007873, dark: 0x63E6E2)
        case .teal: VFColorPair(light: 0x207685, dark: 0x40C8E0)
        case .blue: VFColorPair(light: 0x0068D9, dark: 0x3398FF)
        case .indigo: VFColorPair(light: 0x5856D6, dark: 0x8E8DED)
        case .purple: VFColorPair(light: 0xA134D8, dark: 0xC76FF4)
        case .pink: VFColorPair(light: 0xD80029, dark: 0xFF5B7C)
        }
    }

    /// Label on `action(for:)`: plum on the dark coral, black on the other dark fills, white in light.
    static func onAction(for accent: AppSettings.AccentColorChoice) -> VFColorPair {
        accent == .system ? .onAction : .onAccent
    }
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
    init(_ pair: VFColorPair) {
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
