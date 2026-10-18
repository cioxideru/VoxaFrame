import XCTest

// MARK: - ShortsNavigationUITests
// Tests merged into HomeShortsUITests — see HomeShortsUITests.swift.
// This file retains ShortsSwipeUITests (different launch args: --uitesting-shorts).

// MARK: - ShortsSwipeUITests
//
// Full-app UI tests that exercise swipe-up / swipe-down gesture navigation
// inside ShortsPlayerView.
//
// Setup: the app is launched with `--uitesting-shorts` which bypasses the full
// navigation stack and presents ShortsPlayerView directly with three stub shorts
// (Short One, Short Two, Short Three). No network calls or sign-in required.
//
// The index label `shorts.indexLabel` shows "N / 3" and is the primary assertion
// target: if the swipe registered, the label changes.

final class ShortsSwipeUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--uitesting-shorts", "--uitesting-show-controls"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Performs initial setup: waits for the shorts player to be on screen.
    /// Returns the window element used for swipe gestures.
    private func openControls() -> XCUIElement {
        // This suite pins the controls; auto-hide has its own local playback tests.
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5), "Index label should appear on launch")
        return app.windows.firstMatch
    }

    private var indexLabel: XCUIElement {
        app.staticTexts[AccessibilityID.shortsIndexLabel].firstMatch
    }

    private enum SwipeDirection { case up, down }

    private func swipe(_ direction: SwipeDirection, on element: XCUIElement) {
        switch direction {
        case .up: element.swipeUp(velocity: .fast)
        case .down: element.swipeDown(velocity: .fast)
        }
    }

    // MARK: - Tests

    /// Shorts player appears on launch and shows "1 / 3".
    func testShortsPlayerAppears() {
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5), "Index label should be visible on launch")
        XCTAssertEqual(indexLabel.label, "1 / 3", "Should start at the first short")
    }

    /// Swipe up advances from short 1 → 2.
    func testSwipeUpAdvancesToNextShort() {
        let player = openControls()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(indexLabel.label, "1 / 3")

        swipe(.up, on: player)

        XCTAssertTrue(indexLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(indexLabel.label, "2 / 3", "Swipe up should advance to the next short")
    }

    /// A short swipe must still advance after a tap has hidden the controls.
    func testShortSwipeAdvancesAfterHidingControls() {
        let player = openControls()
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].exists)
        player.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].waitForNonExistence(timeout: 2))
        let start = player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(
            forDuration: 0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)),
            withVelocity: .fast, thenHoldForDuration: 0)
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "2 / 3"), object: indexLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 3), .completed)
    }

    /// Swipe up twice reaches the last short (3 / 3).
    func testSwipeUpTwiceReachesLastShort() {
        let player = openControls()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 3))

        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)

        XCTAssertEqual(indexLabel.label, "3 / 3", "After two swipes up should be on last short")
    }

    /// Swipe down from short 2 goes back to short 1.
    func testSwipeDownGoesToPreviousShort() {
        let player = openControls()

        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "2 / 3")

        swipe(.down, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "1 / 3", "Swipe down should go back to the previous short")
    }

    /// Swipe up at the last short does not overflow past "3 / 3".
    func testSwipeUpAtLastShortDoesNotOverflow() {
        let player = openControls()

        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "3 / 3")

        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 2)

        XCTAssertEqual(indexLabel.label, "3 / 3", "Swipe up at the last short should stay on '3 / 3'")
    }

    /// Swipe down at the first short does not underflow below "1 / 3".
    func testSwipeDownAtFirstShortDoesNotUnderflow() {
        let player = openControls()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(indexLabel.label, "1 / 3")

        swipe(.down, on: player)
        _ = indexLabel.waitForExistence(timeout: 2)

        XCTAssertEqual(indexLabel.label, "1 / 3", "Swipe down at the first short should stay on '1 / 3'")
    }

    /// Full round-trip: advance to last short then swipe back to first.
    func testSwipeUpThenDownRoundTrip() {
        let player = openControls()

        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "3 / 3", "Should reach the last short")

        swipe(.down, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        swipe(.down, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "1 / 3", "Should return to the first short")
    }

    // MARK: - Controls-visible swipe tests
    //
    // These tests verify that swipe navigation still works when the controls
    // overlay is displayed on screen. The launch hook keeps it visible.

    /// Swipe up advances to the next short even when the controls overlay is shown.
    func testSwipeUpWorksWhenControlsAreVisible() {
        let player = openControls()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(indexLabel.label, "1 / 3")

        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].waitForExistence(timeout: 3))

        // Swipe up immediately while the controls overlay is still on screen.
        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)

        XCTAssertEqual(
            indexLabel.label, "2 / 3",
            "Swipe up should advance to the next short even when controls are visible")
    }

    func testControlsRemainAvailableAndMuteSurvivesNextShort() {
        let player = openControls()
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].isHittable)
        XCTAssertTrue(app.buttons[AccessibilityID.shortsPlayPauseButton].exists)
        XCTAssertTrue(app.sliders[AccessibilityID.shortsSeekBar].exists)
        let mute = app.buttons[AccessibilityID.shortsMuteButton]
        XCTAssertTrue(mute.isHittable)
        mute.tap()
        XCTAssertEqual(mute.value as? String, "Muted")
        swipe(.up, on: player)
        let next = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "2 / 3"), object: indexLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
        XCTAssertEqual(mute.value as? String, "Muted")
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].isHittable)
        mute.tap()
        XCTAssertEqual(mute.value as? String, "Sound on")
    }

    /// Swipe down returns to the previous short even when the controls overlay is shown.
    func testSwipeDownWorksWhenControlsAreVisible() {
        let player = openControls()

        // Advance to short 2 first.
        swipe(.up, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)
        XCTAssertEqual(indexLabel.label, "2 / 3")

        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].waitForExistence(timeout: 3))

        // Swipe down while controls are visible.
        swipe(.down, on: player)
        _ = indexLabel.waitForExistence(timeout: 3)

        XCTAssertEqual(
            indexLabel.label, "1 / 3",
            "Swipe down should return to the previous short even when controls are visible")
    }
}

