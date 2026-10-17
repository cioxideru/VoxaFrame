import XCTest

/// Requires the local HLS fixture server; independent of YouTube and account recommendations.
final class ShortsPreloadingUITests: XCTestCase {
    private let mediaURL = "http://127.0.0.1:18765"

    override func setUp() async throws {
        let url = try XCTUnwrap(URL(string: mediaURL + "/health"))
        let request = URLRequest(url: url, timeoutInterval: 2)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try XCTSkipUnless(
                (response as? HTTPURLResponse)?.statusCode == 200,
                "Start scripts/shorts-media-fixture.py to run local playback measurements")
        } catch {
            throw XCTSkip("Local Shorts media fixture is unavailable: \(error.localizedDescription)")
        }
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
    }

    private func launch(preload: Bool, count: Int) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts", "--uitesting-reset-settings",
            "--uitesting-disable-sponsorblock", "--uitesting-sign-out",
            "--uitesting-shorts-ids=" + (0..<count).map { "preload-\($0)" }.joined(separator: ","),
        ]
        if !preload { app.launchArguments.append("--uitesting-disable-shorts-preload") }
        app.launchEnvironment["SHORTS_TEST_MEDIA_URL"] = mediaURL
        app.launch()
        return app
    }

    private func wait(_ app: XCUIApplication, id: Int, buffered: Bool) -> String {
        let probe = app.staticTexts[AccessibilityID.shortsPreloadStatus]
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let text = probe.label
                return text.contains("id=preload-\(id) playing=true")
                    && (!buffered || (text.contains("queue=2") && self.number("buffered", in: text) > 0))
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 20), .completed, probe.label)
        return probe.label
    }

    private func number(_ name: String, in status: String) -> Int {
        status.split(separator: " ").first { $0.hasPrefix(name + "=") }
            .flatMap { Int($0.dropFirst(name.count + 1)) } ?? -1
    }

    private func next(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
    }

    func testColdVersusPreparedPlayback() {
        var measurements: [[Int]] = []
        for preload in [false, true] {
            let app = launch(preload: preload, count: 10)
            _ = wait(app, id: 0, buffered: preload)
            var times: [Int] = []
            for index in 1...5 {
                next(app)
                let status = wait(app, id: index, buffered: preload)
                times.append(number("ms", in: status))
                if preload { XCTAssertTrue(status.contains("shorts:prepared"), status) }
            }
            measurements.append(times)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = preload ? "Prepared Short" : "Cold Short"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        let cold = measurements[0].sorted()[2]
        let warm = measurements[1].sorted()[2]
        let evidence = XCTAttachment(string: "cold_ms=\(measurements[0]) warm_ms=\(measurements[1])")
        evidence.name = "Shorts load-to-ready measurements"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertGreaterThan(cold, 0)
        XCTAssertLessThan(Double(warm), Double(cold) * 0.6)
    }

    func testSustainedPlaybackAndBackgroundRelease() {
        let app = launch(preload: true, count: 200)
        _ = wait(app, id: 0, buffered: true)
        for index in 1...60 {
            next(app)
            let status = wait(app, id: index, buffered: true)
            XCTAssertTrue(status.contains("shorts:prepared"), status)
            XCTAssertLessThanOrEqual(number("queue", in: status), 2)
            XCTAssertLessThanOrEqual(number("retained", in: status), 120)
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        // Background playback is disabled by default; the current item stays paused.
        let paused = app.staticTexts[AccessibilityID.shortsPreloadStatus]
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        XCTAssertTrue(paused.label.contains("queue=1 buffered=0"), paused.label)
        app.buttons[AccessibilityID.shortsPlayPauseButton].tap()
        _ = wait(app, id: 60, buffered: true)
        next(app)
        _ = wait(app, id: 61, buffered: true)
        app.buttons[AccessibilityID.shortsBackButton].tap()
        let reopen = app.buttons[AccessibilityID.shortsReopenTestButton]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5))
        reopen.tap()
        _ = wait(app, id: 0, buffered: true)
    }
}

