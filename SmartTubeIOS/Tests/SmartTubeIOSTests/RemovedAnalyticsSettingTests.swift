import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - RemovedAnalyticsSettingTests

/// The `disableAnalytics` setting (#92) was removed together with crash reporting. Settings
/// saved by older builds still contain the key and must keep decoding.
@Suite("AppSettings without disableAnalytics")
struct RemovedAnalyticsSettingTests {

    @Test("old JSON with disableAnalytics still decodes and keeps other values", arguments: [false, true])
    func legacyKeyIsIgnored(disabled: Bool) throws {
        let json = Data(#"{"disableAnalytics": \#(disabled), "hideShorts": true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        #expect(settings.hideShorts == true)
    }

    @Test("encoded settings no longer contain disableAnalytics")
    func keyIsNotEncoded() throws {
        let encoded = try JSONEncoder().encode(AppSettings())
        let text = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(!text.contains("disableAnalytics"))
    }
}
