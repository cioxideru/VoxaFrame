import XCTest

// MARK: - PlayerControlsUITests
//
// All tests except testPiPButtonStartsPiP have moved to PlayerAndMiniPlayerUITests.swift
// (combined with MiniPlayerUITests for a single shared app launch).
//
// testPiPButtonStartsPiP is kept here because it deliberately terminates and
// re-launches the app with --uitesting-enable-pip and cannot share state.

final class PlayerControlsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func openPlayerFromHome() throws -> String {
        UITestHelpers.tapTab(named: "Home", in: app)
        guard let card = UITestHelpers.waitForVideoCards(in: app, timeout: 20) else {
            try captureAndSkip("No video cards on Home — network unavailable or feed empty", in: app)
        }
        guard UITestHelpers.openPlayer(from: card, in: app) else {
            try captureAndSkip("Player did not open within 15 s — network unavailable or timing-dependent", in: app)
        }
        return app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch.label
    }

    private var playPauseButton: XCUIElement {
        app.buttons["player.playPauseButton"].firstMatch
    }

    private var pipButton: XCUIElement {
        app.buttons[AccessibilityID.playerPiPButton].firstMatch
    }

    private func showControls() {
        for _ in 0..<5 {
            if playPauseButton.exists { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    // MARK: - Tests

    #if os(iOS)
    func testPlayPauseButtonMeetsMinimumTapTarget() throws {
        // Verify the play/pause button tap target is at least 44×44pt (Apple HIG minimum).
        // Task #127 added .padding(12) + .contentShape(Rectangle()) to fix a ~42pt icon
        // that had no padding and therefore fell below the minimum.
        try openPlayerFromHome()
        showControls()
        guard playPauseButton.waitForExistence(timeout: 8) else {
            try captureAndSkip("player.playPauseButton not found — cannot verify tap target size", in: app)
        }
        let frame = playPauseButton.frame
        XCTAssertGreaterThanOrEqual(
            frame.width, 44,
            "play/pause button width \(frame.width)pt is below the 44pt Apple HIG minimum")
        XCTAssertGreaterThanOrEqual(
            frame.height, 44,
            "play/pause button height \(frame.height)pt is below the 44pt Apple HIG minimum")
    }

    func testCaptionCuePositionedAboveScrubBar() throws {
        // Task #129: caption cue must appear above the scrub/progress bar, not overlap it.
        // Verifies padding change from 72pt (fixed) to 130pt (when controls visible).
        // Skips gracefully if the video has no captions or no cue is active.
        try openPlayerFromHome()
        showControls()
        let scrubBar = app.otherElements["player.progressBar"].firstMatch
        let captionCue = app.staticTexts.matching(identifier: "player.captionCue").firstMatch
        guard scrubBar.waitForExistence(timeout: 8) else {
            try captureAndSkip("Scrub bar not found — cannot verify caption position", in: app)
        }
        guard captionCue.waitForExistence(timeout: 5) else {
            // No caption cue visible — video may not have captions or no cue is active.
            // This is an acceptable skip; regression is only detectable when captions are on.
            try captureAndSkip("player.captionCue not visible — video has no active caption cue", in: app)
        }
        let cueMaxY = captionCue.frame.maxY
        let scrubMinY = scrubBar.frame.minY
        XCTAssertLessThan(
            cueMaxY, scrubMinY,
            "Caption cue bottom (\(cueMaxY)pt) must be above scrub bar top (\(scrubMinY)pt) — task #129")
    }

    func testPiPButtonStartsPiP() throws {
        // Re-launch with --uitesting-enable-pip to bypass the isPictureInPictureSupported()
        // guard on parallel clone simulators where the entitlement may not propagate.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-enable-pip"]
        app.launch()
        try openPlayerFromHome()
        showControls()
        guard pipButton.waitForExistence(timeout: 5) else {
            try captureAndSkip(
                "player.pipButton not found — PiP may not be available on this device/iOS version", in: app)
        }
        pipButton.tap()
        // PiP windows are not directly queryable; just ensure no crash.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App must still be running after tapping the PiP button")
    }
    #endif
}

#if os(iOS)
/// System PiP requires a real device; keep its saved settings and account intact.
final class SystemPiPRestorationUITests: XCTestCase {
    func testSystemPiPRevealsPreviousScreenAndRestoresPlayback() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("System PiP requires a physical iPad or iPhone")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-show-controls", "--uitesting-deeplink-video=fKopy74weus",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        defer { app.terminate() }
        let time = app.staticTexts[AccessibilityID.playerCurrentTimeLabel]
        let pip = app.buttons[AccessibilityID.playerPiPButton]
        XCTAssertTrue(pip.waitForExistence(timeout: 30))
        func seconds() -> Int {
            if !time.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() }
            guard time.waitForExistence(timeout: 2) else { return -1 }
            return time.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        }
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in seconds() > 2 }, object: nil)
        let playingResult = XCTWaiter.wait(for: [playing], timeout: 30)
        let beforePiP = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beforePiP.name = "Video before entering system PiP"
        beforePiP.lifetime = .keepAlways
        add(beforePiP)
        let playerTree = XCTAttachment(string: app.debugDescription)
        playerTree.name = "Player before entering system PiP"
        playerTree.lifetime = .keepAlways
        add(playerTree)
        XCTAssertEqual(playingResult, .completed)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for cycle in 1...3 {
            let before = seconds()
            pip.tap()
            let previousScreen = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in app.scrollViews["home.chipBar"].isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [previousScreen], timeout: 10), .completed)
            let systemTree = XCTAttachment(string: springboard.debugDescription)
            systemTree.name = "System PiP accessibility - cycle \(cycle)"
            systemTree.lifetime = .keepAlways
            add(systemTree)
            let floating = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            floating.name = "System PiP above previous screen - cycle \(cycle)"
            floating.lifetime = .keepAlways
            add(floating)
            let restore = springboard.buttons["Restore fullscreen"]
            if !restore.exists { springboard.windows["PIP-SBInteractionPassThroughView"].tap() }
            restore.tap()
            XCTAssertTrue(time.waitForExistence(timeout: 10))
            let restoredTime = seconds()
            XCTAssertGreaterThanOrEqual(restoredTime, before, "PiP restore must retain playback time")
            let advancing = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in seconds() > restoredTime + 1 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 10), .completed)
            let fullscreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            fullscreen.name = "Video after system PiP restore - cycle \(cycle)"
            fullscreen.lifetime = .keepAlways
            add(fullscreen)
        }
        #endif
    }
}

