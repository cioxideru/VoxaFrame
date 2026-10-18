import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Saved video choices and download catalog")
struct OfflineDetailPresentationTests {
    private let english = Locale(identifier: "en_US")

    private func video(
        _ id: String, height: Int = 720, codec: VideoCodec = .h264, hasAudio: Bool = true
    ) -> OfflineTrack {
        var track = OfflineTrack(id: id, kind: .video, label: "Video", hasAudio: hasAudio)
        track.videoSize = OfflineVideoSize(width: height * 16 / 9, height: height)
        track.codec = codec
        track.isOriginalAudio = true
        return track
    }

    private func audio(_ language: String, original: Bool = false) -> OfflineTrack {
        var track = OfflineTrack(
            id: language, kind: .audio, label: "\(language) · Audio · AAC 52 kbps", language: language)
        track.isOriginalAudio = original
        return track
    }

    private func entry(_ tracks: [OfflineTrack], id: String = "saved") -> OfflineEntry {
        OfflineEntry(
            video: Video(id: id, title: "Saved video", channelTitle: "Channel"),
            assets: tracks.map { OfflineAsset(track: $0, filename: $0.id, systemRelativePath: nil) })
    }

    @Test func onlyOneSavedTranslationIsSelectedOnEntry() {
        for languages in [[], ["ru"], ["en", "ru"]] {
            var selection = OfflineDetailPresentation.Selection()
            let saved = entry([video("720")] + languages.map(OfflineTrack.translation))
            selection.update(entry: saved)
            #expect(selection.translationID == (languages.count == 1 ? "vot-ru" : nil))
            #expect(selection.videoID == "720")
        }
    }

