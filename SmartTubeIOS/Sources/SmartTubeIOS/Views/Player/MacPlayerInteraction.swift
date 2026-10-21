#if os(macOS)
import AppKit
import SmartTubeIOSCore
import SwiftUI

/// Input and cursor behavior for the existing video surface, in both windowed and system full screen.
struct MacPlayerInteraction: ViewModifier {
    let vm: PlaybackViewModel
    let hasOpenPanel: Bool
    let focused: FocusState<Bool>.Binding
    @Environment(MacWindowState.self) private var windowState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var pointerInside = false
    @State private var active = false
    @State private var lastControlsReveal: ContinuousClock.Instant?

    private var keepsControlsVisible: Bool { !vm.isPlaying || hasOpenPanel || voiceOverEnabled }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focused)
            .onKeyPress(phases: .down) { press in handleKey(press) }
            // The Playback menu: published only while the video surface has focus, like the keys above.
            .focusedValue(\.macPlayback, active && !hasOpenPanel ? playbackTarget : nil)
            .onContinuousHover { phase in
                guard active else { return }
                switch phase {
                case .active:
                    if !pointerInside { pointerInside = true }
                    revealControls(throttled: true)
                case .ended:
                    pointerInside = false
                    NSCursor.setHiddenUntilMouseMoves(false)
                }
            }
            .onAppear {
                active = true
                focused.wrappedValue = true
                revealControls()
            }
            .onDisappear {
                active = false
                focused.wrappedValue = false
                pointerInside = false
                NSCursor.setHiddenUntilMouseMoves(false)
            }
            .onChange(of: windowState.isImmersive) { _, _ in
                guard active else { return }
                focused.wrappedValue = true
                revealControls()
            }
            .onChange(of: focused.wrappedValue) { _, value in
                if value { revealControls() }
            }
            .onChange(of: keepsControlsVisible) { _, _ in revealControls() }
            .onChange(of: vm.controlsVisible) { _, visible in
                if !visible && keepsControlsVisible { revealControls() }
                updateCursor()
            }
    }

    private var playbackTarget: MacPlaybackTarget {
        MacPlaybackTarget(
            vm: vm, seekBackSeconds: Double(settings.settings.seekBackSeconds),
            seekForwardSeconds: Double(settings.settings.seekForwardSeconds))
    }

    private func revealControls(throttled: Bool = false) {
        guard active else { return }
        NSCursor.setHiddenUntilMouseMoves(false)
        let now = ContinuousClock.now
        if throttled, vm.controlsVisible, let lastControlsReveal,
            lastControlsReveal.duration(to: now) < PlaybackTuning.macControlsHoverThrottle
        {
            return
        }
        lastControlsReveal = now
        vm.showControls()
        if keepsControlsVisible { vm.cancelControlsHide() }
    }

    private func updateCursor() {
        guard active else { return }
        let hidden =
            windowState.isImmersive && windowState.window?.isKeyWindow == true
            && pointerInside && !vm.controlsVisible && !keepsControlsVisible
        NSCursor.setHiddenUntilMouseMoves(hidden)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Text fields, sliders and popovers keep their normal key handling; commands apply to the focused video.
        guard active, !hasOpenPanel,
            press.modifiers.isDisjoint(with: [.command, .control, .option, .shift])
        else { return .ignored }
        switch press.key {
        case .space: vm.togglePlayPause()
        case .leftArrow: vm.seekRelative(seconds: -Double(settings.settings.seekBackSeconds))
        case .rightArrow: vm.seekRelative(seconds: Double(settings.settings.seekForwardSeconds))
        case "f", "F": windowState.toggleFullScreen()
        case .escape:
            guard windowState.isFullScreen else { return .ignored }
            windowState.exitFullScreen()
        default:
            revealControls()
            return .ignored
        }
        revealControls()
        return .handled
    }
}

/// The same gesture sits behind the controls and on the bare video, so double-click works in either state.
struct MacPlayerClickSurface: View {
    let vm: PlaybackViewModel
    let focused: FocusState<Bool>.Binding
    @Environment(MacWindowState.self) private var windowState

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2).exclusively(before: TapGesture())
                    .onEnded { gesture in
                        focused.wrappedValue = true
                        switch gesture {
                        case .first: windowState.toggleFullScreen()
                        case .second:
                            guard !vm.hasVisibleEndCards else { return }
                            if vm.isPlaying { vm.toggleControls() } else { vm.showControls() }
                        }
                    }
            )
    }
}

extension PlayerControlsOverlay {
    var macFullScreenButton: some View {
        Button {
            macWindow.toggleFullScreen()
        } label: {
            Image(systemName: macWindow.isFullScreen ? AppSymbol.exitFullScreen : AppSymbol.enterFullScreen)
                .font(.system(size: 18 * controlScale))
                .playerMediaControl(diameter: VFTarget.touch * controlScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(macWindow.fullScreenTitle)
        .help(macWindow.fullScreenTitle)
        .accessibilityIdentifier(AccessibilityID.playerFullScreenButton)
    }
}
#endif