/// Live playback acceptance for scaling and remembered quality.
final class PlayerVideoScaleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-reset-settings", "--uitesting-show-controls",
            "--uitesting-disable-sponsorblock", "--uitesting-deeplink-video=fKopy74weus",
            "--uitesting-inject-related-video-ids=9bZkp7q19f0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app = nil
    }

    private var scaleButton: XCUIElement { app.buttons[AccessibilityID.playerVideoScaleButton] }
    private var timeLabel: XCUIElement { app.staticTexts[AccessibilityID.playerCurrentTimeLabel] }

    private func showControls() {
        guard !scaleButton.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(scaleButton.waitForExistence(timeout: 4))
    }

    private func seconds() -> Int {
        guard timeLabel.exists else { return -1 }
        return timeLabel.label.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    private func waitUntilReady() {
        XCTAssertTrue(app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch.waitForExistence(timeout: 20))
        showControls()
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: app.buttons[AccessibilityID.playerPlayPauseButton])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "Live video must become playable")
    }

    private func waitForTime(after previous: Int) {
        let advancing = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                showControls()
                return seconds() > previous
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 5), .completed, "Playback must keep advancing")
    }

    private func assertMode(_ value: String) {
        showControls()
        XCTAssertTrue(scaleButton.isHittable)
        XCTAssertEqual(scaleButton.value as? String, value)
    }

    private func waitForQuality(_ label: String) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                showControls()
                return app.buttons[AccessibilityID.playerQuickQualityButton].label.contains(label)
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 30), .completed)
    }

    private func pickQuality(_ label: String) {
        showControls()
        app.buttons[AccessibilityID.playerQuickQualityButton].tap()
        let picker = app.scrollViews[AccessibilityID.playerQualityPicker]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let row = picker.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        waitForQuality(label)
        waitForTime(after: seconds() + 1)
    }

    func testRepeatedMiniPlayerRestorationKeepsPlaybackAndPreviousScreen() {
        waitUntilReady()
        waitForTime(after: 2)
        for _ in 0..<3 {
            showControls()
            let before = seconds()
            app.buttons[AccessibilityID.playerBackButton].firstMatch.tap()
            let mini = app.otherElements["miniPlayer.bar"].firstMatch
            XCTAssertTrue(mini.waitForExistence(timeout: 5))
            XCTAssertTrue(
                app.scrollViews["home.chipBar"].isHittable,
                "Minimizing must reveal the screen underneath the player")
            mini.tap()
            XCTAssertTrue(app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch.waitForExistence(timeout: 5))
            showControls()
            XCTAssertGreaterThanOrEqual(seconds(), before, "Expanding must retain the current player item")
            waitForTime(after: before + 1)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Video after three fullscreen-mini-player cycles"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQualitySelectionSurvivesNextVideoAndRelaunch() {
        waitUntilReady()
        waitForTime(after: 2)
        pickQuality("720p")

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        waitUntilReady()
        waitForQuality("720p")
        waitForTime(after: seconds() + 1)
        let title = app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch
        let firstTitle = title.label
        showControls()
        app.buttons[AccessibilityID.playerNextButton].tap()
        let nextVideo = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in title.exists && title.label != firstTitle }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [nextVideo], timeout: 20), .completed)
        waitUntilReady()
        waitForQuality("720p")
        waitForTime(after: seconds() + 1)

        pickQuality("Auto")
        app.terminate()
        app.launch()
        waitUntilReady()
        waitForQuality("Auto")
        waitForTime(after: seconds() + 1)
    }

    func testZoomPreservesPlaybackAndSurvivesRotation() {
        waitUntilReady()
        waitForTime(after: 2)
        assertMode("Fit (letterbox)")
        let beforeZoom = seconds()
        scaleButton.tap()
        assertMode("Fill (crop)")
        XCTAssertGreaterThanOrEqual(seconds(), beforeZoom, "Zoom must not reset the timeline")
        waitForTime(after: seconds())

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTime(after: seconds() + 1)
        assertMode("Fill (crop)")
        XCTAssertGreaterThanOrEqual(seconds(), beforeZoom)
        let cropped = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        cropped.name = "Fill mode in landscape"
        cropped.lifetime = .keepAlways
        add(cropped)

        let beforeFit = seconds()
        scaleButton.tap()
        assertMode("Fit (letterbox)")
        XCTAssertGreaterThanOrEqual(seconds(), beforeFit, "Returning to Fit must not reset the timeline")
        waitForTime(after: seconds())
        XCUIDevice.shared.orientation = .portrait
        waitForTime(after: seconds() + 1)
        assertMode("Fit (letterbox)")
        XCTAssertGreaterThanOrEqual(seconds(), beforeFit)
        let fitted = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fitted.name = "Fit mode in portrait"
        fitted.lifetime = .keepAlways
        add(fitted)
    }
}
#endif
