import AVFoundation
import SmartTubeIOSCore
import SwiftUI

// MARK: - Self-contained auxiliary views used by PlayerView
//
// Extracted from PlayerView.swift to keep that file under 1 000 lines.

// MARK: - StatsForNerdsOverlay

struct StatsForNerdsOverlay: View {
    let snapshot: StatsForNerdsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Video ID", snapshot.videoId)
            row(
                "Resolution",
                snapshot.fps > 0
                    ? "\(snapshot.displayResolution) @ \(snapshot.fps) fps"
                    : snapshot.displayResolution)
            if !snapshot.pendingQualityLabel.isEmpty {
                identifiedRow(
                    "Selected", snapshot.pendingQualityLabel,
                    valueId: "stats.selectedQuality")
            }
            row("Codec", snapshot.codec)
            row("Nominal Bitrate", snapshot.nominalBitrate)
            row("Connection Speed", snapshot.observedBitrate)
            row("Dropped Frames", "\(snapshot.droppedFrames)")
            row("Stalls", "\(snapshot.stalls)")
            Divider().background(.white.opacity(0.2)).padding(.vertical, 2)
            row("TTP (low-q)", snapshot.timeToPlayMs > 0 ? "\(snapshot.timeToPlayMs) ms" : "—")
            row("TTP (hi-q)", snapshot.timeToHighQualityMs > 0 ? "\(snapshot.timeToHighQualityMs) ms" : "—")
            row("Stream Type", snapshot.streamType.isEmpty ? "—" : snapshot.streamType)
            row("Cache", snapshot.cacheStatus.isEmpty ? "—" : snapshot.cacheStatus)
            smallRow("Stream URL", snapshot.streamURL.isEmpty ? "—" : snapshot.streamURL)
            Divider().background(.white.opacity(0.2)).padding(.vertical, 2)
            Text("Two-finger tap to dismiss")
                .foregroundStyle(VFColor.onMedia.opacity(0.65))
                .font(.system(.caption2, design: .monospaced))
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VFColor.scrim)
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityIdentifier(AccessibilityID.playerStatsOverlay)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(VFColor.onMedia.opacity(0.75))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func smallRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(VFColor.onMedia.opacity(0.75))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(.caption2, design: .monospaced))
    }

    /// Like `row` but applies an accessibility identifier to the value text,
    /// allowing XCUITest to locate it directly by identifier.
    private func identifiedRow(_ key: String, _ value: String, valueId: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(VFColor.onMedia.opacity(0.75))
                .frame(minWidth: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.white)
                .accessibilityIdentifier(valueId)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

// MARK: - PlayerLoadingIndicator

/// Source loading in the regular player and Shorts: a spinner on a glass disc and, while a retry runs,
/// its status. It is not the translation wait, which has its own plate and exit (`PlayerTranslationStatus`).
struct PlayerLoadingIndicator: View {
    let message: String?

    var body: some View {
        VStack(spacing: VFSpace.s12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(VFColor.onMedia)
                .frame(width: 72, height: 72)
                .vfGlass(in: Circle())
            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VFColor.onMedia)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VFSpace.s12)
                    .padding(.vertical, VFSpace.s4)
                    .background(VFColor.scrim, in: Capsule())
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .vfAnimation(value: message)
        .transition(.opacity)
    }
}

/// How far a bar's scrim fades out beyond the bar.
private let playerBarScrimFade: CGFloat = 32

