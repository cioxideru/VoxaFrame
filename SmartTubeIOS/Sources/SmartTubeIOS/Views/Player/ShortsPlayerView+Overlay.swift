import SmartTubeIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Shorts controls (P-Shorts, X-Shorts, T-Shorts)
//
// iPhone, iPad and Mac: back, position and play/pause on top; a rail of round controls at the trailing edge —
// previous and next Short (the visible alternative to the swipes), sound, the Shorts speed, audio and
// translation, Fit/Fill — then channel, title and the position slider on a solid scrim. tvOS keeps its rows:
// the remote's up and down switch Shorts, and there is no slider.

extension ShortsPlayerView {

    @ViewBuilder var shortsOverlay: some View {
        #if os(tvOS)
        tvShortsOverlay
        #else
        touchShortsOverlay
        #endif
    }

    private var indexLabel: some View {
        Text("\(window.discardedCount + currentIndex + 1) / \(window.discardedCount + videos.count)")
            .font(.footnote.monospacedDigit().weight(.semibold))
            .accessibilityIdentifier(AccessibilityID.shortsIndexLabel)
    }

    private var speedValue: String { PlayerSpeedPicker.label(for: store.settings.shortsPlaybackSpeed) }

    /// Mutes the video and the translation voice together.
    private func toggleMute() {
        isMuted.toggle()
        vm.player.isMuted = isMuted
        vm.voiceOver.isMuted = isMuted
    }

    #if !os(tvOS)
    private var touchShortsOverlay: some View {
        VStack(spacing: VFSpace.s12) {
            HStack(spacing: VFSpace.s12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .font(.title3.weight(.semibold))
                        .playerMediaControl(diameter: VFTarget.touch)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier(AccessibilityID.shortsBackButton)
                Spacer()
                indexLabel
                    .padding(.horizontal, VFSpace.s12)
                    .frame(minHeight: 32)
                    .vfGlass()
                Spacer()
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? AppSymbol.pause : AppSymbol.play)
                        .font(.title3)
                        .playerMediaControl(diameter: VFTarget.touch)
                }
                .disabled(vm.isLoading || vm.error != nil)
                .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier(AccessibilityID.shortsPlayPauseButton)
            }
            .padding(.horizontal, VFSpace.s16)
            .padding(.top, VFSpace.s8)

            PlayerTranslationStatus(vm: vm)
                .padding(.horizontal, VFSpace.s16)

            Spacer(minLength: 0)

