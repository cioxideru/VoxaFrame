import XCTest

// MARK: - RecommendedChipUITests
//
// Home is YouTube's recommendations feed, so the separate "Recommended" chip is gone and
// Subscriptions keeps its own chip. `--uitesting-inject-recommended-ids` makes the injected
// videos the whole Home feed, so these tests need no account feed or network.

final class RecommendedChipUITests: XCTestCase {

    /// Stable YouTube video IDs that form the Home recommendations feed.
    private static let injectIDs: [String] = [
        "dQw4w9WgXcQ", "9bZkp7q19f0", "MCv4EyEFgVg", "pPvd8UxmCGY", "fKopy74weus",
    ]

    private static var sharedApp: XCUIApplication!
    private var app: XCUIApplication { RecommendedChipUITests.sharedApp }
    private var chipBar: XCUIElement { app.scrollViews[AccessibilityID.homeChipBar] }

    // MARK: - Lifecycle

    override class func setUp() {
        super.setUp()
        sharedApp = XCUIApplication()
        sharedApp.launchArguments += [
            "--uitesting", "--uitesting-signed-in", "--uitesting-extended-fetch-timeout",
            "--uitesting-inject-recommended-ids=\(injectIDs.joined(separator: ","))",
        ]
        sharedApp.launch()
    }

    override class func tearDown() {
        sharedApp.terminate()
        sharedApp = nil
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let backButton = app.buttons[AccessibilityID.playerBackButton].firstMatch
        if backButton.waitForExistence(timeout: 2) { backButton.tap() }
        UITestHelpers.tapTab(named: "Home", in: app)
        XCTAssertTrue(chipBar.waitForExistence(timeout: 10), "home.chipBar must appear on the Home tab")
        select("Home")
    }

    // MARK: - Tests

    /// Home and Subscriptions are the only feed chips for recommendations and subscriptions.
    func testChipBarHasNoRecommendedChip() {
        XCTAssertTrue(chipBar.buttons["Home"].waitForExistence(timeout: 5), "Home chip must exist")
        XCTAssertTrue(chipBar.buttons["Subscriptions"].waitForExistence(timeout: 5), "Subscriptions chip must exist")
        XCTAssertFalse(chipBar.buttons["Recommended"].exists, "Home replaces the Recommended chip")
    }

    /// Home shows exactly the recommendations feed, and no error alert.
    func testHomeShowsRecommendations() {
        for id in Self.injectIDs {
            let card = app.descendants(matching: .any).matching(identifier: AccessibilityID.videoCard(id)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 20), "Recommendation \(id) must be on Home")
        }
        XCTAssertFalse(app.alerts["Error"].exists, "Loading Home must not show an error alert")
    }

    /// Tapping a Home recommendation opens PlayerView.
    func testTappingRecommendationOpensPlayer() {
        let card = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.videoCard(Self.injectIDs[0])).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "The first recommendation must be on Home")
        XCTAssertTrue(UITestHelpers.openPlayer(from: card, in: app), "PlayerView must open from a Home recommendation")
    }

    /// Subscriptions has its own chip; returning to Home brings the recommendations back.
    func testSwitchingBetweenHomeAndSubscriptions() {
        let homeChip = chipBar.buttons["Home"]
        let subscriptionsChip = chipBar.buttons["Subscriptions"]
        select("Subscriptions")
        XCTAssertTrue(subscriptionsChip.isSelected, "Subscriptions must be selected after tapping it")
        XCTAssertFalse(homeChip.isSelected, "Home must be deselected while Subscriptions is shown")
        select("Home")
        XCTAssertTrue(homeChip.isSelected, "Home must be selected after tapping it")
        let card = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.videoCard(Self.injectIDs[0])).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Home must show the recommendations again")
    }

    // MARK: - Helpers

    private func select(_ title: String) {
        let chip = chipBar.buttons[title]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(title) chip must exist")
        guard !chip.isSelected else { return }
        UITestHelpers.scrollChipIntoView(chip, in: chipBar, app: app)
        chip.tap()
    }
}
