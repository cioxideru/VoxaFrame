import SmartTubeIOSCore
import SwiftUI

// MARK: - PlayerTranslationStatus (VF/TranslationStatus)
//
// The Yandex voice-over states that need the user: preparing, with Watch Without Translation, and failed,
// with Retry and the same way back to the original audio. Off and playing are shown by the audio button and
// the panel's toggle and status line. Preparing is not buffering: it has its own text and an exit.
// The OAuth token never appears here; a failure shows the controller's message only.

struct PlayerTranslationStatus: View {
    let vm: PlaybackViewModel
    /// Over video: a glass plate with `onMedia` text. In the audio panel: plain, on the panel's background.
    var overVideo = true

    private enum Phase: Equatable {
        case preparing(remainingSeconds: Int?)
        case failed(String)
    }

    /// Only the state of the video on screen; a previous video's state is never shown.
    private var phase: Phase? {
        guard vm.voiceOver.videoId == vm.currentVideoId else { return nil }
        switch vm.voiceOver.state {
        case .waiting(let remaining): return .preparing(remainingSeconds: remaining)
        case .failed(let message): return .failed(message)
        case .idle, .playing: return nil
        }
    }

    var body: some View {
        if let phase {
            let plate = VStack(alignment: .leading, spacing: VFSpace.s8) {
                HStack(alignment: .top, spacing: VFSpace.s12) {
                    icon(phase)
                    VStack(alignment: .leading, spacing: 2) {
                        title(phase)
                            .font(.subheadline.weight(.semibold))
                        if let detail = detail(phase) {
                            detail
                                .font(.footnote)
                                .foregroundStyle(
                                    overVideo ? AnyShapeStyle(VFColor.onMedia.opacity(0.85)) : AnyShapeStyle(.secondary)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: VFSpace.s8) {
                    Spacer(minLength: 0)
                    if case .failed = phase {
                        actionButton(Text("Try Again", bundle: .module), primary: false) {
                            vm.setVoiceOverForCurrentVideo(true)
                        }
                    }
                    watchWithoutTranslationButton
                }
            }
            .padding(overVideo ? VFSpace.s12 : VFSpace.s16)
            .accessibilityElement(children: .contain)
            if overVideo {
                plate
                    .foregroundStyle(VFColor.onMedia)
                    .vfGlass(in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: 520)
            } else {
                plate
            }
        }
    }

    @ViewBuilder private func icon(_ phase: Phase) -> some View {
        switch phase {
        case .preparing:
            ProgressView()
                .tint(overVideo ? VFColor.onMedia : nil)
        case .failed:
            Image(systemName: AppSymbol.warning)
                .foregroundStyle(overVideo ? VFColor.onMedia : VFColor.warning)
                .accessibilityHidden(true)
        }
    }

    private func title(_ phase: Phase) -> Text {
        switch phase {
        case .preparing:
            if let language = vm.voiceOverTargetLanguage {
                let name = Locale.current.localizedString(forLanguageCode: language) ?? language
                return Text("Preparing translation · \(name)", bundle: .module)
            }
            return Text("Yandex is translating the video…", bundle: .module)
        case .failed:
            return Text("Translation unavailable", bundle: .module)
        }
    }

    /// The estimate is approximate, so it is only ever "about N minutes".
    private func detail(_ phase: Phase) -> Text? {
        switch phase {
        case .preparing(let remaining):
            guard let remaining, remaining > 0 else { return nil }
            return Text("~\(max(1, remaining / 60)) min", bundle: .module)
        case .failed(let message):
            return Text(verbatim: message)  // verbatim: the view model's failure message, a finished sentence
        }
    }

    @ViewBuilder private var watchWithoutTranslationButton: some View {
        let button = actionButton(Text("Watch Without Translation", bundle: .module), primary: true) {
            vm.setVoiceOverForCurrentVideo(false)
        }
        // One identifier: the panel's copy is reached through the panel instead.
        if overVideo {
            button.accessibilityIdentifier(AccessibilityID.playerVoiceOverCancelButton)
        } else {
            button
        }
    }

    /// Over video: the player's media action (a white capsule on iPhone, iPad and Mac; system buttons on TV).
    @ViewBuilder
    private func actionButton(_ label: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        if overVideo {
            PlayerMediaActionButton(title: label, primary: primary, action: action)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
        }
    }
}
