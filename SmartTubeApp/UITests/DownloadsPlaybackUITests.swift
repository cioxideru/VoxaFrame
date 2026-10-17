import XCTest

/// Exercises real URLSession files, AVPlayer and the local VOT player against loopback media.
@MainActor
final class DownloadsPlaybackUITests: XCTestCase {
    private let mediaURL = "http://127.0.0.1:18766"
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(URL(string: mediaURL + "/health"))
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "Start scripts/shorts-media-fixture.py")
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDownloadThenAddAudioAndTranslationAndPlayAfterRelaunch() async throws {
        let id = "offline-ui-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer()
        openEntry(id)
        waitForSavedVideo("fixture-360")

        app.buttons[AccessibilityID.offlineFindVariants].tap()
        download("fixture-720")
        download("fixture-audio")
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        translation.tap()
        waitUntilDisabled(translation)
        waitForSavedVideo("fixture-720")
        let before = try await requestCount(videoID: id)

        selectAudioAndTranslation()
        play("fixture-360", translated: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectPlayback(translated: true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Saved video and local Yandex audio"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        XCUIDevice.shared.orientation = .portrait

        launch(videoID: nil)
        openEntry(id)
        selectAudioAndTranslation()
        play("fixture-720", translated: true)
        let after = try await requestCount(videoID: id)
        XCTAssertEqual(after, before, "Saved playback must not fetch its original network stream or translation")
    }

    func testHLSIsStoredAsPlayableOfflinePackage() async throws {
        let id = "offline-ui-hls-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer()
        openEntry(id)
        waitForSavedVideo("fixture-360")
        app.buttons[AccessibilityID.offlineFindVariants].tap()
        download("fixture-hls")
        waitForSavedVideo("fixture-hls")
        XCTAssertTrue(app.buttons[AccessibilityID.offlinePlay("fixture-hls")].label.contains("360×640"))
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        translation.tap()
        waitUntilDisabled(translation)
        let before = try await requestCount(videoID: id)
        app.swipeDown()
        app.swipeDown()
        selectTranslation()
        play("fixture-hls", translated: true)
        app.terminate()
        launch(videoID: nil)
        openEntry(id)
        selectTranslation()
        play("fixture-hls", translated: true)
        let after = try await requestCount(videoID: id)
        XCTAssertEqual(after, before, "The saved HLS package must play without fetching segments again")
    }

    private func launch(videoID: String?) {
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-disable-sponsorblock", "--uitesting-sign-out",
            "--uitesting-show-controls", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if let videoID { app.launchArguments.append("--uitesting-deeplink-video=\(videoID)") }
        app.launchEnvironment["SHORTS_TEST_MEDIA_URL"] = mediaURL
        app.launchEnvironment["OFFLINE_TEST_MEDIA_URL"] = mediaURL
        app.launch()
    }

    private func saveFromPlayer() {
        let more = app.buttons["player.moreButton"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 25))
        more.tap()
        let save = app.buttons[AccessibilityID.offlineWatch].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let menu = app.scrollViews["player.moreMenu.scrollView"]
        for _ in 0..<3 where !save.isHittable { menu.swipeUp() }
        save.tap()
        let original = app.buttons["Video with included audio"].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let cancel = app.buttons["player.moreMenu.cancel"].firstMatch
        if cancel.exists { cancel.tap() }
        let back = app.buttons[AccessibilityID.playerBackButton].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let close = app.buttons["miniPlayer.closeButton"].firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
            XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed)
        }
    }

    private func openEntry(_ id: String) {
        UITestHelpers.tapTab(named: "Offline videos", in: app)
        let library = app.segmentedControls[AccessibilityID.offlinePagePicker].buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        library.tap()
        let entry = app.buttons[AccessibilityID.offlineEntry(id)].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        reveal(entry)
        entry.tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func download(_ id: String) {
        let button = app.buttons[AccessibilityID.offlineDownload(id)].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        reveal(button)
        button.tap()
        // A disabled "Downloading" row is not completion; the saved-video button below is authoritative.
        if id == "fixture-audio" {
            let saved = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'Saved'"), object: button)
            XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 45), .completed)
        }
    }

    private func waitUntilDisabled(_ element: XCUIElement) {
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [completed], timeout: 45), .completed)
    }

    private func waitForSavedVideo(_ id: String) {
        XCTAssertTrue(app.buttons[AccessibilityID.offlinePlay(id)].waitForExistence(timeout: 60))
    }

    private func selectAudioAndTranslation() {
        app.swipeDown()
        app.swipeDown()
        let audio = app.buttons[AccessibilityID.offlineAudioPicker]
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap()
        app.buttons["en · Original"].firstMatch.tap()
        selectTranslation()
    }

    private func selectTranslation() {
        app.buttons[AccessibilityID.offlineTranslationPicker].tap()
        app.buttons["Yandex translation · ru"].firstMatch.tap()
    }

    private func play(_ id: String, translated: Bool) {
        let button = app.buttons[AccessibilityID.offlinePlay(id)]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        reveal(button)
        button.tap()
        expectPlayback(translated: translated)
    }

    private func expectPlayback(translated: Bool) {
        let probe = app.staticTexts[AccessibilityID.offlinePlaybackStatus]
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let text = probe.label
                return text.contains("local=true") && text.contains("error=false")
                    && self.value("time", in: text) > 2 && self.value("rate", in: text) > 0
                    && (!translated || (self.value("voiceRate", in: text) > 0 && self.value("voiceTime", in: text) > 0))
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 25), .completed, probe.label)
    }

    private func value(_ key: String, in text: String) -> Double {
        text.split(separator: " ").first { $0.hasPrefix(key + "=") }
            .flatMap { Double($0.dropFirst(key.count + 1)) } ?? -1
    }

    private func requestCount(videoID: String) async throws -> Int {
        let url = try XCTUnwrap(URL(string: mediaURL + "/metrics"))
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String: Int].self, from: data)
            .filter { $0.key.contains("/\(videoID)/") }.values.reduce(0, +)
    }
}