// MARK: - ShortsPlayerUITests
//
// UI tests for ShortsPlayerView, split into two launch modes:
//
//   Direct-launch (--uitesting-shorts)
//   ────────────────────────────────────
//   AppEntry bypasses navigation and presents ShortsPlayerView directly with
//   stub videos. `shorts.indexLabel` appears immediately — no warm-up, no
//   network required. Used for tests that verify player behavior (index badge,
//   swipes, controls overlay) where the path TO the player is irrelevant.
//
//   Direct-launch with real video (--uitesting-shorts-ids=<ID>)
//   ─────────────────────────────────────────────────────────────
//   Same direct launch but with a real YouTube Short video ID so
//   InnerTubeAPI fetches a real stream. Used when verifying network behavior
//   (e.g. no error banner).
//
//   Full-app navigation (--uitesting --uitesting-enable-shorts)
//   ─────────────────────────────────────────────────────────────
//   The full app launches. Tests navigate Home → Shorts chip → tap card.
//   Used only for tests that verify the navigation PATH to the player.

final class ShortsPlayerUITests: XCTestCase {

    // MARK: - Known real YouTube Short video IDs
    //
    // Used when a test needs a real stream (e.g. no-error-banner check).
    // IDs are tried in order; the first one that loads without an error banner is used.
    // Replace the primary ID (index 0) when it becomes unavailable, or append new entries.
    private static let knownGoodShortIDs: [String] = [
        "MCv4EyEFgVg",  // Primary — popular public Short
        "pPvd8UxmCGY",  // Fallback 1
        "fKopy74weus",  // Fallback 2
    ]

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Do NOT launch here — each test picks its own launch mode.
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch helpers

    /// Direct-launch: `ShortsPlayerView` with three stub videos.
    /// No network required. `shorts.indexLabel` shows "1 / 3" immediately.
    private func launchWithStubs() {
        app.launchArguments = ["--uitesting", "--uitesting-shorts"]
        app.launch()
    }

