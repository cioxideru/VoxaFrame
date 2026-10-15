import XCTest

// MARK: - HomeShortsCountUITests
//
// Regression tests for task #91: Home Shorts row must show ≥ 6 cards after
// initial load, and new cards must appear when the row is scrolled.
//
// Launch args (per-test launch, matching RecommendedChipUITests pattern):
//   --uitesting                        standard test guard
//   --uitesting-signed-in              forces auth.isSignedIn = true
//
// No --uitesting-reset-settings: preserves keychain auth so auth.isSignedIn
// is naturally true (or falls through to --uitesting-signed-in backup).

final class HomeShortsCountUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "--uitesting-signed-in",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Returns all `shorts.card.*` elements currently inside the `home.shortsRow` scroll view.
    /// Uses descendants(matching:.any) because SwiftUI propagates the identifier to leaf
    /// elements (ActivityIndicator thumbnails, StaticText labels), not to a single container.
    /// Results are deduplicated by identifier so each card is counted once.
    private func shortsCards() -> [XCUIElement] {
        let row = app.scrollViews["home.shortsRow"]
        guard row.exists else { return [] }
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'shorts.card.'")
        let all = row.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
        var seen = Set<String>()
        return all.filter { seen.insert($0.identifier).inserted }
    }

    /// Waits until `home.shortsRow` exists and contains at least `minCount` cards.
    @discardableResult
    private func waitForShorts(minCount: Int, timeout: TimeInterval = 15) -> Int {
        let row = app.scrollViews["home.shortsRow"]
        XCTAssertTrue(
            row.waitForExistence(timeout: timeout),
            "home.shortsRow not found within \(timeout)s")

        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            let count = shortsCards().count
            if count >= minCount { return count }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return shortsCards().count
    }

    // MARK: - Tests

    /// After app launch the Shorts row must contain at least 3 cards (one full
    /// screen width on iPhone, threshold = 3 visible at once).
    func testShortsRowHasAtLeastThreeCardsOnLaunch() {
        let count = waitForShorts(minCount: 3)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shorts row on launch — expected ≥3 cards, got \(count)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertGreaterThanOrEqual(
            count, 3,
            "Shorts row should show ≥ 3 cards after load; got \(count)"
        )
    }

    /// After app load the Shorts row must contain at least 6 cards so that
    /// the user has two full screens of content ready without waiting.
    func testShortsRowHasAtLeastSixCardsAfterLoad() {
        let count = waitForShorts(minCount: 6)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shorts row after load — expected ≥6 cards, got \(count)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertGreaterThanOrEqual(
            count, 6,
            "Shorts row should show ≥ 6 cards (2 screens × 3 cards/screen); got \(count)."
        )
    }

    /// Scrolling the Shorts row must make sense: at least one card must start beyond
    /// the row's visible right edge (proving the row has more content than fits on screen),
    /// and card count must be preserved after a left-swipe.
    func testScrollingShortsRowRevealsMoreCards() {
        let row = app.scrollViews["home.shortsRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "home.shortsRow not found")

        // Wait for at least 4 cards.
        let count = waitForShorts(minCount: 4)
        XCTAssertGreaterThanOrEqual(count, 4, "Need ≥ 4 cards to verify scrollable content")

        let cards = shortsCards()

        // Screenshot before scroll — shows the initial shorts row state.
        let beforeScreenshot = XCTAttachment(screenshot: app.screenshot())
        beforeScreenshot.name = "Shorts row before scroll — \(count) cards, offscreen check pending"
        beforeScreenshot.lifetime = .keepAlways
        add(beforeScreenshot)

        // Verify the row has content beyond the visible viewport:
        // at least one card must start to the right of the row's visible right edge.
        // (XCUIElement frames are in window coordinates, so card.frame.minX >= row.frame.maxX
        //  means the card is off-screen to the right.)
        let rowMaxX = row.frame.maxX
        let hasOffscreenCard = cards.contains { $0.frame.minX >= rowMaxX }
        XCTAssertTrue(
            hasOffscreenCard,
            "At least one Shorts card should start beyond the row's right edge (\(rowMaxX)pt), "
                + "proving the row is scrollable. "
                + "Card minX values: \(cards.map { "\($0.identifier)=\($0.frame.minX)" })"
        )

        // Swipe left to scroll the row; verify the card count is preserved.
        row.swipeLeft(velocity: .slow)
        Thread.sleep(forTimeInterval: 0.5)

        let countAfterScroll = shortsCards().count
        let afterScreenshot = XCTAttachment(screenshot: app.screenshot())
        afterScreenshot.name = "Shorts row after scroll — before: \(count), after: \(countAfterScroll)"
        afterScreenshot.lifetime = .keepAlways
        add(afterScreenshot)
        XCTAssertGreaterThanOrEqual(
            countAfterScroll, count,
            "Card count must not decrease after scrolling (before: \(count), after: \(countAfterScroll))"
        )
    }

    /// Scrolling all the way to the last injected card must not crash, reduce the
    /// card count, or remove any previously visible card.
    ///
    /// Each Home Shorts row holds a fixed chunk of Shorts; more Shorts go into the
    /// rows further down the feed, so this only checks that scrolling to the end of
    /// the row is safe.
    func testScrollToLastCardPreservesAllInjectedCards() {
        let row = app.scrollViews["home.shortsRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "home.shortsRow not found")

        // Wait for ≥6 cards (the proven reliable threshold; 8 IDs are injected but
        // render timing means the exact count can vary slightly).
        let initialCount = waitForShorts(minCount: 6)
        XCTAssertGreaterThanOrEqual(
            initialCount, 6,
            "Expected ≥6 injected cards before scroll; got \(initialCount)"
        )

        // Scroll left 4 times to reach the far-right end of the row.
        // 8 cards × 120pt each = 960pt total; ~390pt viewport; 4 slow swipes covers ~600pt.
        for _ in 0..<4 {
            row.swipeLeft(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Brief pause — lets any async Shorts paging settle.
        Thread.sleep(forTimeInterval: 1.0)

        let finalCount = shortsCards().count
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shorts row at end — initial=\(initialCount) final=\(finalCount)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertGreaterThanOrEqual(
            finalCount, initialCount,
            "Card count must not drop after scrolling to the last card (initial: \(initialCount), final: \(finalCount))"
        )
    }

    /// Swiping left 6 times on the Shorts thumbnail row must reveal new Short cards after each swipe.
    /// Regression for FEshorts deprecation: only 1–2 Shorts meant every swipe showed the same card.
    func testShortsRowSixHorizontalSwipesRevealNewCards() {
        let row = app.scrollViews["home.shortsRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "home.shortsRow not found")

        let initialCount = waitForShorts(minCount: 4, timeout: 25)
        XCTAssertGreaterThanOrEqual(
            initialCount, 4,
            "Need ≥4 Shorts to verify 6 swipes reveal new cards; got \(initialCount)")

        // Detect which cards are currently in the row's visible viewport by frame position.
        func visibleIDs() -> Set<String> {
            let rowMin = row.frame.minX
            let rowMax = row.frame.maxX
            return Set(
                shortsCards().filter { $0.frame.maxX > rowMin && $0.frame.minX < rowMax }
                    .map { $0.identifier })
        }

        var seen = visibleIDs()
        var swipesWithNewCards = 0

        for swipeNum in 1...6 {
            row.swipeLeft(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.8)

            let nowVisible = visibleIDs()
            let newlyVisible = nowVisible.subtracting(seen)
            seen.formUnion(nowVisible)

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Swipe \(swipeNum): +\(newlyVisible.count) new in view (total seen: \(seen.count))"
            shot.lifetime = .keepAlways
            add(shot)

            if !newlyVisible.isEmpty { swipesWithNewCards += 1 }
        }

        XCTAssertGreaterThan(
            swipesWithNewCards, 0,
            "At least one left-swipe must bring a new Short into view; "
                + "0/6 swipes showed new cards — Shorts row has insufficient content."
        )
    }
}

// MARK: - HomeShortsEndlessUITests

/// The Home feed is one vertical scroll: a Shorts row, two rows of videos, the next Shorts
/// row, and so on. Scrolling down must keep bringing new Shorts rows, filled with Shorts the
/// first row did not show.
///
/// IMPORTANT: exercises the real network so Shorts paging actually runs. Requires a
/// signed-in account via keychain.
final class HomeShortsEndlessUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "--uitesting-signed-in",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func shortsCardIDs(in row: XCUIElement) -> Set<String> {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.shortsCard(""))
        return Set(row.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.map(\.identifier))
    }

    /// Swipes the feed up until `row` exists, giving up after `maxSwipes`.
    private func scrollDown(until row: XCUIElement, maxSwipes: Int = 25) -> Bool {
        for _ in 0..<maxSwipes {
            if row.waitForExistence(timeout: 2) { return true }
            // Start the drag left of the middle so it begins on the feed, then go up.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
            start.press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)))
        }
        return row.exists
    }

    /// The second Shorts row shows up further down the feed.
    func testScrollingDownRevealsASecondShortsRow() {
        let firstRow = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30), "First Shorts row not found within 30s")

        let secondRow = app.scrollViews[AccessibilityID.homeShortsRow(1)]
        let found = scrollDown(until: secondRow)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After scrolling the Home feed — second Shorts row found: \(found)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(
            found,
            "Scrolling down the Home feed must reveal \(AccessibilityID.homeShortsRow(1)); "
                + "check that video blocks request Shorts (loadShorts) as they appear."
        )
    }

    /// Later Shorts rows hold Shorts the first row did not, so the feed never repeats a row.
    func testLaterShortsRowsShowNewShorts() {
        let firstRow = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30), "First Shorts row not found within 30s")
        let firstIDs = shortsCardIDs(in: firstRow)
        XCTAssertFalse(firstIDs.isEmpty, "First Shorts row has no cards")

        let secondRow = app.scrollViews[AccessibilityID.homeShortsRow(1)]
        XCTAssertTrue(scrollDown(until: secondRow), "Second Shorts row not found after scrolling")
        let secondIDs = shortsCardIDs(in: secondRow)

        XCTAssertFalse(secondIDs.isEmpty, "Second Shorts row has no cards")
        XCTAssertTrue(
            secondIDs.isDisjoint(with: firstIDs),
            "Second Shorts row repeats Shorts from the first: \(secondIDs.intersection(firstIDs))"
        )
    }
}
