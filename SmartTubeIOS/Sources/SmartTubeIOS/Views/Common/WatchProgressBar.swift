import SwiftUI

/// The watched part of a video along the bottom edge of its cover, shared by video cards and offline rows.
/// The fill runs on an opaque track in the page background, so it keeps its contrast over any frame: every accent
/// reaches 4.5:1 on `background` in both themes (DesignTokenTests.accentPairsAreReadable).
struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tint)
                .frame(width: geo.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: VFSpace.s4)
        .background(.background)
    }

    /// What VoiceOver reads for the bar, which covers keep hidden: "N% watched", or nil before any progress.
    static func accessibilityText(for fraction: Double?) -> String? {
        guard let fraction, fraction > 0 else { return nil }
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) watched", bundle: .module)
    }
}
