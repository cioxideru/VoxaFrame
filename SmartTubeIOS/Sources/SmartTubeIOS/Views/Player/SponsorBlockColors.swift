import SmartTubeIOSCore
import SwiftUI

// MARK: - SponsorSegment.Category + SwiftUI color
//
// Each category keeps the hue of its SponsorBlock colour (Android's SponsorBlockData), darkened in light so it
// reads on white surfaces and lightened in dark so it reads on the player scrim over any frame: the raw outro and filler are ~2.2:1
// on the player. Tests check the contrast and that the categories stay apart.

extension SponsorSegment.Category {
    /// Light/dark colour of the category: the settings swatch and the Skip button fill.
    var colorPair: VFColorPair {
        switch self {
        case .sponsor: VFColorPair(light: 0x007A00, dark: 0x00D400)
        case .selfPromo: VFColorPair(light: 0x766500, dark: 0xFFFF00)
        case .interaction: VFColorPair(light: 0xA100CC, dark: 0xE066FF)
        case .intro: VFColorPair(light: 0x00786E, dark: 0x00FFFF)
        case .outro: VFColorPair(light: 0x0202ED, dark: 0x9AA4FF)
        case .preview: VFColorPair(light: 0x0062C4, dark: 0x00A3F5)
        case .filler: VFColorPair(light: 0x7300AB, dark: 0xB07AFF)
        case .musicOfftopic: VFColorPair(light: 0xA35500, dark: 0xFF9900)
        case .poiHighlight: VFColorPair(light: 0xCC005F, dark: 0xFF5CA8)
        }
    }

    /// The representative SwiftUI Color for this category.
    var color: Color { Color(colorPair) }

    /// Timeline mark: the dark variant in every theme, because the timeline always sits on the player scrim.
    var markerColor: Color { Color(VFColorPair(light: colorPair.dark, dark: colorPair.dark)) }

    /// Label on a `color` fill (the Skip button).
    var skipLabelColor: Color { Color(colorPair.readableLabel) }

    /// Human-readable label shown in the skip toast and settings UI.
    var displayName: String {
        switch self {
        case .sponsor: return String(localized: "Sponsor", bundle: .module)
        case .selfPromo: return String(localized: "Self-Promotion", bundle: .module)
        case .interaction: return String(localized: "Interaction Reminder", bundle: .module)
        case .intro: return String(localized: "Intro/Recap", bundle: .module)
        case .outro: return String(localized: "Outro/Credits", bundle: .module)
        case .preview: return String(localized: "Preview/Hook", bundle: .module)
        case .filler: return String(localized: "Filler Tangent", bundle: .module)
        case .musicOfftopic: return String(localized: "Music (Off-Topic)", bundle: .module)
        case .poiHighlight: return String(localized: "Highlight", bundle: .module)
        }
    }
}

extension VFColorPair {
    /// Black or white, whichever contrasts more with this fill, per theme.
    var readableLabel: VFColorPair {
        VFColorPair(light: Self.label(on: light), dark: Self.label(on: dark))
    }

    /// WCAG relative luminance of an sRGB hex colour.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// Black when it contrasts more than white: (L + 0.05) / 0.05 against (1.05) / (L + 0.05).
    private static func label(on fill: UInt32) -> UInt32 {
        let lum = luminance(fill)
        return (lum + 0.05) / 0.05 > 1.05 / (lum + 0.05) ? 0x000000 : 0xFFFFFF
    }
}
