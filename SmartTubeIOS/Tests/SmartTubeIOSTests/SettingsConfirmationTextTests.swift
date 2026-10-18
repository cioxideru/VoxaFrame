import Foundation
import SmartTubeIOSCore
import Testing

@testable import SmartTubeIOS

// MARK: - SettingsConfirmationTextTests (PLAN-0027 B1, B2)

@Suite("Settings confirmation text")
struct SettingsConfirmationTextTests {
    private let english = Locale(identifier: "en")
    private let russian = Locale(identifier: "ru")
    private let notAffected =
        "Your YouTube history, search history, saved playback positions, offline videos and queue are not affected."

    @Test(
        "Clear history names the entry count and what is kept",
        arguments: [
            (0, "0 videos will be removed from the watch history on this device."),
            (1, "1 video will be removed from the watch history on this device."),
            (48, "48 videos will be removed from the watch history on this device."),
        ])
    func clearHistoryMessage(count: Int, sentence: String) {
        #expect(
            SettingsConfirmationText.clearHistoryMessage(entryCount: count, locale: english)
                == "\(sentence) \(notAffected)")
    }

    @Test(
        "Clear history uses the Russian plural forms",
        arguments: [(1, "будет удалено 1 видео"), (3, "будут удалены 3 видео"), (5, "будет удалено 5 видео")])
    func clearHistoryRussianPlural(count: Int, fragment: String) {
        let message = SettingsConfirmationText.clearHistoryMessage(entryCount: count, locale: russian)
        #expect(message.contains(fragment))
        #expect(message.contains("очередь не изменятся"))
    }

    @Test("Reset with default settings lists only the reset and what is kept")
    func resetDefaults() {
        let lines = SettingsConfirmationText.resetAllConsequences(for: AppSettings(), locale: english)
        #expect(
            lines == [
                "All app settings return to their defaults, including options changed in the player.",
                "Your Google sign-in, Yandex token, watch history, subscriptions, RSS feeds, queue and offline videos are not affected.",
            ])
    }

    @Test("Reset names the PIN and every user list it clears")
    func resetWithPINAndLists() {
        var settings = AppSettings()
        settings.settingsPINHash = SettingsPINHasher.hash("1234")
        settings.blockedChannels = ["UC1": "Channel"]
        settings.sponsorBlockExcludedChannels = ["UC2": "Other"]
        settings.iCloudSyncEnabled = true
        let lines = SettingsConfirmationText.resetAllConsequences(for: settings, locale: english)
        #expect(
            lines.dropFirst().dropLast() == [
                "The Settings PIN is removed.",
                "Hidden channels appear in feeds again.",
                "The SponsorBlock excluded channels list is cleared.",
                "iCloud Sync turns off.",
            ])
    }

    @Test("Reset without a PIN does not mention it")
    func resetWithoutPIN() {
        var settings = AppSettings()
        settings.iCloudSyncEnabled = true
        let lines = SettingsConfirmationText.resetAllConsequences(for: settings, locale: english)
        #expect(!lines.contains("The Settings PIN is removed."))
        #expect(lines.contains("iCloud Sync turns off."))
    }

    @Test("Reset text is translated into Russian")
    func resetRussian() {
        var settings = AppSettings()
        settings.settingsPINHash = SettingsPINHasher.hash("1234")
        let lines = SettingsConfirmationText.resetAllConsequences(for: settings, locale: russian)
        #expect(lines.contains("PIN для настроек будет удалён."))
    }
}