            // The rail's buttons carry their own glass; the text and the timeline below get a solid scrim.
            shortsRail
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, VFSpace.s16)

            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(vm.currentVideo?.channelTitle ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(vm.currentVideo?.title ?? "")
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.shortsTitleLabel)
                #if os(iOS)
                ShortsSeekSlider(vm: vm)
                #else
                Slider(
                    value: Binding(
                        get: { vm.isScrubbing ? vm.scrubTime : vm.currentTime },
                        set: { position in
                            if vm.isScrubbing {
                                vm.updateScrub(to: position)
                            } else {
                                // Accessibility adjustments do not send editing callbacks.
                                vm.seek(to: position)
                            }
                        }),
                    in: 0...max(vm.duration, 1),
                    onEditingChanged: { editing in
                        if editing { vm.beginScrubbing() } else { vm.commitScrub() }
                    }
                )
                .tint(VFColor.onMedia)
                .disabled(vm.duration <= 0 || vm.isLoading || vm.error != nil)
                .accessibilityLabel("Playback position")
                .accessibilityValue(formatDuration(vm.isScrubbing ? vm.scrubTime : vm.currentTime))
                .accessibilityIdentifier(AccessibilityID.shortsSeekBar)
                #endif
                Text("\(formatDuration(vm.currentTime)) / \(formatDuration(vm.duration))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .accessibilityIdentifier(AccessibilityID.shortsTimeLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VFSpace.s16)
            .padding(.bottom, VFSpace.s8)
            .playerBarScrim(fadingDown: false)
        }
        .buttonStyle(.plain)
        .foregroundStyle(VFColor.onMedia)
        // The controls sit on video whatever the app's appearance, so glass and fallbacks resolve dark.
        .environment(\.colorScheme, .dark)
    }

    /// The round controls above the title, at the trailing edge: one column, or one row in a landscape iPhone layout.
    /// On a short screen or at accessibility text sizes they form two rows of three, so channel, title and the
    /// timeline keep their room; every control stays 52 pt.
    private var shortsRail: some View {
        let row = AnyLayout(HStackLayout(spacing: VFSpace.s12))
        let column = AnyLayout(VStackLayout(spacing: VFSpace.s12))
        let outer = isCompactHeight ? row : column
        let inner = isCompactHeight || isRailCompact ? row : column
        return outer {
            inner { railNavigation }
            inner { railSettings }
        }
    }

    /// A screen too short for a column of six (an iPhone SE, say), or accessibility text, which needs the room.
    private var isRailCompact: Bool {
        dynamicTypeSize.isAccessibilitySize || (containerHeight > 0 && containerHeight < Self.shortScreenHeight)
    }

    private static var shortScreenHeight: CGFloat { 760 }

    /// Previous, next and sound.
    @ViewBuilder private var railNavigation: some View {
        // Previous and next Short: the same moves as the swipes, blocked while a panel is open.
        Button(action: showPreviousShort) {
            Image(systemName: AppSymbol.chevronUp)
                .font(.title3.weight(.semibold))
                .playerMediaControl(diameter: Self.railDiameter)
        }
        .disabled(isPanelOpen)
        .accessibilityLabel(Text("Previous Short", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.shortsPreviousButton)
        Button(action: showNextShort) {
            Image(systemName: AppSymbol.chevronDown)
                .font(.title3.weight(.semibold))
                .playerMediaControl(diameter: Self.railDiameter)
        }
        .disabled(isPanelOpen)
        .accessibilityLabel(Text("Next Short", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.shortsNextButton)
        Button(action: toggleMute) {
            Image(systemName: isMuted ? AppSymbol.muted : AppSymbol.speaker)
                .font(.title3)
                .playerMediaControl(diameter: Self.railDiameter, isActive: isMuted)
        }
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        .accessibilityValue(isMuted ? "Muted" : "Sound on")
        .accessibilityIdentifier(AccessibilityID.shortsMuteButton)
    }

    /// The Shorts speed, audio and translation, and Fit/Fill.
    @ViewBuilder private var railSettings: some View {
        Button {
            showSpeedPicker = true
        } label: {
            Text(speedValue)
                .font(.footnote.weight(.heavy))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .playerMediaControl(diameter: Self.railDiameter)
        }
        // Panels wait until a move to another Short has finished, which would otherwise close them.
        .disabled(isTransitioning)
        .accessibilityLabel("Playback Speed")
        .accessibilityValue(speedValue)
        .accessibilityIdentifier(AccessibilityID.shortsSpeedButton)
        .playerOptionPanelTrigger(.speed)
        Button {
            showAudioTrackPicker = true
        } label: {
            Image(systemName: AppSymbol.audioTrack)
                .font(.title3)
                .playerMediaControl(diameter: Self.railDiameter)
        }
        .disabled(isTransitioning)
        .accessibilityLabel("Audio Track")
        .accessibilityIdentifier(AccessibilityID.shortsAudioTrackButton)
        .playerOptionPanelTrigger(.audio)
        videoScaleButton
    }

    private static var railDiameter: CGFloat { 52 }

    private var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }
    #endif

    private var videoScaleButton: some View {
        Button {
            store.settings.videoGravityMode.toggle()
        } label: {
            videoScaleGlyph
        }
        .accessibilityLabel(Text("Video Fit", bundle: .module))
        .accessibilityValue(
            store.settings.videoGravityMode == .fill
                ? Text("Fill (crop)", bundle: .module) : Text("Fit (letterbox)", bundle: .module)
        )
        .accessibilityIdentifier(AccessibilityID.shortsVideoScaleButton)
    }

    @ViewBuilder private var videoScaleGlyph: some View {
        let glyph = Image(
            systemName: store.settings.videoGravityMode == .fill ? AppSymbol.videoFit : AppSymbol.videoFill)
        #if os(tvOS)
        glyph.frame(minWidth: 44, minHeight: 44)
        #else
        glyph
            .font(.title3)
            .playerMediaControl(diameter: Self.railDiameter)
        #endif
    }

    #if os(tvOS)
    private var tvShortsOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier(AccessibilityID.shortsBackButton)
                Spacer()
                indexLabel
                Button(action: toggleMute) {
                    Image(systemName: isMuted ? AppSymbol.muted : AppSymbol.speaker)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .accessibilityValue(isMuted ? "Muted" : "Sound on")
                .accessibilityIdentifier(AccessibilityID.shortsMuteButton)
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? AppSymbol.pause : AppSymbol.play)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(vm.isLoading || vm.error != nil)
                .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier(AccessibilityID.shortsPlayPauseButton)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .padding()
            .background(VFColor.scrim)

            PlayerTranslationStatus(vm: vm)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        showAudioTrackPicker = true
                    } label: {
                        Label("Audio Track", systemImage: AppSymbol.audioTrack)
                            .frame(minHeight: 44)
                    }
                    // Panels wait until a move to another Short has finished, which would otherwise close them.
                    .disabled(isTransitioning)
                    .accessibilityIdentifier(AccessibilityID.shortsAudioTrackButton)
                    Spacer()
                    Button {
                        showSpeedPicker = true
                    } label: {
                        Label {
                            Text(speedValue)
                        } icon: {
                            Image(systemName: AppSymbol.speedometer)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(isTransitioning)
                    .accessibilityLabel("Playback Speed")
                    .accessibilityValue(speedValue)
                    .accessibilityIdentifier(AccessibilityID.shortsSpeedButton)
                    videoScaleButton
                }
                .buttonStyle(.borderless)
                Text(vm.currentVideo?.title ?? "")
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.shortsTitleLabel)
                Text(vm.currentVideo?.channelTitle ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(formatDuration(vm.currentTime)) / \(formatDuration(vm.duration))")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier(AccessibilityID.shortsTimeLabel)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VFColor.scrim)
        }
        .foregroundStyle(VFColor.onMedia)
    }
    #endif

    #if os(iOS)
    var shortsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                // An open panel owns the touch: no switching to another Short behind it.
                guard !isTransitioning, !vm.isScrubbing, !isPanelOpen else { return }
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) else { return }
                let canMove = dy < 0 ? currentIndex + 1 < videos.count : currentIndex > 0
                slideOffset = canMove ? dy : dy * 0.15
            }
            .onEnded { value in
                guard !isTransitioning, !vm.isScrubbing, !isPanelOpen else { return }
                let dy = value.translation.height
                if let target = ShortsNavigation.targetIndex(
                    vertical: dy, horizontal: abs(value.translation.width),
                    current: currentIndex, count: videos.count
                ) {
                    performVerticalTransition(direction: dy < 0 ? -1 : 1) { goTo(target) }
                } else if dy > abs(value.translation.width), currentIndex == 0 {
                    loadMoreAtStart()
                } else {
                    snapBack()
                    if -dy > abs(value.translation.width), currentIndex == videos.count - 1 {
                        loadMoreIfNeeded(advanceWhenReady: true)
                    }
                }
            }
    }
    #endif
}

