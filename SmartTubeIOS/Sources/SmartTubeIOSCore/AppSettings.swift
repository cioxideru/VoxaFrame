import Foundation

// MARK: - AppSettings

/// Persisted app-wide preferences (mirrors Android `PlayerData`, `MainUIData`, `GeneralData`, etc.).
public struct AppSettings: Codable {
    // MARK: Player
    public var preferredQuality: VideoQuality
    public var lastVideoQuality: VideoQualityPreference?

    public var videoQualityPreference: VideoQualityPreference {
        lastVideoQuality ?? VideoQualityPreference(height: preferredQuality.maxHeight)
    }
    public var playbackSpeed: Double
    public var autoplayEnabled: Bool
    public var subtitlesLanguage: String?
    public var backgroundPlaybackEnabled: Bool
    /// When `true`, the player automatically rotates to landscape when a video starts on iPhone.
    public var landscapeAlwaysPlay: Bool
    /// When `true`, Picture-in-Picture is available and the PiP button is shown in the player.
    public var pipEnabled: Bool
    /// When `true` (default), pressing back or swiping down minimizes the player to the
    /// in-app mini-player bar instead of stopping playback. When `false`, the player is
    /// dismissed and playback stops — mirrors the behaviour of a standalone player app.
    public var miniPlayerEnabled: Bool
    /// Seconds to seek backward (configurable; default 10 mirrors Android's default).
    public var seekBackSeconds: Int
    /// Seconds to seek forward (configurable; default 30 mirrors Android's default).
    public var seekForwardSeconds: Int
    /// Seconds before the player controls auto-hide after the last interaction.
    /// Mirrors Android's `PlayerData.controlsHideTimeoutMs`. Default: 4.
    public var controlsHideTimeout: Int

    /// Whether the video should fill the screen (cropping sides) or fit within bounds.
    public enum VideoGravityMode: String, Codable, CaseIterable, Sendable {
        case fit = "fit"  // resizeAspect — letterbox/pillarbox
        case fill = "fill"  // resizeAspectFill — crops to fill
    }
    public var videoGravityMode: VideoGravityMode

    /// When `true`, the current video replays from the start instead of advancing.
    public var loopEnabled: Bool
    /// When `true`, autoplay picks a random video from the related-videos list.
    public var shuffleEnabled: Bool
    /// When `true`, playing from the Current Queue picks a random remaining video instead of the next sequential one.
    /// Independent from `shuffleEnabled` (which shuffles YouTube recommendations after non-queue playback).
    public var queueShuffleEnabled: Bool

    // MARK: UI
    public var defaultSection: String
    public var compactThumbnails: Bool
    /// Loads 1280×720 CDN thumbnails instead of the smaller API-provided ones.
    public var highResThumbnails: Bool
    /// #121: hides videos from Home/Subscriptions once their watched fraction
    /// (`Video.watchProgress`, YouTube's own resume-progress signal) reaches
    /// `hideWatchedThreshold`. History is deliberately never filtered by this —
    /// watched videos are the entire point of that section.
    public var hideWatchedVideos: Bool
    /// 0.0...1.0 — how far into a video counts as "watched" for `hideWatchedVideos`.
    public var hideWatchedThreshold: Double
    public static let hideWatchedThresholdPercentRange = 5...100
    public static let hideWatchedThresholdPercentStep = 5

    /// Integer steps avoid accumulating rounding errors at the selected boundary.
    public var hideWatchedThresholdPercent: Int {
        get { Int((hideWatchedThreshold * 100).rounded()) }
        set { hideWatchedThreshold = Double(newValue) / 100 }
    }

    public func shouldHideWatched(_ video: Video, in section: BrowseSection.SectionType) -> Bool {
        hideWatchedVideos && section != .history && video.isWatched(threshold: hideWatchedThreshold)
    }

