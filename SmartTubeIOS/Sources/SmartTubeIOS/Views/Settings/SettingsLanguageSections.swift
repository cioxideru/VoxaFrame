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
    /// The Keychain holds a token: read back after every save, never assumed from the field.
    @State private var hasToken = false
    @State private var saveFailed = false
    @State private var showsHelp = false
    @FocusState private var isEditing: Bool

    var body: some View {
        Section {
            SecureField("Yandex OAuth Token", text: $token)
                .autocorrectionDisabled()
                .focused($isEditing)
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: isEditing) { _, editing in
                    if !editing { save() }
                }
                .onAppear {
                    token = TokenManager.yandexVOTToken() ?? ""
                    hasToken = !token.isEmpty
                }
                .onDisappear(perform: save)
                .accessibilityIdentifier(AccessibilityID.settingsYandexVOTTokenField)
            Button("How to Get a Token") { showsHelp = true }
                .sheet(isPresented: $showsHelp) { YandexTokenHelpSheet() }
        } header: {
            Text("Yandex Token", bundle: .module)
        } footer: {
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(
                    "Shared by videos and Shorts. Kept in this device's Keychain and shown only masked.",
                    bundle: .module)
                if saveFailed {
                    Label {
                        Text("Couldn't save the token to the Keychain.", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.warning)
                    }
                    .foregroundStyle(VFColor.danger)
                } else if hasToken {
                    Label {
                        Text("Saved in Keychain", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.checkmarkCircle)
                    }
                }
            }
        }
    }

    /// Writes the token once editing ends, not on every keystroke, then reads back what the Keychain kept.
    /// Blank input removes the token.
    private func save() {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != TokenManager.yandexVOTToken() ?? "" { TokenManager.setYandexVOTToken(normalized) }
        let stored = TokenManager.yandexVOTToken() ?? ""
        saveFailed = stored != normalized
        hasToken = !stored.isEmpty && !saveFailed
        if !saveFailed { token = stored }
    }
}

// MARK: - YandexTokenHelpSheet
//
// The four steps to get a token, with tappable links and text that can be selected and copied.

private struct YandexTokenHelpSheet: View {
    private static let redirectURI = "https://oauth.yandex.ru/verification_code"
    private static let authorizeAddress = "https://oauth.yandex.ru/authorize?response_type=token&client_id="
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The token is only needed for lively voices.", bundle: .module)
                }
                Section {
                    step(1) {
                        Text("Sign in to your Yandex account and create an app:", bundle: .module)
                        link("oauth.yandex.ru/client/new")
                    }
                    step(2) {
                        Text(
                            "Choose \"Web services\", add the \"Access to user's login\" permission (login:info) and this Redirect URI:",
                            bundle: .module)
                        Text(verbatim: Self.redirectURI).monospaced()  // verbatim: an address to copy
                    }
                    step(3) {
                        Text("Open this address with your app's ClientID at the end:", bundle: .module)
                        Text(verbatim: Self.authorizeAddress).monospaced()  // verbatim: an address to copy
                    }
                    step(4) {
                        Text(
                            "Allow access. Yandex shows the token on the page; paste it into the token field.",
                            bundle: .module)
                    }
                } footer: {
                    Text(
                        "The token is stored in the Keychain on this device. A Yandex Plus subscription is not required.",
                        bundle: .module)
                }
            }
            #if !os(tvOS)
            .textSelection(.enabled)
            #endif
            .navigationTitle(Text("Yandex OAuth Token", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
    }

    private func step(_ number: Int, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.s12) {
            Text(number, format: .number).font(.headline).monospacedDigit()
            VStack(alignment: .leading, spacing: VFSpace.s4) { content() }
        }
    }

    /// A tappable `https://` link that reads as the bare address.
    @ViewBuilder private func link(_ address: String) -> some View {
        if let url = URL(string: "https://\(address)") {
            Link(address, destination: url)
        }
    }
}
