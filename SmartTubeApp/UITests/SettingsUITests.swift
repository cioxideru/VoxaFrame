import XCTest

#if os(iOS)
import UIKit
#endif

// MARK: - SettingsUITests
//
// Relaunch and reset-sensitive settings tests live here; shared-launch checks
// remain in HomeFeedAndSettingsUITests.swift.

final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--uitesting-reset-settings"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSignInButtonVisibleWhenSignedOut() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-reset-settings", "--uitesting-sign-out"]
        app.launch()
        UITestHelpers.tapTab(named: "Settings", in: app)
        let signInPredicate = NSPredicate(
            format: "identifier == 'settings.signInButton' OR label == 'Sign in with Google'")
        let signInEl = app.descendants(matching: .any).matching(signInPredicate).firstMatch
        XCTAssertTrue(
            signInEl.waitForExistence(timeout: 5),
            "'Sign in with Google' button must be visible when the session is cleared via --uitesting-sign-out")
    }

    func testShortsTranslationDefaultsAreIndependentAndPersist() {
        UITestHelpers.tapTab(named: "Settings", in: app)
        let shortsToggle = app.switches[AccessibilityID.settingsShortsYandexVOTToggle]
        let regularToggle = app.switches[AccessibilityID.settingsYandexVOTToggle]
        let form = app.collectionViews.firstMatch
        UITestHelpers.scrollUntilVisible(shortsToggle, in: form, maxSwipes: 14)
        XCTAssertTrue(shortsToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(shortsToggle.value as? String, "0")
        shortsToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(shortsToggle.value as? String, "1")
        let original = app.switches[AccessibilityID.settingsShortsKeepOriginalAudioToggle]
        UITestHelpers.scrollUntilVisible(original, in: form)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(original.value as? String, "0")
        XCTAssertEqual(regularToggle.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Separate Shorts translation settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        UITestHelpers.tapTab(named: "Settings", in: app)
        UITestHelpers.scrollUntilVisible(shortsToggle, in: form, maxSwipes: 14)
        XCTAssertEqual(shortsToggle.value as? String, "1")
        UITestHelpers.scrollUntilVisible(original, in: form)
        XCTAssertEqual(original.value as? String, "0")
        XCTAssertEqual(regularToggle.value as? String, "0")
    }
}

#if os(iOS)
/// PLAN-0016: Home sections must avoid native tabs and iPad window controls after restoration.
final class IPadMenuLayoutUITests: XCTestCase {
    private let app = XCUIApplication()
    private let systemSettings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let springBoard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var multitaskingModeToRestore: String?

    private var windowControls: XCUIElement {
        springBoard.buttons[AccessibilityID.systemSmartTubeWindowControls]
    }

    private var channels: XCUIElement {
        app.scrollViews[AccessibilityID.homeChipBar].buttons["Channels"].firstMatch
    }

    private var searchTab: XCUIElement {
        let tab = app.tabBars.buttons["Search"].firstMatch
        return tab.exists ? tab : app.buttons["Search"].firstMatch
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the iPad top tab bar")
        if #unavailable(iOS 18.0) { throw XCTSkip("Requires the iPadOS 18 top tab bar") }
        app.launchArguments = [
            "--uitesting", "--uitesting-subscriptions", "--uitesting-mixed-feed",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        #if targetEnvironment(simulator)
        app.launchArguments.append("--uitesting-reset-settings")
        #endif
        app.launch()
    }

    override func tearDown() {
        if let multitaskingModeToRestore {
            systemSettings.activate()
            let originalMode = systemSettings.buttons[multitaskingModeToRestore]
            XCTAssertTrue(originalMode.waitForExistence(timeout: 5))
            if !originalMode.isSelected { originalMode.tap() }
            XCTAssertTrue(originalMode.isSelected, "Restore the user's multitasking mode")
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testMenusAcrossSplitViewAndWindowResizing() throws {
        if #unavailable(iOS 26.0) { throw XCTSkip("Requires iPad Windowed Apps") }
        XCUIDevice.shared.orientation = .landscapeLeft
        selectChannels()
        enableWindowedApps()
        makeFullScreen()

        let window = app.windows.firstMatch
        let screen = springBoard.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.72)))
        waitForLayout("The system must create a smaller floating window") {
            window.frame.width < screen.frame.width * 0.9 && window.frame.height < screen.frame.height * 0.9
        }
        exerciseNavigationRoundTrips(named: "Floating window")

        let previousFrame = window.frame
        let target = screen.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(
                dx: previousFrame.minX + screen.frame.width * 0.5, dy: previousFrame.minY + screen.frame.height * 0.66))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
            .press(forDuration: 0.2, thenDragTo: target)
        waitForLayout("Dragging the corner must change both width and height") {
            abs(window.frame.width - previousFrame.width) > 40 && abs(window.frame.height - previousFrame.height) > 20
        }
        exerciseNavigationRoundTrips(named: "Resized floating window")

        windowControls.press(forDuration: 1)
        let split = springBoard.buttons["Left and Right"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()
        assertSplitView(fraction: 0.5)
        exerciseNavigationRoundTrips(named: "Split View half", tabsAtBottom: true)
        for fraction in [0.33, 0.67] {
            let dividerX = (window.frame.maxX + systemSettings.windows.firstMatch.frame.minX) / 2
            screen.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: dividerX, dy: screen.frame.midY))
                .press(
                    forDuration: 0.2,
                    thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)))
            assertSplitView(fraction: fraction)
            exerciseNavigationRoundTrips(named: "Split View \(fraction)", tabsAtBottom: fraction < 0.5)
        }
        makeFullScreen()
        exerciseNavigationRoundTrips(named: "Full screen restored", tabsAtBottom: false)
    }

    func testMenusRemainSeparateAfterNavigationRoundTrips() {
        selectChannels()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            exerciseNavigationRoundTrips(named: "Orientation \(orientation.rawValue)")
        }
    }

    private func enableWindowedApps() {
        systemSettings.activate()
        let windowedApps = systemSettings.buttons[AccessibilityID.systemWindowedApps]
        if !windowedApps.exists {
            let multitasking = systemSettings.buttons[AccessibilityID.systemMultitasking]
            UITestHelpers.scrollUntilVisible(
                multitasking, in: systemSettings.collectionViews[AccessibilityID.systemSettingsSidebar])
            XCTAssertTrue(multitasking.waitForExistence(timeout: 5))
            multitasking.tap()
        }
        XCTAssertTrue(windowedApps.waitForExistence(timeout: 5))
        multitaskingModeToRestore = [
            AccessibilityID.systemFullScreenApps, AccessibilityID.systemWindowedApps,
            AccessibilityID.systemStageManager,
        ].first { systemSettings.buttons[$0].isSelected }
        XCTAssertNotNil(multitaskingModeToRestore)
        if !windowedApps.isSelected { windowedApps.tap() }
        app.activate()
    }

    private func makeFullScreen() {
        if windowControls.exists {
            windowControls.tap()
            let zoom = springBoard.buttons[AccessibilityID.systemWindowZoom].firstMatch
            XCTAssertTrue(zoom.waitForExistence(timeout: 5))
            zoom.tap()
        }
        waitForLayout("SmartTube must fill the screen") {
            abs(self.app.windows.firstMatch.frame.width - self.springBoard.windows.firstMatch.frame.width) < 1
        }
    }

    private func assertSplitView(fraction: CGFloat) {
        waitForLayout("Both apps must occupy separate sides of Split View at \(fraction)") {
            let left = self.app.windows.firstMatch.frame
            let right = self.systemSettings.windows.firstMatch.frame
            let screen = self.springBoard.windows.firstMatch.frame
            return abs(left.minX - screen.minX) < 1 && left.maxX <= right.minX
                && abs(right.maxX - screen.maxX) < 1 && right.width > 300
                && abs(left.width - screen.width * fraction) < 40
        }
    }

    private func waitForLayout(_ message: String, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, message)
    }

    private func selectChannels() {
        UITestHelpers.tapTab(named: "Home", in: app)
        let chipBar = app.scrollViews[AccessibilityID.homeChipBar].firstMatch
        XCTAssertTrue(chipBar.waitForExistence(timeout: 5))
        UITestHelpers.scrollChipIntoView(channels, in: chipBar, app: app)
        channels.tap()
    }

    private func exerciseNavigationRoundTrips(named name: String, tabsAtBottom: Bool? = nil) {
        let chipBar = app.scrollViews[AccessibilityID.homeChipBar].firstMatch
        XCTAssertTrue(chipBar.waitForExistence(timeout: 5))
        UITestHelpers.scrollChipIntoView(channels, in: chipBar, app: app)
        XCTAssertTrue(channels.isSelected, "Changing the window must preserve the selected section")
        if let tabsAtBottom {
            XCTAssertEqual(searchTab.frame.midY > app.windows.firstMatch.frame.midY, tabsAtBottom)
        }
        for _ in 0..<2 {
            XCTAssertTrue(app.buttons[AccessibilityID.subscriptionRow("UCfixtureAlpha")].waitForExistence(timeout: 5))
            assertMenusDoNotOverlap(channels)
            app.buttons[AccessibilityID.subscriptionRow("UCfixtureAlpha")].tap()
            let channelNavigation = app.navigationBars["Alpha Channel"].firstMatch
            XCTAssertTrue(channelNavigation.waitForExistence(timeout: 5))
            channelNavigation.buttons.firstMatch.tap()
            XCTAssertTrue(channels.waitForExistence(timeout: 5))
            assertMenusDoNotOverlap(channels)

            for destination in ["Settings", "Search", "Library"] {
                UITestHelpers.tapTab(named: destination, in: app)
                if destination == "Settings" { openAndCloseVisibleSections() }
                UITestHelpers.tapTab(named: "Home", in: app)
                XCTAssertTrue(chipBar.waitForExistence(timeout: 5))
                assertMenusDoNotOverlap(channels)
                XCTAssertTrue(channels.isSelected, "Returning to Home must retain the selected Channels section")
            }
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let geometry = XCTAttachment(
            string: "\(name): window \(app.windows.firstMatch.frame), section \(channels.frame), tab \(searchTab.frame)"
        )
        geometry.name = name + " geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func openAndCloseVisibleSections() {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let visibleSections = form.cells.containing(.staticText, identifier: "Visible Sections").firstMatch
        UITestHelpers.scrollUntilVisible(visibleSections, in: form)
        XCTAssertTrue(visibleSections.waitForExistence(timeout: 5))
        visibleSections.tap()
        let navigationBar = app.navigationBars["Visible Sections"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        navigationBar.buttons.firstMatch.tap()
        XCTAssertTrue(form.waitForExistence(timeout: 5))
    }

    private func assertMenusDoNotOverlap(
        _ sectionChip: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let tab = searchTab
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        let separated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !sectionChip.frame.isEmpty && !tab.frame.isEmpty
                    && (sectionChip.frame.minY >= tab.frame.maxY || sectionChip.frame.maxY <= tab.frame.minY)
                    && (!self.windowControls.exists || sectionChip.frame.minY >= self.windowControls.frame.maxY)
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [separated], timeout: 5), .completed,
            "Home controls \(sectionChip.frame) must avoid native tabs \(tab.frame) and window controls", file: file,
            line: line)
        XCTAssertTrue(tab.isHittable, file: file, line: line)
        XCTAssertTrue(sectionChip.isHittable, file: file, line: line)
    }
}
#endif

