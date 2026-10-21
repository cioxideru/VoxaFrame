import XCTest

#if os(iOS)
/// PLAN-0010: repeatable device measurements without changing the user's settings.
final class IPadPerformanceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testLaunchToResponsive() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.terminate()
            app.launch()
        }
    }

    func testHomeScrolling() {
        app.launch()
        XCTAssertNotNil(UITestHelpers.waitForVideoCards(in: app, timeout: 45))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app),
            ], options: options
        ) {
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
    }

    func testTabNavigationRetainsHomeFeed() {
        app.launch()
        XCTAssertNotNil(UITestHelpers.waitForVideoCards(in: app, timeout: 45))
        for _ in 0..<3 {
            UITestHelpers.tapTab(named: "Settings", in: app)
            XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5))
            UITestHelpers.tapTab(named: "Search", in: app)
            XCTAssertTrue(UITestHelpers.searchField(in: app).waitForExistence(timeout: 5))
            UITestHelpers.tapTab(named: "Library", in: app)
            XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
            UITestHelpers.tapTab(named: "Home", in: app)
            XCTAssertNotNil(UITestHelpers.waitForVideoCards(in: app, timeout: 5))
        }
    }
}
#endif

// MARK: - HomeInteractionsUITests
//
// Combined from SearchUITests (13 tests) + WatchLaterContextMenuUITests (3 tests).
// All tests share a single app launch with --uitesting.
//
// SearchUITests: search bar, suggestions, filters, results, player open, history.
// WatchLaterContextMenuUITests: context-menu regression for browse/edit_playlist (#fix).

final class HomeInteractionsUITests: XCTestCase {

    // MARK: - Shared app lifecycle

    private static var sharedApp: XCUIApplication!
    private var app: XCUIApplication { HomeInteractionsUITests.sharedApp }

    override class func setUp() {
        super.setUp()
        sharedApp = XCUIApplication()
        sharedApp.launchArguments += ["--uitesting"]
        sharedApp.launch()
    }

    override class func tearDown() {
        sharedApp.terminate()
        sharedApp = nil
        super.tearDown()
    }