    /// #107/#143: opts the app out of iOS 26's Liquid Glass tab bar. Apple's documented
    /// mechanism (`UIDesignRequiresCompatibility` in Info.plist) is build-time only and
    /// can't back a live, per-user toggle — see `TabBarConfigurator`, which
    /// instead restyles the actual on-screen `UITabBar` instance directly. Takes effect
    /// immediately, no restart needed. Also turns `vfGlass` surfaces opaque.
    public var disableLiquidGlass: Bool
    /// #126: SHA256 hex digest of the Settings-screen parental-control PIN (see
    /// `SettingsPINHasher`). `nil` means no PIN is configured and Settings behaves as
    /// today with no lock. Never stores the raw PIN.
    public var settingsPINHash: String?
    /// Hide Shorts from feeds; on by default.
    public var hideShorts: Bool
    /// Show the Queue as its own sidebar item on a regular-width iPad window and on macOS; off by default.
    /// The queue stays in Library either way.
    public var showQueueTab: Bool
    public var hideLiveShorts: Bool
    public var hideVideoPremieres: Bool
    /// When `true` (default), a per-device `visitorData` token is included in home-feed
    /// requests so YouTube tailors recommendations to this device.
    /// When `false`, the token is cleared and YouTube returns its default shared feed.
    public var perDeviceRecommendationsEnabled: Bool
    public var themeName: ThemeName
    public var accentColor: AccentColorChoice
    /// Video grid column count when the window is taller than wide (ignored on tvOS).
    public var gridColumnsPortrait: Int
    /// Video grid column count when the window is wider than tall (ignored on tvOS).
    public var gridColumnsLandscape: Int
    /// Ordered list of section types visible in the sidebar/tab bar.
    /// When empty, all default sections are shown.
    public var enabledSections: [BrowseSection.SectionType]

    // MARK: General

    /// Controls whether watch history is recorded locally and fetched from YouTube.
    /// Mirrors Android's `GeneralData.historyEnabled`.
    public enum HistoryState: String, Codable, CaseIterable, Sendable {
        /// Default — history is fetched from YouTube and local positions are saved.
        case enabled = "enabled"
        /// History section shows nothing and local watch positions are not saved.
        case disabled = "disabled"
    }
    public var historyState: HistoryState

    // MARK: SponsorBlock

    /// Per-segment action that controls how each SponsorBlock category is handled.
    /// Mirrors Android's per-category action setting in `SponsorBlockData`.
    public enum SponsorBlockAction: String, Codable, CaseIterable, Sendable {
        /// Automatically skip the segment without user interaction.
        case skip = "skip"
        /// Show a dismissible toast and let the user manually skip.
        case showToast = "showToast"
        /// Take no action — segment plays through normally.
        case nothing = "nothing"
    }

    public var sponsorBlockEnabled: Bool
    /// Per-category action. Categories absent from this dict are treated as `.nothing`.
    public var sponsorBlockActions: [SponsorSegment.Category: SponsorBlockAction]
    /// Minimum segment length (seconds). Segments shorter than this value are ignored.
    /// 0 means "accept all" (no filtering). Mirrors Android's `SponsorBlockData.minSegmentDuration`.
    public var sponsorBlockMinSegmentDuration: Double
    /// Channels where SponsorBlock is disabled. Key = channelId, value = display title.
    /// Mirrors Android's `SponsorBlockData.excludedChannels`.
    public var sponsorBlockExcludedChannels: [String: String]
    /// Refresh SponsorBlock segments of saved offline videos in the background, at most once a day.
    public var offlineSponsorBlockAutoUpdate: Bool
    /// Channels hidden from the feed via "Don't Recommend Channel". Key = channelId, value = channel title.
    /// Persists across sessions and syncs via iCloud when `iCloudSyncEnabled` is true.
    public var blockedChannels: [String: String]

    /// Convenience: the set of categories whose action is not `.nothing`.
    /// Passed to `SponsorBlockService.fetchSegments` so we only fetch relevant segments.
    public var activeSponsorCategories: Set<SponsorSegment.Category> {
        Set(sponsorBlockActions.compactMap { $0.value != .nothing ? $0.key : nil })
    }

    /// Returns the action for a given category (`.nothing` if not configured).
    public func sponsorAction(for category: SponsorSegment.Category) -> SponsorBlockAction {
        sponsorBlockActions[category] ?? .nothing
    }

