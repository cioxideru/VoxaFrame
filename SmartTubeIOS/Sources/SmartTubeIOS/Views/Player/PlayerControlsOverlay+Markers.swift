import SmartTubeIOSCore
import SwiftUI

// MARK: - Timeline marks
//
// Drawn over a track that is `inset` from both edges of its frame and `height` tall (VF/Timeline):
// chapter starts are dark gaps across the track, SponsorBlock segments fill it in their category colour.
// The colour is never the only cue: the timeline's VoiceOver value and the skip toast name the category.
// The iPhone, iPad and Mac progress bar that carries them is at the end of this file.

extension PlayerControlsOverlay {
    func chapterMarkers(inset: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            let trackW = geo.size.width - inset * 2
            ForEach(vm.chapters) { chapter in
                let x = inset + trackW * CGFloat(PlayerTimeline.fraction(chapter.startTime, of: vm.duration))
                ZStack {
                    // Invisible enlarged hit area
                    Color.clear
                        .frame(width: 24, height: 44)
                    // The gap between two chapters
                    Rectangle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 3, height: height + 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !vm.isScrubbing else { return }
                    vm.seek(to: chapter.startTime)
                }
                .position(x: x, y: geo.size.height / 2)
                // The first chapter starts with the video; a gap there would only shorten the track.
                .opacity(chapter.startTime > 0 ? 1 : 0)
            }
        }
    }

    // SponsorBlock segment markers on the progress bar
    func sponsorBlockMarkers(inset: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            let trackW = geo.size.width - inset * 2
            ForEach(vm.sponsorSegments) { seg in
                if let span = PlayerTimeline.span(start: seg.start, end: seg.end, duration: vm.duration) {
                    // A highlight is a point; it keeps a 2 pt mark.
                    let width = max(trackW * CGFloat(span.upperBound - span.lowerBound), 2)
                    Rectangle()
                        .fill(seg.category.markerColor)
                        .frame(width: width, height: height)
                        .position(x: inset + trackW * CGFloat(span.lowerBound) + width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Progress bar (iPhone, iPad and Mac)

#if !os(tvOS)
extension PlayerControlsOverlay {
    var iosProgressBar: some View {
        // Wrap in an outer GeometryReader so the highPriorityGesture below can
        // reference the bar's width.  The gesture is placed on the full-height
        // VStack (tooltip row + track row = 60 pt) so any touch in that area —
        // including the 28 pt invisible tooltip strip above the visible bar — will
        // activate the scrub drag.  Previously the gesture was only on the inner
        // 28 pt track ZStack, which meant touches on the empty tooltip row were
        // silently swallowed without triggering the seek.
        GeometryReader { outerGeo in
            let hPad: CGFloat = 20
            let trackW = outerGeo.size.width - hPad * 2

            VStack(spacing: 4) {
                // Tooltip row — always occupies space so layout doesn't jump
                GeometryReader { geo in
                    if vm.isScrubbing && vm.duration > 0 {
                        let thumbX = hPad + trackW * CGFloat(PlayerTimeline.fraction(vm.scrubTime, of: vm.duration))
                        let chapterAtScrub = vm.chapters.last(where: { $0.startTime <= vm.scrubTime })
                        let labelW: CGFloat = chapterAtScrub != nil ? min(outerGeo.size.width * 0.5, 180) : 64
                        let clampedX = min(max(thumbX, hPad + labelW / 2), outerGeo.size.width - hPad - labelW / 2)

                        VStack(spacing: 2) {
                            if let chapter = chapterAtScrub {
                                Text(chapter.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(VFColor.onMedia.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Text(formatDuration(vm.scrubTime))
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(VFColor.onMedia)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            VFColor.scrim, in: RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous)
                        )
                        .frame(width: labelW)
                        .position(x: clampedX, y: geo.size.height / 2)
                    }
                }
                .frame(height: 28)

                // Track: remaining in `onMediaTrack`, played in full `onMedia`, SponsorBlock segments in their category
                // colour, chapter starts as gaps, and the knob, which grows while scrubbing.
                GeometryReader { geo in
                    let time = vm.isScrubbing ? vm.scrubTime : vm.currentTime
                    let played = trackW * CGFloat(PlayerTimeline.fraction(time, of: vm.duration))
                    let knob: CGFloat = vm.isScrubbing ? 24 : 16

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(VFColor.onMediaTrack)
                            .frame(height: Self.trackHeight)
                        Capsule()
                            .fill(VFColor.onMedia)
                            .frame(width: max(played, 0), height: Self.trackHeight)
                    }
                    .padding(.horizontal, hPad)
                    .frame(maxHeight: .infinity)
                    .overlay(sponsorBlockMarkers(inset: hPad, height: Self.trackHeight))
                    .overlay(chapterMarkers(inset: hPad, height: Self.trackHeight))
                    .overlay {
                        Circle()
                            .fill(VFColor.onMedia)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .frame(width: knob, height: knob)
                            .position(x: hPad + played, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                    }
                    .vfAnimation(VFMotion.fast, value: vm.isScrubbing)
                }
                .frame(height: 28)
                .modifier(TimelineAccessibility(vm: vm))
            }
            .contentShape(Rectangle())
            // highPriorityGesture on the full VStack (tooltip + track, 60 pt total)
            // ensures the seek-bar drag beats any child-view tap gestures (e.g.
            // chapter-marker hit areas) and activates even when the touch lands on
            // the invisible tooltip strip above the visible progress bar.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max((value.location.x - hPad) / trackW, 0), 1)
                        if !vm.isScrubbing { vm.beginScrubbing() }
                        vm.updateScrub(to: Double(fraction) * vm.duration)
                    }
                    .onEnded { _ in vm.commitScrub() }
            )
        }
        .frame(height: 60)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.playerProgressBar)
    }

    static let trackHeight: CGFloat = 4
}

/// The timeline is one adjustable element for VoiceOver: swipe up or down moves 10 s, and the value names the
/// time, the chapter and any SponsorBlock segment, so the marks and colours are not the only carrier.
private struct TimelineAccessibility: ViewModifier {
    let vm: PlaybackViewModel

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel(Text("Playback position", bundle: .module))
            .accessibilityValue(
                PlayerTimeline.accessibilityValue(
                    time: vm.isScrubbing ? vm.scrubTime : vm.currentTime, duration: vm.duration,
                    chapters: vm.chapters, segments: vm.sponsorSegments)
            )
            .accessibilityAdjustableAction { direction in
                guard vm.duration > 0 else { return }
                switch direction {
                case .increment: vm.seekRelative(seconds: PlayerTimeline.accessibilityStep)
                case .decrement: vm.seekRelative(seconds: -PlayerTimeline.accessibilityStep)
                @unknown default: break
                }
            }
    }
}
#endif
