import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - DisableLiquidGlassSettingTests (#107)

@Suite("AppSettings.disableLiquidGlass (#107)")
struct DisableLiquidGlassSettingTests {

    @Test("defaults to false")
    func defaultsToFalse() {
        #expect(AppSettings().disableLiquidGlass == false)
    }

    @Test("encode/decode round-trip preserves the value")
    func roundTripPreservesValue() throws {
        var original = AppSettings()
        original.disableLiquidGlass = true

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.disableLiquidGlass == true)
    }

    @Test("old JSON missing this field decodes to the default instead of failing")
    func missingFieldDecodesToDefault() throws {
        // Mirrors AppSettingsMigrationTests' pattern: a field added after some users
        // already had settings stored must not cause the whole decode to fail.
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        #expect(settings.disableLiquidGlass == false)
    }
}
