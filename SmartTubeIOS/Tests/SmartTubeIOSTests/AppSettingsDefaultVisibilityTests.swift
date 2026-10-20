import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("AppSettings visibility defaults")
struct AppSettingsDefaultVisibilityTests {

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test("New installs hide Shorts and the Queue tab")
    func newInstallDefaults() {
        let settings = AppSettings()
        #expect(settings.hideShorts == true)
        #expect(settings.showQueueTab == false)
    }

    @Test("Stored settings without the keys pick the new defaults")
    func missingKeysUseNewDefaults() throws {
        let settings = try decode(#"{"playbackSpeed": 1.5}"#)
        #expect(settings.hideShorts == true)
        #expect(settings.showQueueTab == false)
    }

    @Test("Stored values are kept")
    func storedValuesAreKept() throws {
        let settings = try decode(#"{"hideShorts": false, "showQueueTab": true}"#)
        #expect(settings.hideShorts == false)
        #expect(settings.showQueueTab == true)
    }

    @Test("Stored values survive an encode and decode round trip")
    func roundTrip() throws {
        var original = AppSettings()
        original.hideShorts = false
        original.showQueueTab = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
        #expect(decoded.hideShorts == false)
        #expect(decoded.showQueueTab == true)
    }
}
