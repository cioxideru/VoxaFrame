import Foundation
import SmartTubeIOSCore

// MARK: - SettingsConfirmationText (PLAN-0027 B1, B2)
//
// Message text for the two destructive Settings confirmations. The wording follows what the actions
// really touch: `LocalWatchHistoryStore.clear()` empties only the on-device watch list, and
// `SettingsStore.reset()` replaces `AppSettings` (every preference, the PIN hash, the hidden and
// SponsorBlock-excluded channel lists, the iCloud switch) and nothing stored outside it.

enum SettingsConfirmationText {
    /// B1: how many entries "Clear Watch History on This Device" removes, and what it leaves alone.
    static func clearHistoryMessage(entryCount: Int, locale: Locale = .current) -> String {
        [
            localized("\(entryCount) videos will be removed from the watch history on this device.", locale),
            localized(
                "Your YouTube history, search history, saved playback positions, offline videos and queue are not affected.",
                locale),
        ].joined(separator: " ")
    }

    /// B2: one line per consequence of "Reset All Settings" for the current settings, then what is kept.
    static func resetAllConsequences(for settings: AppSettings, locale: Locale = .current) -> [String] {
        var lines = [
            localized("All app settings return to their defaults, including options changed in the player.", locale)
        ]
        if settings.settingsPINHash != nil {
            lines.append(localized("The Settings PIN is removed.", locale))
        }
        if !settings.blockedChannels.isEmpty {
            lines.append(localized("Hidden channels appear in feeds again.", locale))
        }
        if !settings.sponsorBlockExcludedChannels.isEmpty {
            lines.append(localized("The SponsorBlock excluded channels list is cleared.", locale))
        }
        if settings.iCloudSyncEnabled {
            lines.append(localized("iCloud Sync turns off.", locale))
        }
        lines.append(
            localized(
                "Your Google sign-in, Yandex token, watch history, subscriptions, RSS feeds, queue and offline videos are not affected.",
                locale))
        return lines
    }

    private static func localized(_ value: String.LocalizationValue, _ locale: Locale) -> String {
        String(localized: LocalizedStringResource(value, locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
    }
}