// Controls visibility uses the same local media fixture and setup as the preloading suite.
extension ShortsPreloadingUITests {
    private func waitForControls(_ visible: Bool, in app: XCUIApplication, timeout: TimeInterval = 8) {
        let back = app.buttons[AccessibilityID.shortsBackButton]
        XCTAssertTrue(visible ? back.waitForExistence(timeout: timeout) : back.waitForNonExistence(timeout: timeout))
    }

    private func tapVideo(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
    }

    func testControlsAutoHideAndSingleTapTogglesWithoutPausing() {
        let app = launch(preload: true, count: 3, autoHideControls: true)
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].waitForExistence(timeout: 10))
        _ = wait(app, id: 0, buffered: false)
        waitForControls(false, in: app)
        XCTAssertFalse(app.buttons[AccessibilityID.shortsMuteButton].exists)
        XCTAssertFalse(app.sliders[AccessibilityID.shortsSeekBar].exists)
        XCTAssertFalse(app.staticTexts[AccessibilityID.shortsTimeLabel].exists)

        tapVideo(in: app)
        waitForControls(true, in: app, timeout: 1)
        XCTAssertEqual(app.buttons[AccessibilityID.shortsPlayPauseButton].label, "Pause")
        tapVideo(in: app)
        // Shorter than the hide setting: this must be the tap, not a later timer firing.
        waitForControls(false, in: app, timeout: 1)

        tapVideo(in: app)
        let title = app.staticTexts[AccessibilityID.shortsTitleLabel]
        XCTAssertTrue(title.waitForExistence(timeout: 1))
        title.tap()
        waitForControls(false, in: app, timeout: 1)
        _ = wait(app, id: 0, buffered: false)
    }

    func testHiddenControlsDoNotCatchTapsAndSwipesStillChangeShorts() {
        let app = launch(preload: true, count: 3, autoHideControls: true)
        _ = wait(app, id: 0, buffered: true)
        waitForControls(false, in: app)
        tapVideo(in: app)
        waitForControls(true, in: app, timeout: 1)
        let mute = app.buttons[AccessibilityID.shortsMuteButton]
        let muteFrame = mute.frame
        let mutePoint = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: muteFrame.midX - app.frame.minX, dy: muteFrame.midY - app.frame.minY))
        tapVideo(in: app)
        waitForControls(false, in: app, timeout: 1)
        mutePoint.tap()
        waitForControls(true, in: app, timeout: 1)
        XCTAssertEqual(mute.value as? String, "Sound on", "The hidden mute button must not receive the tap")

        tapVideo(in: app)
        waitForControls(false, in: app, timeout: 1)
        next(app)
        let index = app.staticTexts[AccessibilityID.shortsIndexLabel]
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '2 / 3'"), object: index)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].isHittable)
        _ = wait(app, id: 1, buffered: false)
        waitForControls(false, in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(
            forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1 / 3'"), object: index)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertTrue(app.buttons[AccessibilityID.shortsBackButton].isHittable)
    }

    func testOptionPanelsStayOpenAndClosingRestartsControlsTimeout() {
        let app = launch(preload: false, count: 3, autoHideControls: true)
        _ = wait(app, id: 0, buffered: false)
        for (trigger, choice) in [
            (AccessibilityID.shortsSpeedButton, AccessibilityID.playerSpeed(1)),
            (AccessibilityID.shortsAudioTrackButton, AccessibilityID.playerAudioTrackPickerAuto),
        ] {
            waitForControls(false, in: app)
            tapVideo(in: app)
            waitForControls(true, in: app, timeout: 1)
            app.buttons[trigger].tap()
            let option = app.buttons[choice]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            XCTAssertFalse(option.waitForNonExistence(timeout: Double(controlsHideTimeout) + 1))
            option.tap()
            waitForControls(true, in: app, timeout: 1)
        }
        waitForControls(false, in: app)
        tapVideo(in: app)
        waitForControls(true, in: app, timeout: 1)
        app.buttons[AccessibilityID.shortsPlayPauseButton].tap()
        XCTAssertEqual(app.buttons[AccessibilityID.shortsPlayPauseButton].label, "Play")
        waitForControls(false, in: app)
        tapVideo(in: app)
        waitForControls(true, in: app, timeout: 1)
        XCTAssertEqual(app.buttons[AccessibilityID.shortsPlayPauseButton].label, "Play")
    }
}

