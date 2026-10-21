import SmartTubeIOSCore
import SwiftUI

// MARK: - Quick-access row (iOS and macOS)
//
// Glass capsules with the current value — speed, quality, audio, offline — that open their option panel
// without the 3-dot more menu (GitHub issue #52). On TV these live in the menu.
extension PlayerControlsOverlay {
    @ViewBuilder var videoScaleButton: some View {
        let isFilled = store.settings.videoGravityMode == .fill
        let symbol = isFilled ? AppSymbol.videoFit : AppSymbol.videoFill
        Group {
            #if os(tvOS)
            tvOverlayControl(
                highlighted: highlightedControl == .videoScale,
                scale: 1.5, shadowRadius: 12,
                identifier: AccessibilityID.playerVideoScaleButton,
                width: 64, height: 64
            ) {
                Image(systemName: symbol)
                    .font(.system(size: 18 * controlScale))
                    .foregroundStyle(VFColor.onMedia)
            }
            #else
            Button {
                store.settings.videoGravityMode.toggle()
                vm.showControls()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 18 * controlScale))
                    .playerMediaControl(diameter: VFTarget.touch * controlScale)
            }
            .buttonStyle(.plain)
            .playerIconControl(Text("Video Fit", bundle: .module), symbol: symbol)
            .accessibilityIdentifier(AccessibilityID.playerVideoScaleButton)
            #endif
        }
        .accessibilityLabel(Text("Video Fit", bundle: .module))
        .accessibilityValue(
            isFilled ? Text("Fill (crop)", bundle: .module) : Text("Fit (letterbox)", bundle: .module))
    }

    #if !os(tvOS)

    /// The setting pills; the caller places them in its own row.
    @ViewBuilder var quickAccessButtons: some View {
        HStack(spacing: VFSpace.s8) {
            quickAccessButton(
                systemImage: AppSymbol.speedometer,
                label: PlayerSpeedPicker.label(for: store.settings.playbackSpeed),
                accessibilityLabel: Text("Playback Speed", bundle: .module),
                accessibilityId: AccessibilityID.playerQuickSpeedButton
            ) { showSpeedPicker = true }
            .playerOptionPanelTrigger(.speed)

            if !vm.isAudioOnlyMode {
                quickAccessButton(
                    systemImage: AppSymbol.videoQuality,
                    label: qualityLabel,
                    accessibilityLabel: Text("Quality", bundle: .module),
                    accessibilityId: AccessibilityID.playerQuickQualityButton
                ) { showQualityPicker = true }
                .disabled(vm.availableFormats.isEmpty)
                .opacity(vm.availableFormats.isEmpty ? 0.4 : 1)
                .playerOptionPanelTrigger(.quality)
            }

            if vm.hasAudioOptions {
                quickAccessButton(
                    systemImage: AppSymbol.audioTrack,
                    label: audioTrackLabel,
                    accessibilityLabel: Text("Audio Track", bundle: .module),
                    accessibilityId: AccessibilityID.playerQuickAudioButton
                ) { showAudioTrackPicker = true }
                .playerOptionPanelTrigger(.audio)
            }

            offlineQuickButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.playerQuickAccessRow)
    }

    // MARK: - Quick-access label helpers

    /// The user's choice (Auto or a quality), kept while a fallback stream plays.
    private var qualityLabel: String {
        vm.selectedFormat?.qualityLabel
            ?? (vm.pendingQualityLabel.isEmpty ? String(localized: "Auto", bundle: .module) : vm.pendingQualityLabel)
    }

    private var audioTrackLabel: String {
        let track =
            vm.selectedAudioTrack.map { $0.hasKnownLanguage ? $0.languageCode : $0.name }
            ?? String(localized: "Auto", bundle: .module)
        guard vm.isVoiceOverActive, let target = vm.voiceOverTargetLanguage else { return track }
        return "\(track) → \(target) (Yandex)"
    }

    /// Same action and sheet as the former More-menu row; disabled when the video cannot be saved or already is.
    private var offlineQuickButton: some View {
        let current = vm.currentVideo ?? video
        let snapshot = OfflineCoordinator.shared.snapshot
        let action = OfflinePresentation.quickAction(video: current, entries: snapshot.entries, jobs: snapshot.jobs)
        let label =
            switch action {
            case .saved: String(localized: "Saved", bundle: .module)
            case .queued: String(localized: "Queued", bundle: .module)
            case .offline, .unavailable: String(localized: "Offline", bundle: .module)
            }
        return quickAccessButton(
            systemImage: AppSymbol.download,
            label: label,
            accessibilityLabel: Text("Offline watch", bundle: .module),
            accessibilityId: AccessibilityID.playerQuickOfflineButton
        ) { offlineDownloadVideo = current }
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.4)
    }

    // MARK: - Single pill button

    /// VoiceOver hears the setting, then the value shown ("Quality, 720p"); the label keeps the value
    /// so it can be matched in UI tests.
    @ViewBuilder
    private func quickAccessButton(
        systemImage: String,
        label: String,
        accessibilityLabel: Text,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .lineLimit(1)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VFColor.onMedia)
                .padding(.horizontal, VFSpace.s12)
                .frame(minHeight: Self.quickAccessTarget)
                .vfGlass()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel + Text(verbatim: ", \(label)"))  // verbatim: the value shown, localized
        .accessibilityIdentifier(accessibilityId)
    }

    private static var quickAccessTarget: CGFloat {
        #if os(macOS)
        VFTarget.pointer
        #else
        VFTarget.touch
        #endif
    }
    #endif
}
