import XCTest

#if os(iOS)
import UIKit
#endif

// MARK: - SettingsUITests
//
// Relaunch and reset-sensitive settings tests live here; shared-launch checks
// remain in HomeFeedAndSettingsUITests.swift.

final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--uitesting-reset-settings"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSignInButtonVisibleWhenSignedOut() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-reset-settings", "--uitesting-sign-out"]
        app.launch()
        UITestHelpers.tapTab(named: "Settings", in: app)
        let signInPredicate = NSPredicate(
            format: "identifier == 'settings.signInButton' OR label == 'Sign in with Google'")
        let signInEl = app.descendants(matching: .any).matching(signInPredicate).firstMatch
        XCTAssertTrue(
            signInEl.waitForExistence(timeout: 5),
            "'Sign in with Google' button must be visible when the session is cleared via --uitesting-sign-out")
    }

    func testShortsTranslationDefaultsAreIndependentAndPersist() {
        UITestHelpers.tapTab(named: "Settings", in: app)
        let shortsToggle = app.switches[AccessibilityID.settingsShortsYandexVOTToggle]
        let regularToggle = app.switches[AccessibilityID.settingsYandexVOTToggle]
        let form = app.collectionViews.firstMatch
        UITestHelpers.scrollUntilVisible(shortsToggle, in: form, maxSwipes: 14)
        XCTAssertTrue(shortsToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(shortsToggle.value as? String, "0")
        shortsToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(shortsToggle.value as? String, "1")
        let original = app.switches[AccessibilityID.settingsShortsKeepOriginalAudioToggle]
        UITestHelpers.scrollUntilVisible(original, in: form)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(original.value as? String, "0")
        XCTAssertEqual(regularToggle.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Separate Shorts translation settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        UITestHelpers.tapTab(named: "Settings", in: app)
        UITestHelpers.scrollUntilVisible(shortsToggle, in: form, maxSwipes: 14)
        XCTAssertEqual(shortsToggle.value as? String, "1")
        UITestHelpers.scrollUntilVisible(original, in: form)
        XCTAssertEqual(original.value as? String, "0")
        XCTAssertEqual(regularToggle.value as? String, "0")
    }
}

#if os(iOS)
/// PLAN-0016: tab restoration must keep the Home section controls below the iPad tab bar.
final class IPadMenuLayoutUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the iPad top tab bar")
        if #unavailable(iOS 18.0) { throw XCTSkip("Requires the iPadOS 18 top tab bar") }
        app.launchArguments = [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-subscriptions", "--uitesting-mixed-feed",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testMenusRemainSeparateAfterNavigationRoundTrips() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            UITestHelpers.tapTab(named: "Home", in: app)
            let chipBar = app.scrollViews[AccessibilityID.homeChipBar].firstMatch
            XCTAssertTrue(chipBar.waitForExistence(timeout: 5))
            let channels = chipBar.buttons["Channels"].firstMatch
            UITestHelpers.scrollChipIntoView(channels, in: chipBar, app: app)
            XCTAssertTrue(channels.waitForExistence(timeout: 5))
            channels.tap()
            XCTAssertTrue(app.buttons[AccessibilityID.subscriptionRow("UCfixtureAlpha")].waitForExistence(timeout: 5))
            assertMenusDoNotOverlap(channels)
            app.buttons[AccessibilityID.subscriptionRow("UCfixtureAlpha")].tap()
            let channelNavigation = app.navigationBars["Alpha Channel"].firstMatch
            XCTAssertTrue(channelNavigation.waitForExistence(timeout: 5))
            channelNavigation.buttons.firstMatch.tap()
            XCTAssertTrue(channels.waitForExistence(timeout: 5))
            assertMenusDoNotOverlap(channels)

            for destination in ["Settings", "Search", "Library"] {
                UITestHelpers.tapTab(named: destination, in: app)
                if destination == "Settings" { openAndCloseVisibleSections() }
                UITestHelpers.tapTab(named: "Home", in: app)
                XCTAssertTrue(chipBar.waitForExistence(timeout: 5))
                assertMenusDoNotOverlap(channels)
                XCTAssertTrue(channels.isSelected, "Returning to Home must retain the selected Channels section")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Separated iPad menus - \(orientation.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func openAndCloseVisibleSections() {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let visibleSections = form.cells.containing(.staticText, identifier: "Visible Sections").firstMatch
        UITestHelpers.scrollUntilVisible(visibleSections, in: form)
        XCTAssertTrue(visibleSections.waitForExistence(timeout: 5))
        visibleSections.tap()
        let navigationBar = app.navigationBars["Visible Sections"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        navigationBar.buttons.firstMatch.tap()
        XCTAssertTrue(form.waitForExistence(timeout: 5))
    }

    private func assertMenusDoNotOverlap(
        _ sectionChip: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let searchTab = app.tabBars.buttons["Search"].firstMatch
        let topTab = searchTab.exists ? searchTab : app.buttons["Search"].firstMatch
        XCTAssertTrue(topTab.waitForExistence(timeout: 5), file: file, line: line)
        let separated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !sectionChip.frame.isEmpty && !topTab.frame.isEmpty && sectionChip.frame.minY >= topTab.frame.maxY
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [separated], timeout: 5), .completed,
            "Home controls \(sectionChip.frame) must stay below the iPad tab \(topTab.frame)", file: file, line: line)
        XCTAssertTrue(topTab.isHittable, file: file, line: line)
    }
}
#endif
