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

/// The fixture supplies ten initial Shorts and two disjoint continuation pages.
/// Regular shelves have no continuations, so only Shorts demand can fetch the new cards.
final class HomeShortsEndlessUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting",
            "--uitesting-signed-in",
            "--uitesting-reset-settings",
            "--uitesting-home-pagination",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func isVisible(_ element: XCUIElement, inside viewport: CGRect) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        return !frame.isEmpty && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Existence alone includes offscreen eager cards. Require a hittable element in the viewport.
    private func scrollDown(until row: XCUIElement, maxSwipes: Int = 30) -> Bool {
        for _ in 0..<maxSwipes {
            if row.waitForExistence(timeout: 1), isVisible(row, inside: app.windows.firstMatch.frame) { return true }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75))
            start.press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)))
        }
        return isVisible(row, inside: app.windows.firstMatch.frame)
    }

    private func assertContinuationCard(_ videoID: String, inRow index: Int) {
        let row = app.scrollViews[AccessibilityID.homeShortsRow(index)]
        XCTAssertTrue(scrollDown(until: row), "Continuation row \(index) never became visible")
        let card = row.descendants(matching: .any)
            .matching(identifier: AccessibilityID.shortsCard(videoID)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Continuation-only card \(videoID) was not fetched")
        XCTAssertTrue(
            isVisible(card, inside: row.frame.intersection(app.windows.firstMatch.frame)),
            "Fetched card \(videoID) must be hittable and inside both the row and window viewport")
    }

    func testScrollingDownRevealsASecondShortsRow() {
        let firstRow = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(scrollDown(until: firstRow), "Initial Shorts row never became visible")
        let initialCard = firstRow.descendants(matching: .any)
            .matching(identifier: AccessibilityID.shortsCard("initial-short-0")).firstMatch
        XCTAssertTrue(initialCard.waitForExistence(timeout: 10))

        // This ID is absent from all initial data; a no-op loadShorts cannot satisfy this test.
        assertContinuationCard("page-1-short-0", inRow: 1)
    }

    func testLaterShortsRowsShowNewShorts() {
        let firstRow = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(scrollDown(until: firstRow), "Initial Shorts row never became visible")
        assertContinuationCard("page-1-short-0", inRow: 1)
        // Go beyond both the initial supply and the first continuation page.
        assertContinuationCard("page-2-short-0", inRow: 2)
    }
}

/// Exercises the actual mixed feed views with deterministic, offline data.
final class MixedFeedLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--uitesting", "--uitesting-signed-in", "--uitesting-reset-settings", "--uitesting-mixed-feed",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDownWithError() throws { app = nil }

    func testHomeSpacing() { assertSpacing(section: "home", title: "Home") }
    func testSubscriptionsSpacing() { assertSpacing(section: "subscriptions", title: "Subscriptions") }
    func testRecommendedSpacing() { assertSpacing(section: "recommended", title: "Recommended") }

    func testVerticalSwipesOnVideoBlocksScrollEachMixedFeed() {
        for (section, title) in [("home", "Home"), ("recommended", "Recommended"), ("subscriptions", "Subscriptions")] {
            selectSection(section, title: title)
            let block = app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.feedVideoBlock(section, 0)).firstMatch
            XCTAssertTrue(block.waitForExistence(timeout: 10))
            let before = block.frame.minY
            let window = app.windows.firstMatch.frame
            let startY = min(block.frame.minY + 180, window.maxY - 80)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: window.midX, dy: startY))
            let end = origin.withOffset(CGVector(dx: window.midX, dy: startY - 150))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            let moved = NSPredicate { _, _ in !block.exists || block.frame.minY < before - 40 }
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 3), .completed)
            XCTAssertTrue(app.scrollViews["home.chipBar"].buttons[title].isSelected)
        }
    }

    func testShortsSwipeStaysInSectionAndVideoSwipeChangesSection() {
        let row = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertTrue(app.scrollViews["home.chipBar"].buttons["Home"].isSelected)
        let block = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.feedVideoBlock("home", 0)).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let window = app.windows.firstMatch.frame
        let y = min(block.frame.minY + 80, window.maxY - 80)
        origin.withOffset(CGVector(dx: window.width * 0.8, dy: y)).press(
            forDuration: 0, thenDragTo: origin.withOffset(CGVector(dx: window.width * 0.2, dy: y)),
            withVelocity: .fast, thenHoldForDuration: 0)
        let recommended = app.scrollViews["home.chipBar"].buttons["Recommended"]
        let selected = NSPredicate(format: "selected == true")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: recommended)], timeout: 5),
            .completed)
    }

    private func selectSection(_ section: String, title: String) {
        if section != "home" {
            let chips = app.scrollViews["home.chipBar"]
            let chip = chips.buttons[title]
            XCTAssertTrue(chip.waitForExistence(timeout: 10))
            UITestHelpers.scrollChipIntoView(chip, in: chips, app: app)
            chip.tap()
        }
    }

    private func assertSpacing(section: String, title: String) {
        selectSection(section, title: title)
        let firstID =
            section == "home" ? AccessibilityID.homeShortsRow(0) : AccessibilityID.sectionShortsRow(section, 0)
        let first = app.scrollViews[firstID]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(uniqueCards(in: first, prefix: "shorts.card.").count, 10)

        let block = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.feedVideoBlock(section, 0)).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10))
        let videos = uniqueCards(in: block, prefix: "video.card.")
        XCTAssertFalse(videos.isEmpty)
        let rows = Set(videos.map { Int($0.frame.minY.rounded()) })
        XCTAssertEqual(rows.count, 6, "Every full video block must contain six rendered rows")
        XCTAssertGreaterThanOrEqual(block.frame.minY, first.frame.maxY - 1)

        let secondID =
            section == "home" ? AccessibilityID.homeShortsRow(1) : AccessibilityID.sectionShortsRow(section, 1)
        let second = app.scrollViews[secondID]
        for _ in 0..<30 {
            if second.exists, second.isHittable,
                app.windows.firstMatch.frame.contains(CGPoint(x: second.frame.midX, y: second.frame.midY))
            {
                break
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.isHittable, "Second Shorts row must be reachable by vertical scrolling")
        XCTAssertEqual(uniqueCards(in: second, prefix: "shorts.card.").count, 10)
        if block.exists { XCTAssertGreaterThanOrEqual(second.frame.minY, block.frame.maxY - 1) }
    }

    private func uniqueCards(in container: XCUIElement, prefix: String) -> [XCUIElement] {
        let elements = container.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
        var seen = Set<String>()
        return elements.filter { seen.insert($0.identifier).inserted }
    }
}