final class ShortsPlaybackControlsUITests: XCTestCase {
    func testPauseMuteSeekAndAdvanceKeepWorking() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-shorts",
            "--uitesting-show-controls",
            "--uitesting-disable-sponsorblock", "--uitesting-shorts-ids=fKopy74weus,9bZkp7q19f0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        defer { app.terminate() }
        let play = app.buttons[AccessibilityID.shortsPlayPauseButton]
        let time = app.staticTexts[AccessibilityID.shortsTimeLabel]
        func seconds() -> Int {
            guard time.exists, let elapsed = time.label.components(separatedBy: " / ").first else { return -1 }
            return elapsed.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        }
        func wait(
            _ predicate: NSPredicate, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
        ) {
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout),
                .completed, file: file, line: line)
        }
        wait(NSPredicate { _, _ in play.exists && play.isEnabled && seconds() > 1 }, timeout: 45)
        play.tap()
        XCTAssertEqual(play.label, "Play")
        let paused = seconds()
        let advancedWhilePaused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in seconds() > paused + 1 }, object: nil)
        advancedWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [advancedWhilePaused], timeout: 2), .completed)
        app.buttons[AccessibilityID.shortsMuteButton].tap()
        XCTAssertEqual(play.label, "Play", "Muting must not resume a paused Short")
        app.sliders[AccessibilityID.shortsSeekBar].adjust(toNormalizedSliderPosition: 0.25)
        wait(NSPredicate { _, _ in seconds() > paused + 5 })
        XCTAssertEqual(
            app.staticTexts[AccessibilityID.shortsIndexLabel].label, "1 / 2",
            "Horizontal scrubbing must not change the Short")
        play.tap()
        let resumed = seconds()
        wait(NSPredicate { _, _ in seconds() > resumed + 1 })
        app.windows.firstMatch.swipeUp(velocity: .fast)
        wait(NSPredicate { _, _ in app.staticTexts[AccessibilityID.shortsIndexLabel].label == "2 / 2" })
        wait(NSPredicate { _, _ in play.isEnabled && seconds() > 1 }, timeout: 45)
        XCTAssertEqual(app.buttons[AccessibilityID.shortsMuteButton].value as? String, "Muted")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Playing second Short with persistent controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

