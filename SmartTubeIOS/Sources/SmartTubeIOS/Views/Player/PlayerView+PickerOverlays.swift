import AVKit
import SmartTubeIOSCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private let pickerLog = ViewModelLogger(category: "PlayerMenu")

// MARK: - PlayerView option panels + share sheet
//
// The media settings panels (VF/PlaybackOptions). Their container is in PlayerOptionPanel.swift: a sheet or
// popover on iOS and macOS (`playerContentView`), a full-height menu inside the player's ZStack on tvOS
// (`overlayStack`), where the Siri Remote focus and Back handling need the panel in the player's own tree.
//
// Includes:
//   • qualityPickerOverlay       — video quality selection
//   • speedPickerOverlay         — playback speed selection
//   • sleepTimerPickerOverlay    — sleep timer duration
//   • captionPickerOverlay       — subtitle/caption track selection
//   • audioTrackPickerOverlay    — audio track and translation
//   • presentShareSheet(url:)    — UIActivityViewController (iOS only)

extension PlayerView {

    /// The player with its option panels attached. tvOS draws them in `overlayStack` instead.
    @ViewBuilder var playerContentView: some View {
        #if os(tvOS)
        playerContentBase
        #else
        let panels =
            playerContentWithMoreMenu
            .playerOptionPanel(isPresented: $showSpeedPicker, trigger: .speed) { speedPickerOverlay }
            .playerOptionPanel(isPresented: $showQualityPicker, trigger: .quality) { qualityPickerOverlay }
            .playerOptionPanel(isPresented: $showCaptionPicker, trigger: nil) { captionPickerOverlay }
            .playerOptionPanel(isPresented: $showAudioTrackPicker, trigger: .audio) { audioTrackPickerOverlay }
            .playerOptionPanel(isPresented: $showSleepTimerPicker, trigger: .sleepTimer) { sleepTimerPickerOverlay }
            // The controls stay while a panel is open, so its popover keeps pointing at the button that opened it;
            // closing the last panel starts the hide timer again.
            .onChange(of: isOptionPanelOpen) { _, open in
                vm.showControls()
                if open { vm.cancelControlsHide() }
            }
            // Playback can restart the hide timer under an open panel (the first frame after loading, say), so a
            // hide that fires then is undone at once.
            .onChange(of: vm.controlsVisible) { _, visible in
                guard !visible, isOptionPanelOpen else { return }
                vm.showControls()
                vm.cancelControlsHide()
            }
        #if os(iOS)
        // Leaving full screen (mini-player, PiP, stop) closes the panels with the player.
        panels.onChange(of: playerState.presentation) { _, presentation in
            if presentation != .fullScreen { closeOptionPanels() }
        }
        #else
        panels
        #endif
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder private var playerContentWithMoreMenu: some View {
        #if os(iOS)
        playerContentBase
            .playerOptionPanel(isPresented: $showMoreMenu, trigger: .more, onDismiss: moreMenuDidDismiss) {
                moreMenuPanel
            }
        #else
        playerContentBase
        #endif
    }

    private var isOptionPanelOpen: Bool {
        let pickerOpen =
            showSpeedPicker || showQualityPicker || showCaptionPicker || showAudioTrackPicker || showSleepTimerPicker
        #if os(iOS)
        return pickerOpen || showMoreMenu || moreMenuDestination != nil
        #else
        return pickerOpen
        #endif
    }
    #endif

    #if os(iOS)
    private func closeOptionPanels() {
        moreMenuDestination = nil
        showMoreMenu = false
        showSpeedPicker = false
        showQualityPicker = false
        showCaptionPicker = false
        showAudioTrackPicker = false
        showSleepTimerPicker = false
    }
    #endif

    // MARK: - Quality picker overlay

    private func selectAndRememberQuality(_ format: VideoFormat?) {
        vm.selectFormat(format)
        store.settings.lastVideoQuality = vm.settings.lastVideoQuality
    }

    /// Lists Auto and the formats this video actually has. The checkmark is the user's choice, which is
    /// remembered for the next videos.
    var qualityPickerOverlay: some View {
        let panel = PlayerOptionPanel(title: Text("Quality", bundle: .module), isPresented: $showQualityPicker) {
            qualityChoices
        }
        .accessibilityIdentifier(AccessibilityID.playerQualityPicker)
        .task {
            // Fix 2A: pre-warm all quality tiers the moment the picker opens so that
            // by the time the user taps a resolution, tracks are cached (< 100ms switch).
            await vm.prefetchAllQualityTracks()
        }
        #if os(tvOS)
        return
            panel
            .focusScope(qualityPickerNamespace)
            .onExitCommand {
                pickerLog.notice("[qualityPicker] onExitCommand fired — dismissing")
                showQualityPicker = false
            }
        #else
        return panel
        #endif
    }

    @ViewBuilder private var qualityChoices: some View {
        let scroll = ScrollView {
            VStack(spacing: 0) {
                let auto = PlayerOptionRow(title: Text("Auto", bundle: .module), isSelected: vm.selectedFormat == nil) {
                    pickerLog.notice(
                        "[qualityPicker] selected Auto (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))")
                    selectAndRememberQuality(nil)
                    showQualityPicker = false
                    qualityToastMessage = "Auto quality"
                }
                .accessibilityIdentifier(AccessibilityID.playerQualityPickerAuto)
                #if os(tvOS)
                auto.prefersDefaultFocus(in: qualityPickerNamespace)
                #else
                auto
                #endif
                Divider()
                ForEach(vm.availableFormats) { fmt in
                    let name =
                        fmt.codecShortLabel.isEmpty ? fmt.qualityLabel : "\(fmt.qualityLabel) · \(fmt.codecShortLabel)"
                    PlayerOptionRow(title: Text(name), isSelected: vm.selectedFormat?.id == fmt.id) {
                        pickerLog.notice(
                            "[qualityPicker] selected \(fmt.qualityLabel) (was: \(vm.selectedFormat?.qualityLabel ?? "Auto"))"
                        )
                        selectAndRememberQuality(fmt)
                        showQualityPicker = false
                        qualityToastMessage = "\(fmt.qualityLabel) · may take up to 30s"
                    }
                    // The label starts with the quality, so XCTest queries like `label BEGINSWITH "720p"` keep
                    // working; the codec follows for VoiceOver.
                    .accessibilityLabel(
                        fmt.codecShortLabel.isEmpty ? fmt.qualityLabel : "\(fmt.qualityLabel), \(fmt.codecShortLabel)")
                    Divider()
                }
            }
        }
        #if os(tvOS)
        scroll
            .prefersDefaultFocus(in: qualityPickerNamespace)
            .focused($qualityPickerFocused)
        #else
        scroll
        #endif
    }

    // MARK: - Speed picker overlay

    var speedPickerOverlay: some View {
        PlayerSpeedPicker(vm: vm, showSpeedPicker: $showSpeedPicker)
    }

    // MARK: - Sleep timer picker overlay

    var sleepTimerPickerOverlay: some View {
        let panel = PlayerOptionPanel(title: Text("Sleep Timer", bundle: .module), isPresented: $showSleepTimerPicker) {
            ScrollView {
                VStack(spacing: 0) {
                    let off = PlayerOptionRow(
                        title: Text("Off", bundle: .module), isSelected: vm.sleepTimerMinutes == nil
                    ) {
                        vm.setSleepTimer(minutes: nil)
                        showSleepTimerPicker = false
                    }
                    #if os(tvOS)
                    off
                        .prefersDefaultFocus(in: sleepTimerNamespace)
                        .focused($sleepTimerPickerFocused)
                    #else
                    off
                    #endif
                    Divider()
                    ForEach(PlaybackViewModel.sleepTimerOptions, id: \.self) { mins in
                        PlayerOptionRow(
                            title: Text("\(mins) min", bundle: .module), isSelected: vm.sleepTimerMinutes == mins
                        ) {
                            vm.setSleepTimer(minutes: mins)
                            showSleepTimerPicker = false
                        }
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.playerSleepTimerPicker)
        #if os(tvOS)
        return
            panel
            .focusScope(sleepTimerNamespace)
            .onExitCommand {
                pickerLog.notice("[sleepTimerPicker] onExitCommand fired — dismissing")
                showSleepTimerPicker = false
            }
        #else
        return panel
        #endif
    }

    // MARK: - Caption picker overlay

    var captionPickerOverlay: some View {
        let panel = PlayerOptionPanel(title: Text("Captions", bundle: .module), isPresented: $showCaptionPicker) {
            captionChoices
        }
        .accessibilityIdentifier(AccessibilityID.playerCaptionPicker)
        #if os(tvOS)
        return
            panel
            .focusScope(captionPickerNamespace)
            .onExitCommand { showCaptionPicker = false }
        #else
        return panel
        #endif
    }

    @ViewBuilder private var captionChoices: some View {
        let scroll = ScrollView {
            VStack(spacing: 0) {
                // Off row
                let off = PlayerOptionRow(title: Text("Off", bundle: .module), isSelected: vm.selectedCaption == nil) {
                    vm.selectCaption(nil)
                    showCaptionPicker = false
                }
                .accessibilityIdentifier(AccessibilityID.playerCaptionPickerOff)
                #if os(tvOS)
                off.prefersDefaultFocus(in: captionPickerNamespace)
                #else
                off
                #endif
                Divider()
                ForEach(vm.availableCaptions) { track in
                    PlayerOptionRow(
                        title: Text(track.name),
                        detail: track.isAutoGenerated ? Text("Auto-generated") : nil,
                        isSelected: vm.selectedCaption?.id == track.id
                    ) {
                        vm.selectCaption(track)
                        showCaptionPicker = false
                    }
                    .accessibilityIdentifier(AccessibilityID.playerCaptionPickerTrack(track.id))
                    Divider()
                }
            }
        }
        #if os(tvOS)
        scroll.focused($captionPickerFocused)
        #else
        scroll
        #endif
    }

    // MARK: - Audio track picker overlay

    var audioTrackPickerOverlay: some View {
        PlayerAudioTrackPicker(vm: vm, showAudioTrackPicker: $showAudioTrackPicker)
    }

    // MARK: - Share sheet

    #if os(iOS)
    func presentShareSheet(url: URL) {
        let wasPlaying = vm.isPlaying
        vm.suspend()
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.view.accessibilityIdentifier = AccessibilityID.playerShareSheet
        vc.completionWithItemsHandler = { _, _, _, _ in
            if wasPlaying { vm.resume() }
        }
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        // On iPad, UIActivityViewController must have a popover source or UIKit crashes.
        if let popover = vc.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(
                x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
    #endif
}

#if os(tvOS)
// MARK: - PickerHeaderButtonStyle (tvOS)

/// Flat style for the Cancel button in picker sheet headers. The default tvOS
/// button style renders a bright white platter that clashes with the dark
/// sheet material; this shows a gray highlight when focused instead, matching
/// the more-menu row treatment.
struct PickerHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PickerHeaderButtonLabel(configuration: configuration)
    }

    private struct PickerHeaderButtonLabel: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isFocused ? Color.gray.opacity(0.35) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif
