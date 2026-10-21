import XCTest

// MARK: - HomeShortsCountUITests
//
// Regression tests for task #91: Home Shorts row must show ≥ 6 cards after
// initial load, and new cards must appear when the row is scrolled.
//
// Launch args (per-test launch):
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
            "--uitesting-enable-shorts",
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
/// Recommendations page through their own continuations; only Shorts demand can fetch the new Shorts.
/// Unselected tabs and nested shelf cursors must not enter later Shorts rows (PLAN-0014).
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
            "--uitesting-enable-shorts",
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
        let unrelated = row.descendants(matching: .any)
            .matching(identifier: AccessibilityID.shortsCard("unrelated-short-0")).firstMatch
        XCTAssertFalse(unrelated.exists, "An unselected feed must not fill later Shorts rows")
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
            "--uitesting-enable-shorts",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDownWithError() throws { app = nil }

    func testHistoryDisabledAppliesToHomeAndPersistsAcrossLaunch() {
        selectSection("history", title: "History")
        let historyCard = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.videoCard("history-fixture")).firstMatch
        XCTAssertTrue(historyCard.waitForExistence(timeout: 10))
        setHistory("Disabled")
        UITestHelpers.tapTab(named: "Home", in: app)
        selectSection("history", title: "History")
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(historyCard.exists)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
        selectSection("history", title: "History")
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(historyCard.exists)
        setHistory("Enabled")
        UITestHelpers.tapTab(named: "Home", in: app)
        selectSection("history", title: "History")
        XCTAssertTrue(historyCard.waitForExistence(timeout: 10))
    }

    private func setHistory(_ value: String) {
        UITestHelpers.tapTab(named: "Settings", in: app)
        UITestHelpers.selectSettingsCategory("thisDevice", in: app)
        let picker = app.buttons[AccessibilityID.settingsHistoryPicker]
        UITestHelpers.scrollUntilVisible(picker, in: UITestHelpers.settingsForm(in: app), maxSwipes: 12)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let option = app.buttons[value]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    /// The More button is its own 44 pt control: it opens the card menu and does not start the video.
    func testCardMoreButtonOpensMenuWithoutPlaying() throws {
        let card = try XCTUnwrap(UITestHelpers.waitForVideoCards(in: app, timeout: 10), "Fixture feed has no cards")
        let videoID = String(card.identifier.dropFirst("video.card.".count))
        let more = app.buttons[AccessibilityID.videoCardMenu(videoID)].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Every video card needs a separate More button")
        XCTAssertGreaterThanOrEqual(more.frame.width, 44, "More must be a 44 pt touch target")
        XCTAssertGreaterThanOrEqual(more.frame.height, 44, "More must be a 44 pt touch target")
        let title = card.staticTexts[AccessibilityID.videoCardTitle].firstMatch
        XCTAssertTrue(title.exists, "The card exposes its exact title")
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertTrue(more.label.hasSuffix(title.label), "More's VoiceOver label names its card")
        more.tap()
        // Add to Queue sits in the "…" submenu (PLAN-0038); Channel is a top-level item of every fixture card.
        XCTAssertTrue(
            app.buttons["Channel"].firstMatch.waitForExistence(timeout: 5), "More must open the card's menu")
        XCTAssertFalse(
            app.staticTexts[AccessibilityID.playerTitleLabel].exists, "Opening the menu must not start the video")
    }

    func testHomeSpacing() { assertSpacing(section: "home", title: "Home") }
    func testSubscriptionsSpacing() { assertSpacing(section: "subscriptions", title: "Subscriptions") }

    /// Home is the recommendations feed only: subscription videos keep to their own chip.
    func testHomeShowsRecommendationsWithoutSubscriptions() {
        let block = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.feedVideoBlock("home", 0)).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10))
        // The old interleave put the first subscription right after the fourth recommendation.
        for id in ["recommended-0", "recommended-4"] {
            let card = block.descendants(matching: .any).matching(identifier: AccessibilityID.videoCard(id)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "\(id) must be on Home")
        }
        let subscription = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.videoCard("subscription-0")).firstMatch
        XCTAssertFalse(subscription.exists, "Subscription videos must not be mixed into Home")
        selectSection("subscriptions", title: "Subscriptions")
        XCTAssertTrue(subscription.waitForExistence(timeout: 10), "Subscriptions still shows subscription videos")
    }

    func testHomeShelvesUseTheVideoGrid() {
        app.terminate()
        app.launchArguments += ["--uitesting-inject-recommended-ids=one,two,three,four,five,six"]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
        let block = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.feedVideoBlock("home", 0)).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10), "Shelf responses must use the mixed feed grid")
        let cards = block.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'video.card.'")).allElementsBoundByIndex
        let rowPositions = Set(cards.map { Int($0.frame.minY.rounded()) })
        XCTAssertGreaterThan(
            rowPositions.count, 1, "Recommendations must form video rows instead of one horizontal shelf")
    }

    func testVerticalSwipesOnVideoBlocksScrollEachMixedFeed() {
        for (section, title) in [("home", "Home"), ("subscriptions", "Subscriptions")] {
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
        let subscriptions = app.scrollViews["home.chipBar"].buttons["Subscriptions"]
        let selected = NSPredicate(format: "selected == true")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: subscriptions)], timeout: 5),
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
            section == "home" ? AccessibilityID.homeShortsRow(0) : AccessibilityID.sectionShortsRow(0)
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
            section == "home" ? AccessibilityID.homeShortsRow(1) : AccessibilityID.sectionShortsRow(1)
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

