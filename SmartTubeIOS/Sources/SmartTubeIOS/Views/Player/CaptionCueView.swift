import MediaAccessibility
import SwiftUI

// MARK: - CaptionCueView
//
// Renders the active caption cue over the video.
// Positioned at the bottom of the player just above the progress bar.
// YouTube-style: semi-transparent black pill background, white semibold text.

public struct CaptionCueView: View {
    public let text: String

    private static var baseFontSize: CGFloat {
        #if os(tvOS)
        36
        #else
        17
        #endif
    }

    /// Follows Dynamic Type from the body style.
    @ScaledMetric(relativeTo: .body) private var scaledFontSize = CaptionCueView.baseFontSize

    /// Dynamic Type times the system caption style's text size (Accessibility > Subtitles & Captioning),
    /// capped at twice the base so a cue never covers most of the picture.
    private var fontSize: CGFloat {
        let userScale = MACaptionAppearanceGetRelativeCharacterSize(.user, nil)
        return min(scaledFontSize * (userScale > 0 ? userScale : 1), Self.baseFontSize * 2)
    }

    private var textHorizontalPadding: CGFloat {
        #if os(tvOS)
        18
        #else
        10
        #endif
    }

    private var textVerticalPadding: CGFloat {
        #if os(tvOS)
        10
        #else
        5
        #endif
    }

    private var screenHorizontalPadding: CGFloat {
        #if os(tvOS)
        80
        #else
        24
        #endif
    }

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, textHorizontalPadding)
            .padding(.vertical, textVerticalPadding)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            .padding(.horizontal, screenHorizontalPadding)
            .accessibilityIdentifier("player.captionCue")
    }
}
