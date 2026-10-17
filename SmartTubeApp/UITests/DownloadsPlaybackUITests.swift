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
        let probe = app.staticTexts[AccessibilityID.offlinePlaybackStatus]
        let timeBeforeRotation = value("time", in: probe.label)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                // XCTest may expose an empty auxiliary window before the main window.
                let frame = self.app.frame
                return frame.width > frame.height && self.value("time", in: probe.label) > timeBeforeRotation + 2
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [rotated], timeout: 15), .completed,
            "app=\(app.frame) \(probe.label)")
        expectPlayback(translated: true)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    func testChooseOnlySelectedStreamsThenDeleteTaskAndLibraryFiles() async throws {
        let id = "offline-ui-selection-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer(selectTracks: true)
        openEntry(id)
        waitForSavedVideo("fixture-720")
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        waitUntilDisabled(translation)
        XCTAssertFalse(app.buttons[AccessibilityID.offlinePlay("fixture-360")].exists)
        let metricsURL = try XCTUnwrap(URL(string: mediaURL + "/metrics"))
        let (data, _) = try await URLSession.shared.data(from: metricsURL)
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertGreaterThan(counts["/\(id)/video720.mp4"] ?? 0, 0)
        XCTAssertGreaterThan(counts["/\(id)/original.m4a"] ?? 0, 0)
        XCTAssertGreaterThan(counts["/\(id)/voice.mp3"] ?? 0, 0)
        XCTAssertEqual(counts["/\(id)/video.mp4"] ?? 0, 0)

        app.navigationBars.buttons.firstMatch.tap()
        let pages = app.segmentedControls[AccessibilityID.offlinePagePicker]
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.buttons["Downloads"].tap()
        let job = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "offline.job."))
            .containing(.staticText, identifier: id)
            .containing(.staticText, identifier: "en · Original").firstMatch
        reveal(job)
        XCTAssertTrue(job.waitForExistence(timeout: 8))
        let remove = job.buttons["Delete task and files"]
        XCTAssertTrue(remove.exists)
        remove.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: job)
        XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 10), .completed)
        pages.buttons["Library"].tap()
        let deleteEntry = app.buttons[AccessibilityID.offlineDeleteEntry(id)]
        reveal(deleteEntry)
        XCTAssertTrue(deleteEntry.waitForExistence(timeout: 5))
        deleteEntry.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let entryRemoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: deleteEntry)
        XCTAssertEqual(XCTWaiter().wait(for: [entryRemoved], timeout: 10), .completed)
        app.terminate()
        launch(videoID: nil)
        UITestHelpers.tapTab(named: "Offline videos", in: app)
        XCTAssertTrue(app.segmentedControls[AccessibilityID.offlinePagePicker].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons[AccessibilityID.offlineEntry(id)].exists)
    }

    func testExternalHLSDownloadsOnlyChosenVideoAndLanguage() async throws {
        let id = "offline-ui-external-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer()
        openEntry(id)
        waitForSavedVideo("fixture-360")
        app.buttons[AccessibilityID.offlineFindVariants].tap()
        download("fixture-hls-ru")
        waitForSavedVideo("fixture-hls-ru")
        let before = try await requestCount(videoID: id)
        play("fixture-hls-ru", translated: false)
        app.terminate()
        launch(videoID: nil)
        openEntry(id)
        play("fixture-hls-ru", translated: false)
        let after = try await requestCount(videoID: id)
        XCTAssertEqual(after, before)
        let url = try XCTUnwrap(URL(string: mediaURL + "/metrics"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertGreaterThan(counts["/\(id)/russian-seg000.ts"] ?? 0, 0)
        XCTAssertGreaterThan(counts["/\(id)/video720-seg000.ts"] ?? 0, 0)
        XCTAssertEqual(counts.filter { $0.key.hasPrefix("/\(id)/english-seg") }.values.reduce(0, +), 0)
        XCTAssertEqual(counts.filter { $0.key.hasPrefix("/\(id)/video-seg") }.values.reduce(0, +), 0)
        app.terminate()
        launch(videoID: nil)
        UITestHelpers.tapTab(named: "Offline videos", in: app)
        let remove = app.buttons[AccessibilityID.offlineDeleteEntry(id)]
        reveal(remove)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
        XCTAssertEqual(XCTWaiter().wait(for: [deleted], timeout: 10), .completed)
    }

    func testDeleteAllConfirmsAndClearsBothPagesAfterRelaunch() {
        let first = "offline-ui-bulk-hls-" + UUID().uuidString
        launch(videoID: first)
        saveFromPlayer()
        openEntry(first)
        waitForSavedVideo("fixture-360")
        app.buttons[AccessibilityID.offlineFindVariants].tap()
        download("fixture-hls")
        waitForSavedVideo("fixture-hls")
        app.terminate()

        let second = "offline-ui-bulk-tracks-" + UUID().uuidString
        launch(videoID: second)
        saveFromPlayer(selectTracks: true)
        openEntry(second)
        waitForSavedVideo("fixture-720")
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        waitUntilDisabled(translation)
        app.navigationBars.buttons.firstMatch.tap()

        let remove = app.buttons[AccessibilityID.offlineDeleteAll]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // iPad confirmation popovers cancel through the outside dismiss region.
            let dismiss = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
        }
        XCTAssertTrue(app.buttons[AccessibilityID.offlineDeleteEntry(second)].exists)
        let pages = app.segmentedControls[AccessibilityID.offlinePagePicker]
        pages.buttons["Downloads"].tap()
        remove.tap()
        let confirm = app.buttons["Delete all"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Confirm deletion of all offline videos and cache"
        attachment.lifetime = .keepAlways
        add(attachment)
        confirm.tap()
        pages.buttons["Library"].tap()
        let empty = app.staticTexts[
            "Choose Offline watch from a video's menu. Accepted downloads continue when you leave this page."]
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        app.terminate()
        launch(videoID: nil)
        UITestHelpers.tapTab(named: "Offline videos", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[AccessibilityID.offlineEntry(first)].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.offlineEntry(second)].exists)
        pages.buttons["Downloads"].tap()
        XCTAssertFalse(app.staticTexts[first].exists)
        XCTAssertFalse(app.staticTexts[second].exists)
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

    private func saveFromPlayer(selectTracks: Bool = false) {
        let more = app.buttons["player.moreButton"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 25))
        more.tap()
        let save = app.buttons[AccessibilityID.offlineWatch].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let menu = app.scrollViews["player.moreMenu.scrollView"]
        for _ in 0..<3 where !save.isHittable { menu.swipeUp() }
        save.tap()
        let original = app.buttons[AccessibilityID.offlineSelectionDownload].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: original)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed)
        app.buttons[AccessibilityID.offlineSelectionVideo].tap()
        if selectTracks {
            app.buttons["720p · H.264 · MP4"].firstMatch.tap()
            app.buttons[AccessibilityID.offlineSelectionAudio].tap()
            app.buttons["en · Original"].firstMatch.tap()
            app.switches[AccessibilityID.offlineSelectionTranslate].switches.firstMatch.tap()
            XCTAssertTrue(app.buttons[AccessibilityID.offlineSelectionLanguage].waitForExistence(timeout: 3))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Offline stream and translation selection"
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            app.buttons["360p · H.264 · MP4"].firstMatch.tap()
        }
        original.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let cancel = app.buttons["player.moreMenu.cancel"].firstMatch
        if cancel.exists { cancel.tap() }
        let back = app.buttons[AccessibilityID.playerBackButton].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let close = app.buttons[AccessibilityID.miniPlayerClose].firstMatch
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
        reveal(entry)
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<24 {
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
