import XCTest

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
