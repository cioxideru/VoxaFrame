import Foundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("Design tokens")
struct DesignTokenTests {

    @Test("Content columns collapse in narrow windows and at accessibility text sizes")
    func columnsRequireReadableContentWidth() {
        #expect(!VFColumn.supportsColumns(width: 0, typeSize: .large))
        #expect(!VFColumn.supportsColumns(width: VFColumn.minimumContentWidth - 1, typeSize: .large))
        #expect(VFColumn.supportsColumns(width: VFColumn.minimumContentWidth, typeSize: .xxxLarge))
        #expect(!VFColumn.supportsColumns(width: 1200, typeSize: .accessibility1))
        #expect(!VFColumn.supportsColumns(width: 1200, typeSize: .accessibility5))
    }

    @Test("List columns keep their minimum width and stop growing at their platform maximum")
    func columnWidthsStayWithinBounds() {
        for maximum in [
            VFColumn.offlineListMaximum, VFColumn.settingsCategoriesMaximum, VFColumn.settingsCategoriesTVMaximum,
        ] {
            #expect(VFColumn.listWidth(in: VFColumn.minimumContentWidth, maximum: maximum) == VFColumn.listMinimum)
            #expect(VFColumn.listWidth(in: 2400, maximum: maximum) == maximum)
        }
        #expect(VFColumn.listWidth(in: 800, maximum: VFColumn.offlineListMaximum) == 320)
    }

    private struct Surface {
        let name: String
        let light: UInt32
        let dark: UInt32
    }

    /// The design's reference surfaces (tokens.json); real system colours differ per platform.
    private static let surfaces = [
        Surface(name: "background", light: 0xFFFFFF, dark: 0x000000),
        Surface(name: "surface", light: 0xF2F2F7, dark: 0x1C1C1E),
        Surface(name: "elevated", light: 0xFFFFFF, dark: 0x2C2C2E),
    ]

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (high + 0.05) / (low + 0.05)
    }

    @Test(
        "Status text reaches 4.5:1 on every surface in both themes",
        arguments: [
            ("success", VFColorPair.success), ("warning", VFColorPair.warning), ("danger", VFColorPair.danger),
        ])
    func textColoursAreReadable(name: String, pair: VFColorPair) {
        for surface in Self.surfaces {
            #expect(Self.contrast(pair.light, surface.light) >= 4.5, "\(name) on \(surface.name), light")
            #expect(Self.contrast(pair.dark, surface.dark) >= 4.5, "\(name) on \(surface.name), dark")
        }
    }

    @Test("The focus ring reaches 3:1 on every surface in both themes")
    func focusRingIsVisible() {
        for surface in Self.surfaces {
            #expect(Self.contrast(VFColorPair.focus.light, surface.light) >= 3, "light on \(surface.name)")
            #expect(Self.contrast(VFColorPair.focus.dark, surface.dark) >= 3, "dark on \(surface.name)")
        }
    }

    @Test(
        "Every accent: its label reads on its fill and it reads as text on every surface, in both themes",
        arguments: AppSettings.AccentColorChoice.allCases)
    func accentPairsAreReadable(accent: AppSettings.AccentColorChoice) {
        let fill = VFColorPair.action(for: accent)
        let label = VFColorPair.onAction(for: accent)
        #expect(Self.contrast(label.light, fill.light) >= 4.5, "label, light")
        #expect(Self.contrast(label.dark, fill.dark) >= 4.5, "label, dark")
        for surface in Self.surfaces {
            #expect(Self.contrast(fill.light, surface.light) >= 4.5, "text on \(surface.name), light")
            #expect(Self.contrast(fill.dark, surface.dark) >= 4.5, "text on \(surface.name), dark")
        }
    }

    /// `.primary` text, the design's `text` token.
    private static let primaryText = VFColorPair(light: 0x000000, dark: 0xFFFFFF)

    /// `top` at `alpha` over an opaque `base`, per sRGB channel.
    private static func blend(_ top: UInt32, alpha: Double, over base: UInt32) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let mixed = Double((top >> shift) & 0xFF) * alpha + Double((base >> shift) & 0xFF) * (1 - alpha)
            return result | UInt32(mixed.rounded()) << shift
        }
    }

    @Test(
        "Every accent: the search filter chip label reads on its accent wash on every surface, in both themes",
        arguments: AppSettings.AccentColorChoice.allCases)
    func filterChipIsReadable(accent: AppSettings.AccentColorChoice) {
        let fill = VFColorPair.action(for: accent)
        for surface in Self.surfaces {
            let light = Self.blend(fill.light, alpha: FilterChip.fillOpacity, over: surface.light)
            let dark = Self.blend(fill.dark, alpha: FilterChip.fillOpacity, over: surface.dark)
            #expect(Self.contrast(Self.primaryText.light, light) >= 4.5, "on \(surface.name), light")
            #expect(Self.contrast(Self.primaryText.dark, dark) >= 4.5, "on \(surface.name), dark")
        }
    }

    #if os(macOS)
    @Test("macOS keeps the user's system accent for System")
    func macOSKeepsSystemAccent() {
        #expect(AppSettings.AccentColorChoice.system.color == nil)
    }
    #endif
}