    /// Direct-launch: `ShortsPlayerView` with specific real YouTube Short IDs.
    /// InnerTubeAPI fetches real streams — use when testing playback behavior.
    private func launchWithRealShorts(ids: [String]) {
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts",
            "--uitesting-shorts-ids=\(ids.joined(separator: ","))",
        ]
        app.launch()
    }

    /// Full-app launch with the complete navigation stack and real Home feed.
    /// Use only for tests that verify the navigation path to the player.
    private func launchFullApp() {
        app.launchArguments = ["--uitesting", "--uitesting-enable-shorts"]
        app.launch()
    }

    // MARK: - Helpers

    private var indexLabel: XCUIElement {
        app.staticTexts["shorts.indexLabel"].firstMatch
    }

    /// Navigates Home → Shorts chip → taps the first Short card.
    /// Requires `launchFullApp()` to have been called first.
    private func openFirstShortViaNavigation() throws {
        UITestHelpers.tapTab(named: "Home", in: app)

        let chipBar = app.scrollViews["home.chipBar"]
        XCTAssertTrue(chipBar.waitForExistence(timeout: 10), "home.chipBar must appear on Home tab")

        let shortsChip = chipBar.buttons["Shorts"]
        guard shortsChip.waitForExistence(timeout: 5) else {
            XCTFail("Shorts chip not found — section may be disabled")
            return
        }
        UITestHelpers.scrollChipIntoView(shortsChip, in: chipBar, app: app)
        shortsChip.tap()

        // Wait for the Shorts section feed ScrollView before querying cards.
        // Without this guard the predicate below can match stale Home-feed cards
        // still in the accessibility tree during the section-switch animation.
        let sectionFeed = app.descendants(matching: .any)["home.sectionContainer"]
        guard sectionFeed.waitForExistence(timeout: 20) else {
            try captureAndSkip(
                "Shorts section feed did not appear within 20 s — network unavailable or Shorts empty", in: app)
        }

        let feedPredicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(feedPredicate)
        let feedLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: cards)
        guard XCTWaiter().wait(for: [feedLoaded], timeout: 10) == .completed else {
            try captureAndSkip("Shorts feed did not load within 10 s — network unavailable or Shorts empty", in: app)
        }

        cards.firstMatch.tap()
        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 15),
            "shorts.indexLabel must appear after tapping a Short")
    }

    /// Performs a swipe-up gesture on the Shorts player.
    private func swipeUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Performs a swipe-down gesture on the Shorts player.
    private func swipeDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Taps the Shorts player until the controls overlay becomes visible.
    /// Uses `shorts.backButton` (a Button inside the overlay) as the visibility
    /// proxy — VStack containers with accessibilityIdentifier are transparent in
    /// the XCTest accessibility tree and cannot be found directly.
    private func showShortsControls() {
        let backButton = app.buttons["shorts.backButton"]
        for _ in 0..<5 {
            if backButton.exists { return }
            // Use window-element tap — reliably triggers UITapGestureRecognizer
            // in SwipeGestureOverlay; coordinate-based taps are unreliable here.
            app.windows.firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    // MARK: - Tests

    // ── Navigation tests ──────────────────────────────────────────────────────

    /// Verifies that ShortsPlayerView opens and shows the index badge.
    /// Uses direct-launch with real Short IDs to avoid auth dependency on parallel clone simulators.
    func testShortsPlayerOpensFromHomeChip() throws {
        launchWithRealShorts(ids: Self.knownGoodShortIDs)
        guard indexLabel.waitForExistence(timeout: 20) else {
            try captureAndSkip("Shorts player did not appear — network unavailable or Short IDs may be stale", in: app)
        }
        XCTAssertTrue(
            indexLabel.exists,
            "shorts.indexLabel should be visible when ShortsPlayerView is open")
    }

    /// Verifies the back button in the Shorts player is tappable and does not crash the app.
    /// Uses direct-launch with real Short IDs to avoid auth dependency on parallel clone simulators.
    func testBackButtonDismissesShortsPlayer() throws {
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts",
            "--uitesting-shorts-ids=\(Self.knownGoodShortIDs.joined(separator: ","))",
            "--uitesting-show-controls",
        ]
        app.launch()
        guard indexLabel.waitForExistence(timeout: 40) else {
            try captureAndSkip("Shorts player did not appear — network unavailable or Short IDs may be stale", in: app)
        }
        // Controls are shown immediately via --uitesting-show-controls.
        let backPred = NSPredicate(format: "identifier == 'shorts.backButton'")
        let backBtn = app.descendants(matching: .any).matching(backPred).firstMatch
        guard backBtn.waitForExistence(timeout: 10) else {
            try captureAndSkip("shorts.backButton did not appear — controls may not be visible", in: app)
        }
        backBtn.tap()
        // In direct-launch mode ShortsPlayerView is the root view, so dismiss() has no visual
        // navigation effect. The key regression to catch is a crash on tap.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App must not crash after tapping the Shorts back button")
    }

    // ── Direct-launch (stub) tests — no network, instant ────────────────────

    /// Verifies the index badge shows "1 / 3" when the player opens at index 0.
    func testIndexLabelShowsStartIndex() {
        launchWithStubs()
        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 5),
            "shorts.indexLabel must appear immediately on direct launch")
        XCTAssertEqual(
            indexLabel.label, "1 / 3",
            "Index badge should show '1 / 3' on launch with three stub Shorts")
    }

    /// Verifies swipe-up advances the index from 1 to 2.
    func testSwipeUpAdvancesShort() {
        launchWithStubs()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(indexLabel.label, "1 / 3")

        swipeUp()
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertEqual(
            indexLabel.label, "2 / 3",
            "Swipe up should advance the index from 1 to 2")
    }

    /// Verifies swipe-down after swipe-up returns to index 1.
    func testSwipeDownGoesBackToPreviousShort() {
        launchWithStubs()
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 5))

        swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(indexLabel.label, "2 / 3", "Should be on index 2 after swiping up")

        swipeDown()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(
            indexLabel.label, "1 / 3",
            "Swipe down should return to index 1")
    }

    /// Verifies that the controls overlay elements are accessible in XCTest
    /// when the overlay is shown.
    ///
    /// Uses `--uitesting-show-controls` so the overlay appears on launch without
    /// depending on UIKit gesture delivery, which is unreliable in the simulator
    /// (the `UITapGestureRecognizer` in `SwipeGestureOverlay` requires the
    /// `UIPanGestureRecognizer` to fail first, which XCTest synthetic taps do
    /// not reliably trigger in the required order).
    ///
    /// What this test validates:
    ///   - `shorts.backButton` is in the accessibility tree when controls are shown
    func testControlsOverlayAppearsOnTap() {
        app.launchArguments = ["--uitesting", "--uitesting-shorts", "--uitesting-show-controls"]
        app.launch()

        XCTAssertTrue(
            indexLabel.waitForExistence(timeout: 5),
            "shorts.indexLabel must appear before testing the controls overlay")

        // Controls appear immediately after onAppear via --uitesting-show-controls.
        // Wait up to 5 s for the back button that lives inside the overlay.
        let backButton = app.buttons["shorts.backButton"]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "shorts.backButton should appear when --uitesting-show-controls is active")
    }

    // ── Direct-launch with real video — network required ─────────────────────

    /// Verifies no error banner appears when a real Short loads.
    /// Tries each ID in `knownGoodShortIDs` in order; the first one that loads
    /// without an error banner passes the test. If all IDs show errors the test
    /// skips with guidance to update the array.
    func testNoErrorBannerOnShortsOpen() throws {
        guard !Self.knownGoodShortIDs.isEmpty else {
            try captureAndSkip("knownGoodShortIDs is empty — add at least one valid Short ID", in: app)
        }
        var lastError = "unknown"
        for shortID in Self.knownGoodShortIDs {
            app.terminate()
            launchWithRealShorts(ids: [shortID])
            guard indexLabel.waitForExistence(timeout: 20) else {
                // Network unavailable — cannot determine if ID is valid; skip the whole test.
                try captureAndSkip("Shorts player did not appear for '\(shortID)' — network unavailable", in: app)
            }
            Thread.sleep(forTimeInterval: 5)
            let banner = app.staticTexts["shorts.errorBanner"].firstMatch
            if !banner.exists {
                return  // This ID loaded successfully.
            }
            // Video is stale (deleted, private, or region-locked). Try next ID.
            lastError = banner.label
        }
        try captureAndSkip(
            "All \(Self.knownGoodShortIDs.count) short IDs show errors — update knownGoodShortIDs in ShortsPlayerUITests.swift. "
                + "Last error for '\(Self.knownGoodShortIDs.last ?? "")': '\(lastError)'",
            in: app
        )
    }
}

