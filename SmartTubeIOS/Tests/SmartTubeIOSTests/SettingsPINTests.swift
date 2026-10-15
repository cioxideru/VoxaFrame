import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - SettingsPINTests (#126)

@Suite("SettingsPINHasher")
struct SettingsPINHasherTests {

    @Test("same PIN hashes to the same value")
    func sameInputSameHash() {
        #expect(SettingsPINHasher.hash("1234") == SettingsPINHasher.hash("1234"))
    }

    @Test("different PINs hash to different values")
    func differentInputDifferentHash() {
        #expect(SettingsPINHasher.hash("1234") != SettingsPINHasher.hash("4321"))
    }

    @Test("hash never equals the raw PIN")
    func hashIsNotPlaintext() {
        #expect(SettingsPINHasher.hash("1234") != "1234")
    }
}

@Suite("AppSettings.settingsPINHash (#126)")
struct SettingsPINHashSettingTests {

    @Test("defaults to nil — no PIN configured out of the box")
    func defaultsToNil() {
        #expect(AppSettings().settingsPINHash == nil)
    }

    @Test("encode/decode round-trip preserves the value")
    func roundTripPreservesValue() throws {
        var original = AppSettings()
        original.settingsPINHash = SettingsPINHasher.hash("1234")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        #expect(decoded.settingsPINHash == original.settingsPINHash)
    }

    @Test("old JSON missing this field decodes to nil instead of failing")
    func missingFieldDecodesToDefault() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        #expect(settings.settingsPINHash == nil)
    }
}