// MARK: - ShortsLiveSwipeUITests
//
// End-to-end UI tests that use NO mocks and NO launch argument bypass.
// The app launches normally, navigates to Home → Shorts chip, waits for real
// content to load over the network, taps the first Short card to open
// ShortsPlayerView, then exercises swipe-up and swipe-down navigation.
//
// Requirements:
//   • The simulator must have network access so InnerTube can return Shorts.
//   • The test allows up to 20 s for the feed to populate.
//   • Swiping is performed via coordinate-based drag on the window so the
//     UIKit-level UIPanGestureRecognizer in SwipeGestureOverlay fires correctly.

final class ShortsLiveSwipeUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitesting-enable-shorts ensures the Shorts chip is visible.
        app.launchArguments += ["--uitesting-enable-shorts"]
        app.launch()  // No --uitesting-shorts; full real navigation
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Taps the named tab, supporting both the bottom tab bar (iPhone) and the
    /// iPadOS 18 sidebar where tab items appear as standalone buttons.
    private func tapTab(named label: String, timeout: TimeInterval = 5) {
        let tabBarButton = app.tabBars.buttons[label]
        if tabBarButton.waitForExistence(timeout: min(timeout, 3)) {
            tabBarButton.tap()
            return
        }
        let sidebarButton = app.buttons[label].firstMatch
        XCTAssertTrue(
            sidebarButton.waitForExistence(timeout: timeout),
            "'\(label)' navigation item not found in tab bar or sidebar")
        sidebarButton.tap()
    }

    /// Scrolls the chip bar left until the Shorts chip is in view then taps it.
    /// Fails the test (XCTFail) if the Shorts chip is not present.
    private func navigateToShortsChip() throws {
        tapTab(named: "Home")

        let shortsChip = app.buttons["Shorts"]
        guard shortsChip.waitForExistence(timeout: 5) else {
            XCTFail("Shorts chip not visible — --uitesting-enable-shorts may not have applied in time")
            return
        }

        // Scroll chip bar until Shorts is fully on-screen, then tap.
        let rightEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.09))
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.09))
        let screenWidth = app.windows.firstMatch.frame.width
        for _ in 0..<6 {
            let frame = shortsChip.frame
            guard frame.origin.x < 4 || frame.maxX > screenWidth - 4 else { break }
            if frame.origin.x < 4 {
                leftEdge.press(forDuration: 0.05, thenDragTo: rightEdge)
            } else {
                rightEdge.press(forDuration: 0.05, thenDragTo: leftEdge)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }

        shortsChip.tap()

        // Wait for the Shorts section feed before querying cards — prevents
        // the predicate matching stale Home-feed cards still in the tree.
        let sectionFeed = app.descendants(matching: .any)["home.sectionContainer"]
        guard sectionFeed.waitForExistence(timeout: 20) else { return }
    }

    /// Waits up to `timeout` seconds for any `shorts.card.*` element to appear
    /// inside the Shorts section feed and returns the first one.
    private func waitForFirstShortsCard(timeout: TimeInterval = 10) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.shortsCard(""))
        let cards = app.descendants(matching: .any).matching(predicate)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        guard result == .completed else { return nil }
        return cards.firstMatch
    }

    /// Performs a swipe by dragging from bottom-centre to top-centre of the screen.
    private func swipeUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Performs a swipe by dragging from top-centre to bottom-centre of the screen.
    private func swipeDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private var indexLabel: XCUIElement {
        app.staticTexts[AccessibilityID.shortsIndexLabel].firstMatch
    }

    // MARK: - Tests

    /// Full end-to-end: navigate to Shorts with real network, open a video,
    /// swipe up to next, swipe down back to previous.
    func testLiveShortSwipeUpThenDown() throws {
        try navigateToShortsChip()

        // Wait for real Shorts to load from the network.
        guard let firstCard = waitForFirstShortsCard(timeout: 20) else {
            try captureAndSkip("No Shorts loaded within 20 s — network unavailable or feed empty", in: app)
        }

        // Tap the first Short to open ShortsPlayerView.
        // A portrait card can be taller than an iPad's landscape viewport.
        let visibleCard = firstCard.frame.intersection(app.frame)
        XCTAssertFalse(visibleCard.isEmpty)
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: visibleCard.midX - app.frame.minX, dy: visibleCard.midY - app.frame.minY)
        ).tap()

        // Index label must appear (always-visible badge added for testability).
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 10), "Shorts player index label should appear")
        let initialLabel = indexLabel.label
        func waitForPlayback() {
            let playable = NSPredicate { [self] _, _ in
                let button = app.buttons[AccessibilityID.shortsPlayPauseButton]
                let time = app.staticTexts[AccessibilityID.shortsTimeLabel]
                guard button.exists, button.isEnabled, time.exists else { return false }
                let elapsed = time.label.components(separatedBy: " / ")[0]
                    .split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
                return elapsed > 1
            }
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playable, object: nil)], timeout: 40),
                .completed, "A real feed Short must start playing")
            XCTAssertTrue(app.buttons[AccessibilityID.shortsPlayPauseButton].isHittable)
            XCTAssertTrue(app.buttons[AccessibilityID.shortsMuteButton].isHittable)
            XCTAssertTrue(app.sliders[AccessibilityID.shortsSeekBar].isHittable)
            let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            frame.name = "Playing real Short \(indexLabel.label)"
            frame.lifetime = .keepAlways
            add(frame)
        }
        waitForPlayback()

        // Swipe up → should advance to the next short.
        swipeUp()
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialLabel), object: indexLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        waitForPlayback()
        let afterSwipeUp = indexLabel.label
        XCTAssertNotEqual(afterSwipeUp, initialLabel, "Swipe up should advance to the next short")

        // Swipe down → should go back to the previous short.
        swipeDown()
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", initialLabel), object: indexLabel)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        waitForPlayback()
        let afterSwipeDown = indexLabel.label
        XCTAssertEqual(afterSwipeDown, initialLabel, "Swipe down should return to the original short")
    }

    /// Confirms swipe-up on the last short in the list does not crash or wrap.
    func testLiveShortsSwipeUpBoundary() throws {
        try navigateToShortsChip()

        guard let firstCard = waitForFirstShortsCard(timeout: 20) else {
            try captureAndSkip("No Shorts loaded within 20 s — network unavailable or feed empty", in: app)
        }
        firstCard.tap()

        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5))

        // Swipe up repeatedly until the label stops changing (we're at the end).
        // Use 200 as the upper bound so large lists (e.g. 57 items) can be fully
        // traversed — 50 was too low and caused the loop to exit prematurely.
        var previous = ""
        var current = indexLabel.label
        var attempts = 0
        while current != previous && attempts < 200 {
            previous = current
            swipeUp()
            sleep(1)
            current = indexLabel.label
            attempts += 1
        }

        // One extra swipe — label must not change (boundary clamped).
        swipeUp()
        sleep(1)
        XCTAssertEqual(indexLabel.label, current, "Swipe up past the last short should stay on the last item")
    }
}
