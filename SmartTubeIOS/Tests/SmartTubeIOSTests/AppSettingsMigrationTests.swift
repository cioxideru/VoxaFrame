import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - AppSettingsMigrationTests
//
// Regression tests for task #181: user settings (quality, theme, SponsorBlock, etc.)
// were silently reset to defaults on every app update that added or renamed a property
// in AppSettings.
//
// Root cause: the synthesized Codable init(from:) requires ALL non-Optional properties
// to be present in the JSON. A single missing property (added in a new version) causes
// JSONDecoder to throw, which SettingsStore catches via `try?` and falls back to a fresh
// AppSettings() — wiping all user preferences.
//
// Fix: custom init(from:) using decodeIfPresent with per-field defaults so that missing
// keys always receive their intended default rather than causing a total settings reset.

@Suite("AppSettings forward-compatible decoding (#181)")
struct AppSettingsMigrationTests {

    @Test("Older settings default to two simultaneous downloads and preserve other preferences")
    func defaultConcurrentDownloads() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"playbackSpeed":1.5}"#.utf8))
        #expect(settings.maximumConcurrentDownloads == AppSettings.defaultConcurrentDownloads)
        #expect(settings.maximumConcurrentDownloads == 2)
        #expect(settings.playbackSpeed == 1.5)
    }

    @Test("A stored Recommended chip is dropped and the rest of the section order survives")
    func retiredRecommendedSection() throws {
        let json = #"{"enabledSections":["home","recommended","history","subscriptions"],"playbackSpeed":1.5}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.enabledSections == [.home, .history, .subscriptions])
        #expect(settings.playbackSpeed == 1.5)
        #expect(!BrowseSection.allSections.contains { $0.type == .recommended })
    }

    @Test("Simultaneous download limit survives saves", arguments: AppSettings.availableConcurrentDownloadCounts)
    func concurrentDownloadsRoundTrip(limit: Int) throws {
        var settings = AppSettings()
        settings.maximumConcurrentDownloads = limit
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.maximumConcurrentDownloads == limit)
    }

    @Test("Invalid saved limits remain in the supported range", arguments: [0, -4, 5, Int.max])
    func concurrentDownloadsClampsInvalidValues(limit: Int) throws {
        let data = Data("{\"maximumConcurrentDownloads\":\(limit)}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.maximumConcurrentDownloads == AppSettings.clampedConcurrentDownloads(limit))
        #expect(AppSettings.availableConcurrentDownloadCounts.contains(settings.maximumConcurrentDownloads))
    }

    @Test("Null and mismatched limits use the default", arguments: ["null", "\"four\"", "true"])
    func concurrentDownloadsIgnoresMismatchedValues(value: String) throws {
        let data = Data("{\"maximumConcurrentDownloads\":\(value),\"playbackSpeed\":1.5}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.maximumConcurrentDownloads == AppSettings.defaultConcurrentDownloads)
        #expect(settings.playbackSpeed == 1.5)
    }

    @Test("Legacy playback speed seeds Shorts once without resetting other preferences")
    func migrateShortsPlaybackSpeed() throws {
        let data = Data(#"{"playbackSpeed":1.5,"autoplayEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.playbackSpeed == 1.5)
        #expect(settings.shortsPlaybackSpeed == 1.5)
        #expect(!settings.autoplayEnabled)
        #expect(AppSettings().shortsPlaybackSpeed == 1)
    }

    @Test("Shorts speed survives saves independently of regular speed", arguments: AppSettings.availableSpeeds)
    func independentShortsSpeedRoundTrip(speed: Double) throws {
        var settings = AppSettings()
        settings.playbackSpeed = 1.25
        settings.shortsPlaybackSpeed = speed
        var restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        restored.playbackSpeed = 2
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(restored))
        #expect(reloaded.playbackSpeed == 2)
        #expect(reloaded.shortsPlaybackSpeed == speed)
        #expect(reloaded.shortsPlaybackSettings.playbackSpeed == speed)
    }

    @Test("Legacy translation preferences seed an independent Shorts copy")
    func migrateShortsTranslationPreferences() throws {
        let json = Data(
            """
            {"preferredAudioLanguage":"ru","yandexVOTEnabled":true,
             "yandexVOTLivelyVoice":true,"yandexVOTKeepOriginalAudio":false,"playbackSpeed":1.5}
            """.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.shortsPreferredAudioLanguage == "ru")
        #expect(settings.shortsYandexVOTEnabled)
        #expect(settings.shortsYandexVOTLivelyVoice)
        #expect(!settings.shortsYandexVOTKeepOriginalAudio)
        #expect(settings.preferredAudioLanguage == "ru")
        #expect(settings.playbackSpeed == 1.5)
    }

    @Test(
        "Shorts Auto and disabled choices survive saves and regular-player changes",
        arguments: [nil, "en"] as [String?])
    func independentShortsPreferencesRoundTrip(language: String?) throws {
        var settings = AppSettings()
        settings.preferredAudioLanguage = "ru"
        settings.yandexVOTEnabled = true
        settings.yandexVOTLivelyVoice = true
        settings.shortsPreferredAudioLanguage = language
        settings.shortsYandexVOTKeepOriginalAudio = false
        let data = try JSONEncoder().encode(settings)
        var restored = try JSONDecoder().decode(AppSettings.self, from: data)
        restored.preferredAudioLanguage = "kk"
        let savedAgain = try JSONEncoder().encode(restored)
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: savedAgain)
        #expect(reloaded.shortsPreferredAudioLanguage == language)
        #expect(!reloaded.shortsYandexVOTEnabled)
        #expect(!reloaded.shortsYandexVOTLivelyVoice)
        #expect(!reloaded.shortsYandexVOTKeepOriginalAudio)
        #expect(reloaded.preferredAudioLanguage == "kk")
        #expect(reloaded.yandexVOTEnabled)
        #expect(reloaded.yandexVOTLivelyVoice)
        #expect(reloaded.yandexVOTKeepOriginalAudio)
    }

    // MARK: - Missing new field → default, other fields preserved

    /// Simulates loading settings stored by an old app version that doesn't have
    /// a field that was added in the current version (e.g. `settingsVersion`).
    /// The decode must succeed and return the stored values, not fall back to defaults.
    @Test("Old JSON missing new field decodes successfully with stored values preserved")
    func oldJSONMissingNewFieldDecodeSucceeds() throws {
        // JSON without `settingsVersion` (a field added in the current version)
        let json = """
            {
                "preferredQuality": "1080p",
                "playbackSpeed": 1.5,
                "autoplayEnabled": false,
                "backgroundPlaybackEnabled": false,
                "landscapeAlwaysPlay": true,
                "pipEnabled": false,
                "miniPlayerEnabled": true,
                "seekBackSeconds": 15,
                "seekForwardSeconds": 45,
                "controlsHideTimeout": 6,
                "videoGravityMode": "fill",
                "loopEnabled": true,
                "shuffleEnabled": false,
                "defaultSection": "subscriptions",
                "compactThumbnails": true,
                "hideShorts": true,
                "perDeviceRecommendationsEnabled": false,
                "themeName": "Dark",
                "enabledSections": ["home", "subscriptions"],
                "historyState": "disabled",
                "sponsorBlockEnabled": false,
                "sponsorBlockActions": {},
                "sponsorBlockMinSegmentDuration": 2.5,
                "sponsorBlockExcludedChannels": {},
                "deArrowEnabled": true,
                "audioOnlyMode": true,
                "preferH264": true,
                "iCloudSyncEnabled": true
            }
            """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        // Stored values must survive
        #expect(settings.preferredQuality == .q1080)
        #expect(settings.playbackSpeed == 1.5)
        #expect(settings.autoplayEnabled == false)
        #expect(settings.landscapeAlwaysPlay == true)
        #expect(settings.pipEnabled == false)
        #expect(settings.seekBackSeconds == 15)
        #expect(settings.seekForwardSeconds == 45)
        #expect(settings.controlsHideTimeout == 6)
        #expect(settings.videoGravityMode == .fill)
        #expect(settings.loopEnabled == true)
        #expect(settings.hideShorts == true)
        #expect(settings.themeName == .dark)
        #expect(settings.historyState == .disabled)
        #expect(settings.sponsorBlockEnabled == false)
        #expect(settings.sponsorBlockMinSegmentDuration == 2.5)
        #expect(settings.deArrowEnabled == true)
        #expect(settings.audioOnlyMode == true)
        #expect(settings.preferH264 == true)
        #expect(settings.iCloudSyncEnabled == true)

        // Missing field must decode to 0 (the pre-migration sentinel)
        #expect(
            settings.settingsVersion == 0,
            "Old JSON without settingsVersion should decode as 0 (migration sentinel), not fail")
    }

    // MARK: - Type-mismatched field → default for that field, others preserved

    /// Simulates a field whose stored type no longer matches (e.g. Bool stored where Int expected).
    /// Only the mismatched field should fall to its default; all other fields must be preserved.
    @Test("Type-mismatched field falls to default, all other fields preserved")
    func typeMismatchedFieldFallsToDefault() throws {
        // controlsHideTimeout stored as a string (invalid) — was Int
        let json = """
            {
                "preferredQuality": "720p",
                "playbackSpeed": 2.0,
                "autoplayEnabled": true,
                "backgroundPlaybackEnabled": false,
                "landscapeAlwaysPlay": false,
                "pipEnabled": true,
                "miniPlayerEnabled": true,
                "seekBackSeconds": 10,
                "seekForwardSeconds": 30,
                "controlsHideTimeout": "bad_value",
                "videoGravityMode": "fit",
                "loopEnabled": false,
                "shuffleEnabled": false,
                "defaultSection": "home",
                "compactThumbnails": false,
                "hideShorts": false,
                "perDeviceRecommendationsEnabled": true,
                "themeName": "System",
                "enabledSections": [],
                "historyState": "enabled",
                "sponsorBlockEnabled": true,
                "sponsorBlockActions": {},
                "sponsorBlockMinSegmentDuration": 0,
                "sponsorBlockExcludedChannels": {},
                "deArrowEnabled": false,
                "audioOnlyMode": false,
                "preferH264": false,
                "iCloudSyncEnabled": false,
                "settingsVersion": 1
            }
            """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        // Type-mismatched field falls to default (4 seconds)
        #expect(
            settings.controlsHideTimeout == 4,
            "Type-mismatched field must fall to its default, not crash/reset all settings")

        // All other stored values must survive
        #expect(settings.preferredQuality == .q720)
        #expect(settings.playbackSpeed == 2.0)
        #expect(settings.settingsVersion == 1)
    }

    // MARK: - Round-trip: encode then decode preserves all values

    /// Verifies that a full encode → decode cycle preserves every field including
    /// settingsVersion. This confirms the custom init(from:) and synthesized encode(to:)
    /// are consistent with each other.
    @Test("Full encode/decode round-trip preserves all settings")
    func roundTripPreservesAllSettings() throws {
        var original = AppSettings()
        original.preferredQuality = .q1440
        original.playbackSpeed = 0.75
        original.autoplayEnabled = false
        original.subtitlesLanguage = "fr"
        original.landscapeAlwaysPlay = true
        original.seekBackSeconds = 20
        original.seekForwardSeconds = 60
        original.controlsHideTimeout = 8
        original.videoGravityMode = .fill
        original.hideShorts = true
        original.themeName = .dark
        original.historyState = .disabled
        original.sponsorBlockEnabled = false
        original.deArrowEnabled = true
        original.iCloudSyncEnabled = true
        original.settingsVersion = 1

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.preferredQuality == original.preferredQuality)
        #expect(decoded.playbackSpeed == original.playbackSpeed)
        #expect(decoded.autoplayEnabled == original.autoplayEnabled)
        #expect(decoded.subtitlesLanguage == original.subtitlesLanguage)
        #expect(decoded.landscapeAlwaysPlay == original.landscapeAlwaysPlay)
        #expect(decoded.seekBackSeconds == original.seekBackSeconds)
        #expect(decoded.seekForwardSeconds == original.seekForwardSeconds)
        #expect(decoded.controlsHideTimeout == original.controlsHideTimeout)
        #expect(decoded.videoGravityMode == original.videoGravityMode)
        #expect(decoded.hideShorts == original.hideShorts)
        #expect(decoded.themeName == original.themeName)
        #expect(decoded.historyState == original.historyState)
        #expect(decoded.sponsorBlockEnabled == original.sponsorBlockEnabled)
        #expect(decoded.deArrowEnabled == original.deArrowEnabled)
        #expect(decoded.iCloudSyncEnabled == original.iCloudSyncEnabled)
        #expect(decoded.settingsVersion == original.settingsVersion)
    }

    // MARK: - Completely empty JSON → all defaults (no crash)

    /// Simulates a completely empty JSON object (e.g. corrupted store).
    /// Must return all defaults rather than throwing or crashing.
    @Test("Completely empty JSON decodes to all defaults without crashing")
    func emptyJSONDecodesToDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        let defaults = AppSettings()

        #expect(settings.preferredQuality == defaults.preferredQuality)
        #expect(settings.playbackSpeed == defaults.playbackSpeed)
        #expect(settings.autoplayEnabled == defaults.autoplayEnabled)
        #expect(settings.seekBackSeconds == defaults.seekBackSeconds)
        #expect(settings.sponsorBlockEnabled == defaults.sponsorBlockEnabled)
        #expect(settings.settingsVersion == 0, "Empty JSON should yield settingsVersion=0 (migration sentinel)")
    }
}
