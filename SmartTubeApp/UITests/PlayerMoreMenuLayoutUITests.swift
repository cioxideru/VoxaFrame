import XCTest

/// Merged from `PlayerMoreMenuLayoutUITests` + `PlayerPickerOverlayLayoutUITests`.
/// The menu layout tests share one app launch. First-open panel regressions live in
/// `PlayerOptionPanelBoundsUITests` and use the local media fixture.
final class PlayerMenuAndPickerLayoutUITests: XCTestCase {

    // MARK: - Class-level shared state

    private static var sharedApp: XCUIApplication!
    private static var skipAllTests = false
    private static let skipReason = "Player did not open within 20 s — network unavailable or video inaccessible"
    private static var skipScreenshot: XCUIScreenshot?

    override class func setUp() {
        super.setUp()
        let a = XCUIApplication()
        a.launchArguments = [
            "--uitesting",
            "--uitesting-deeplink-video=dQw4w9WgXcQ",
            "--uitesting-open-more-menu",
        ]
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        a.launch()
        sharedApp = a
        // Wait for the more menu to appear — the --uitesting-open-more-menu flag
        // opens it on top of the player, so player.view is inaccessible under the sheet.
        skipAllTests = !a.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch.waitForExistence(timeout: 20)
        if skipAllTests {
            skipScreenshot = a.screenshot()
        }
    }

    override class func tearDown() {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        sharedApp?.terminate()
        sharedApp = nil
        skipAllTests = false
        skipScreenshot = nil
        super.tearDown()
    }

    // MARK: - Per-test lifecycle

