// The earlier live menu tests are in `PlayerMenuAndPickerLayoutUITests`.
// These panel regressions use local media so layout checks do not depend on YouTube.

import XCTest

#if os(iOS)
import UIKit

/// PLAN-0029: first-open placement at the bottom controls and trailing Shorts rail.
/// Run with scripts/shorts-media-fixture.py on port 18765; no YouTube/account dependency.
@MainActor
final class PlayerOptionPanelBoundsUITests: XCTestCase {
    private let mediaURL = "http://127.0.0.1:18765"
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let url = try XCTUnwrap(URL(string: mediaURL + "/health"))
        do {
            let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 2))
            try XCTSkipUnless(
                (response as? HTTPURLResponse)?.statusCode == 200,
                "Start scripts/shorts-media-fixture.py on port 18765")
        } catch {
            throw XCTSkip("Local media fixture unavailable: \(error.localizedDescription)")
        }
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testRegularSpeedPanelStaysInsideWindow() throws {
        try requirePad()
        launch()
        checkPanel(
            trigger: AccessibilityID.playerQuickSpeedButton, panel: AccessibilityID.playerSpeedPicker,
            firstChoice: AccessibilityID.playerSpeed(0.25))
    }

    func testRegularQualityPanelStaysInsideWindow() throws {
        try requirePad()
        launch()
        checkPanel(
            trigger: AccessibilityID.playerQuickQualityButton, panel: AccessibilityID.playerQualityPicker,
            firstChoice: AccessibilityID.playerQualityPickerAuto)
    }

    func testShortSpeedPanelFitsItsContentOnIPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Checks the iPad popover's content height")
        launch()
        let speed = app.buttons[AccessibilityID.playerQuickSpeedButton].firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 20))
        assertReady(speed)
        speed.tap()
        let panel = element(AccessibilityID.playerSpeedPicker)
        let firstChoice = app.buttons[AccessibilityID.playerSpeed(0.25)].firstMatch
        assertPanel(panel, firstChoice: firstChoice, in: app.frame)

        let footnote = panel.staticTexts["Regular videos only. Shorts keep their own speed."].firstMatch
        XCTAssertTrue(footnote.waitForExistence(timeout: 5))
        let fitted = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                footnote.isHittable && panel.frame.maxY - footnote.frame.maxY <= firstChoice.frame.height
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [fitted], timeout: 5), .completed,
            "A short panel must not leave more than one choice-height of empty space below its content")
    }

    func testShortsSpeedPanelStaysInsideWindow() throws {
        try requirePad()
        launch(shorts: true)
        checkPanel(
            trigger: AccessibilityID.shortsSpeedButton, panel: AccessibilityID.playerSpeedPicker,
            firstChoice: AccessibilityID.playerSpeed(0.25))
    }

    func testShortsAudioPanelStaysInsideWindow() throws {
        try requirePad()
        launch(shorts: true)
        checkPanel(
            trigger: AccessibilityID.shortsAudioTrackButton, panel: AccessibilityID.playerAudioTrackPicker,
            firstChoice: AccessibilityID.playerAudioTrackPickerAuto)
    }

    func testSleepTimerRowInMoreMenuSetsAndClearsTimerInBothOrientations() {
        launch()
        // iPhone landscape is portrait-only here: any tall option panel (Quality too) hangs the app's main thread
        // there, a separate pre-existing defect.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        for orientation in isPad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            rotate(to: orientation)
            chooseSleepTimer("15 min")
            openMoreMenu()
            let row = app.buttons[AccessibilityID.playerMoreMenuSleepTimerRow].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains("15 min"), "Row detail must show the timer: \(row.label)")
            app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch.tap()
            assertDismissed(element(AccessibilityID.playerMoreMenu))
            chooseSleepTimer("Off")
            openMoreMenu()
            XCTAssertTrue(
                app.buttons[AccessibilityID.playerMoreMenuSleepTimerRow].firstMatch.label.contains("Off"),
                "Row detail must show Off after clearing")
            app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch.tap()
            assertDismissed(element(AccessibilityID.playerMoreMenu))
        }
    }

    /// Opens More, the Sleep Timer panel (checked for bounds and a hittable choice), then picks `choice`.
    private func chooseSleepTimer(_ choice: String) {
        openMoreMenu()
        let row = app.buttons[AccessibilityID.playerMoreMenuSleepTimerRow].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        row.tap()
        assertDismissed(element(AccessibilityID.playerMoreMenu))
        let panel = element(AccessibilityID.playerSleepTimerPicker)
        let option = panel.buttons[choice].firstMatch
        assertPanel(panel, firstChoice: option, in: app.frame)
        option.tap()
        assertDismissed(panel)
    }

    func testOfflineDownloadActionIsHittableWithoutScrolling() {
        launch()
        let offline = app.buttons[AccessibilityID.playerQuickOfflineButton].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 20))
        assertReady(offline)
        offline.tap()

        let download = app.buttons[AccessibilityID.offlineSelectionDownload].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        assertReady(download)
        XCTAssertTrue(app.frame.contains(download.frame), "Download must be fully inside the sheet's window")

        let translation = app.switches[AccessibilityID.offlineSelectionTranslate].firstMatch
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        // iOS 26 exposes the Form row as a switch containing the actual switch control.
        let innerSwitch = translation.switches.firstMatch
        let control = innerSwitch.exists ? innerSwitch : translation
        assertReady(control)
        XCTAssertEqual(control.value as? String, "0")
        if innerSwitch.exists {
            control.tap()
        } else {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertTrue(app.buttons[AccessibilityID.offlineSelectionLanguage].waitForExistence(timeout: 5))
        assertReady(download)
        rotate(to: .landscapeLeft)
        assertReady(download)
        XCTAssertTrue(app.frame.contains(download.frame), "Download must stay visible after rotation")
    }

    func testMoreMenuShareAppearsAfterPanelDismissal() {
        launch()
        openMoreMenu()
        let share = app.buttons[AccessibilityID.playerMoreMenuShareRow].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        assertReady(share)
        share.tap()
        assertDismissed(element(AccessibilityID.playerMoreMenu))

        // The system share service exposes its own hierarchy, without the app's controller identifier.
        let sheet = app.otherElements["shareSheet.activity.contentView"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Share must survive dismissal of the More popover")
        let copy = sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        assertReady(copy)
    }

    func testMoreMenuOmitsAudioWhenQuickAccessAudioIsVisible() throws {
        launch()
        let quality = app.buttons[AccessibilityID.playerQuickQualityButton].firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 20))
        assertReady(quality)
        let audio = app.buttons[AccessibilityID.playerQuickAudioButton].firstMatch
        try XCTSkipUnless(
            audio.waitForExistence(timeout: 20),
            "Local fixture has one audio track and no translation language; "
                + "run PlayerMoreMenuDuplicationUITests for #217 coverage")
        assertReady(audio)
        openMoreMenu()
        XCTAssertFalse(
            app.buttons[AccessibilityID.playerMoreMenuAudioTrackRow].exists,
            "More must not duplicate the visible audio pill (#217)")
    }

    func testMorePanelKeepsCancelVisibleAndLastActionReachable() {
        launch()
        // iPhone landscape is portrait-only here: any tall option panel (Quality too) hangs the app's main thread
        // there, a separate pre-existing defect.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        for orientation in isPad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            rotate(to: orientation)
            let window = app.frame
            openMoreMenu()
            let panel = element(AccessibilityID.playerMoreMenu)
            let cancel = app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch
            assertPanel(panel, firstChoice: cancel, in: window)
            let scroll = app.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch
            let lastAction = app.buttons[AccessibilityID.playerMoreMenuStatsForNerds].firstMatch
            for _ in 0..<6 where !lastAction.isHittable { scroll.swipeUp() }
            XCTAssertTrue(lastAction.isHittable, "The last More action must remain reachable")
            XCTAssertTrue(cancel.isHittable, "The header must stay visible while the actions scroll")
            cancel.tap()
            assertDismissed(panel)
        }
    }

    func testUpNextRecommendationsPlayAndMoreOmitsRepeatedHeading() {
        launch(playerArguments: [
            "--uitesting-deeplink-video=preload-0",
            "--uitesting-inject-related-video-ids=preload-1,preload-2",
        ])
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        for orientation in isPad ? [UIDeviceOrientation.portrait, .landscapeLeft] : [.portrait] {
            rotate(to: orientation)
            openMoreMenu()
            let menu = element(AccessibilityID.playerMoreMenu)
            XCTAssertFalse(menu.staticTexts["preload-0"].exists, "More must not repeat the video title")
            XCTAssertFalse(menu.staticTexts["Local fixture"].exists, "More must not repeat the channel name")
            XCTAssertFalse(menu.buttons["Up next"].exists, "Up Next must move out of More")
            app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch.tap()
            assertDismissed(menu)
            openUpNext()
            let panel = element(AccessibilityID.playerUpNextPanel)
            let next = app.buttons[AccessibilityID.playerUpNextVideo("preload-1")].firstMatch
            assertPanel(panel, firstChoice: next, in: app.frame)
            XCTAssertTrue(app.buttons[AccessibilityID.playerUpNextVideo("preload-2")].exists)
            next.tap()
            assertDismissed(panel)
            let title = element(AccessibilityID.playerTitleLabel)
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "preload-1"), object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        }
    }

    func testUpNextQueueKeepsDuplicatePositionsAndRefreshesAfterSelection() {
        launch(playerArguments: [
            "--uitesting-inject-queue-video-ids=preload-0,preload-1,preload-1,preload-2",
            "--uitesting-inject-related-video-ids=preload-3",
        ])
        openUpNext()
        let first = app.buttons[AccessibilityID.playerUpNextVideo("preload-1", queueIndex: 1)].firstMatch
        let second = app.buttons[AccessibilityID.playerUpNextVideo("preload-1", queueIndex: 2)].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[AccessibilityID.playerUpNextVideo("preload-3")].exists)
        assertReady(second)
        second.tap()
        assertDismissed(element(AccessibilityID.playerUpNextPanel))

        openUpNext()
        let remaining = app.buttons[AccessibilityID.playerUpNextVideo("preload-2", queueIndex: 3)].firstMatch
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        XCTAssertFalse(second.exists)
        app.buttons[AccessibilityID.playerUpNextPanelCancel].firstMatch.tap()
        assertDismissed(element(AccessibilityID.playerUpNextPanel))
    }

    func testUpNextEmptyStateAndCancel() {
        launch(playerArguments: [
            "--uitesting-deeplink-video=preload-0", "--uitesting-inject-related-video-ids=",
        ])
        openUpNext()
        let panel = element(AccessibilityID.playerUpNextPanel)
        XCTAssertTrue(panel.staticTexts["Nothing up next."].waitForExistence(timeout: 10))
        let cancel = app.buttons[AccessibilityID.playerUpNextPanelCancel].firstMatch
        assertPanel(panel, firstChoice: cancel, in: app.frame)
        cancel.tap()
        assertDismissed(panel)
        openMoreMenu()
        XCTAssertTrue(app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch.isHittable)
    }

    func testPlayerControlsMatchLayoutInBothOrientations() {
        launch(playerArguments: [
            "--uitesting-deeplink-video=preload-0",
            "--uitesting-inject-related-video-ids=preload-1,preload-2",
        ])
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(to: orientation)
            let play = app.buttons[AccessibilityID.playerPlayPauseButton].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 20))
            assertReady(play)
            let window = app.frame
            let centered = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    abs(play.frame.midX - window.midX) < 2 && abs(play.frame.midY - window.midY) < 2
                }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 5), .completed)

            let timeline = element(AccessibilityID.playerProgressBar)
            let duration = app.staticTexts[AccessibilityID.playerDurationLabel].firstMatch
            XCTAssertLessThan(duration.frame.maxY, timeline.frame.midY, "Time must sit above the track")
            XCTAssertEqual(duration.frame.maxX, timeline.frame.maxX - 20, accuracy: 2)
            let speed = app.buttons[AccessibilityID.playerQuickSpeedButton].firstMatch
            let audioOnly = app.buttons[AccessibilityID.playerAudioOnlyButton].firstMatch
            XCTAssertEqual(speed.frame.midY, audioOnly.frame.midY, accuracy: 2, "Bottom groups must align")
            XCTAssertLessThan(timeline.frame.maxY, speed.frame.minY)
            XCTAssertLessThan(play.frame.maxY, timeline.frame.minY, "The timeline must clear the centered controls")

            revealUpNext()
            let offline = app.buttons[AccessibilityID.playerQuickOfflineButton].firstMatch
            let upNext = app.buttons[AccessibilityID.playerQuickUpNextButton].firstMatch
            XCTAssertGreaterThan(upNext.frame.minX, offline.frame.maxX, "Up Next follows Offline")
            XCTAssertEqual(upNext.frame.midY, audioOnly.frame.midY, accuracy: 2)
            XCTAssertTrue(window.contains(upNext.frame))
            if UIDevice.current.userInterfaceIdiom == .phone && !orientation.isLandscape {
                for identifier in [
                    AccessibilityID.playerQuickSpeedButton, AccessibilityID.playerQuickQualityButton,
                    AccessibilityID.playerQuickOfflineButton, AccessibilityID.playerQuickUpNextButton,
                ] {
                    let button = app.buttons[identifier].firstMatch
                    XCTAssertLessThanOrEqual(button.frame.width, button.frame.height + 4, "Narrow controls use icons")
                }
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Player layout - \(orientation.isLandscape ? "landscape" : "portrait")"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            upNext.tap()
            let panel = element(AccessibilityID.playerUpNextPanel)
            let cancel = app.buttons[AccessibilityID.playerUpNextPanelCancel].firstMatch
            assertPanel(panel, firstChoice: cancel, in: window)
            cancel.tap()
            assertDismissed(panel)
        }
    }

    func testLargeTextTimerStaysAboveTimeline() {
        launch(playerArguments: [
            "--uitesting-deeplink-video=preload-0",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let duration = app.staticTexts[AccessibilityID.playerDurationLabel].firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(duration.frame.height, 28, "The check must use enlarged text")
        let timeline = element(AccessibilityID.playerProgressBar)
        XCTAssertLessThan(duration.frame.maxY, timeline.frame.maxY - 28, "Large time text must clear the track")
        revealUpNext()
    }

    private func revealUpNext() {
        let button = app.buttons[AccessibilityID.playerQuickUpNextButton].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let scroll = app.scrollViews[AccessibilityID.playerQuickAccessScrollView].firstMatch
        if scroll.exists {
            for _ in 0..<6 where !button.isHittable || !scroll.frame.contains(button.frame) { scroll.swipeLeft() }
        }
        assertReady(button)
    }

    private func openUpNext() {
        revealUpNext()
        app.buttons[AccessibilityID.playerQuickUpNextButton].firstMatch.tap()
        XCTAssertTrue(element(AccessibilityID.playerUpNextPanel).waitForExistence(timeout: 5))
    }

    private func launch(
        shorts: Bool = false, playerArguments: [String] = ["--uitesting-deeplink-video=preload-0"]
    ) {
        app.launchArguments = [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-sign-out",
            "--uitesting-disable-sponsorblock", "--uitesting-show-controls",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if shorts {
            app.launchArguments += ["--uitesting-shorts", "--uitesting-shorts-ids=preload-0,preload-1"]
        } else {
            app.launchArguments += playerArguments
        }
        app.launchEnvironment["SHORTS_TEST_MEDIA_URL"] = mediaURL
        app.launchEnvironment["OFFLINE_TEST_MEDIA_URL"] = mediaURL
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openMoreMenu() {
        let more = app.buttons[AccessibilityID.playerMoreButton].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        assertReady(more)
        more.tap()
        XCTAssertTrue(element(AccessibilityID.playerMoreMenu).waitForExistence(timeout: 5))
    }

    private func checkPanel(trigger: String, panel identifier: String, firstChoice: String) {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(to: orientation)
            let button = app.buttons[trigger].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            assertReady(button)
            let window = app.frame
            button.tap()
            let panel = element(identifier)
            assertPanel(panel, firstChoice: app.buttons[firstChoice].firstMatch, in: window)
            rotate(to: orientation.isPortrait ? .landscapeLeft : .portrait)
            assertPanel(panel, firstChoice: app.buttons[firstChoice].firstMatch, in: app.frame)
            app.buttons[AccessibilityID.playerOptionPanelCancel].firstMatch.tap()
            assertDismissed(panel)
        }
    }

    private func assertPanel(_ panel: XCUIElement, firstChoice: XCUIElement, in window: CGRect) {
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(firstChoice.waitForExistence(timeout: 5))
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !panel.frame.isEmpty && window.contains(panel.frame) && firstChoice.isHittable
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        XCTAssertTrue(window.contains(panel.frame), "Panel \(panel.frame) must fit inside window \(window)")
        XCTAssertTrue(firstChoice.isHittable, "The first choice must be tappable on the first presentation")
    }

    /// The bounds checks are about the iPad popover; iPhone presents these panels as a system sheet.
    private func requirePad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPhone shows option panels as a sheet")
    }

    private func assertReady(_ button: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func assertDismissed(_ panel: XCUIElement) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                orientation.isLandscape ? app.frame.width > app.frame.height : app.frame.width < app.frame.height
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    }
}
#endif