    // MARK: Audio
    /// BCP 47 language code of the user's default audio language (e.g. "ru", "es", "pt-BR"),
    /// `"original"` for the creator's track, `nil` for the HLS / system default. On iOS, when
    /// the video has neither an original nor a dubbed track in this language and Yandex VOT is
    /// enabled, the video is voice-over translated into it.
    public var preferredAudioLanguage: String?

    // MARK: Yandex voice-over translation (AVPlayer only)
    /// Translates videos into `preferredAudioLanguage` with Yandex VOT when no matching track exists.
    public var yandexVOTEnabled: Bool
    /// Requests Yandex "lively voices" (needs the Yandex OAuth token, Russian target only).
    public var yandexVOTLivelyVoice: Bool
    /// Keeps the original audio quietly under the translation (Yandex returns the voice only,
    /// without music or effects); off mutes it.
    public var yandexVOTKeepOriginalAudio: Bool

    // MARK: Shorts playback, audio and translation
    public var shortsPlaybackSpeed: Double
    public var shortsPreferredAudioLanguage: String?
    public var shortsYandexVOTEnabled: Bool
    public var shortsYandexVOTLivelyVoice: Bool
    public var shortsYandexVOTKeepOriginalAudio: Bool

    /// Resolve the independent preferences at the Shorts playback boundary.
    public var shortsPlaybackSettings: AppSettings {
        var result = self
        result.playbackSpeed = shortsPlaybackSpeed
        result.preferredAudioLanguage = shortsPreferredAudioLanguage
        result.yandexVOTEnabled = shortsYandexVOTEnabled
        result.yandexVOTLivelyVoice = shortsYandexVOTLivelyVoice
        result.yandexVOTKeepOriginalAudio = shortsYandexVOTKeepOriginalAudio
        return result
    }

    // MARK: Video codecs (AVPlayer, VISIONOS HLS)
    /// Plays the VP9 ladder (up to 2160p) when the device has a VP9 decoder.
    public var vp9Enabled: Bool
    /// Plays the H.264 ladder (up to 1080p). Used anyway when VP9 is off or not decodable.
    public var h264Enabled: Bool

    /// BCP 47 language code of the user's last selected caption track (e.g. "en", "es").
    /// `nil` means captions are off. Set implicitly when the user picks a caption track in the player.
    /// Applied automatically to each new video on load.
    public var preferredCaptionLanguage: String?

    // MARK: DeArrow
    public var deArrowEnabled: Bool

    // MARK: Network
    /// Optional URL of a self-hosted poToken microservice (e.g. youtube-trusted-session-generator).
    /// When set, `ServerPoTokenProvider` is wired up to `InnerTubeAPI` so poToken is injected
    /// into every `/player` request. Nil by default — no token is sent until the user configures
    /// a server URL (see docs/potoken.md §Step 5).
    public var poTokenServiceURL: URL?

    // MARK: Audio-only mode
    /// When `true`, videos load only the audio stream and display the thumbnail.
    /// ~90% data reduction vs 1080p. Live streams are excluded automatically.
    public var audioOnlyMode: Bool

    // MARK: Codec preference
    /// When `true`, restricts adaptive video format selection to H.264 (`avc1`) only.
    /// Mirrors Android's `limitVideoCodec("avc1")` opt-in for devices with VP9/AV1
    /// decoder issues. Defaults to `false` (all codecs allowed).
    public var preferH264: Bool

    // MARK: iCloud sync
    /// When `true`, local user data (subscriptions, RSS feeds, video state, queue) is
    /// synced to iCloud via `NSUbiquitousKeyValueStore`. Defaults to `false` (opt-in).
    public var iCloudSyncEnabled: Bool

    // MARK: Offline downloads
    /// A job is one video, audio or translation track, including source resolution.
    public var maximumConcurrentDownloads: Int
    public static let defaultConcurrentDownloads = 2
    public static let availableConcurrentDownloadCounts = 1...4

    public static func clampedConcurrentDownloads(_ value: Int) -> Int {
        min(max(value, availableConcurrentDownloadCounts.lowerBound), availableConcurrentDownloadCounts.upperBound)
    }

    // MARK: Schema version
    /// Persisted schema version. Starts at 1 for newly stored settings.
    /// Old JSON lacking this key decodes as 0, signalling a pre-migration store.
    /// Increment when a breaking schema change requires a migration step.
    public var settingsVersion: Int

