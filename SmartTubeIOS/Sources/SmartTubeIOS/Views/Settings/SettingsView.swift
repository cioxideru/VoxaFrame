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
    @State var selectedGroup: SettingsGroup = .account
    #if os(iOS)
    @State var contentWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    #if os(tvOS)
    @State private var showGithubQR = false
    @FocusState var focusedGroup: SettingsGroup?
    #endif
    /// #126: whether the current visit to this screen has already passed the PIN
    /// check. Reset to `false` on `.onDisappear` (see body) so leaving and coming back
    /// to Settings (e.g. switching tabs) re-locks it — a parental-control PIN that
    /// only had to be entered once per app launch wouldn't stop a kid who's already
    /// seen the tab switch away and back.
    @State private var isUnlocked = false
    @State private var parentalControlsSheetMode: ParentalControlsMode?
    /// B1 and B2: both destructive rows ask first; Cancel is the safe default.
    @State private var confirmsClearHistory = false
    @State private var confirmsReset = false
    #if os(macOS)
    private(set) var showsPanes = false
    #endif

    public init() {}

    #if os(macOS)
    /// `true` for the Settings window (Command-comma): one toolbar tab per group. The main window's
    /// Settings section keeps the single form.
    init(showsPanes: Bool) {
        self.showsPanes = showsPanes
    }
    #endif

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

    @ViewBuilder
    private var settingsForm: some View {
        let form = settingsContent.sheet(item: $parentalControlsSheetMode) { mode in
            ParentalControlsSheet(mode: mode)
        }
        // Hide the blank navigation bar on iOS and tvOS — a visible nav bar on tvOS
        // conflicts with the TabView tab bar scroll-hide animation (issue #102 / gh-34).
        // .navigationBar placement is unavailable on macOS.
        #if os(macOS)
        form
        #elseif os(tvOS)
        form.toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showGithubQR) { GitHubQRView(url: settingsGitHubURL) }
        #else
        form.toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: - Parental Controls

    var parentalControlsSection: some View {
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

    var accountSection: some View {
        Section {
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
                    .accessibilityIdentifier(AccessibilityID.settingsSignInButton)
                    .sheet(isPresented: $showSignIn) { SignInView() }
            }
        } header: {
            Text("Account")
        } footer: {
            // The first of the three data areas (§17): what lives in the Google account, not on this device.
            if auth.isSignedIn {
                Text(
                    "Subscriptions, playlists and likes are stored in your Google account; changes need a network connection.",
                    bundle: .module)
            }
        }
    }

    // MARK: - Player

    var playerSection: some View {
        @Bindable var store = store
        return Section {
            Picker("Playback Speed", selection: $store.settings.playbackSpeed) {
                ForEach(AppSettings.availableSpeeds, id: \.self) { s in
                    Text(s == 1.0 ? "Normal" : "\(s, specifier: "%.2g")×").tag(s)
                }
            }

            #if !os(iOS)
            Picker(
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
            } label: {
                Text("Default Quality")
                Text("Changing it clears the quality you last picked in the player.", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.settingsPreferredQualityPicker)
            #endif

            #if os(tvOS)
            Picker("Seek Back", selection: $store.settings.seekBackSeconds) {
                ForEach(AppSettings.availableSeekOptions, id: \.self) { s in
                    Text("\(s) s").tag(s)
                }
            }
            .accessibilityIdentifier(AccessibilityID.settingsSeekBackRow)
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
            .accessibilityIdentifier(AccessibilityID.settingsSeekBackRow)
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
        } header: {
            Text("Playback", bundle: .module)
        }
    }
}

extension SettingsView {

    // MARK: - History and data on this device

    /// The second data area (§17). There is no "clear everything" action: each kind of data keeps its own.
    var generalSection: some View {
        @Bindable var store = store
        let history = LocalWatchHistoryStore.shared
        return Section {
            Picker(selection: $store.settings.historyState) {
                Text("Enabled").tag(AppSettings.HistoryState.enabled)
                Text("Disabled").tag(AppSettings.HistoryState.disabled)
            } label: {
                Text("Watch History")
                Text("Turning it off stops recording but deletes nothing.", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.settingsHistoryPicker)
            if !history.entries.isEmpty {
                Button(role: .destructive) {
                    confirmsClearHistory = true
                } label: {
                    Text("Clear Watch History on This Device")
                }
                .accessibilityIdentifier(AccessibilityID.settingsClearLocalHistoryButton)
                .confirmationDialog(
                    Text("Clear History on This Device?", bundle: .module),
                    isPresented: $confirmsClearHistory,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        history.clear()
                    } label: {
                        Text("Clear History", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsClearLocalHistoryConfirm)
                    confirmationCancelButton(AccessibilityID.settingsClearLocalHistoryCancel)
                } message: {
                    Text(SettingsConfirmationText.clearHistoryMessage(entryCount: history.entries.count))
                }
            }
        } header: {
            Text("This Device", bundle: .module)
        } footer: {
            VStack(alignment: .leading, spacing: VFSpace.s8) {
                Text(
                    "Watch history is saved on this device. VoxaFrame also tries to report watches to your YouTube account, but YouTube may not always record them."
                )
                // The third area: offline files are removed only from the Offline videos section.
                Text("Offline videos are kept until you delete them in Offline videos.", bundle: .module)
            }
        }
    }

    var downloadsSection: some View {
        @Bindable var store = store
        return Section {
            Picker(selection: $store.settings.maximumConcurrentDownloads) {
                ForEach(AppSettings.availableConcurrentDownloadCounts, id: \.self) { count in
                    Text(count, format: .number).tag(count)
                }
            } label: {
                Text("Simultaneous downloads", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.settingsConcurrentDownloadsPicker)
        } header: {
            Text("Downloads", bundle: .module)
        } footer: {
            Text("Each video, audio or translation track counts as one download.", bundle: .module)
        }
    }

    var iCloudSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Sync to iCloud", isOn: $store.settings.iCloudSyncEnabled)
                .accessibilityIdentifier("settings.iCloudSyncToggle")
        } header: {
            Text(verbatim: "iCloud")  // verbatim: product name, the same in every language
        }
    }

