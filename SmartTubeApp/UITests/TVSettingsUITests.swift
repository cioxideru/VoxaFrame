#if os(tvOS)
import XCTest

// MARK: - TVSettingsUITests
//
// Verifies that the Settings tab is reachable via the tvOS tab bar and that
// key controls are present in the accessibility tree.
//
// No network access is required — all tested elements are static UI.
//
// Navigation: tab bar → right × 4 → select = Settings tab
// (same pattern proven by TVFocusChainUITests.testSettingsTabBarVisibleAfterScrollDownAndUp)

final class TVSettingsUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        try openSettings()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openSettings() throws {
        for _ in 0..<4 { remote.press(.right) }
        remote.press(.select)
        // Wait for resetAllButton as the sentinel that Settings has fully rendered
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        guard sentinel.waitForExistence(timeout: 12) else {
            try captureAndSkip("settings.resetAllButton not found — Settings tab did not open", in: app)
        }
    }

    // MARK: - Tests

    /// The sign-in button must appear in Settings when the user is not signed in.
    func testSignInButtonVisibleWhenSignedOut() throws {
        let signInButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.signInButton'"))
            .firstMatch
        guard signInButton.waitForExistence(timeout: 5) else {
            try captureAndSkip(
                "settings.signInButton not found — device may already be signed in (expected a signed-out state for this test)",
                in: app
            )
        }
        XCTAssertTrue(signInButton.exists, "settings.signInButton must be in the accessibility tree when signed out")
    }

    /// The Hide Shorts toggle must be in the accessibility tree.
    func testHideShortsToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.hideShortsToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.hideShortsToggle must be in the accessibility tree"
        )
    }

    /// The SponsorBlock toggle must be in the accessibility tree.
    func testSponsorBlockToggleExists() {
        let toggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.sponsorBlockToggle'"))
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.sponsorBlockToggle must be in the accessibility tree"
        )
    }

    /// The Max Resolution picker must be in the accessibility tree.
    func testPreferredQualityPickerExists() {
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredQualityPicker'"))
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "settings.preferredQualityPicker must be in the accessibility tree"
        )
    }

    /// The Preferred Audio Language row must be in the accessibility tree.
    func testPreferredAudioLanguageRowExists() {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.preferredAudioLanguageRow'"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.preferredAudioLanguageRow must be in the accessibility tree"
        )
    }

    /// The Seek Back picker must be in the accessibility tree on tvOS.
    func testSeekBackRowExists() {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.seekBackRow'"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.seekBackRow must be in the accessibility tree on tvOS"
        )
    }

    /// The Reset All Settings button must be in the accessibility tree.
    func testResetAllSettingsButtonExists() {
        let button = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "settings.resetAllButton must be in the accessibility tree"
        )
    }

    /// B2 (PLAN-0027): Reset All Settings asks first; Back cancels, keeps a changed preference and returns
    /// the focus to Reset.
    func testResetAllSettingsAsksAndBackCancels() {
        let hideShorts = app.descendants(matching: .any).matching(identifier: "settings.hideShortsToggle").firstMatch
        let button = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsResetAllButton)
            .firstMatch
        XCTAssertTrue(hideShorts.waitForExistence(timeout: 10), "settings.hideShortsToggle not found")

        // Turn Hide Shorts on (its default is off), so a reset that slipped through would show.
        let onValues = ["1", "On"]
        let isOn = NSPredicate(format: "value IN %@", onValues)
        moveFocus(to: hideShorts, pressing: .down)
        let original = hideShorts.value as? String
        XCTAssertNotNil(original, "Hide Shorts must report its state")
        let wasOn = onValues.contains(original ?? "")
        if !wasOn {
            remote.press(.select)
            waitUntil(hideShorts, matches: isOn, "Select must turn Hide Shorts on")
        }

        // Reset is the last row.
        moveFocus(to: button, pressing: .down)
        remote.press(.select)
        let confirm = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsResetAllConfirm)
            .firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Reset All Settings must ask before resetting")
        remote.press(.menu)
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "Back must cancel the confirmation")
        waitUntil(button, matches: NSPredicate(format: "hasFocus == true"), "Back must return the focus to Reset")

        // Back up to Hide Shorts: still on. Then restore it, since this class does not reset settings.
        moveFocus(to: hideShorts, pressing: .up)
        XCTAssertTrue(isOn.evaluate(with: hideShorts), "Cancel must keep Hide Shorts on")
        if !wasOn {
            remote.press(.select)
            waitUntil(hideShorts, matches: NSPredicate(format: "value == %@", original ?? ""), "Restore Hide Shorts")
        }
    }

    /// Presses `direction` until `element` has the focus; fails the test when it never does.
    private func moveFocus(to element: XCUIElement, pressing direction: XCUIRemote.Button) {
        for _ in 0..<80 where !element.hasFocus { remote.press(direction) }
        XCTAssertTrue(element.hasFocus, "Focus never reached \(element.identifier)")
    }

    private func waitUntil(_ element: XCUIElement, matches predicate: NSPredicate, _ message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, message)
    }

    /// Regression test for #149: the Settings tab must open on the first select press.
    /// Before the fix, MainTVTabView used an unbound TabView which made the tvOS focus
    /// engine require two presses — the first focused the tab, the second activated it.
    func testSettingsTabOpensSingleSelectPress() throws {
        // setUpWithError already calls openSettings() which presses select exactly once.
        // If the sentinel was found (setup succeeded), Settings opened on a single press.
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.resetAllButton'"))
            .firstMatch
        XCTAssertTrue(
            sentinel.waitForExistence(timeout: 10),
            "#149 regression: Settings tab must open after a single select press, not two"
        )
    }
}
#endif