    // MARK: Types

    /// Canonical ordered list of selectable playback speeds — single source of truth.
    public static let availableSpeeds: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Canonical ordered list of selectable seek-interval values (seconds) — used by Stepper on iOS and Picker on tvOS.
    public static let availableSeekOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

    /// Every column count a stored setting may hold; each device offers a part of it (Mac up to 5, iPad landscape 4).
    public static let availableGridColumnCounts: ClosedRange<Int> = 1...5

    /// `.system` is the VoxaFrame coral on iPhone and iPad and the platform accent on macOS and tvOS.
    /// The UI target resolves each choice to a colour (on iPhone and iPad, the design's contrast-safe pair).
    public enum AccentColorChoice: String, Codable, CaseIterable, Sendable {
        case system, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink
    }

    public enum VideoQuality: String, Codable, CaseIterable, Sendable {
        case auto = "auto"
        case q2160 = "2160p"
        case q1440 = "1440p"
        case q1080 = "1080p"
        case q720 = "720p"
        case q480 = "480p"
        case q360 = "360p"
        case q240 = "240p"
        case q144 = "144p"

        /// The maximum pixel height corresponding to this quality level.
        /// Returns `nil` for `.auto` (no cap).
        public var maxHeight: Int? {
            switch self {
            case .auto: return nil
            case .q144: return 144
            case .q240: return 240
            case .q360: return 360
            case .q480: return 480
            case .q720: return 720
            case .q1080: return 1080
            case .q1440: return 1440
            case .q2160: return 2160
            }
        }

        /// Returns the `VideoQuality` matching an exact pixel height, or `nil` if none matches.
        public static func from(height: Int) -> VideoQuality? {
            allCases.first { $0.maxHeight == height }
        }
    }

    public enum ThemeName: String, Codable, CaseIterable {
        case system = "System"
        case dark = "Dark"
        case light = "Light"
    }

    // MARK: Defaults

    public init() {
        preferredQuality = .auto
        lastVideoQuality = nil
        playbackSpeed = 1.0
        autoplayEnabled = true
        subtitlesLanguage = nil
        backgroundPlaybackEnabled = false
        landscapeAlwaysPlay = false
        pipEnabled = true
        miniPlayerEnabled = true
        seekBackSeconds = 10
        seekForwardSeconds = 30
        controlsHideTimeout = 4
        videoGravityMode = .fit
        loopEnabled = false
        shuffleEnabled = false
        queueShuffleEnabled = false
        defaultSection = BrowseSection.SectionType.home.rawValue
        compactThumbnails = false
        highResThumbnails = false
        hideWatchedVideos = false
        hideWatchedThreshold = 0.9
        disableLiquidGlass = false
        settingsPINHash = nil
        hideShorts = true
        showQueueTab = false
        hideLiveShorts = false
        hideVideoPremieres = false
        perDeviceRecommendationsEnabled = true
        themeName = .system
        accentColor = .system
        gridColumnsPortrait = 2
        gridColumnsLandscape = 3
        enabledSections = BrowseSection.defaultSections.map(\.type)
        historyState = .enabled
        sponsorBlockEnabled = true
        // Default actions mirror Android's SponsorBlockData defaults:
        //   sponsor / selfPromo → auto-skip; interaction / intro / preview / musicOfftopic → show toast; others → nothing
        sponsorBlockActions = [
            .sponsor: .skip,
            .selfPromo: .skip,
            .interaction: .showToast,
            .intro: .showToast,
            .outro: .nothing,
            .preview: .showToast,
            .filler: .nothing,
            .musicOfftopic: .showToast,
            .poiHighlight: .nothing,
        ]
        sponsorBlockMinSegmentDuration = 0
        sponsorBlockExcludedChannels = [:]
        offlineSponsorBlockAutoUpdate = true
        blockedChannels = [:]
        preferredAudioLanguage = nil
        yandexVOTEnabled = false
        yandexVOTLivelyVoice = false
        yandexVOTKeepOriginalAudio = true
        shortsPlaybackSpeed = 1.0
        shortsPreferredAudioLanguage = nil
        shortsYandexVOTEnabled = false
        shortsYandexVOTLivelyVoice = false
        shortsYandexVOTKeepOriginalAudio = true
        vp9Enabled = true
        h264Enabled = false
        preferredCaptionLanguage = nil
        deArrowEnabled = false
        poTokenServiceURL = nil
        audioOnlyMode = false
        preferH264 = false
        iCloudSyncEnabled = false
        maximumConcurrentDownloads = Self.defaultConcurrentDownloads
        settingsVersion = 1
    }
}

