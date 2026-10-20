import SmartTubeIOSCore
import SwiftUI

/// One audio and translation surface for the regular player and Shorts.
/// YouTube's own tracks (Auto, Original, dubs) and Yandex voice-over have separate groups.
/// The whole panel scrolls, so its toggles stay reachable at the medium detent and at large text sizes.
struct PlayerAudioTrackPicker: View {
    let vm: PlaybackViewModel
    @Binding var showAudioTrackPicker: Bool
    @Environment(SettingsStore.self) private var store
    #if os(tvOS)
    @Namespace private var audioTrackPickerNamespace
    @FocusState private var audioTrackPickerFocused: Bool
    #endif

    var body: some View {
        let panel = PlayerOptionPanel(title: Text("Audio Track", bundle: .module), isPresented: $showAudioTrackPicker) {
            panelScroll
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.playerAudioTrackPicker)
        #if os(tvOS)
        panel
            .focusScope(audioTrackPickerNamespace)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                audioTrackPickerFocused = true
            }
            .onExitCommand { showAudioTrackPicker = false }
        #else
        panel
        #endif
    }

    @ViewBuilder private var panelScroll: some View {
        let scroll = ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "YouTube")  // verbatim: provider brand
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding()
                        trackRows
                    }
                    .accessibilityElement(children: .contain)
                    translationSection
                }
            }
            .onAppear {
                if let selected = vm.selectedAudioTrack?.id { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        #if os(tvOS)
        scroll.focused($audioTrackPickerFocused)
        #else
        scroll
        #endif
    }

    // MARK: - The video's own tracks

    @ViewBuilder private var trackRows: some View {
        // "Auto" row — resets this video to the HLS default track
        let auto = PlayerOptionRow(title: Text("Auto", bundle: .module), isSelected: vm.selectedAudioTrack == nil) {
            vm.setVoiceOverForCurrentVideo(false)
            vm.selectAudioTrack(nil)
            showAudioTrackPicker = false
        }
        .accessibilityIdentifier(AccessibilityID.playerAudioTrackPickerAuto)
        #if os(tvOS)
        auto.prefersDefaultFocus(in: audioTrackPickerNamespace)
        #else
        auto
        #endif
        Divider()
        // Original first, then dubs — the list can hold ~25 languages.
        ForEach(
            vm.availableAudioTracks.filter(\.isOriginal)
                + vm.availableAudioTracks.filter { !$0.isOriginal }
        ) { track in
            // Choosing a track turns a forced translation off for this video.
            PlayerOptionRow(
                title: Text(track.name),
                detail: track.isOriginal ? Text("Original") : nil,
                isSelected: vm.selectedAudioTrack?.id == track.id
            ) {
                vm.setVoiceOverForCurrentVideo(false)
                vm.selectAudioTrack(track)
                showAudioTrackPicker = false
            }
            .accessibilityIdentifier(AccessibilityID.playerAudioTrack(track.id))
            .id(track.id)
            Divider()
        }
    }

    // MARK: - Yandex voice-over controls (inside the audio track picker)

    private var translationSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translation · Yandex", bundle: .module)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LabeledContent {
                    translationLanguagePicker.labelsHidden()
                } label: {
                    Text("Translation language", bundle: .module)
                }
                if let target = vm.voiceOverTargetLanguage {
                    voiceOverControls(target: target)
                }
            }
            .padding()
            PlayerTranslationStatus(vm: vm, overVideo: false)
        }
        .accessibilityElement(children: .contain)
    }

    /// Per-video translation into the default audio language from Settings, plus lively voices.
    @ViewBuilder private func voiceOverControls(target: String) -> some View {
        let livelyVoiceKey = vm.isShortsPlayer ? \AppSettings.shortsYandexVOTLivelyVoice : \.yandexVOTLivelyVoice
        let originalAudioKey =
            vm.isShortsPlayer ? \AppSettings.shortsYandexVOTKeepOriginalAudio : \.yandexVOTKeepOriginalAudio
        Group {
            Toggle(
                "Yandex Translation → \(Locale.current.localizedString(forLanguageCode: target) ?? target)",
                isOn: Binding(
                    get: { vm.isVoiceOverActive },
                    set: { vm.setVoiceOverForCurrentVideo($0) }
                )
            )
            .accessibilityIdentifier(AccessibilityID.playerAudioTrackPickerVoiceOverToggle)
            if vm.currentVideo?.isDownloaded == true {
                Text(
                    "Saved translations play without internet. A new live translation needs internet and is not saved; download it in Offline videos for later.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if target == "ru" {
                Toggle(
                    "Lively Voices",
                    isOn: Binding(
                        get: { store.settings[keyPath: livelyVoiceKey] },
                        set: { isOn in
                            store.settings[keyPath: livelyVoiceKey] = isOn
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
                    get: { store.settings[keyPath: originalAudioKey] },
                    set: { isOn in
                        store.settings[keyPath: originalAudioKey] = isOn
                        vm.updateSettings(store.settings)
                        vm.voiceOver.keepsOriginalAudio = isOn
                    }
                )
            )
            .accessibilityIdentifier(AccessibilityID.playerAudioKeepOriginalAudioToggle)
            if let status = playingStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The playing voice; preparing and failed have their own actions in the translation section.
    private var playingStatus: String? {
        guard vm.voiceOver.videoId == vm.currentVideoId, case .playing(let livelyVoice) = vm.voiceOver.state else {
            return nil
        }
        return livelyVoice
            ? String(localized: "Playing: lively voice") : String(localized: "Playing: classic voice")
    }

    private var translationLanguagePicker: some View {
        let languageKey = vm.isShortsPlayer ? \AppSettings.shortsPreferredAudioLanguage : \.preferredAudioLanguage
        return Picker(
            selection: Binding(
                get: { store.settings[keyPath: languageKey] },
                set: { language in
                    let wasActive = vm.isVoiceOverActive
                    store.settings[keyPath: languageKey] = language
                    vm.updateSettings(store.settings)
                    if wasActive { vm.restartVoiceOver() }
                }
            )
        ) {
            Text("Auto (System Default)").tag(nil as String?)
            if let language = store.settings[keyPath: languageKey],
                !YandexVOTClient.targetLanguages.contains(language)
            {
                Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                    .tag(language as String?)
            }
            ForEach(YandexVOTClient.targetLanguages.sorted(), id: \.self) { language in
                Text(Locale.current.localizedString(forLanguageCode: language) ?? language)
                    .tag(language as String?)
            }
        } label: {
            Text("Translation language", bundle: .module)
        }
        .accessibilityIdentifier(AccessibilityID.playerTranslationLanguagePicker)
        .frame(minHeight: VFTarget.touch)
    }
}