    private var app: XCUIApplication { Self.sharedApp }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        if let shot = Self.skipScreenshot {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "App state when player failed to load"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        guard !Self.skipAllTests else { return }
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        // Wait for the portrait frame to settle before opening the menu.
        let a2 = app
        let portraitSettled = NSPredicate { _, _ in a2.frame.size.width < a2.frame.size.height }
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: portraitSettled, object: nil)], timeout: 5)
        ensureMoreMenuVisible()
    }

    override func tearDown() {
        dismissPickerIfOpen()
        // If a landscape test just ran, close the menu before returning to portrait.
        // This gives the next setUp a clean state to reopen the menu in portrait.
        let wasLandscape = app.frame.size.width > app.frame.size.height
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        if wasLandscape {
            // Wait for the frame to confirm portrait before closing the menu.
            let a = app
            let portraitPred = NSPredicate { _, _ in a.frame.size.width < a.frame.size.height }
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: portraitPred, object: nil)], timeout: 5)
            closeMoreMenuIfOpen()
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// Ensures the more menu is visible; re-opens it if a previous test dismissed it.
    /// Uses two tap attempts in case controls auto-hid before the first tap registered.
    private func ensureMoreMenuVisible() {
        let scrollView = app.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch
        if scrollView.waitForExistence(timeout: 5) { return }
        let moreButton = app.buttons[AccessibilityID.playerMoreButton].firstMatch
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if moreButton.waitForExistence(timeout: 4) {
                moreButton.tap()
                break
            }
        }
        _ = scrollView.waitForExistence(timeout: 8)
    }

    /// Dismisses an open picker overlay so the more menu can be restored.
    private func dismissPickerIfOpen() {
        let anyOpen = [
            AccessibilityID.playerQualityPicker, AccessibilityID.playerSpeedPicker,
            AccessibilityID.playerSleepTimerPicker,
        ]
        .contains { app.descendants(matching: .any).matching(identifier: $0).firstMatch.exists }
        if anyOpen {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
            _ = app.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch.waitForExistence(timeout: 2)
        }
    }

    /// Dismisses the more menu via its cancel row to restore a clean player state.
    private func closeMoreMenuIfOpen() {
        let cancel = app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch
        if cancel.waitForExistence(timeout: 5), cancel.isHittable { cancel.tap() }
    }

    /// Rotates to landscape and waits for the frame to confirm the change.
    private func rotateToLandscapeAndWait() {
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif
        let a = app
        let pred = NSPredicate { _, _ in a.frame.size.width > a.frame.size.height }
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: pred, object: nil)], timeout: 5)
    }

    // MARK: - More menu layout tests

    func testMoreMenuIsScrollableAndUsableInLandscape() throws {
        try XCTSkipIf(Self.skipAllTests, Self.skipReason)
        rotateToLandscapeAndWait()
        ensureMoreMenuVisible()

        let scrollView = app.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch
        XCTAssertTrue(
            scrollView.waitForExistence(timeout: 10),
            "More menu scroll view must be accessible in landscape")

        let downloadButton = app.buttons[AccessibilityID.offlineWatch].firstMatch
        XCTAssertTrue(
            downloadButton.waitForExistence(timeout: 5),
            "Download button should be accessible in landscape more menu")
        for _ in 0..<6 where !downloadButton.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(
            downloadButton.isHittable,
            "Download button should be tappable in landscape")

        let cancelButton = app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !cancelButton.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(
            cancelButton.exists,
            "Cancel row should remain in the accessibility tree")
        XCTAssertTrue(
            cancelButton.isHittable,
            "Cancel row should be reachable by scrolling in landscape")
        XCTAssertEqual(
            app.state, .runningForeground,
            "App must remain running while interacting with the landscape more menu")
    }

    func testMoreMenuWidthIsConstrainedInPortrait() throws {
        try XCTSkipIf(Self.skipAllTests, Self.skipReason)

        let scrollView = app.scrollViews[AccessibilityID.playerMoreMenuScrollView].firstMatch
        XCTAssertTrue(
            scrollView.waitForExistence(timeout: 10),
            "More menu scroll view must appear in portrait")

        #if os(iOS)
        let panel = app.descendants(matching: .any).matching(identifier: AccessibilityID.playerMoreMenu).firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let contained = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                !panel.frame.isEmpty && app.frame.contains(panel.frame)
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [contained], timeout: 5), .completed)
        #else
        let screenWidth = app.frame.size.width
        let menuWidth = scrollView.frame.size.width
        XCTAssertLessThanOrEqual(
            menuWidth, screenWidth * 0.85,
            "More menu width (\(menuWidth)pt) must be ≤ 85 % of screen width "
                + "(\(screenWidth)pt) — task #44 constraint")
        XCTAssertGreaterThan(
            menuWidth, screenWidth * 0.5,
            "More menu width (\(menuWidth)pt) must be reasonable (> 50 % of screen)")
        #endif
        let downloadButton = app.buttons[AccessibilityID.offlineWatch].firstMatch
        for _ in 0..<6 where !downloadButton.isHittable { scrollView.swipeUp() }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: downloadButton)
        _ = XCTWaiter().wait(for: [hittable], timeout: 12)
        XCTAssertTrue(
            downloadButton.isHittable,
            "Download button must be tappable in portrait — confirms menu items are accessible")
    }

    /// Cancel stays outside the scrolling actions in the native panel header.
    func testMoreMenuCancelIsHittableWithoutScrollingInPortrait() throws {
        try XCTSkipIf(Self.skipAllTests, Self.skipReason)

        let cancelButton = app.buttons[AccessibilityID.playerMoreMenuCancelButton].firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 10),
            "Cancel button must be accessible in the portrait more menu")
        XCTAssertTrue(
            cancelButton.isHittable,
            "Cancel button must be hittable without scrolling in portrait")
    }

}

/// The More menu's "Open Channel" row opens the channel page (the same `ChannelView` as the Subscriptions section).
final class PlayerMoreMenuOpenChannelUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--uitesting-deeplink-video=dQw4w9WgXcQ", "--uitesting-open-more-menu"]
        app.launchArguments.append("--uitesting-video-channel=UCuAXFkgsw1L7xaCfnd5JJOw")
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        app.launch()
    }

    override func tearDown() { app.terminate() }

    func testOpenChannelRowShowsChannelScreen() throws {
        let row = app.buttons[AccessibilityID.playerMoreMenuOpenChannel].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Open Channel row is missing from the More menu")
        row.tap()
        let header = app.descendants(matching: .any)[AccessibilityID.channelHeader].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20), "Channel screen did not open")
    }
}
