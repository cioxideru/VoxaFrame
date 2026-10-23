import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// `writes` has a single consumer: the main-actor store under test and its test body.
private final class CountingDefaults: UserDefaults, @unchecked Sendable {
    var writes = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }
}

// `SettingsStore.save()` writes `iCloudSyncManager.shared.syncEnabled`.
extension SyncEnabledSuites {
    @MainActor
    @Suite("SettingsStore saves")
    struct SettingsStoreSaveTests {
        @Test("A settings action that changes two values saves once")
        func batchedUpdateSavesOnce() throws {
            let suite = "SettingsStoreSaveTests.\(UUID().uuidString)"
            let defaults = try #require(CountingDefaults(suiteName: suite))
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let store = SettingsStore(defaults: defaults)
            store.settings.lastVideoQuality = VideoQualityPreference(height: 480)
            defaults.writes = 0
            store.update {
                $0.preferredQuality = .q720
                $0.lastVideoQuality = nil
            }
            #expect(defaults.writes == 1)
            let reloaded = SettingsStore(defaults: defaults)
            #expect(reloaded.settings.preferredQuality == .q720)
            #expect(reloaded.settings.lastVideoQuality == nil)
        }

        @Test(
            "Each thumbnail style saves once and maps back to itself",
            arguments: [
                SettingsView.ThumbnailStyle.standard, .highResolution, .compact,
            ])
        func thumbnailStyleSavesOnce(style: SettingsView.ThumbnailStyle) throws {
            let suite = "SettingsStoreSaveTests.\(UUID().uuidString)"
            let defaults = try #require(CountingDefaults(suiteName: suite))
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let store = SettingsStore(defaults: defaults)
            store.settings.compactThumbnails = style != .compact
            store.settings.highResThumbnails = style != .highResolution
            defaults.writes = 0
            store.update { style.apply(to: &$0) }
            #expect(defaults.writes == 1)
            #expect(SettingsView.ThumbnailStyle(store.settings) == style)
            #expect(store.settings.compactThumbnails == (style == .compact))
            #expect(store.settings.highResThumbnails == (style == .highResolution))
        }
    }
}