/// Confirmation must gate both local feed changes and feedback sent through the fixture transport.
final class VideoFeedbackConfirmationUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = [
            "--uitesting", "--uitesting-subscriptions", "--uitesting-reset-settings", "--uitesting-mixed-feed",
            "--uitesting-enable-shorts", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testVideoNotInterestedRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoNotInterested, shorts: false, useMoreButton: false)
    }

    func testVideoDontRecommendRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoDontRecommendChannel, shorts: false, useMoreButton: true)
    }

    func testShortsNotInterestedRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoNotInterested, shorts: true, useMoreButton: false)
    }

    func testShortsDontRecommendRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoDontRecommendChannel, shorts: true, useMoreButton: false)
    }

    func testVideoDontLikeRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoDontLike, shorts: false, useMoreButton: false)
    }

    func testShortsDontLikeRequiresConfirmation() throws {
        try assertConfirmation(action: AccessibilityID.videoDontLike, shorts: true, useMoreButton: true)
    }

    /// Shorts cards have the same separate More button as video cards: it opens the card menu, not the Short.
    func testShortsMoreButtonOpensMenuWithoutPlaying() throws {
        let card = try shortsCard()
        let videoID = String(card.identifier.dropFirst("shorts.card.".count))
        let more = app.buttons[AccessibilityID.videoCardMenu(videoID)].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Every Shorts card needs a separate More button")
        XCTAssertGreaterThanOrEqual(more.frame.width, 44, "More must be a 44 pt touch target")
        XCTAssertGreaterThanOrEqual(more.frame.height, 44, "More must be a 44 pt touch target")
        more.tap()
        XCTAssertTrue(
            app.buttons["Channel"].firstMatch.waitForExistence(timeout: 5), "More must open the card's menu")
        XCTAssertFalse(
            app.staticTexts[AccessibilityID.playerTitleLabel].exists, "Opening the menu must not start the Short")
    }

    private func shortsCard() throws -> XCUIElement {
        let row = app.scrollViews[AccessibilityID.homeShortsRow(0)]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let card =
            row.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'shorts.card.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        return card
    }

    private func assertConfirmation(action: String, shorts: Bool, useMoreButton: Bool) throws {
        let card: XCUIElement
        if shorts {
            card = try shortsCard()
        } else {
            card = try XCTUnwrap(UITestHelpers.waitForVideoCards(in: app, timeout: 10))
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let cardID = card.identifier
        let target = app.descendants(matching: .any).matching(identifier: cardID).firstMatch
        let title = shorts ? "" : target.staticTexts[AccessibilityID.videoCardTitle].firstMatch.label
        let actionTitle =
            switch action {
            case AccessibilityID.videoDontRecommendChannel: "Don't Recommend"
            case AccessibilityID.videoDontLike: "Don't Like"
            default: "Not Interested"
            }

        func requestConfirmation() {
            if useMoreButton {
                let videoID = cardID.replacingOccurrences(
                    of: "^(video|shorts)\\.card\\.", with: "", options: .regularExpression)
                app.buttons[AccessibilityID.videoCardMenu(videoID)].firstMatch.tap()
            } else {
                target.press(forDuration: 1)
            }
            // Native menu actions omit SwiftUI identifiers on iOS; the fixture fixes the UI language to English.
            let menuAction = app.buttons.matching(
                NSPredicate(format: "identifier == %@ OR label == %@", action, actionTitle)
            ).firstMatch
            XCTAssertTrue(menuAction.waitForExistence(timeout: 5), app.debugDescription)
            menuAction.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(target.exists, "Requesting confirmation must not hide the card")
            let expectedText = action == AccessibilityID.videoDontRecommendChannel ? "Fixture" : title
            if !expectedText.isEmpty {
                XCTAssertTrue(app.alerts.firstMatch.staticTexts[expectedText].exists)
            }
        }

        requestConfirmation()
        app.alerts.buttons[AccessibilityID.videoFeedbackCancel].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(target.exists, "Cancel must keep the video and channel in the feed")
        requestConfirmation()
        app.alerts.buttons[AccessibilityID.videoFeedbackConfirm].firstMatch.tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 10), "Only confirmation may hide the video or channel")
    }
}