// MARK: - Forward-compatible Codable

// The synthesized init(from:) requires ALL non-Optional properties to be present in the
// stored JSON. If any property is added, renamed, or type-changed in a new app version,
// the decode throws and SettingsStore silently resets all settings to defaults (bug #181).
//
// This custom init(from:) uses decodeIfPresent with per-field defaults so that:
//  - New fields get their default value when absent from old JSON (forward compatibility).
//  - Renamed/type-changed fields fall back to defaults rather than wiping everything.
//  - settingsVersion = 0 in old JSON signals a pre-migration store for future use.

private extension KeyedDecodingContainer {
    /// Decodes T if the key exists and the value is the right type; returns `defaultValue`
    /// for absent keys, null values, or type mismatches — never throws.
    func safeDecode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

extension AppSettings {
    // Explicit CodingKeys keep JSON key names stable even if Swift property names change.
    enum CodingKeys: String, CodingKey {
        case settingsVersion
        case preferredQuality
        case lastVideoQuality
        case playbackSpeed
        case shortsPlaybackSpeed
        case autoplayEnabled
        case subtitlesLanguage
        case backgroundPlaybackEnabled
        case landscapeAlwaysPlay
        case pipEnabled
        case miniPlayerEnabled
        case seekBackSeconds
        case seekForwardSeconds
        case controlsHideTimeout
        case videoGravityMode
        case loopEnabled
        case shuffleEnabled
        case queueShuffleEnabled
        case defaultSection
        case compactThumbnails
        case highResThumbnails
        case hideWatchedVideos
        case hideWatchedThreshold
        case disableLiquidGlass
        case settingsPINHash
        case hideShorts
        case showQueueTab
        case hideLiveShorts
        case hideVideoPremieres
        case perDeviceRecommendationsEnabled
        case themeName
        case accentColor
        case gridColumnsPortrait
        case gridColumnsLandscape
        case enabledSections
        case historyState
        case sponsorBlockEnabled
        case sponsorBlockActions
        case sponsorBlockMinSegmentDuration
        case sponsorBlockExcludedChannels
        case offlineSponsorBlockAutoUpdate
        case blockedChannels
        case preferredAudioLanguage
        case yandexVOTEnabled
        case yandexVOTLivelyVoice
        case yandexVOTKeepOriginalAudio
        case shortsPreferredAudioLanguage
        case shortsYandexVOTEnabled
        case shortsYandexVOTLivelyVoice
        case shortsYandexVOTKeepOriginalAudio
        case vp9Enabled
        case h264Enabled
        case preferredCaptionLanguage
        case deArrowEnabled
        case poTokenServiceURL
        case audioOnlyMode
        case preferH264
        case iCloudSyncEnabled
        case maximumConcurrentDownloads
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()  // defaults for any missing/mismatched field
        self = d
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settingsVersion = c.safeDecode(Int.self, forKey: .settingsVersion, default: 0)
        preferredQuality = c.safeDecode(VideoQuality.self, forKey: .preferredQuality, default: d.preferredQuality)
        lastVideoQuality = c.safeDecode(VideoQualityPreference?.self, forKey: .lastVideoQuality, default: nil)
        playbackSpeed = c.safeDecode(Double.self, forKey: .playbackSpeed, default: d.playbackSpeed)
        // Preserve the formerly shared choice once; subsequent saves keep the two speeds separate.
        shortsPlaybackSpeed = c.safeDecode(Double.self, forKey: .shortsPlaybackSpeed, default: playbackSpeed)
        autoplayEnabled = c.safeDecode(Bool.self, forKey: .autoplayEnabled, default: d.autoplayEnabled)
        subtitlesLanguage = c.safeDecode(String?.self, forKey: .subtitlesLanguage, default: d.subtitlesLanguage)
        backgroundPlaybackEnabled = c.safeDecode(
            Bool.self, forKey: .backgroundPlaybackEnabled, default: d.backgroundPlaybackEnabled)
        landscapeAlwaysPlay = c.safeDecode(Bool.self, forKey: .landscapeAlwaysPlay, default: d.landscapeAlwaysPlay)
        pipEnabled = c.safeDecode(Bool.self, forKey: .pipEnabled, default: d.pipEnabled)
        miniPlayerEnabled = c.safeDecode(Bool.self, forKey: .miniPlayerEnabled, default: d.miniPlayerEnabled)
        seekBackSeconds = c.safeDecode(Int.self, forKey: .seekBackSeconds, default: d.seekBackSeconds)
        seekForwardSeconds = c.safeDecode(Int.self, forKey: .seekForwardSeconds, default: d.seekForwardSeconds)
        controlsHideTimeout = c.safeDecode(Int.self, forKey: .controlsHideTimeout, default: d.controlsHideTimeout)
        videoGravityMode = c.safeDecode(VideoGravityMode.self, forKey: .videoGravityMode, default: d.videoGravityMode)
        loopEnabled = c.safeDecode(Bool.self, forKey: .loopEnabled, default: d.loopEnabled)
        shuffleEnabled = c.safeDecode(Bool.self, forKey: .shuffleEnabled, default: d.shuffleEnabled)
        queueShuffleEnabled = c.safeDecode(Bool.self, forKey: .queueShuffleEnabled, default: d.queueShuffleEnabled)
        defaultSection = c.safeDecode(String.self, forKey: .defaultSection, default: d.defaultSection)
        compactThumbnails = c.safeDecode(Bool.self, forKey: .compactThumbnails, default: d.compactThumbnails)
        highResThumbnails = c.safeDecode(Bool.self, forKey: .highResThumbnails, default: d.highResThumbnails)
        hideWatchedVideos = c.safeDecode(Bool.self, forKey: .hideWatchedVideos, default: d.hideWatchedVideos)
        hideWatchedThreshold = c.safeDecode(
            Double.self, forKey: .hideWatchedThreshold, default: d.hideWatchedThreshold)
        disableLiquidGlass = c.safeDecode(Bool.self, forKey: .disableLiquidGlass, default: d.disableLiquidGlass)
        settingsPINHash = c.safeDecode(String?.self, forKey: .settingsPINHash, default: d.settingsPINHash)
        hideShorts = c.safeDecode(Bool.self, forKey: .hideShorts, default: d.hideShorts)
        showQueueTab = c.safeDecode(Bool.self, forKey: .showQueueTab, default: d.showQueueTab)
        hideLiveShorts = c.safeDecode(Bool.self, forKey: .hideLiveShorts, default: d.hideLiveShorts)
        hideVideoPremieres = c.safeDecode(Bool.self, forKey: .hideVideoPremieres, default: d.hideVideoPremieres)
        perDeviceRecommendationsEnabled = c.safeDecode(
            Bool.self, forKey: .perDeviceRecommendationsEnabled, default: d.perDeviceRecommendationsEnabled)
        themeName = c.safeDecode(ThemeName.self, forKey: .themeName, default: d.themeName)
        accentColor = c.safeDecode(AccentColorChoice.self, forKey: .accentColor, default: d.accentColor)
        let columns = Self.availableGridColumnCounts
        gridColumnsPortrait = min(
            max(
                c.safeDecode(Int.self, forKey: .gridColumnsPortrait, default: d.gridColumnsPortrait), columns.lowerBound
            ),
            columns.upperBound)
        gridColumnsLandscape = min(
            max(
                c.safeDecode(Int.self, forKey: .gridColumnsLandscape, default: d.gridColumnsLandscape),
                columns.lowerBound),
            columns.upperBound)
        // Home is the recommendations feed now; drop the retired Recommended chip.
        enabledSections = c.safeDecode(
            [BrowseSection.SectionType].self, forKey: .enabledSections, default: d.enabledSections
        ).filter { $0 != .recommended }
        historyState = c.safeDecode(HistoryState.self, forKey: .historyState, default: d.historyState)
        decodeSponsorBlock(from: c, defaults: d)
        blockedChannels = c.safeDecode([String: String].self, forKey: .blockedChannels, default: d.blockedChannels)
        preferredAudioLanguage = c.safeDecode(
            String?.self, forKey: .preferredAudioLanguage, default: d.preferredAudioLanguage)
        yandexVOTEnabled = c.safeDecode(Bool.self, forKey: .yandexVOTEnabled, default: d.yandexVOTEnabled)
        yandexVOTLivelyVoice = c.safeDecode(Bool.self, forKey: .yandexVOTLivelyVoice, default: d.yandexVOTLivelyVoice)
        yandexVOTKeepOriginalAudio = c.safeDecode(
            Bool.self, forKey: .yandexVOTKeepOriginalAudio, default: d.yandexVOTKeepOriginalAudio)
        vp9Enabled = c.safeDecode(Bool.self, forKey: .vp9Enabled, default: d.vp9Enabled)
        h264Enabled = c.safeDecode(Bool.self, forKey: .h264Enabled, default: d.h264Enabled)
        preferredCaptionLanguage = c.safeDecode(
            String?.self, forKey: .preferredCaptionLanguage, default: d.preferredCaptionLanguage)
        deArrowEnabled = c.safeDecode(Bool.self, forKey: .deArrowEnabled, default: d.deArrowEnabled)
        poTokenServiceURL = c.safeDecode(URL?.self, forKey: .poTokenServiceURL, default: d.poTokenServiceURL)
        audioOnlyMode = c.safeDecode(Bool.self, forKey: .audioOnlyMode, default: d.audioOnlyMode)
        preferH264 = c.safeDecode(Bool.self, forKey: .preferH264, default: d.preferH264)
        iCloudSyncEnabled = c.safeDecode(Bool.self, forKey: .iCloudSyncEnabled, default: d.iCloudSyncEnabled)
        maximumConcurrentDownloads = Self.clampedConcurrentDownloads(
            c.safeDecode(Int.self, forKey: .maximumConcurrentDownloads, default: d.maximumConcurrentDownloads))
        decodeShortsTranslation(from: c)
    }

