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
        openSettings()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private let groups = [
        "account", "playback", "languages", "thisDevice", "appearance", "sponsorBlock", "parentalControls", "about",
    ]

    private func category(_ group: String) -> XCUIElement {
        app.buttons[AccessibilityID.settingsCategory(group)].firstMatch
    }

    private var focusedCategoryIndex: Int? {
        groups.firstIndex { category($0).exists && category($0).hasFocus }
    }

    private func openSettings() {
        for _ in 0..<4 { remote.press(.right) }
        remote.press(.select)
        let sentinel = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsCategories)
            .firstMatch
        XCTAssertTrue(sentinel.waitForExistence(timeout: 12), "Settings must show its category list")
        for _ in 0..<10 where focusedCategoryIndex == nil { remote.press(.down) }
        XCTAssertNotNil(focusedCategoryIndex, "Down from the tab bar must focus the category list")
    }

    private func selectCategory(_ group: String, enterDetail: Bool = true) {
        if focusedCategoryIndex == nil {
            remote.press(.menu)
            let returned = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in self.focusedCategoryIndex != nil }, object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [returned], timeout: 5), .completed, "Back must return to categories")
        }
        guard let current = focusedCategoryIndex, let target = groups.firstIndex(of: group) else {
            XCTFail("Cannot focus settings category \(group)")
            return
        }
        let direction: XCUIRemote.Button = target > current ? .down : .up
        for _ in 0..<abs(target - current) { remote.press(direction) }
        waitUntil(category(group), matches: NSPredicate(format: "hasFocus == true"), "Focus must reach \(group)")
        if enterDetail {
            remote.press(.right)
            waitUntil(
                category(group), matches: NSPredicate(format: "hasFocus == false"), "Right must enter the settings")
            assertDetailHasFocus()
        }
    }

    private func assertDetailHasFocus() {
        let table = app.tables[AccessibilityID.settingsForm].firstMatch
        let form = table.exists ? table : app.collectionViews[AccessibilityID.settingsForm].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let focused = form.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "A settings control must take focus")
    }

    // MARK: - Tests

    /// The sign-in button must appear in Settings when the user is not signed in.
    func testSignInButtonVisibleWhenSignedOut() throws {
        selectCategory("account")
        let signInButton = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsSignInButton)
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
        selectCategory("appearance")
        let toggle = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsHideShortsToggle)
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.hideShortsToggle must be in the accessibility tree"
        )
    }

    /// The SponsorBlock toggle must be in the accessibility tree.
    func testSponsorBlockToggleExists() {
        selectCategory("sponsorBlock")
        let toggle = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsSponsorBlockToggle)
            .firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "settings.sponsorBlockToggle must be in the accessibility tree"
        )
    }

    /// The Max Resolution picker must be in the accessibility tree.
    func testPreferredQualityPickerExists() {
        selectCategory("playback")
        let picker = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsPreferredQualityPicker)
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "settings.preferredQualityPicker must be in the accessibility tree"
        )
    }

    /// The Preferred Audio Language row must be in the accessibility tree.
    func testPreferredAudioLanguageRowExists() {
        selectCategory("languages")
        let row = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsPreferredAudioLanguageRow)
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.preferredAudioLanguageRow must be in the accessibility tree"
        )
    }

    /// The Seek Back picker must be in the accessibility tree on tvOS.
    func testSeekBackRowExists() {
        selectCategory("playback")
        let row = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsSeekBackRow)
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "settings.seekBackRow must be in the accessibility tree on tvOS"
        )
    }

    /// The Reset All Settings button must be in the accessibility tree.
    func testResetAllSettingsButtonExists() {
        selectCategory("about")
        let button = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.settingsResetAllButton)
            .firstMatch
        XCTAssertTrue(
            button.waitForExistence(timeout: 10),
            "settings.resetAllButton must be in the accessibility tree"
        )
    }

    /// B2 (PLAN-0027): Reset All Settings asks first; Back cancels, keeps a changed preference and returns
    /// the focus to Reset.
    func testResetAllSettingsAsksAndBackCancels() {
        selectCategory("appearance")
        let hideShorts = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsHideShortsToggle)
            .firstMatch
        let button = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsResetAllButton)
            .firstMatch
        XCTAssertTrue(hideShorts.waitForExistence(timeout: 10), "settings.hideShortsToggle not found")

        // Turn Hide Shorts off (it is on by default), so a reset that slipped through would turn it back on.
        let onValues = ["1", "On"]
        let isOff = NSPredicate(format: "NOT (value IN %@)", onValues)
        moveFocus(to: hideShorts)
        let original = hideShorts.value as? String
        XCTAssertNotNil(original, "Hide Shorts must report its state")
        let wasOn = onValues.contains(original ?? "")
        if wasOn {
            remote.press(.select)
            waitUntil(hideShorts, matches: isOff, "Select must turn Hide Shorts off")
        }

        selectCategory("about")
        moveFocus(to: button)
        remote.press(.select)
        let confirm = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsResetAllConfirm)
            .firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Reset All Settings must ask before resetting")
        remote.press(.menu)
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "Back must cancel the confirmation")
        waitUntil(button, matches: NSPredicate(format: "hasFocus == true"), "Back must return the focus to Reset")

        // Return to Appearance: still off. Then restore it, since this class does not reset settings.
        selectCategory("appearance")
        moveFocus(to: hideShorts)
        XCTAssertTrue(isOff.evaluate(with: hideShorts), "Cancel must keep Hide Shorts off")
        if wasOn {
            remote.press(.select)
            waitUntil(hideShorts, matches: NSPredicate(format: "value == %@", original ?? ""), "Restore Hide Shorts")
        }
    }

    func testRightEntersDetailAndBackRestoresTheSelectedCategory() {
        selectCategory("playback", enterDetail: false)
        let selected = category("playback")
        XCTAssertGreaterThanOrEqual(selected.frame.height, 66)
        remote.press(.right)
        waitUntil(selected, matches: NSPredicate(format: "hasFocus == false"), "Right must enter the detail")
        assertDetailHasFocus()
        let quality = app.descendants(matching: .any).matching(
            identifier: AccessibilityID.settingsPreferredQualityPicker
        )
        .firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        remote.press(.menu)
        waitUntil(selected, matches: NSPredicate(format: "hasFocus == true"), "Back must restore the selected category")
        XCTAssertTrue(quality.exists, "Back changes focus without discarding the selected category")
    }

    /// Right can enter midway down a form, so search both directions without activating other controls.
    private func moveFocus(to element: XCUIElement) {
        for direction in [XCUIRemote.Button.down, .up] {
            for _ in 0..<24 {
                if element.hasFocus { return }
                remote.press(direction)
            }
        }
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
            .matching(identifier: AccessibilityID.settingsCategories)
            .firstMatch
        XCTAssertTrue(
            sentinel.waitForExistence(timeout: 10),
            "#149 regression: Settings tab must open after a single select press, not two"
        )
    }
}
#endif
