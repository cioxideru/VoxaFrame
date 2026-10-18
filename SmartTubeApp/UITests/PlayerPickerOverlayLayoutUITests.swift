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

    func testOfflineDownloadActionIsHittableWithoutScrolling() {
        launch()
        openMoreMenu()
        let offline = app.buttons[AccessibilityID.offlineWatch].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 5))
        XCTAssertTrue(offline.isHittable)
        offline.tap()
        assertDismissed(element(AccessibilityID.playerMoreMenu))

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
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
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

    private func launch(shorts: Bool = false) {
        app.launchArguments = [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-sign-out",
            "--uitesting-disable-sponsorblock", "--uitesting-show-controls",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if shorts {
            app.launchArguments += ["--uitesting-shorts", "--uitesting-shorts-ids=preload-0,preload-1"]
        } else {
            app.launchArguments.append("--uitesting-deeplink-video=preload-0")
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