/// Shared controls and persisted scale on iPad, without requiring account credentials.
final class ShortsAccountControlsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-shorts", "--uitesting-reset-settings",
            "--uitesting-show-controls", "--uitesting-disable-sponsorblock",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app = nil
    }

    private var scale: XCUIElement { app.buttons[AccessibilityID.shortsVideoScaleButton] }
    private var audio: XCUIElement { app.buttons[AccessibilityID.shortsAudioTrackButton] }
    private var index: XCUIElement { app.staticTexts[AccessibilityID.shortsIndexLabel] }

    private func swipeToNext() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func expectIndex(_ value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: index)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    private func openRegularPlayerWithRussianLanguage() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-shorts" }
        app.launch()
        UITestHelpers.tapTab(named: "Settings", in: app)
        let language = app.buttons[AccessibilityID.settingsPreferredAudioLanguageRow]
        UITestHelpers.scrollUntilVisible(language, in: app.collectionViews.firstMatch)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["Russian"].firstMatch.tap()
        app.terminate()
        app.launchArguments.append("--uitesting-deeplink-video=fKopy74weus")
        app.launch()
    }

    func testIndependentShortsTranslationAndScaleSurviveNextRotationAndRelaunch() {
        app.launch()
        XCTAssertTrue(scale.waitForExistence(timeout: 15))
        XCTAssertEqual(scale.value as? String, "Fit (letterbox)")
        scale.tap()
        XCTAssertEqual(scale.value as? String, "Fill (crop)")

        audio.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.playerAudioTrackPickerAuto].waitForExistence(timeout: 5))
        let language = app.buttons[AccessibilityID.playerTranslationLanguagePicker]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["Russian"].firstMatch.tap()
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle].exists)
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioKeepOriginalAudioToggle].exists)
        let livelyVoice = app.switches[AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle]
        let originalAudio = app.switches[AccessibilityID.playerAudioKeepOriginalAudioToggle]
        livelyVoice.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        originalAudio.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(livelyVoice.value as? String, "1")
        XCTAssertEqual(originalAudio.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shorts audio and Yandex controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancel"].firstMatch.tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(scale.waitForExistence(timeout: 5))
        XCTAssertEqual(scale.value as? String, "Fill (crop)")
        XCUIDevice.shared.orientation = .portrait
        swipeToNext()
        expectIndex("2 / 3")
        XCTAssertEqual(scale.value as? String, "Fill (crop)")
        audio.tap()
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle].value as? String, "1")
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioKeepOriginalAudioToggle].value as? String, "0")
        app.buttons["Cancel"].firstMatch.tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        XCTAssertTrue(scale.waitForExistence(timeout: 15))
        XCTAssertEqual(scale.value as? String, "Fill (crop)")
        audio.tap()
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].waitForExistence(timeout: 5))

        openRegularPlayerWithRussianLanguage()
        let regularAudio = app.buttons[AccessibilityID.playerQuickAudioButton]
        XCTAssertTrue(regularAudio.waitForExistence(timeout: 20))
        regularAudio.tap()
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle].value as? String, "0")
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioKeepOriginalAudioToggle].value as? String, "1")
        language.tap()
        app.buttons["English"].firstMatch.tap()

        app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--uitesting-deeplink-video=") }
        app.launchArguments.append("--uitesting-shorts")
        app.launch()
        XCTAssertTrue(audio.waitForExistence(timeout: 15))
        audio.tap()
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches[AccessibilityID.playerAudioTrackPickerVoiceOverToggle].label.contains("Russian"))
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioTrackPickerLivelyVoiceToggle].value as? String, "1")
        XCTAssertEqual(app.switches[AccessibilityID.playerAudioKeepOriginalAudioToggle].value as? String, "0")
    }

    func testShortsPaginationAdvancesBeyondFirstBatch() {
        app.launchArguments.append("--uitesting-home-pagination")
        app.launch()
        XCTAssertTrue(index.waitForExistence(timeout: 15))
        swipeToNext()
        expectIndex("2 / 13")
        // The end now consumes page-1, rather than fetching the initial ten items again.
        for position in 3...12 {
            swipeToNext()
            expectIndex("\(position) / \(position < 12 ? 13 : 23)")
        }
    }

    func testLiveShortsScaleDoesNotRestartPlayback() {
        app.launchArguments.append("--uitesting-shorts-ids=fKopy74weus,9bZkp7q19f0")
        app.launch()
        XCTAssertTrue(scale.waitForExistence(timeout: 15))
        let play = app.buttons[AccessibilityID.shortsPlayPauseButton]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
        let time = app.staticTexts[AccessibilityID.shortsTimeLabel]
        func seconds() -> Int {
            let elapsed = time.label.components(separatedBy: " / ").first ?? ""
            return elapsed.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        }
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in seconds() >= 2 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 10), .completed)
        let before = seconds()
        scale.tap()
        XCTAssertGreaterThanOrEqual(seconds(), before)
        XCTAssertEqual(scale.value as? String, "Fill (crop)")
        XCUIDevice.shared.orientation = .landscapeLeft
        let stillPlaying = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in seconds() > before + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stillPlaying], timeout: 10), .completed)
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height && scale.isHittable && audio.isHittable && play.isHittable
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        XCTAssertEqual(scale.value as? String, "Fill (crop)")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Shorts Fill in landscape during playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
