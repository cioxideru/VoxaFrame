import SmartTubeIOSCore
import SwiftUI

#if !os(tvOS)
// MARK: - Quick-access row (iOS and macOS)
//
// Compact pill buttons giving one-tap access to speed, quality, audio track,
// and sleep-timer pickers without opening the 3-dot more menu.
// Surfaced directly below the progress bar as requested in GitHub issue #52.
extension PlayerControlsOverlay {

    @ViewBuilder var quickAccessButtonRow: some View {
        HStack(spacing: 8) {
            quickAccessButton(
                systemImage: AppSymbol.speedometer,
                label: speedLabel,
                accessibilityId: "player.quickAccess.speed"
            ) { showSpeedPicker = true }

            if !vm.isAudioOnlyMode {
                quickAccessButton(
                    systemImage: AppSymbol.videoQuality,
                    label: qualityLabel,
                    accessibilityId: "player.quickAccess.quality"
                ) { showQualityPicker = true }
                .disabled(vm.availableFormats.isEmpty)
                .opacity(vm.availableFormats.isEmpty ? 0.4 : 1)
            }

            if vm.availableAudioTracks.count > 1 || vm.voiceOverTargetLanguage != nil {
                quickAccessButton(
                    systemImage: AppSymbol.audioTrack,
                    label: audioTrackLabel,
                    accessibilityId: "player.quickAccess.audioTrack"
                ) { showAudioTrackPicker = true }
            }

            quickAccessButton(
                systemImage: AppSymbol.sleepTimer,
                label: sleepTimerLabel,
                accessibilityId: "player.quickAccess.sleepTimer"
            ) { showSleepTimerPicker = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.playerQuickAccessRow)
    }

    // MARK: - Quick-access label helpers

    private var speedLabel: String {
        store.settings.playbackSpeed == 1.0
            ? "Normal"
            : String(format: "%.2g", store.settings.playbackSpeed) + "×"
    }

    private var qualityLabel: String {
        vm.selectedFormat?.qualityLabel
            ?? (vm.pendingQualityLabel.isEmpty ? "Auto" : vm.pendingQualityLabel)
    }

    private var audioTrackLabel: String {
        let track = vm.selectedAudioTrack.map { $0.languageCode } ?? "Auto"
        guard vm.isVoiceOverActive, let target = vm.voiceOverTargetLanguage else { return track }
        return "\(track) → \(target) (Yandex)"
    }

    private var sleepTimerLabel: String {
        vm.sleepTimerMinutes.map { "\($0) min" } ?? "Off"
    }

    // MARK: - Single pill button

    @ViewBuilder
    private func quickAccessButton(
        systemImage: String,
        label: String,
        accessibilityId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .lineLimit(1)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }
}
#endif