final class HideWatchedSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-signed-in", "--uitesting-reset-settings",
            "--uitesting-enable-shorts", "--uitesting-watched-feed",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    func testLowThresholdPersistsAndGitHubPointsToFork() {
        setHideWatched(true)
        let stepper = app.steppers[AccessibilityID.settingsHideWatchedThresholdStepper]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        XCTAssertTrue(stepper.label.contains("90%"))
        for _ in 0..<17 { stepper.buttons[AccessibilityID.settingsHideWatchedThresholdStepper + "-Decrement"].tap() }
        XCTAssertTrue(stepper.label.contains("5%"))
        stepper.buttons[AccessibilityID.settingsHideWatchedThresholdStepper + "-Decrement"].tap()
        XCTAssertTrue(stepper.label.contains("5%"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Watched threshold minimum 5 percent"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launch()
        setHideWatched(true)
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        XCTAssertTrue(stepper.label.contains("5%"))
        for _ in 0..<19 { stepper.buttons[AccessibilityID.settingsHideWatchedThresholdStepper + "-Increment"].tap() }
        XCTAssertTrue(stepper.label.contains("100%"))
        stepper.buttons[AccessibilityID.settingsHideWatchedThresholdStepper + "-Increment"].tap()
        XCTAssertTrue(stepper.label.contains("100%"))

        let link = app.descendants(matching: .any).matching(identifier: AccessibilityID.settingsGitHubLink).firstMatch
        UITestHelpers.scrollUntilVisible(link, in: app.collectionViews.firstMatch, maxSwipes: 16)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertEqual(link.value as? String, "https://github.com/cioxideru/VoxaFrame")
    }

    func testFilteringHomeSectionsShortsAndHistory() {
        setHideWatched(true)
        let stepper = app.steppers[AccessibilityID.settingsHideWatchedThresholdStepper]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        for _ in 0..<13 { stepper.buttons[AccessibilityID.settingsHideWatchedThresholdStepper + "-Decrement"].tap() }
        XCTAssertTrue(stepper.label.contains("25%"))
        UITestHelpers.tapTab(named: "Home", in: app)

        for (title, prefix) in [
            ("Home", "recommended"), ("Recommended", "recommended"), ("Subscriptions", "subscription"),
        ] {
            selectSection(title)
            assertFilteredCards(prefix: prefix, shorts: false)
            assertFilteredCards(prefix: "\(prefix)-short", shorts: true)
        }
        selectSection("Shorts")
        assertFilteredCards(prefix: "initial-short", shorts: true)
        selectSection("History")
        XCTAssertTrue(card("history-fixture", shorts: false).waitForExistence(timeout: 10))

        setHideWatched(false)
        XCTAssertFalse(app.steppers[AccessibilityID.settingsHideWatchedThresholdStepper].exists)
        UITestHelpers.tapTab(named: "Home", in: app)
        selectSection("Home")
        XCTAssertTrue(card("recommended-0", shorts: false).waitForExistence(timeout: 10))
        XCTAssertTrue(card("recommended-short-0", shorts: true).waitForExistence(timeout: 10))
    }

    func testMoreWorksWhenTheEntirePageIsWatched() {
        setHideWatched(true)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--uitesting-reset-settings" }
        app.launchArguments.append("--uitesting-watched-page")
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
        for title in ["Home", "Recommended", "Subscriptions"] {
            selectSection(title)
            let more = app.buttons[AccessibilityID.homeFilteredLoadMoreButton]
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.tap()
            let prefix = title == "Subscriptions" ? "subscription" : "recommended"
            XCTAssertTrue(card("\(prefix)-next", shorts: false).waitForExistence(timeout: 10))
            XCTAssertFalse(card("\(prefix)-0", shorts: false).exists)
        }
        setHideWatched(false)
        UITestHelpers.tapTab(named: "Home", in: app)
        selectSection("Home")
        XCTAssertTrue(card("recommended-short-0", shorts: true).waitForExistence(timeout: 10))
    }

    private func setHideWatched(_ enabled: Bool) {
        UITestHelpers.tapTab(named: "Settings", in: app)
        let toggle = app.switches[AccessibilityID.settingsHideWatchedVideosToggle]
        UITestHelpers.scrollUntilVisible(toggle, in: app.collectionViews.firstMatch, maxSwipes: 16)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != enabled {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
    }

    private func selectSection(_ title: String) {
        let chips = app.scrollViews[AccessibilityID.homeChipBar]
        let chip = chips.buttons[title]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        UITestHelpers.scrollChipIntoView(chip, in: chips, app: app)
        chip.tap()
    }

    private func card(_ id: String, shorts: Bool) -> XCUIElement {
        app.descendants(matching: .any).matching(
            identifier: shorts ? AccessibilityID.shortsCard(id) : AccessibilityID.videoCard(id)
        ).firstMatch
    }

    private func assertFilteredCards(prefix: String, shorts: Bool) {
        XCTAssertTrue(card("\(prefix)-2", shorts: shorts).waitForExistence(timeout: 10))
        XCTAssertTrue(card("\(prefix)-3", shorts: shorts).exists, "Unknown progress remains visible")
        XCTAssertFalse(card("\(prefix)-0", shorts: shorts).exists, "90% is above the 25% threshold")
        XCTAssertFalse(card("\(prefix)-1", shorts: shorts).exists, "Exact threshold must be hidden")
    }
}