    private mutating func decodeSponsorBlock(
        from container: KeyedDecodingContainer<CodingKeys>, defaults: AppSettings
    ) {
        sponsorBlockEnabled = container.safeDecode(
            Bool.self, forKey: .sponsorBlockEnabled, default: defaults.sponsorBlockEnabled)
        sponsorBlockActions = container.safeDecode(
            [SponsorSegment.Category: SponsorBlockAction].self, forKey: .sponsorBlockActions,
            default: defaults.sponsorBlockActions)
        sponsorBlockMinSegmentDuration = container.safeDecode(
            Double.self, forKey: .sponsorBlockMinSegmentDuration, default: defaults.sponsorBlockMinSegmentDuration)
        sponsorBlockExcludedChannels = container.safeDecode(
            [String: String].self, forKey: .sponsorBlockExcludedChannels, default: defaults.sponsorBlockExcludedChannels
        )
        offlineSponsorBlockAutoUpdate = container.safeDecode(
            Bool.self, forKey: .offlineSponsorBlockAutoUpdate, default: defaults.offlineSponsorBlockAutoUpdate)
    }

    private mutating func decodeShortsTranslation(from container: KeyedDecodingContainer<CodingKeys>) {
        // Copy legacy choices once; an omitted optional language in a new profile means Auto.
        shortsPreferredAudioLanguage = container.safeDecode(
            String?.self, forKey: .shortsPreferredAudioLanguage,
            default: container.contains(.shortsYandexVOTEnabled) ? nil : preferredAudioLanguage)
        shortsYandexVOTEnabled = container.safeDecode(
            Bool.self, forKey: .shortsYandexVOTEnabled, default: yandexVOTEnabled)
        shortsYandexVOTLivelyVoice = container.safeDecode(
            Bool.self, forKey: .shortsYandexVOTLivelyVoice, default: yandexVOTLivelyVoice)
        shortsYandexVOTKeepOriginalAudio = container.safeDecode(
            Bool.self, forKey: .shortsYandexVOTKeepOriginalAudio, default: yandexVOTKeepOriginalAudio)
    }
}
