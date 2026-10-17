import AuthenticationServices
import SmartTubeIOSCore
import SwiftUI

private let settingsGitHubURL = URL(string: "https://github.com/cioxideru/VoxaFrame")!

// MARK: - SettingsView
//
// App preferences.  Mirrors the Android settings presenters
// (PlayerData, MainUIData, SponsorBlockData, DeArrowData, AccountsData).

public struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @State private var showSignIn = false
    #if os(tvOS)
    @State private var showGithubQR = false
    #endif
    /// #126: whether the current visit to this screen has already passed the PIN
    /// check. Reset to `false` on `.onDisappear` (see body) so leaving and coming back
    /// to Settings (e.g. switching tabs) re-locks it — a parental-control PIN that
    /// only had to be entered once per app launch wouldn't stop a kid who's already
    /// seen the tab switch away and back.
    @State private var isUnlocked = false
    @State private var parentalControlsSheetMode: ParentalControlsMode?
    /// Loaded from the Keychain when the token field appears, not on every view init.
    @State private var yandexToken = ""
    @State private var showYandexTokenHelp = false

    public init() {}

    public var body: some View {
        Group {
            if let pinHash = store.settings.settingsPINHash, !isUnlocked {
                SettingsPINLockView(expectedHash: pinHash) { isUnlocked = true }
            } else {
                settingsForm
            }
        }
        .onDisappear {
            if store.settings.settingsPINHash != nil { isUnlocked = false }
        }
    }

    private var settingsForm: some View {
        Form {
            accountSection
            playerSection
            videoCodecsSection
            yandexVOTSection
            shortsTranslationSection
            generalSection
            uiSection
            sponsorBlockSection
            deArrowSection
            parentalControlsSection
            aboutSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        // Hide the blank navigation bar on iOS and tvOS — a visible nav bar on tvOS
        // conflicts with the TabView tab bar scroll-hide animation (issue #102 / gh-34).
        // .navigationBar placement is unavailable on macOS.
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        #if os(tvOS)
        .sheet(isPresented: $showGithubQR) {
            GitHubQRView()
        }
        #endif
        .sheet(item: $parentalControlsSheetMode) { mode in
            ParentalControlsSheet(mode: mode)
        }
    }

    // MARK: - Parental Controls

    private var parentalControlsSection: some View {
        Section {
            if store.settings.settingsPINHash == nil {
                Button("Set PIN") { parentalControlsSheetMode = .set }
                    .accessibilityIdentifier(AccessibilityID.settingsSetPINButton)
            } else {
                Button("Change PIN") { parentalControlsSheetMode = .change }
                    .accessibilityIdentifier(AccessibilityID.settingsChangePINButton)
                Button("Remove PIN", role: .destructive) { parentalControlsSheetMode = .remove }
                    .accessibilityIdentifier(AccessibilityID.settingsRemovePINButton)
            }
        } header: {
            Text("Parental Controls")
        } footer: {
            Text("When a PIN is set, it must be entered every time this Settings screen is opened.")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if auth.isSignedIn {
                HStack {
                    #if os(tvOS)
                    let avatarSize: CGFloat = 64
                    #else
                    let avatarSize: CGFloat = 40
                    #endif
                    AsyncImage(url: auth.accountAvatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure, .empty:
                            Circle().fill(Color.secondary.opacity(0.3))
                                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                        @unknown default:
                            Circle().fill(Color.secondary.opacity(0.3))
                        }
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    Text(auth.accountName ?? "Unknown")
                }
                Button("Sign Out", role: .destructive) { auth.signOut() }
            } else {
                Button("Sign in with Google") { showSignIn = true }
                    .accessibilityIdentifier("settings.signInButton")
                    .sheet(isPresented: $showSignIn) { SignInView() }
            }
        }
    }

    // MARK: - Player

    private var playerSection: some View {
        @Bindable var store = store
        return Section("Player") {
            Picker("Playback Speed", selection: $store.settings.playbackSpeed) {
                ForEach(AppSettings.availableSpeeds, id: \.self) { s in
                    Text(s == 1.0 ? "Normal" : "\(s, specifier: "%.2g")×").tag(s)
                }
            }

            #if !os(iOS)
            Picker(
                "Default Quality",
                selection: Binding(
                    get: { store.settings.preferredQuality },
                    set: {
                        store.settings.preferredQuality = $0
                        store.settings.lastVideoQuality = nil
                    }
                )
            ) {
                ForEach(AppSettings.VideoQuality.allCases, id: \.self) { q in
                    Text(q.rawValue.capitalized).tag(q)
                }
            }
            .accessibilityIdentifier("settings.preferredQualityPicker")
            #endif

            #if os(tvOS)
            Picker("Seek Back", selection: $store.settings.seekBackSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s").tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekBackRow")
            Picker("Seek Forward", selection: $store.settings.seekForwardSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s").tag(s)
                }
            }
            .accessibilityIdentifier("settings.seekForwardRow")
            #elseif os(macOS)
            Stepper(
                "Seek Back: \(store.settings.seekBackSeconds) s",
                value: $store.settings.seekBackSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekBackRow")
            Stepper(
                "Seek Forward: \(store.settings.seekForwardSeconds) s",
                value: $store.settings.seekForwardSeconds,
                in: 5...60,
                step: 5
            )
            .accessibilityIdentifier("settings.seekForwardRow")
            #endif

            #if !os(iOS)
            Picker("Hide Controls After", selection: $store.settings.controlsHideTimeout) {
                Text("2s").tag(2)
                Text("3s").tag(3)
                Text("4s").tag(4)
                Text("5s").tag(5)
                Text("8s").tag(8)
                Text("10s").tag(10)
            }

            Picker("Video Fit", selection: $store.settings.videoGravityMode) {
                Text("Fit (letterbox)").tag(AppSettings.VideoGravityMode.fit)
                Text("Fill (crop)").tag(AppSettings.VideoGravityMode.fill)
            }
            #endif

            Toggle("Loop Video", isOn: $store.settings.loopEnabled)
            Toggle("Shuffle", isOn: $store.settings.shuffleEnabled)

            Toggle("Autoplay next video", isOn: $store.settings.autoplayEnabled)
            Toggle("Background Playback", isOn: $store.settings.backgroundPlaybackEnabled)
            #if !os(iOS)
            Toggle("Prefer H.264 Codec", isOn: $store.settings.preferH264)
                .accessibilityIdentifier("settings.preferH264Toggle")
            #endif
        }
    }

    // MARK: - General

    private var generalSection: some View {
        @Bindable var store = store
        return Section {
            Picker("Watch History", selection: $store.settings.historyState) {
                Text("Enabled").tag(AppSettings.HistoryState.enabled)
                Text("Disabled").tag(AppSettings.HistoryState.disabled)
            }
            .accessibilityIdentifier(AccessibilityID.settingsHistoryPicker)
            if !LocalWatchHistoryStore.shared.entries.isEmpty {
                Button("Clear Watch History on This Device", role: .destructive) {
                    LocalWatchHistoryStore.shared.clear()
                }
                .accessibilityIdentifier(AccessibilityID.settingsClearLocalHistoryButton)
            }
            Toggle("Sync to iCloud", isOn: $store.settings.iCloudSyncEnabled)
                .accessibilityIdentifier("settings.iCloudSyncToggle")
        } header: {
            Text("General")
        } footer: {
            Text(
                "Watch history is saved on this device. VoxaFrame also tries to report watches to your YouTube account, but YouTube may not always record them."
            )
        }
    }

    // MARK: - UI

    private enum ThumbnailStyle: Hashable {
        case standard, highResolution, compact
    }

    /// UI-only view over the two independent `compactThumbnails` / `highResThumbnails` flags.
    private var thumbnailStyle: Binding<ThumbnailStyle> {
        Binding(
            get: {
                if store.settings.compactThumbnails { return .compact }
                return store.settings.highResThumbnails ? .highResolution : .standard
            },
            set: { style in
                store.settings.compactThumbnails = style == .compact
                store.settings.highResThumbnails = style == .highResolution
            }
        )
    }

    private var uiSection: some View {
        @Bindable var store = store
        return Section("Interface") {
            Picker("Theme", selection: $store.settings.themeName) {
                ForEach(AppSettings.ThemeName.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .accessibilityIdentifier("settings.themeRow")
            Picker("Accent Color", selection: $store.settings.accentColor) {
                ForEach(AppSettings.AccentColorChoice.allCases, id: \.self) { choice in
                    Label {
                        Text(choice.displayName)
                    } icon: {
                        choice.swatch
                    }
                    .tag(choice)
                }
            }
            .accessibilityIdentifier(AccessibilityID.settingsAccentColorPicker)
            Picker("Thumbnails", selection: thumbnailStyle) {
                Text("Standard").tag(ThumbnailStyle.standard)
                Text("High Resolution").tag(ThumbnailStyle.highResolution)
                Text("Compact").tag(ThumbnailStyle.compact)
            }
            .accessibilityIdentifier(AccessibilityID.settingsThumbnailStylePicker)
            #if !os(tvOS)
            Picker("Columns (Portrait)", selection: $store.settings.gridColumnsPortrait) {
                ForEach(AppSettings.availableGridColumnCounts, id: \.self) { Text("\($0)").tag($0) }
            }
            .disabled(store.settings.compactThumbnails)
            .accessibilityIdentifier(AccessibilityID.settingsGridColumnsPortraitPicker)
            Picker("Columns (Landscape)", selection: $store.settings.gridColumnsLandscape) {
                ForEach(AppSettings.availableGridColumnCounts, id: \.self) { Text("\($0)").tag($0) }
            }
            .disabled(store.settings.compactThumbnails)
            .accessibilityIdentifier(AccessibilityID.settingsGridColumnsLandscapePicker)
            #endif
            Toggle("Hide Shorts", isOn: $store.settings.hideShorts)
                .accessibilityIdentifier("settings.hideShortsToggle")
            Toggle("Hide Live Shorts", isOn: $store.settings.hideLiveShorts)
                .accessibilityIdentifier("settings.hideLiveShortsToggle")
            Toggle("Hide Video Premieres", isOn: $store.settings.hideVideoPremieres)
                .accessibilityIdentifier("settings.hideVideoPremieresToggle")
            Toggle("Per-Device Recommendations", isOn: $store.settings.perDeviceRecommendationsEnabled)
                .accessibilityIdentifier("settings.perDeviceRecommendationsToggle")
            Toggle("Hide Watched Videos", isOn: $store.settings.hideWatchedVideos)
                .accessibilityIdentifier(AccessibilityID.settingsHideWatchedVideosToggle)
            if store.settings.hideWatchedVideos {
                #if os(tvOS)
                // tvOS has no Stepper.
                Picker("Watched threshold", selection: $store.settings.hideWatchedThresholdPercent) {
                    ForEach(
                        Array(
                            stride(
                                from: AppSettings.hideWatchedThresholdPercentRange.lowerBound,
                                through: AppSettings.hideWatchedThresholdPercentRange.upperBound,
                                by: AppSettings.hideWatchedThresholdPercentStep)), id: \.self
                    ) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsHideWatchedThresholdStepper)
                #else
                Stepper(
                    "Watched threshold: \(store.settings.hideWatchedThresholdPercent)%",
                    value: $store.settings.hideWatchedThresholdPercent,
                    in: AppSettings.hideWatchedThresholdPercentRange,
                    step: AppSettings.hideWatchedThresholdPercentStep
                )
                .accessibilityIdentifier(AccessibilityID.settingsHideWatchedThresholdStepper)
                #endif
            }
            #if os(iOS)
            if #available(iOS 26.0, *) {
                Toggle("Disable Liquid Glass", isOn: $store.settings.disableLiquidGlass)
                    .accessibilityIdentifier(AccessibilityID.settingsDisableLiquidGlassToggle)
            }
            #endif
            NavigationLink("Visible Sections") {
                SectionsSettingsView()
                    .environment(store)
            }
            .accessibilityIdentifier(AccessibilityID.settingsVisibleSectionsLink)
        }
    }

}

extension SettingsView {

    // MARK: - SponsorBlock

    private var sponsorBlockSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Enable SponsorBlock", isOn: $store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier("settings.sponsorBlockToggle")

            if store.settings.sponsorBlockEnabled {
                ForEach(SponsorSegment.Category.allCases, id: \.self) { cat in
                    HStack {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 10, height: 10)
                        Picker(
                            cat.displayName,
                            selection: Binding(
                                get: { store.settings.sponsorBlockActions[cat] ?? .nothing },
                                set: { store.settings.sponsorBlockActions[cat] = $0 }
                            )
                        ) {
                            Text("Skip").tag(AppSettings.SponsorBlockAction.skip)
                            Text("Show Toast").tag(AppSettings.SponsorBlockAction.showToast)
                            Text("Nothing").tag(AppSettings.SponsorBlockAction.nothing)
                        }
                        .accessibilityIdentifier("settings.sponsorBlock.\(cat.rawValue)")
                    }
                }

                // Minimum segment duration
                Picker("Min. Segment Length", selection: $store.settings.sponsorBlockMinSegmentDuration) {
                    Text("Off").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }

                // Excluded channels
                NavigationLink("Excluded Channels (\(store.settings.sponsorBlockExcludedChannels.count))") {
                    SponsorBlockExcludedChannelsView()
                }
                .accessibilityIdentifier("settings.sponsorBlockExcludedChannels")
            }
        } header: {
            Text("SponsorBlock")
        } footer: {
            Text("Skip \u{2014} auto-skips. Show Toast \u{2014} shows a skip button. Nothing \u{2014} plays through.")
        }
    }

    // MARK: - DeArrow

    private var deArrowSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Enable DeArrow", isOn: $store.settings.deArrowEnabled)
        } header: {
            Text("DeArrow")
        } footer: {
            Text("Replace clickbait titles and thumbnails with community-sourced alternatives.")
        }
    }

    // MARK: - Yandex voice-over translation

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
            if (store.settings.yandexVOTEnabled && store.settings.yandexVOTLivelyVoice)
                || (store.settings.shortsYandexVOTEnabled && store.settings.shortsYandexVOTLivelyVoice)
            {
                SecureField("Yandex OAuth Token", text: $yandexToken)
                    .autocorrectionDisabled()
                    .onAppear { yandexToken = TokenManager.yandexVOTToken() ?? "" }
                    .onChange(of: yandexToken) { _, token in
                        if token != TokenManager.yandexVOTToken() ?? "" { TokenManager.setYandexVOTToken(token) }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsYandexVOTTokenField)
                Button("How to Get a Token") { showYandexTokenHelp = true }
                    .alert("Yandex OAuth Token", isPresented: $showYandexTokenHelp) {
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

    // MARK: - Video codecs (AVPlayer)

    private var videoCodecsSection: some View {
        @Bindable var store = store
        let settings = store.settings
        return Section {
            // At least one codec stays on: the last one enabled can't be switched off.
            Toggle("VP9 (up to 4K)", isOn: $store.settings.vp9Enabled)
                .disabled(settings.vp9Enabled && !settings.h264Enabled)
                .accessibilityIdentifier(AccessibilityID.settingsVp9Toggle)
            Toggle("H.264 (up to 1080p)", isOn: $store.settings.h264Enabled)
                .disabled(settings.h264Enabled && !settings.vp9Enabled)
                .accessibilityIdentifier(AccessibilityID.settingsH264Toggle)
        } header: {
            Text("Video Codecs")
        } footer: {
            Text(
                HLSPlaybackPolicy.isVP9DecodingAvailable
                    ? "VP9 gives 1440p and 4K. H.264 tops out at 1080p but plays on every device. With both on, the player picks between them. Applies to the next video."
                    : "This device has no VP9 decoder (iOS 26.2 or later needed), so H.264 up to 1080p is used."
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        @Bindable var store = store
        return Section {
            LabeledContent("Version", value: appVersion)
            #if os(tvOS)
            Button {
                showGithubQR = true
            } label: {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .accessibilityIdentifier(AccessibilityID.settingsGitHubLink)
            #else
            Link(destination: settingsGitHubURL) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .accessibilityIdentifier(AccessibilityID.settingsGitHubLink)
            .accessibilityValue(settingsGitHubURL.absoluteString)
            #endif
            Button("Reset All Settings", role: .destructive) { store.reset() }
                .accessibilityIdentifier("settings.resetAllButton")
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - GitHubQRView (tvOS)

#if os(tvOS)
private struct GitHubQRView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)

                    Text("VoxaFrame on GitHub")
                        .font(.largeTitle).fontWeight(.bold)

                    Text("Scan the QR code with your phone to view the project on GitHub.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                QRCodeView(content: settingsGitHubURL.absoluteString)
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(settingsGitHubURL.absoluteString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.headline)
            }
            .padding(40)
        }
    }
}
#endif