    // MARK: - Per-test reset

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Dismiss any alert left by a previous test (e.g. Watch Later success/error).
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let okButton = alert.buttons["OK"].firstMatch
            if okButton.exists { okButton.tap() } else { alert.buttons.firstMatch.tap() }
        }
        // Dismiss player if open.
        let backButton = app.buttons[AccessibilityID.playerBackButton].firstMatch
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
            _ = app.buttons["Home"].waitForExistence(timeout: 3)
        }
        // Dismiss mini-player if present.
        let closeButton = app.buttons[AccessibilityID.miniPlayerClose].firstMatch
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        }
        // Navigate to Home tab to dismiss any active keyboard (left by search tests)
        // and ensure the home feed is visible before WatchLater tests need it.
        UITestHelpers.tapTab(named: "Home", in: app)
    }

    // MARK: - Search helpers

    private func openSearch() {
        UITestHelpers.openSearch(in: app)
    }

    private var searchBar: XCUIElement {
        UITestHelpers.searchField(in: app)
    }

    /// Navigates to Search, clears any previous query, types `query`, and submits.
    private func search(for query: String) {
        openSearch()
        let bar = searchBar
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "search.bar must exist")
        bar.tap()
        // Clear any text left from a prior test in the shared-launch session.
        UITestHelpers.clearSearchField(in: app)
        bar.tap()
        // A typed Return submits with any keyboard language (the key's identifier is localized).
        bar.typeText(query + "\n")
    }

    // MARK: - WatchLater helpers

    /// Navigates to the Home tab and waits for at least one video card.
    private func firstHomeCard() throws -> XCUIElement {
        UITestHelpers.tapTab(named: "Home", in: app)
        guard let card = UITestHelpers.waitForVideoCards(in: app, timeout: 60) else {
            try captureAndSkip("No video cards on Home — network unavailable or home feed still loading", in: app)
        }
        return card
    }

    /// Long-presses `element` and returns the "Watch Later" menu button, or nil.
    private func openContextMenuWatchLaterButton(on element: XCUIElement) -> XCUIElement? {
        element.press(forDuration: 1.0)
        let button = app.buttons["Watch Later"].firstMatch
        guard button.waitForExistence(timeout: 5) else { return nil }
        return button
    }

    // MARK: - Tests (from SearchUITests)

    func testSearchBarAppearsOnSearchTab() {
        openSearch()
        XCTAssertTrue(
            searchBar.waitForExistence(timeout: 5),
            "search.bar must appear after tapping the Search tab")
        XCTAssertTrue(searchBar.isHittable, "search.bar must be hittable")
    }

    func testSearchTabOpensWithoutCrash() {
        openSearch()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App should still be running after opening the Search tab")
    }

    func testTypingQueryShowsSuggestions() throws {
        openSearch()
        let bar = searchBar
        guard bar.waitForExistence(timeout: 5) else {
            XCTFail("search.bar not found")
            return
        }
        bar.tap()
        UITestHelpers.clearSearchField(in: app)
        bar.tap()
        bar.typeText("swift")

        // Suggestions sit in the system list under the search field; each row carries its own identifier.
        let suggestionsPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@", AccessibilityID.searchSuggestion(""))
        let suggestion = app.descendants(matching: .any).matching(suggestionsPredicate).firstMatch
        guard suggestion.waitForExistence(timeout: 20) else {
            try captureAndSkip("No search suggestion appeared within 20 s — network may be unavailable", in: app)
        }
    }

    func testClearButtonEmptiesQuery() throws {
        openSearch()
        let bar = searchBar
        guard bar.waitForExistence(timeout: 5) else {
            XCTFail("search.bar not found")
            return
        }
        bar.tap()
        UITestHelpers.clearSearchField(in: app)
        bar.tap()
        bar.typeText("swift")
        XCTAssertEqual(
            bar.value as? String, "swift",
            "Search bar should contain the typed query before clearing")

        let clearButton = UITestHelpers.searchClearButton(in: app)
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 3),
            "The search field's clear button should appear when query is non-empty")
        clearButton.tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertNotEqual(
            bar.value as? String, "swift",
            "Search bar value should change after tapping clear")
    }

    func testSearchReturnsVideoCards() throws {
        search(for: "swift programming")
        let results = app.scrollViews[AccessibilityID.searchResults]
        guard results.waitForExistence(timeout: 5) else {
            XCTFail("search.results container did not appear — network may be unavailable")
            return
        }
        guard let _ = UITestHelpers.waitForVideoCards(in: app, timeout: 20) else {
            XCTFail("No video cards appeared in search results within 20 s")
            return
        }
    }

    func testNoErrorAlertOnSearch() throws {
        search(for: "swift")
        Thread.sleep(forTimeInterval: 10)
        UITestHelpers.assertNoErrorAlert(in: app)
    }

    func testFilterSheetOpensAndCloses() throws {
        search(for: "swift")
        _ = UITestHelpers.waitForVideoCards(in: app, timeout: 20)

        let filterButton = app.buttons[AccessibilityID.searchFilterButton]
        guard filterButton.waitForExistence(timeout: 5) else {
            XCTFail("search.filterButton not found")
            return
        }
        filterButton.tap()

        let sheet = app.otherElements[AccessibilityID.searchFilterSheet]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "search.filterSheet should appear after tapping the filter button")

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "Cancel button must exist in filter sheet")
        cancelButton.tap()

        XCTAssertFalse(
            sheet.waitForExistence(timeout: 3),
            "search.filterSheet should be dismissed after tapping Cancel")
    }

    func testFilterSheetApplyCreatesActiveChip() throws {
        search(for: "swift")
        _ = UITestHelpers.waitForVideoCards(in: app, timeout: 20)

        let filterButton = app.buttons[AccessibilityID.searchFilterButton]
        guard filterButton.waitForExistence(timeout: 5) else {
            XCTFail("search.filterButton not found")
            return
        }
        filterButton.tap()

        let sheet = app.otherElements[AccessibilityID.searchFilterSheet]
        guard sheet.waitForExistence(timeout: 5) else {
            XCTFail("search.filterSheet did not appear")
            return
        }

        let thisWeekPredicate = NSPredicate(format: "label == 'This week' OR identifier == 'This week'")
        let thisWeekOption = app.descendants(matching: .any).matching(thisWeekPredicate).firstMatch
        let sheetForm = app.collectionViews.firstMatch
        UITestHelpers.scrollUntilVisible(thisWeekOption, in: sheetForm)
        XCTAssertTrue(
            thisWeekOption.waitForExistence(timeout: 5),
            "'This week' option must be visible in the Upload date picker")
        thisWeekOption.tap()

        let applyButton = app.buttons["Apply"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 3), "Apply button must exist in filter sheet")
        applyButton.tap()

        let chipPredicate = NSPredicate(format: "label == 'This week'")
        let chip = app.staticTexts.matching(chipPredicate).firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 5),
            "An active filter chip labelled 'This week' should appear after applying the filter")
    }

    func testTappingResultOpensPlayer() throws {
        search(for: "swift programming")
        guard let firstCard = UITestHelpers.waitForVideoCards(in: app, timeout: 20) else {
            XCTFail("No video cards in search results — network may be unavailable")
            return
        }
        XCTAssertTrue(
            UITestHelpers.openPlayer(from: firstCard, in: app),
            "player.titleLabel should appear after tapping a search result")
    }

    func testSubmittedQueryAppearsInHistory() throws {
        search(for: "history test query")

        let bar = searchBar
        guard bar.waitForExistence(timeout: 5) else {
            XCTFail("search.bar not found")
            return
        }
        bar.tap()
        UITestHelpers.clearSearchField(in: app)

        let historyRow = app.buttons[AccessibilityID.searchHistory("history test query")]
        XCTAssertTrue(
            historyRow.waitForExistence(timeout: 5),
            "Submitted query should appear as a history row")
    }

    func testTappingHistoryRowTriggersSearch() throws {
        search(for: "history tap test")

        let bar = searchBar
        guard bar.waitForExistence(timeout: 5) else {
            XCTFail("search.bar not found")
            return
        }
        bar.tap()
        UITestHelpers.clearSearchField(in: app)

        let historyRow = app.buttons[AccessibilityID.searchHistory("history tap test")]
        guard historyRow.waitForExistence(timeout: 5) else {
            XCTFail("History row not found — previous search may not have persisted")
            return
        }
        historyRow.tap()

        let results = app.scrollViews[AccessibilityID.searchResults]
        XCTAssertTrue(
            results.waitForExistence(timeout: 10),
            "Tapping a history row should trigger the search and show results")
    }

    func testDeleteHistoryEntryRemovesRow() throws {
        search(for: "entry to delete")

        let bar = searchBar
        guard bar.waitForExistence(timeout: 5) else {
            XCTFail("search.bar not found")
            return
        }
        bar.tap()
        UITestHelpers.clearSearchField(in: app)

        let deleteButton = app.buttons["Remove entry to delete from history"]
        guard deleteButton.waitForExistence(timeout: 5) else {
            XCTFail("Delete button for history entry not found")
            return
        }
        deleteButton.tap()

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(
            app.buttons[AccessibilityID.searchHistory("entry to delete")].exists,
            "History entry should be removed after tapping its delete button")
    }

    func testClearAllHistoryRemovesAllEntries() throws {
        search(for: "clear all test a")
        search(for: "clear all test b")
        openClearHistoryConfirmation()

        let confirm = app.buttons[AccessibilityID.searchHistoryClearConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Clear History must ask for confirmation")
        confirm.tap()

        XCTAssertTrue(
            app.buttons[AccessibilityID.searchHistory("clear all test a")].waitForNonExistence(timeout: 5),
            "All history entries should be removed after Clear History")
        XCTAssertFalse(
            app.buttons[AccessibilityID.searchHistory("clear all test b")].exists,
            "All history entries should be removed after Clear History")
    }

    func testCancelClearHistoryKeepsEntries() throws {
        search(for: "keep history test")
        openClearHistoryConfirmation()

        let confirm = app.buttons[AccessibilityID.searchHistoryClearConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Clear History must ask for confirmation")
        let cancel = app.buttons[AccessibilityID.searchHistoryClearCancel].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // iPad confirmation popovers cancel through the outside dismiss region.
            let dismiss = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
        }

        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "Cancel must close the confirmation")
        XCTAssertTrue(
            app.buttons[AccessibilityID.searchHistory("keep history test")].waitForExistence(timeout: 5),
            "Cancel must keep the search history")
    }

    /// Shows the idle history list and taps Clear History.
    private func openClearHistoryConfirmation() {
        let bar = searchBar
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "search.bar not found")
        bar.tap()
        UITestHelpers.clearSearchField(in: app)

        let clearAll = app.buttons[AccessibilityID.searchHistoryClearAll]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5), "Clear History button not found")
        clearAll.tap()
    }

    // MARK: - Tests (from WatchLaterContextMenuUITests)

    func testA_ContextMenuAppearsOnLongPress() throws {
        let card = try firstHomeCard()
        card.press(forDuration: 1.0)
        let shareItem = app.buttons["Share"].firstMatch
        XCTAssertTrue(
            shareItem.waitForExistence(timeout: 5),
            "Context menu 'Share' item should appear after long-pressing a video card")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    func testA_WatchLaterMenuItemVisibleWhenSignedIn() throws {
        let card = try firstHomeCard()
        guard let button = openContextMenuWatchLaterButton(on: card) else {
            try captureAndSkip("'Watch Later' not shown — account may not be signed in", in: app)
        }
        XCTAssertTrue(
            button.exists,
            "'Watch Later' context menu item must be visible for signed-in users")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    func testA_SaveToWatchLaterShowsSuccessAlertNotError() throws {
        let card = try firstHomeCard()
        guard let button = openContextMenuWatchLaterButton(on: card) else {
            try captureAndSkip("'Watch Later' not shown — account may not be signed in", in: app)
        }
        button.tap()

        let anyAlert = app.alerts.firstMatch
        XCTAssertTrue(
            anyAlert.waitForExistence(timeout: 10),
            "An alert should appear after tapping 'Watch Later'")

        let successAlert = app.alerts["Saved to Watch Later"].firstMatch
        let errorAlert = app.alerts["Could Not Save"].firstMatch

        XCTAssertFalse(
            errorAlert.exists,
            "Got 'Could Not Save' alert — endpoint returned an error. "
                + "Check that InnerTubeAPI+Social uses 'browse/edit_playlist' (slash), not 'browse_edit_playlist' (underscore)."
        )
        XCTAssertTrue(
            successAlert.exists,
            "'Saved to Watch Later' success alert must appear after a successful API call")

        successAlert.buttons["OK"].tap()
    }
}
