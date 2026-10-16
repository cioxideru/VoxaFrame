import SmartTubeIOSCore
import SwiftUI

/// One audio and translation surface for the regular player and Shorts.
struct PlayerAudioTrackPicker: View {
    let vm: PlaybackViewModel
    @Binding var showAudioTrackPicker: Bool
    var maxWidth: CGFloat = .infinity
    @Environment(SettingsStore.self) private var store
    @State private var trackListHeight: CGFloat = 0
    #if os(tvOS)
    @Namespace private var audioTrackPickerNamespace
    @FocusState private var audioTrackPickerFocused: Bool
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showAudioTrackPicker = false }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { showAudioTrackPicker = false }
                        #if os(tvOS)
                    .buttonStyle(PickerHeaderButtonStyle())
                        #endif
                        .padding()
                    Spacer()
                    Text("Audio Track")
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 70, height: 44)
                }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // "Auto" row — resets this video to the HLS default track
                            Button {
                                vm.setVoiceOverForCurrentVideo(false)
                                vm.selectAudioTrack(nil)
                                showAudioTrackPicker = false
                            } label: {
                                HStack {
                                    Text("Auto")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if vm.selectedAudioTrack == nil {
                                        Image(systemName: AppSymbol.checkmark)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityID.playerAudioTrackPickerAuto)
                            #if os(tvOS)
                            .prefersDefaultFocus(in: audioTrackPickerNamespace)
                            #endif
                            Divider()
                            // Original first, then dubs — the list can hold ~25 languages.
                            ForEach(
                                vm.availableAudioTracks.filter(\.isOriginal)
                                    + vm.availableAudioTracks.filter { !$0.isOriginal }
                            ) { track in
                                Button {
                                    vm.setVoiceOverForCurrentVideo(false)
                                    vm.selectAudioTrack(track)
                                    showAudioTrackPicker = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.name)
                                                .foregroundStyle(.primary)
                                            if track.isOriginal {
                                                Text("Original")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if vm.selectedAudioTrack?.id == track.id {
                                            Image(systemName: AppSymbol.checkmark)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(AccessibilityID.playerAudioTrack(track.id))
                                .id(track.id)
                                Divider()
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            trackListHeight = $0
                        }
                    }
                    .onAppear {
                        if let selected = vm.selectedAudioTrack?.id { proxy.scrollTo(selected, anchor: .center) }
                    }
                }
                .frame(height: min(trackListHeight, 360))
                #if os(tvOS)
                .focused($audioTrackPickerFocused)
                #endif
                translationLanguagePicker
                if let target = vm.voiceOverTargetLanguage {
                    voiceOverControls(target: target)
                }
            }
            .frame(maxWidth: maxWidth)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.playerAudioTrackPicker)
            #if os(tvOS)
            .focusScope(audioTrackPickerNamespace)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                audioTrackPickerFocused = true
            }
            .onExitCommand { showAudioTrackPicker = false }
            #endif
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }

    // MARK: - Yandex voice-over controls (inside the audio track picker)

    /// Per-video translation into the default audio language from Settings, plus lively voices.
    @ViewBuilder private func voiceOverControls(target: String) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Yandex Translation → \(Locale.current.localizedString(forLanguageCode: target) ?? target)",
                isOn: Binding(
                    get: { vm.isVoiceOverActive },
                    set: { vm.setVoiceOverForCurrentVideo($0) }
                )
            )
            .accessibilityIdentifier(AccessibilityID.playerAudioTrackPickerVoiceOverToggle)
            if target == "ru" {
                Toggle(
                    "Lively Voices",
                    isOn: Binding(
                        get: { store.settings.yandexVOTLivelyVoice },
                        set: { isOn in
                            store.settings.yandexVOTLivelyVoice = isOn
                            vm.updateSettings(store.settings)
                            if vm.isVoiceOverActive { vm.restartVoiceOver() }
                        }
                    )
                )
                .accessibilityIdentifier(AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle)
            }
            Toggle(
                "Original Audio in Background",
                isOn: Binding(
                    get: { store.settings.yandexVOTKeepOriginalAudio },
                    set: { isOn in
                        store.settings.yandexVOTKeepOriginalAudio = isOn
                        vm.updateSettings(store.settings)
                        vm.voiceOver.keepsOriginalAudio = isOn
                    }
                )
            )
            .accessibilityIdentifier(AccessibilityID.playerAudioKeepOriginalAudioToggle)
            if let status = voiceOverStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var voiceOverStatus: String? {
        guard vm.voiceOver.videoId == vm.currentVideoId else { return nil }
        switch vm.voiceOver.state {
        case .idle: return nil
        case .waiting: return String(localized: "Yandex is translating the video…")
        case .playing(let livelyVoice):
            return livelyVoice
                ? String(localized: "Playing: lively voice") : String(localized: "Playing: classic voice")
        case .failed(let message): return message
        }
    }

    private var translationLanguagePicker: some View {
        Picker(
            "Default Audio Language",
            selection: Binding(
                get: { store.settings.preferredAudioLanguage },
                set: { language in
                    let wasActive = vm.isVoiceOverActive
                    store.settings.preferredAudioLanguage = language
                    vm.updateSettings(store.settings)
                    if wasActive { vm.restartVoiceOver() }
                }
            )
        ) {
            Text("Auto (System Default)").tag(nil as String?)
            if let language = store.settings.preferredAudioLanguage,
                !YandexVOTClient.targetLanguages.contains(language)
            {
                Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                    .tag(language as String?)
            }
            ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                    .tag(language as String?)
            }
        }
        .accessibilityIdentifier(AccessibilityID.playerTranslationLanguagePicker)
        .padding(.horizontal)
    }
}
