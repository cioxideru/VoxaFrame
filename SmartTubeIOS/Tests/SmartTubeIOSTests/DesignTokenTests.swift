import Foundation
import Testing

@testable import SmartTubeIOS

@Suite("Design tokens")
struct DesignTokenTests {

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
        "Action and status text reach 4.5:1 on every surface in both themes",
        arguments: [
            ("action", VFColorPair.action), ("success", VFColorPair.success),
            ("warning", VFColorPair.warning), ("danger", VFColorPair.danger),
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

    @Test("Text on an action fill reaches 4.5:1 in both themes")
    func onActionIsReadable() {
        #expect(Self.contrast(VFColorPair.onAction.light, VFColorPair.action.light) >= 4.5)
        #expect(Self.contrast(VFColorPair.onAction.dark, VFColorPair.action.dark) >= 4.5)
    }
}