extension View {
    /// Puts a bar of text and controls over video on its own scrim: solid under the bar, then fading out over the
    /// video (downwards for a top bar, upwards for a bottom one). It follows the bar's real height and reaches into
    /// the safe area, so white text keeps its contrast on a white frame in every layout and text size.
    func playerBarScrim(fadingDown: Bool) -> some View {
        background {
            VStack(spacing: 0) {
                if !fadingDown {
                    LinearGradient(colors: [.clear, VFColor.scrim], startPoint: .top, endPoint: .bottom)
                        .frame(height: playerBarScrimFade)
                }
                VFColor.scrim
                if fadingDown {
                    LinearGradient(colors: [VFColor.scrim, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: playerBarScrimFade)
                }
            }
            .padding(fadingDown ? .bottom : .top, -playerBarScrimFade)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// A round control drawn over video: an `onMedia` glyph on glass, never smaller than `diameter`.
    /// `isActive` inverts it (white disc, dark glyph), so an on state does not rely on colour alone.
    func playerMediaControl(diameter: CGFloat, isActive: Bool = false) -> some View {
        foregroundStyle(isActive ? Color.black : VFColor.onMedia)
            .frame(width: diameter, height: diameter)
            .background {
                if isActive { Circle().fill(VFColor.onMedia) }
            }
            .vfGlass(in: Circle())
            .contentShape(Circle())
    }

    /// An icon-only player control. Its glyph keeps a fixed size over the video, so at large text sizes the Large
    /// Content Viewer shows it with its name; on the Mac the same name is the tooltip.
    func playerIconControl(_ label: Text, symbol: String) -> some View {
        accessibilityLabel(label)
            .accessibilityShowsLargeContentViewer {
                Label {
                    label
                } icon: {
                    Image(systemName: symbol)
                }
            }
            .playerTooltip(label)
    }

    @ViewBuilder private func playerTooltip(_ label: Text) -> some View {
        #if os(macOS)
        help(label)
        #else
        self
        #endif
    }
}

/// An action over the video (Try Again, Sign In, the translation exits). iPhone, iPad and Mac: a white capsule
/// with a dark label, or a translucent one, which reads on any frame. tvOS: the system buttons, for the remote's
/// focus effect, at the 10-foot target.
struct PlayerMediaActionButton: View {
    let title: Text
    var primary = true
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        let button = Button(action: action) { title.frame(minHeight: playerActionTarget) }
        if primary {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
        #else
        Button(action: action) {
            title
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(primary ? Color.black : VFColor.onMedia)
                .padding(.horizontal, VFSpace.s20)
                .frame(minHeight: playerActionTarget)
                .background(primary ? VFColor.onMedia : VFColor.onMedia.opacity(0.2), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - RelatedVideosView

struct RelatedVideosView: View {
    let videos: [Video]
    let onSelect: (Video) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(videos) { video in
                    VideoCardView(video: video, compact: true)
                        .padding(.horizontal)
                        .onTapGesture { onSelect(video) }
                }
            }
        }
    }
}

// MARK: - CommentRowView

struct CommentRowView: View {
    let comment: Comment
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: VFSpace.s12) {
            AsyncImage(url: comment.authorAvatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(VFColor.placeholder)
            }
            .frame(width: VFSize.commentAvatar, height: VFSize.commentAvatar)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: VFSpace.s4) {
                HStack(spacing: VFSpace.s8) {
                    Text(comment.author)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(comment.publishedTime)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(timestampLinkedAttributedString(comment.text))
                    .font(.callout)
                if !comment.likeCount.isEmpty {
                    HStack(spacing: VFSpace.s4) {
                        Image(systemName: AppSymbol.thumbsUp)
                        Text(comment.likeCount)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(VFSpace.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One VoiceOver element per comment; each timestamp stays reachable as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityActions {
            // By position, not by time: the same timestamp can appear twice in one comment.
            ForEach(Array(findTimestamps(in: comment.text).enumerated()), id: \.offset) { _, stamp in
                Button(String(comment.text[stamp.range])) {
                    if let url = URL(string: "smarttube://seek/\(Int(stamp.seconds))") { openURL(url) }
                }
            }
        }
    }

    private var spokenSummary: String {
        var parts = [comment.author, comment.publishedTime, comment.text]
        if !comment.likeCount.isEmpty {
            parts.append(String(localized: "\(comment.likeCount) likes", bundle: .module))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func timestampLinkedAttributedString(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for (range, seconds) in findTimestamps(in: text) {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].link = URL(string: "smarttube://seek/\(Int(seconds))")
        }
        return attributed
    }
}

// MARK: - EndCardOverlay

/// Positions YouTube end-screen cards absolutely within the player bounds.
/// Cards are shown only during their `startMs…endMs` window and dismissed when
/// the controls overlay is visible (consistent with official YouTube behaviour).
#if !os(tvOS)
struct EndCardOverlay: View {
    let cards: [EndCard]
    let currentTime: TimeInterval
    let onSelect: (EndCard) -> Void

    private var visibleCards: [EndCard] {
        let ms = Int(currentTime * 1000)
        return cards.filter { $0.style == .video && $0.videoId != nil && ms >= $0.startMs && ms <= $0.endMs }
    }

    var body: some View {
        // Self-sizing via an internal GeometryReader avoids passing geo.size from the
        // outer player GeometryReader. Passing geo.size directly and then setting an
        // explicit .frame(width: geo.size.width, height: geo.size.height) here created
        // an AnimatableFrameAttribute that fed back into the outer GR during animations,
        // causing SIGSEGV/SIGBUS crashes at AttributeGraph recursion level 10.
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(visibleCards) { card in
                    let cardWidth = card.width / 100 * proxy.size.width
                    let cardHeight = cardWidth / max(card.aspectRatio, 0.1)
                    let x = card.left / 100 * proxy.size.width
                    let y = card.top / 100 * proxy.size.height
                    EndCardButton(card: card, width: cardWidth, height: cardHeight, onSelect: onSelect)
                        .offset(x: x, y: y)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeOut(duration: 0.2), value: visibleCards.count)
                }
            }
            .allowsHitTesting(!visibleCards.isEmpty)
        }
    }
}

struct EndCardButton: View {
    let card: EndCard
    let width: CGFloat
    let height: CGFloat
    let onSelect: (EndCard) -> Void

    var body: some View {
        Button {
            onSelect(card)
        } label: {
            ZStack(alignment: .bottom) {
                AsyncImage(url: card.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.4)
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                if !card.title.isEmpty {
                    Text(card.title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.65))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End card: \(card.title)")
    }
}
#endif

// MARK: - AppSettings.VideoGravityMode → AVLayerVideoGravity mapping

extension AppSettings.VideoGravityMode {
    mutating func toggle() {
        self = self == .fit ? .fill : .fit
    }

    var avGravity: AVLayerVideoGravity {
        self == .fill ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - AirPlayRoutePickerView

#if canImport(UIKit)
import UIKit
import AVKit

/// Wraps `AVRoutePickerView` (the iOS AirPlay button) in a SwiftUI-compatible view.
struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor.systemBlue
        // Set the identifier directly on the UIKit view so XCUITest can find it.
        // The SwiftUI `.accessibilityIdentifier()` modifier applies to the hosting
        // wrapper view, not to AVRoutePickerView itself.
        picker.accessibilityIdentifier = AccessibilityID.playerAirPlayButton
        picker.isAccessibilityElement = true
        // As one element the picker hides its inner button's name, so it needs its own.
        picker.accessibilityLabel = String(localized: "AirPlay", bundle: .module)
        picker.accessibilityTraits = [.button]
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
