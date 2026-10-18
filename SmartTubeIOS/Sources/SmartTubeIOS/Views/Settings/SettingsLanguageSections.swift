import SmartTubeIOSCore
import SwiftUI

// MARK: - SettingsLanguageSections
//
// "Languages and translation" (functional brief §15.2): two independent blocks, regular videos and Shorts,
// then the one Yandex token both blocks share. Rows of a `Form`, placed by `SettingsView`.

struct SettingsLanguageSections: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        yandexVOTSection
        shortsTranslationSection
        if (store.settings.yandexVOTEnabled && store.settings.yandexVOTLivelyVoice)
            || (store.settings.shortsYandexVOTEnabled && store.settings.shortsYandexVOTLivelyVoice)
        {
            SettingsYandexTokenSection()
        }
    }

    private var yandexVOTSection: some View {
        @Bindable var store = store
        return Section {
            audioLanguagePicker(selection: $store.settings.preferredAudioLanguage)
                .accessibilityIdentifier(AccessibilityID.settingsPreferredAudioLanguageRow)
            Toggle("Yandex Voice-Over Translation", isOn: $store.settings.yandexVOTEnabled)
                .accessibilityIdentifier(AccessibilityID.settingsYandexVOTToggle)
            if store.settings.yandexVOTEnabled {
                Toggle("Lively Voices", isOn: $store.settings.yandexVOTLivelyVoice)
                    .accessibilityIdentifier(AccessibilityID.settingsYandexVOTLivelyVoiceToggle)
                Toggle("Original Audio in Background", isOn: $store.settings.yandexVOTKeepOriginalAudio)
                    .accessibilityIdentifier(AccessibilityID.settingsYandexVOTKeepOriginalAudioToggle)
            }
        } header: {
            Text("Audio Language")
        } footer: {
            Text(
                "The video's original or dubbed track in this language is played instead of the system language. With Yandex translation on, a video without such a track is voice-over translated by Yandex into Russian, English or Kazakh. AVPlayer only (turn off the IFrame Player). A video Yandex hasn't translated before stays paused for a few minutes until the translation is ready. Lively voices: Russian only, needs the token."
            )
        }
    }

    private var shortsTranslationSection: some View {
        @Bindable var store = store
        return Section {
            audioLanguagePicker(selection: $store.settings.shortsPreferredAudioLanguage)
                .accessibilityIdentifier(AccessibilityID.settingsShortsAudioLanguageRow)
            Toggle("Yandex Voice-Over Translation", isOn: $store.settings.shortsYandexVOTEnabled)
                .accessibilityIdentifier(AccessibilityID.settingsShortsYandexVOTToggle)
            if store.settings.shortsYandexVOTEnabled {
                Toggle("Lively Voices", isOn: $store.settings.shortsYandexVOTLivelyVoice)
                    .accessibilityIdentifier(AccessibilityID.settingsShortsLivelyVoiceToggle)
                Toggle("Original Audio in Background", isOn: $store.settings.shortsYandexVOTKeepOriginalAudio)
                    .accessibilityIdentifier(AccessibilityID.settingsShortsKeepOriginalAudioToggle)
            }
        } header: {
            HStack {
                Text("Shorts")
                Text(verbatim: "·")  // verbatim: punctuation separating two localized labels
                Text("Audio Language")
            }
        }
    }

    private func audioLanguagePicker(selection: Binding<String?>) -> some View {
        Picker("Default Audio Language", selection: selection) {
            Text("Auto (System Default)").tag(nil as String?)
            Divider()
            Text("Russian").tag("ru" as String?)
            Text("English").tag("en" as String?)
            Text("Kazakh").tag("kk" as String?)
            Text("Spanish").tag("es" as String?)
            Text("French").tag("fr" as String?)
            Text("German").tag("de" as String?)
            Text("Japanese").tag("ja" as String?)
            Text("Korean").tag("ko" as String?)
            Text("Portuguese (Brazil)").tag("pt-BR" as String?)
            Text("Chinese (Simplified)").tag("zh-Hans" as String?)
            Divider()
            Text("Original Track Only").tag("original" as String?)
        }
    }
}

// MARK: - SettingsYandexTokenSection
//
// The Yandex OAuth token for lively voices lives in the Keychain (`TokenManager`) and is loaded only while this
// section is on screen. The field is a `SecureField`, so the value is only ever shown masked. Never log it or copy
// it into settings JSON.

private struct SettingsYandexTokenSection: View {
    @State private var token = ""
    @State private var showsHelp = false

    var body: some View {
        Section {
            SecureField("Yandex OAuth Token", text: $token)
                .autocorrectionDisabled()
                .onAppear { token = TokenManager.yandexVOTToken() ?? "" }
                .onChange(of: token) { _, token in
                    if token != TokenManager.yandexVOTToken() ?? "" { TokenManager.setYandexVOTToken(token) }
                }
                .accessibilityIdentifier(AccessibilityID.settingsYandexVOTTokenField)
            Button("How to Get a Token") { showsHelp = true }
                .alert("Yandex OAuth Token", isPresented: $showsHelp) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(
                        """
                        The token is only needed for lively voices.

                        1. Sign in to your Yandex account and open oauth.yandex.ru/client/new.
                        2. Create an app for "Web services" with the "Access to user's login" permission (login:info) and Redirect URI https://oauth.yandex.ru/verification_code.
                        3. Open oauth.yandex.ru/authorize?response_type=token&client_id=<your app's ClientID>.
                        4. Allow access — Yandex shows the token on the page. Paste it here.

                        The token is stored in the Keychain on this device. A Yandex Plus subscription is not required.
                        """)
                }
        } header: {
            Text("Yandex Token", bundle: .module)
        } footer: {
            Text("Shared by videos and Shorts. Kept in this device's Keychain and shown only masked.", bundle: .module)
        }
    }
}
