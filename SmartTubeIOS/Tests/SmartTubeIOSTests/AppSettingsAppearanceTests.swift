import Foundation
import SwiftUI
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("AppSettings accent color and grid columns")
struct AppSettingsAppearanceTests {

    @Test("Theme UI adapter preserves system, dark and light appearance")
    func themeColorScheme() {
        #expect(AppSettings.ThemeName.system.colorScheme == nil)
        #expect(AppSettings.ThemeName.dark.colorScheme == ColorScheme.dark)
        #expect(AppSettings.ThemeName.light.colorScheme == ColorScheme.light)
    }

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test("Missing keys fall back to defaults")
    func missingKeysUseDefaults() throws {
        let settings = try decode("{}")
        #expect(settings.accentColor == .system)
        #expect(settings.gridColumnsPortrait == 2)
        #expect(settings.gridColumnsLandscape == 3)
    }

    @Test("Accent color round-trips", arguments: AppSettings.AccentColorChoice.allCases)
    func accentColorRoundTrip(choice: AppSettings.AccentColorChoice) throws {
        var settings = AppSettings()
        settings.accentColor = choice
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.accentColor == choice)
    }

    @Test("Unknown accent color falls back to system")
    func unknownAccentColor() throws {
        #expect(try decode(#"{"accentColor": "chartreuse"}"#).accentColor == .system)
    }

    @Test("Column counts are clamped to the selectable range")
    func columnsClamped() throws {
        let settings = try decode(#"{"gridColumnsPortrait": 0, "gridColumnsLandscape": 9}"#)
        #expect(settings.gridColumnsPortrait == 1)
        #expect(settings.gridColumnsLandscape == 6)
        #expect(try decode(#"{"gridColumnsLandscape": "six"}"#).gridColumnsLandscape == 3)
    }

    @Test("Saved column counts from before six columns stay as they are", arguments: 1...5)
    func columnsPreserved(count: Int) throws {
        let settings = try decode(#"{"gridColumnsPortrait": \#(count), "gridColumnsLandscape": \#(count)}"#)
        #expect(settings.gridColumnsPortrait == count)
        #expect(settings.gridColumnsLandscape == count)
    }

    @Test("Six landscape columns are kept through encoding")
    func sixLandscapeColumnsRoundTrip() throws {
        #expect(try decode(#"{"gridColumnsLandscape": 6}"#).gridColumnsLandscape == 6)
        var settings = AppSettings()
        settings.gridColumnsLandscape = 6
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.gridColumnsLandscape == 6)
        #expect(decoded.gridColumnsPortrait == 2)
    }

    #if os(macOS)
    @Test("Mac offers six landscape and five portrait columns and lays out the stored count")
    @MainActor
    func macColumnChoices() {
        #expect(gridColumnChoices(landscape: true) == 1...6)
        #expect(gridColumnChoices(landscape: false) == 1...5)
        var settings = AppSettings()
        settings.gridColumnsLandscape = 6
        settings.gridColumnsPortrait = 6
        #expect(videoGridColumnCount(settings, landscape: true) == 6)
        #expect(videoGridColumnCount(settings, landscape: false) == 5)
    }

    @Test("A Mac window narrower than six cards drops columns instead")
    @MainActor
    func macSixColumnsFitWidth() {
        var settings = AppSettings()
        settings.gridColumnsLandscape = 6
        #expect(videoGridColumnCount(settings, landscape: true, width: 2000, dynamicTypeSize: .large) == 6)
        #expect(videoGridColumnCount(settings, landscape: true, width: 1200, dynamicTypeSize: .large) == 4)
        #expect(videoGridColumnCount(settings, landscape: true, width: 2000, dynamicTypeSize: .accessibility1) == 1)
    }

    @Test("Playlist and Channel grids drop columns that would make cards narrower than the minimum")
    @MainActor
    func macPlaylistChannelGridFitsWidth() {
        var settings = AppSettings()
        settings.gridColumnsLandscape = 6
        // 1300 pt: six cards would be about 207 pt wide, under `VFMargin.cardMinWidth`; five fit.
        #expect(videoGridColumns(settings, landscape: true, width: 1300, dynamicTypeSize: .large).count == 5)
        #expect(videoGridColumns(settings, landscape: true, width: 2000, dynamicTypeSize: .large).count == 6)
        #expect(videoGridColumns(settings, landscape: true, width: 0, dynamicTypeSize: .large).count == 6)
        #expect(videoGridColumns(settings, landscape: true, width: 2000, dynamicTypeSize: .accessibility1).count == 1)
    }
    #endif

    @Test("High-res thumbnails default off and decode when present")
    func highResThumbnails() throws {
        #expect(try decode("{}").highResThumbnails == false)
        #expect(try decode(#"{"highResThumbnails": true}"#).highResThumbnails == true)
    }

    @Test("High-res fallback chain starts at hq720 and ends at mqdefault")
    func highResFallbackChain() {
        let names = Video(id: "abc", title: "t", channelTitle: "c").highResThumbnailFallbackURLs.map(
            \.lastPathComponent)
        #expect(names == ["hq720.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg"])
    }
}