    @Test func explicitOffSurvivesUpdatesAndNewVisitRestoresTheSingleTranslation() {
        var saved = entry([video("720"), .translation("ru")])
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: saved)
        selection.chooseTranslation(nil)
        saved.assets += entry([video("1080", height: 1080)]).assets
        selection.update(entry: saved)
        #expect(selection.translationID == nil)
        #expect(selection.videoID == "720")
        var nextVisit = OfflineDetailPresentation.Selection()
        nextVisit.update(entry: saved)
        #expect(nextVisit.translationID == "vot-ru")
    }

    @Test func newDownloadsDoNotChangeAnExistingChoice() {
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: entry([video("720")]))
        selection.update(entry: entry([video("720"), .translation("ru")]))
        #expect(selection.translationID == "vot-ru")
        #expect(!selection.translationChosen)
        selection.update(entry: entry([video("720"), .translation("ru"), .translation("en")]))
        #expect(selection.translationID == "vot-ru")
        selection.chooseTranslation(nil)
        selection.update(entry: entry([video("720"), .translation("ru")]))
        #expect(selection.translationID == nil)
        #expect(selection.translationChosen)
    }

    @Test func removalSelectsTheOnlyRemainingTranslationUnlessTheUserChose() {
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: entry([video("720"), .translation("ru"), .translation("en")]))
        #expect(selection.translationID == nil)
        selection.update(entry: entry([video("720"), .translation("ru")]))
        #expect(selection.translationID == "vot-ru")
        selection.update(entry: entry([video("720"), .translation("en")]))
        #expect(selection.translationID == "vot-en")
        selection.chooseTranslation("vot-en")
        selection.update(entry: entry([video("720"), .translation("en"), .translation("ru")]))
        #expect(selection.translationID == "vot-en")
        selection.update(entry: entry([video("720"), .translation("ru")]))
        #expect(selection.translationID == nil)
        selection.update(entry: entry([video("720"), .translation("ru")], id: "another"))
        #expect(selection.translationID == "vot-ru")
        #expect(!selection.translationChosen)
    }

    @Test func removedAssetsAndAnotherEntryCannotRetainStaleSelections() {
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: entry([video("720"), audio("fr"), .translation("ru")]))
        selection.audioID = "fr"
        let remaining = entry([video("1080", height: 1080)])
        selection.update(entry: remaining)
        #expect(selection.videoID == "1080")
        #expect(selection.audioID == nil)
        #expect(selection.translationID == nil)
        selection.update(entry: entry([video("1080"), .translation("en")], id: "another"))
        #expect(selection.translationID == "vot-en")
    }

    @Test func summaryUsesTheSameAudioAndTranslationAsPlayback() throws {
        let saved = entry([video("720"), audio("de-DE"), .translation("ru")])
        let video = try #require(saved.assets.first)
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: saved)
        func summary() -> OfflineDetailPresentation.Summary {
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: saved.assets, locale: english)
        }
        #expect(summary() == .init(quality: "720p", sound: .voiceOver("Russian")))
        selection.chooseTranslation(nil)
        #expect(summary().sound == .original)
        selection.audioID = "de-DE"
        #expect(summary().sound == .audio("German (Germany)"))
    }

    @Test func silentVideoStillUsesTheFirstSavedAudioAndReportsMissingAudio() throws {
        let saved = entry([video("720", hasAudio: false), audio("fr"), audio("en", original: true)])
        let video = try #require(saved.assets.first)
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: saved)
        #expect(selection.audio(for: video, in: saved.assets)?.id == "fr")
        #expect(
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: saved.assets, locale: english)
                .sound == .audio("French"))
        selection.audioID = "en"
        #expect(
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: saved.assets).sound
                == .original)
        #expect(
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: [video]).sound
                == .missingAudio)
        selection.chooseTranslation("vot-ru")
        let withoutAudio = [video] + entry([.translation("ru")]).assets
        #expect(
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: withoutAudio, locale: english)
                .sound == .voiceOver("Russian"))
    }

    @Test func hlsPackageNeverPassesSeparateAudioToThePlayer() throws {
        var package = OfflineTrack(id: "hls", kind: .hls, label: "720p · H.264", language: "ru", hasAudio: true)
        package.isOriginalAudio = false
        let saved = entry([package, audio("fr")])
        let video = try #require(saved.assets.first)
        var selection = OfflineDetailPresentation.Selection()
        selection.update(entry: saved)
        selection.audioID = "fr"
        #expect(selection.audio(for: video, in: saved.assets) == nil)
        #expect(
            OfflineDetailPresentation.summary(video: video, selection: selection, assets: saved.assets, locale: english)
                .sound == .audio("Russian"))
    }

    @Test func catalogGroupsQualityHighestFirstAndRecommendsSupportedFormats() throws {
        let tracks = [
            video("720-av1", codec: .av1), video("1080-hevc", height: 1080, codec: .hevc),
            video("1080-h264", height: 1080), video("360", height: 360), video("720-vp9", codec: .vp9),
        ]
        let catalog = OfflineDetailPresentation.catalog(tracks, saved: [], targetLanguages: [], hardwareCodecs: [.vp9])
        #expect(catalog.videoGroups.map(\.height) == [1080, 720, 360])
        #expect(catalog.videoGroups[0].tracks.map(\.id) == ["1080-h264", "1080-hevc"])
        #expect(catalog.videoGroups[0].recommendedID == "1080-h264")
        #expect(catalog.videoGroups[1].tracks.map(\.id) == ["720-vp9", "720-av1"])
        #expect(catalog.videoGroups[1].recommendedID == "720-vp9")
        let unsupported = OfflineDetailPresentation.catalog(
            [tracks[0]], saved: [], targetLanguages: [], hardwareCodecs: [])
        #expect(try #require(unsupported.videoGroups.first).recommendedID == nil)
    }

    @Test func av1AndVP9RequireHardwareSupportButH264AndHEVCDoNot() {
        for codec in [VideoCodec.h264, .hevc, .av1, .vp9] {
            let track = video(codec.rawValue, codec: codec)
            #expect(
                OfflineDetailPresentation.isPlayable(track, hardwareCodecs: []) == (codec == .h264 || codec == .hevc))
            #expect(OfflineDetailPresentation.isPlayable(track, hardwareCodecs: [.av1, .vp9]))
        }
        let unknown = OfflineTrack(id: "unknown", kind: .video, label: "Video")
        #expect(!OfflineDetailPresentation.isPlayable(unknown, hardwareCodecs: [.av1, .vp9]))
    }

    @Test func knownFrameRatesSortBeforeMissingMetadata() {
        let unspecified = video("a")
        var explicit = video("b")
        explicit.fps = 30
        var fast = video("c")
        fast.fps = 60
        for tracks in [[explicit, unspecified, fast], [fast, unspecified, explicit]] {
            let catalog = OfflineDetailPresentation.catalog(tracks, saved: [], targetLanguages: [], hardwareCodecs: [])
            #expect(catalog.videoGroups.first?.tracks.map(\.id) == ["c", "b", "a"])
        }
    }

    @Test func originalAudioComesFirstAndRegionalLanguagesAreExpanded() {
        let tracks = [audio("de-DE"), audio("ar"), audio("en", original: true)]
        let catalog = OfflineDetailPresentation.catalog(
            tracks, saved: [], targetLanguages: [], hardwareCodecs: [], locale: english)
        #expect(catalog.audio.map(\.id) == ["en", "ar", "de-DE"])
        #expect(OfflineDetailPresentation.languageName("de-DE", locale: english) == "German (Germany)")
        #expect(OfflineDetailPresentation.languageName("ru", locale: english) == "Russian")
        #expect(OfflineDetailPresentation.languageName("ru", locale: Locale(identifier: "ru_RU")) == "русский")
        #expect(OfflineDetailPresentation.audioLabel(tracks[2], locale: english).hasPrefix("English ·"))
        #expect(OfflineDetailPresentation.audioLabel(tracks[0], locale: english).hasPrefix("German (Germany) ·"))
        #expect(OfflineDetailPresentation.audioDetail(tracks[0]) == "AAC 52 kbps")
    }

    @Test func savedAudioChoicesUseLanguageAndDistinguishTheSoundInTheFile() throws {
        let tracks = [audio("de-DE"), audio("en", original: true)]
        let original = OfflineDetailPresentation.audioOptions(for: video("720"), saved: tracks, locale: english)
        #expect(original.map(\.id) == [nil, "en", "de-DE"])
        #expect(original[1].label == "English")
        #expect(original[2].label.hasPrefix("German (Germany) ·"))
        #expect(Set(original.map(\.label)).count == original.count)

        var dubbed = OfflineTrack(id: "dubbed", kind: .video, label: "720p", language: "de-DE", hasAudio: true)
        dubbed.isOriginalAudio = false
        let options = OfflineDetailPresentation.audioOptions(for: dubbed, saved: tracks, locale: english)
        #expect(options[0].label == "German (Germany)")
        #expect(Set(options.map(\.label)).count == options.count)

        let unknown = OfflineTrack(id: "unknown", kind: .video, label: "720p", hasAudio: true)
        let unknownOptions = OfflineDetailPresentation.audioOptions(for: unknown, saved: tracks, locale: english)
        #expect(unknownOptions[0].label != original[0].label)
        let asset = try #require(entry([unknown]).assets.first)
        #expect(OfflineDetailPresentation.summary(video: asset, selection: .init(), assets: [asset]).sound == .inFile)

        let sameLanguage = OfflineTrack(id: "same", kind: .video, label: "720p", language: "en", hasAudio: true)
        let distinct = OfflineDetailPresentation.audioOptions(for: sameLanguage, saved: tracks, locale: english)
        #expect(distinct[0].label.hasPrefix("English ·"))
        #expect(Set(distinct.map(\.label)).count == distinct.count)
    }

    @Test func duplicateSavedLanguagesIncludeFormatDetailsAndRemainDistinct() {
        let tracks = [
            OfflineTrack(id: "low", kind: .audio, label: "en · Audio · AAC 52 kbps", language: "en"),
            OfflineTrack(id: "high", kind: .audio, label: "en · Audio · AAC 128 kbps", language: "en"),
            OfflineTrack(id: "legacy1", kind: .audio, label: "Original", language: "en"),
            OfflineTrack(id: "legacy2", kind: .audio, label: "Original", language: "en"),
        ]
        let options = OfflineDetailPresentation.audioOptions(
            for: video("silent", hasAudio: false), saved: tracks, locale: english)
        #expect(!options.contains { $0.id == nil })
        #expect(options.first { $0.id == "low" }?.label == "English · AAC 52 kbps")
        #expect(options.first { $0.id == "high" }?.label == "English · AAC 128 kbps")
        #expect(Set(options.map(\.label)).count == options.count)
    }

    @Test func savedItemsDisappearFromEveryDownloadGroup() {
        let saved = entry([video("720"), audio("en", original: true), .translation("ru")])
        let available = saved.assets.map(\.track) + [video("1080", height: 1080), audio("fr")]
        let catalog = OfflineDetailPresentation.catalog(
            available, saved: saved.assets, targetLanguages: ["ru", "kk", "en"], hardwareCodecs: [], locale: english)
        #expect(catalog.videoGroups.flatMap(\.tracks).map(\.id) == ["1080"])
        #expect(catalog.audio.map(\.id) == ["fr"])
        #expect(catalog.translationLanguages == ["en", "kk"])
        let allSaved = OfflineDetailPresentation.catalog(
            saved.assets.map(\.track), saved: saved.assets, targetLanguages: ["ru"], hardwareCodecs: [])
        #expect(allSaved.videoGroups.isEmpty)
        #expect(allSaved.audio.isEmpty)
        #expect(allSaved.translationLanguages.isEmpty)
    }

    @Test func legacyVideoLabelsAndActualPackageDimensionsRemainVisible() throws {
        let legacy = OfflineTrack(id: "legacy", kind: .video, label: "720p · H.264", hasAudio: true)
        let package = OfflineTrack(id: "hls", kind: .hls, label: "HLS · H.264 + AAC", hasAudio: true)
        let catalog = OfflineDetailPresentation.catalog(
            [package, legacy], saved: [], targetLanguages: [], hardwareCodecs: [])
        #expect(catalog.videoGroups.map(\.height) == [720, 0])
        #expect(catalog.videoGroups[0].recommendedID == "legacy")
        var asset = try #require(entry([package]).assets.first)
        asset.savedVideoSizes = [.init(width: 360, height: 640)]
        #expect(OfflineDetailPresentation.savedVideoLabel(asset).contains("360×640"))
    }
}
