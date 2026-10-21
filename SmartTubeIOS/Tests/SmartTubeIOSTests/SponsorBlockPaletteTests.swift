import Foundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

@Suite("SponsorBlock palette")
struct SponsorBlockPaletteTests {

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (lhs, rhs) = (VFColorPair.luminance(first), VFColorPair.luminance(second))
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    /// `VFColor.scrim` (black at 72 %) over a white video frame, the lightest backdrop a timeline mark can get.
    private static let scrimOverWhite: UInt32 = 0x474747

    @Test("The label picks black on light fills and white on dark ones")
    func labelFollowsFill() {
        #expect(
            VFColorPair(light: 0xFFFF00, dark: 0x0202ED).readableLabel == VFColorPair(light: 0x000000, dark: 0xFFFFFF))
    }

    @Test(
        "Skip label reads on its fill and the timeline mark reads on the player scrim, in both themes",
        arguments: SponsorSegment.Category.allCases)
    func categoryIsReadable(category: SponsorSegment.Category) {
        let fill = category.colorPair
        let label = fill.readableLabel
        #expect(Self.contrast(label.light, fill.light) >= 4.5, "label, light")
        #expect(Self.contrast(label.dark, fill.dark) >= 4.5, "label, dark")
        #expect(Self.contrast(fill.dark, Self.scrimOverWhite) >= 3, "timeline mark on the scrim over a white frame")
    }

    @Test("Categories stay apart from each other in both themes")
    func categoriesAreDistinct() {
        func distance(_ first: UInt32, _ second: UInt32) -> Double {
            let squares = [16, 8, 0].map { shift -> Double in
                let delta = Double((first >> UInt32(shift)) & 0xFF) - Double((second >> UInt32(shift)) & 0xFF)
                return delta * delta
            }
            return squares.reduce(0, +).squareRoot()
        }
        let pairs = SponsorSegment.Category.allCases.map(\.colorPair)
        for (index, first) in pairs.enumerated() {
            for second in pairs[(index + 1)...] {
                #expect(distance(first.light, second.light) >= 40)
                #expect(distance(first.dark, second.dark) >= 40)
            }
        }
    }
}