// MARK: - Shorts option panels

/// Shorts' own speed and audio panels, which read and write the Shorts settings, never the regular ones.
/// A sheet or popover on iOS and macOS; a full-height menu over the video on tvOS.
struct ShortsOptionPanels: ViewModifier {
    let vm: PlaybackViewModel
    @Binding var showAudioTrackPicker: Bool
    @Binding var showSpeedPicker: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.overlay {
            if showAudioTrackPicker {
                PlayerAudioTrackPicker(vm: vm, showAudioTrackPicker: $showAudioTrackPicker)
            }
            if showSpeedPicker {
                PlayerSpeedPicker(vm: vm, showSpeedPicker: $showSpeedPicker)
            }
        }
        #else
        // The rail is at the trailing edge, so the popovers open towards the video.
        content
            .playerOptionPanel(isPresented: $showAudioTrackPicker, trigger: .audio, arrowEdge: .leading) {
                PlayerAudioTrackPicker(vm: vm, showAudioTrackPicker: $showAudioTrackPicker)
            }
            .playerOptionPanel(isPresented: $showSpeedPicker, trigger: .speed, arrowEdge: .leading) {
                PlayerSpeedPicker(vm: vm, showSpeedPicker: $showSpeedPicker)
            }
        #endif
    }
}

#if os(iOS)
// MARK: - Shorts position slider

/// A UISlider, because SwiftUI's Slider cannot colour its unplayed track: here it is `VFColor.onMediaTrack`, as on
/// the regular timeline. It stays a real slider for VoiceOver and UI tests (`app.sliders[shortsSeekBar]`).
struct ShortsSeekSlider: UIViewRepresentable {
    let vm: PlaybackViewModel

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumTrackTintColor = UIColor(VFColor.onMedia)
        slider.maximumTrackTintColor = UIColor(VFColor.onMediaTrack)
        slider.accessibilityIdentifier = AccessibilityID.shortsSeekBar
        slider.accessibilityLabel = String(localized: "Playback position", bundle: .module)
        let coordinator = context.coordinator
        slider.addTarget(coordinator, action: #selector(Coordinator.began), for: .touchDown)
        slider.addTarget(coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(coordinator, action: #selector(Coordinator.ended), for: [.touchUpInside, .touchUpOutside])
        slider.addTarget(coordinator, action: #selector(Coordinator.ended), for: .touchCancel)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.vm = vm
        let position = vm.isScrubbing ? vm.scrubTime : vm.currentTime
        slider.maximumValue = Float(max(vm.duration, 1))
        if !slider.isTracking { slider.value = Float(position) }
        slider.isEnabled = vm.duration > 0 && !vm.isLoading && vm.error == nil
        slider.accessibilityValue = formatDuration(position)
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    /// Dragging scrubs and commits on release; a VoiceOver adjustment, which has no touches, seeks at once.
    @MainActor
    final class Coordinator: NSObject {
        var vm: PlaybackViewModel

        init(vm: PlaybackViewModel) { self.vm = vm }

        @objc func began() { vm.beginScrubbing() }

        @objc func changed(_ slider: UISlider) {
            if vm.isScrubbing {
                vm.updateScrub(to: Double(slider.value))
            } else {
                vm.seek(to: Double(slider.value))
            }
        }

        @objc func ended() { vm.commitScrub() }
    }
}
#endif
