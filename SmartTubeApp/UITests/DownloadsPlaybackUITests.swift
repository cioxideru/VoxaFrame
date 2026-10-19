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
        waitForSaved("fixture-360")

        findVariants()
        download("fixture-720")
        download("fixture-audio")
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        translation.tap()
        waitForSaved("vot-ru")
        waitForSaved("fixture-720")
        scrollToPlayback()
        XCTAssertTrue(app.buttons[AccessibilityID.offlinePlay("fixture-360")].exists)
        expectSummary(containing: "Russian voice-over")
        let before = try await requestCount(videoID: id)

        selectAudioAndTranslation()
        play("fixture-360", translated: true)
        expectSavedStatus(saved: true)
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
        selectAudio()
        expectSummary(containing: "Russian voice-over")
        play("fixture-720", translated: true)
        let after = try await requestCount(videoID: id)
        XCTAssertEqual(after, before, "Saved playback must not fetch its original network stream or translation")
    }

    func testQuickOfflineButtonGoesQueuedThenSavedAndStaysSavedWhenStreaming() {
        let id = "offline-ui-" + UUID().uuidString
        launch(videoID: id)
        let quick = app.buttons[AccessibilityID.playerQuickOfflineButton].firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 25))
        XCTAssertTrue(quick.label.contains("Offline"), quick.label)
        XCTAssertTrue(quick.isEnabled)
        quick.tap()
        let original = app.buttons[AccessibilityID.offlineSelectionDownload].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: original)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed)
        app.buttons[AccessibilityID.offlineSelectionVideo].tap()
        app.buttons["360p · H.264 · MP4"].firstMatch.tap()
        original.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let progressed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Queued' OR label CONTAINS 'Saved'"), object: quick)
        XCTAssertEqual(XCTWaiter().wait(for: [progressed], timeout: 15), .completed, quick.label)
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Saved' AND enabled == false"), object: quick)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 90), .completed, quick.label)

        // Reopen the saved video; whatever source plays, the library entry keeps it Saved.
        app.terminate()
        launch(videoID: id)
        let again = app.buttons[AccessibilityID.playerQuickOfflineButton].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 25))
        let stillSaved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Saved' AND enabled == false"), object: again)
        XCTAssertEqual(XCTWaiter().wait(for: [stillSaved], timeout: 15), .completed, again.label)
    }

    func testHLSIsStoredAsPlayableOfflinePackage() async throws {
        let id = "offline-ui-hls-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer()
        openEntry(id)
        waitForSaved("fixture-360")
        findVariants()
        download("fixture-hls")
        download("fixture-audio")
        waitForSaved("fixture-hls")
        selectVideo("fixture-hls")
        let videoPicker = app.buttons[AccessibilityID.offlineVideoPicker]
        reveal(videoPicker)
        XCTAssertEqual((videoPicker.value as? String)?.contains("360×640"), true)
        let audioPicker = app.buttons[AccessibilityID.offlineAudioPicker]
        reveal(audioPicker)
        XCTAssertTrue(audioPicker.exists)
        XCTAssertFalse(audioPicker.isEnabled)
        let translation = app.buttons[AccessibilityID.offlineDownloadTranslation("ru")]
        reveal(translation)
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        translation.tap()
        waitForSaved("vot-ru")
        let before = try await requestCount(videoID: id)
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

    func testSavedVoiceOverCanBeTurnedOffBeforePlaying() {
        let id = "offline-ui-voice-off-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer(selectTracks: true)
        openEntry(id)
        waitForSaved("fixture-720")
        waitForSaved("vot-ru")
        expectSummary(containing: "Russian voice-over")
        selectTranslation("Off")
        waitForSaved("vot-ru")
        expectSummary(containing: "Sound in video file")
        XCTAssertFalse(app.buttons[AccessibilityID.offlineDownloadTranslation("ru")].exists)
        play("fixture-720", translated: false)
    }

    func testChooseOnlySelectedStreamsThenDeleteTaskAndLibraryFiles() async throws {
        let id = "offline-ui-selection-" + UUID().uuidString
        launch(videoID: id)
        saveFromPlayer(selectTracks: true)
        openEntry(id)
        waitForSaved("fixture-720")
        waitForSaved("vot-ru")
        XCTAssertFalse(app.buttons[AccessibilityID.offlinePlay("fixture-360")].exists)
        XCTAssertFalse(app.buttons[AccessibilityID.offlineVideoPicker].exists)
        let metricsURL = try XCTUnwrap(URL(string: mediaURL + "/metrics"))
        let (data, _) = try await URLSession.shared.data(from: metricsURL)
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertGreaterThan(counts["/\(id)/video720.mp4"] ?? 0, 0)
        XCTAssertGreaterThan(counts["/\(id)/original.m4a"] ?? 0, 0)
        XCTAssertGreaterThan(counts["/\(id)/voice.mp3"] ?? 0, 0)
        XCTAssertEqual(counts["/\(id)/video.mp4"] ?? 0, 0)

        returnToLibrary()
        let pages = app.segmentedControls[AccessibilityID.offlinePagePicker]
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.buttons["Downloads"].tap()
        // Jobs sit under their video's title; each job row carries that title as its accessibility label.
        let job = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "offline.job.", id))
            .containing(.staticText, identifier: "en · Original").firstMatch
        reveal(job, in: AccessibilityID.offlineJobsList)
        XCTAssertTrue(job.waitForExistence(timeout: 8))
        swipeToDelete(job, action: "Delete task and files", identifierPrefix: "offline.deleteJob.")
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: job)
        XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 10), .completed)
        pages.buttons["Library"].tap()
        let entry = app.buttons[AccessibilityID.offlineEntry(id)].firstMatch
        reveal(entry, in: AccessibilityID.offlineLibraryList)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        swipeToDelete(entry, action: "Delete video and files", identifierPrefix: AccessibilityID.offlineDeleteEntry(id))
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let entryRemoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: entry)
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
        waitForSaved("fixture-360")
        findVariants()
        let group = app.buttons[AccessibilityID.offlineQualityGroup(720)]
        reveal(group)
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        group.tap()
        XCTAssertEqual(group.value as? String, "Expanded")
        download("fixture-hls-ru")
        waitForSaved("fixture-hls-ru")
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
        let entry = app.buttons[AccessibilityID.offlineEntry(id)].firstMatch
        reveal(entry, in: AccessibilityID.offlineLibraryList)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        swipeToDelete(entry, action: "Delete video and files", identifierPrefix: AccessibilityID.offlineDeleteEntry(id))
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: entry)
        XCTAssertEqual(XCTWaiter().wait(for: [deleted], timeout: 10), .completed)
        app.terminate()
        launch(videoID: id)
        expectSavedStatus(saved: false)
    }

    /// The player title speaks the saved status exactly once, and only while the video is saved.
    private func expectSavedStatus(saved: Bool) {
        let title = app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 25))
        let count = title.label.components(separatedBy: "Saved offline").count - 1
        XCTAssertEqual(count, saved ? 1 : 0, title.label)
    }

    func testSponsorBlockSegmentsAreStoredAndUpdatedManually() {
        let id = "offline-ui-sponsor-" + UUID().uuidString
        launch(videoID: id, sponsorBlock: true)
        saveFromPlayer()
        openEntry(id)
        waitForSaved("fixture-360")
        let status = app.staticTexts[AccessibilityID.offlineSponsorBlockStatus].firstMatch
        let update = app.buttons[AccessibilityID.offlineUpdateSponsorBlock].firstMatch
        reveal(update)
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        // The download stored the segments without any action.
        let stored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH '1 segments'"), object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [stored], timeout: 20), .completed, status.label)
        update.tap()
        // The stub answers with one more segment per request, so only a fresh response changes the label.
        let refreshed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH '2 segments'"), object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [refreshed], timeout: 15), .completed, status.label)
        attachScreenshot("Saved video SponsorBlock update")
        returnToLibrary()
        // Overflow menu items drop their identifier, so the label (outside other offline controls) is the fallback.
        let more = app.buttons["More"].firstMatch
        if more.waitForExistence(timeout: 5) { more.tap() }
        let bulk = app.buttons.matching(
            NSPredicate(
                format:
                    "identifier == %@ OR (label BEGINSWITH 'Update SponsorBlock' AND NOT (identifier BEGINSWITH 'offline.'))",
                AccessibilityID.offlineUpdateSponsorBlockAll)
        ).firstMatch
        XCTAssertTrue(bulk.waitForExistence(timeout: 5))
        attachScreenshot("Library SponsorBlock update action")
        bulk.tap()
        let result = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Updated ' AND label ENDSWITH 'failed 0.'")
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        attachScreenshot("Library SponsorBlock update result")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDeleteAllConfirmsAndClearsBothPagesAfterRelaunch() {
        let first = "offline-ui-bulk-hls-" + UUID().uuidString
        launch(videoID: first)
        saveFromPlayer()
        openEntry(first)
        waitForSaved("fixture-360")
        findVariants()
        download("fixture-hls")
        waitForSaved("fixture-hls")
        app.terminate()

        let second = "offline-ui-bulk-tracks-" + UUID().uuidString
        launch(videoID: second)
        saveFromPlayer(selectTracks: true)
        openEntry(second)
        waitForSaved("fixture-720")
        waitForSaved("vot-ru")
        returnToLibrary()

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
        XCTAssertTrue(app.buttons[AccessibilityID.offlineEntry(second)].exists)
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

}

extension DownloadsPlaybackUITests {
    private func launch(videoID: String?, sponsorBlock: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-sign-out",
            "--uitesting-show-controls", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        // Earlier launches may have saved SponsorBlock as off; start this one from defaults.
        app.launchArguments.append(sponsorBlock ? "--uitesting-reset-settings" : "--uitesting-disable-sponsorblock")
        if let videoID { app.launchArguments.append("--uitesting-deeplink-video=\(videoID)") }
        app.launchEnvironment["SHORTS_TEST_MEDIA_URL"] = mediaURL
        app.launchEnvironment["OFFLINE_TEST_MEDIA_URL"] = mediaURL
        app.launch()
    }

    private func saveFromPlayer(selectTracks: Bool = false) {
        let save = app.buttons[AccessibilityID.playerQuickOfflineButton].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 25))
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
        reveal(entry, in: AccessibilityID.offlineLibraryList)
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(offlineList(AccessibilityID.offlineDetailList).waitForExistence(timeout: 5))
        if library.exists && library.isHittable {
            XCTAssertTrue(entry.isSelected, "The adjacent library must retain the selected video")
        }
    }

    private func offlineList(_ identifier: String) -> XCUIElement {
        let table = app.tables[identifier].firstMatch
        return table.exists ? table : app.collectionViews[identifier].firstMatch
    }

    private func returnToLibrary() {
        let pages = app.segmentedControls[AccessibilityID.offlinePagePicker]
        // In columns the picker remains beside the detail; the navigation bar has no detail Back button.
        if pages.exists && pages.isHittable { return }
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
    }

    /// Rows delete through a trailing swipe; its button opens the confirmation.
    /// The swipe button may lose its identifier, so the label (outside other offline controls) is the fallback.
    private func swipeToDelete(_ row: XCUIElement, action label: String, identifierPrefix: String) {
        let action = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ OR (label == %@ AND NOT (identifier BEGINSWITH 'offline.'))",
                identifierPrefix, label)
        ).firstMatch
        // Swipe the List cell: a swipe that starts on a control inside it may not reveal the actions.
        let cell = app.cells.containing(.any, identifier: row.identifier).firstMatch
        (cell.exists ? cell : row).swipeLeft()
        XCTAssertTrue(action.waitForExistence(timeout: 5), "The trailing swipe must reveal \(label)")
        XCTAssertTrue(row.exists, "A swipe on the row must not leave the list")
        action.tap()
    }

    private func reveal(_ element: XCUIElement, in listID: String = AccessibilityID.offlineDetailList) {
        let list = offlineList(listID)
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            list.swipeUp()
        }
    }

    private func findVariants() {
        scrollToPlayback()
        let button = app.buttons[AccessibilityID.offlineFindVariants]
        reveal(button)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed)
    }

    private func download(_ id: String) {
        scrollToPlayback()
        let button = app.buttons[AccessibilityID.offlineDownload(id)].firstMatch
        let height = id == "fixture-hls" ? 0 : 720
        let group = app.buttons[AccessibilityID.offlineQualityGroup(height)].firstMatch
        let list = offlineList(AccessibilityID.offlineDetailList)
        for _ in 0..<24 {
            if button.exists && button.isHittable { break }
            if id != "fixture-audio", group.exists && group.isHittable, group.value as? String == "Collapsed" {
                group.tap()
            } else {
                list.swipeUp()
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(button.isHittable)
        button.tap()
        waitForSaved(id)
    }

    @discardableResult
    private func waitForSaved(_ id: String) -> String {
        let saved = app.staticTexts[AccessibilityID.offlineSaved(id)].firstMatch
        let list = offlineList(AccessibilityID.offlineDetailList)
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        // The fixture's saved rows are at the top, including while a new asset is still downloading.
        for _ in 0..<12 {
            if saved.exists && saved.isHittable { break }
            list.swipeDown()
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 60), "Missing saved asset: \(id)")
        return saved.label
    }

    private func selectVideo(_ id: String) {
        let label = waitForSaved(id)
        scrollToPlayback()
        let play = app.buttons[AccessibilityID.offlinePlay(id)]
        if play.exists { return }
        let picker = app.buttons[AccessibilityID.offlineVideoPicker]
        reveal(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let option = app.buttons[label].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        scrollToPlayback()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
    }

    private func selectAudioAndTranslation() {
        selectAudio()
        selectTranslation()
    }

    private func selectAudio() {
        scrollToPlayback()
        let audio = app.buttons[AccessibilityID.offlineAudioPicker]
        reveal(audio)
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap()
        let option = app.buttons["English"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    private func selectTranslation(_ title: String = "Russian") {
        scrollToPlayback()
        let picker = app.buttons[AccessibilityID.offlineTranslationPicker]
        reveal(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertEqual(picker.value as? String, title)
    }

    private func expectSummary(containing text: String) {
        scrollToPlayback()
        let summary = app.staticTexts[AccessibilityID.offlinePlaySummary]
        reveal(summary)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains(text), summary.label)
    }

    private func scrollToPlayback() {
        let play = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.offlinePlay(""))
        ).firstMatch
        let list = offlineList(AccessibilityID.offlineDetailList)
        for _ in 0..<12 {
            if play.exists && play.isHittable { return }
            list.swipeDown()
        }
    }

    private func play(_ id: String, translated: Bool) {
        selectVideo(id)
        scrollToPlayback()
        let button = app.buttons[AccessibilityID.offlinePlay(id)]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        expectPlayback(translated: translated)
    }

    private func expectPlayback(translated: Bool) {
        XCTAssertTrue(app.buttons[AccessibilityID.playerBackButton].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons[AccessibilityID.miniPlayerClose].exists)
        let probe = app.staticTexts[AccessibilityID.offlinePlaybackStatus]
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let text = probe.label
                return text.contains("local=true") && text.contains("error=false")
                    && self.value("time", in: text) > 2 && self.value("rate", in: text) > 0
                    && (translated
                        ? self.value("voiceRate", in: text) > 0 && self.value("voiceTime", in: text) > 0
                        : self.value("voiceRate", in: text) == 0)
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