    /// Cancel for the destructive confirmations: the safe default, and the Return key on macOS.
    private func confirmationCancelButton(_ identifier: String) -> some View {
        let button = Button(role: .cancel) {
        } label: {
            Text("Cancel", bundle: .module)
        }
        .accessibilityIdentifier(identifier)
        #if os(macOS)
        return button.keyboardShortcut(.defaultAction)
        #else
        return button
        #endif
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

    var uiSection: some View {
        @Bindable var store = store
        return Section {
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
            #if os(iOS)
            if #available(iOS 26.0, *) {
                Toggle(isOn: $store.settings.disableLiquidGlass) {
                    Text("Disable Liquid Glass")
                    // Applied live: TabBarLiquidGlassConfigurator and vfGlassScope both read the setting.
                    Text("Opaque bars and panels instead of glass.", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.settingsDisableLiquidGlassToggle)
            }
            #endif
        } header: {
            Text("Appearance", bundle: .module)
        }
    }

    var feedFiltersSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Hide Shorts", isOn: $store.settings.hideShorts)
                .accessibilityIdentifier(AccessibilityID.settingsHideShortsToggle)
            Toggle("Hide Live Shorts", isOn: $store.settings.hideLiveShorts)
                .accessibilityIdentifier("settings.hideLiveShortsToggle")
            Toggle("Hide Video Premieres", isOn: $store.settings.hideVideoPremieres)
                .accessibilityIdentifier("settings.hideVideoPremieresToggle")
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
            Toggle("Per-Device Recommendations", isOn: $store.settings.perDeviceRecommendationsEnabled)
                .accessibilityIdentifier("settings.perDeviceRecommendationsToggle")
        } header: {
            Text("Feed Filters", bundle: .module)
        }
    }

    var homeSectionsSection: some View {
        Section {
            NavigationLink("Visible Sections") {
                SectionsSettingsView()
                    .environment(store)
            }
            .accessibilityIdentifier(AccessibilityID.settingsVisibleSectionsLink)
        } header: {
            Text("Home Sections", bundle: .module)
        }
    }

    // MARK: - SponsorBlock

    var sponsorBlockSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(isOn: $store.settings.sponsorBlockEnabled) {
                Text("Enable SponsorBlock")
                Text("Segments marked by the community inside videos.", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.settingsSponsorBlockToggle)

            if store.settings.sponsorBlockEnabled {
                // Nine categories, each Skip / Show Toast / Nothing. The colour matches the timeline marks
                // and is never the only cue: the category name is the label.
                ForEach(SponsorSegment.Category.allCases, id: \.self) { cat in
                    HStack {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
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

    var deArrowSection: some View {
        @Bindable var store = store
        return Section {
            Toggle("Enable DeArrow", isOn: $store.settings.deArrowEnabled)
        } header: {
            Text("DeArrow")
        } footer: {
            Text("Replace clickbait titles and thumbnails with community-sourced alternatives.")
        }
    }

    // MARK: - Video codecs (AVPlayer)

    var videoCodecsSection: some View {
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

    var aboutSection: some View {
        @Bindable var store = store
        return Section {
            LabeledContent("Version", value: appVersion)
            #if os(tvOS)
            Button {
                showGithubQR = true
            } label: {
                Label("View on GitHub", systemImage: AppSymbol.sourceCode)
            }
            .accessibilityIdentifier(AccessibilityID.settingsGitHubLink)
            #else
            Link(destination: settingsGitHubURL) {
                Label("View on GitHub", systemImage: AppSymbol.sourceCode)
            }
            .accessibilityIdentifier(AccessibilityID.settingsGitHubLink)
            .accessibilityValue(settingsGitHubURL.absoluteString)
            #endif
            Button(role: .destructive) {
                confirmsReset = true
            } label: {
                Text("Reset All Settings")
            }
            .accessibilityIdentifier(AccessibilityID.settingsResetAllButton)
            .confirmationDialog(
                Text("Reset All Settings to Defaults?", bundle: .module),
                isPresented: $confirmsReset,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    store.reset()
                } label: {
                    Text("Reset", bundle: .module)
                }
                .accessibilityIdentifier(AccessibilityID.settingsResetAllConfirm)
                confirmationCancelButton(AccessibilityID.settingsResetAllCancel)
            } message: {
                Text(SettingsConfirmationText.resetAllConsequences(for: store.settings).joined(separator: "\n"))
            }
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
