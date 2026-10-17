// LibrarySubscriptionsUITests.swift
// Isolated account-management scenarios; general feed coverage remains in LibraryUITests.

import XCTest

final class SubscriptionManagementUITests: XCTestCase {
    private let app = XCUIApplication()
    private let channelID = "UCfixtureAlpha"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments =
            [
                "--uitesting", "--uitesting-reset-settings", "--uitesting-subscriptions", "--uitesting-mixed-feed",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ] + extra
        app.launch()
        UITestHelpers.tapTab(named: "Home", in: app)
        let chip = app.buttons[AccessibilityID.homeSectionChip("Channels")]
        let bar = app.scrollViews[AccessibilityID.homeChipBar]
        UITestHelpers.scrollChipIntoView(chip, in: bar, app: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
    }

    private var row: XCUIElement { app.buttons[AccessibilityID.subscriptionRow(channelID)] }
    private var remove: XCUIElement { app.buttons[AccessibilityID.subscriptionRemove(channelID)] }
    private var confirm: XCUIElement { app.buttons[AccessibilityID.subscriptionConfirm].firstMatch }

    private func cancelConfirmation() {
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad confirmation popovers dismiss outside; UIKit omits the Cancel button.
            app.otherElements[AccessibilityID.popoverDismissRegion].tap()
        } else {
            app.buttons[AccessibilityID.subscriptionCancel].firstMatch.tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
    }

    func testIconCancellationAndConfirmedRemoval() {
        launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[AccessibilityID.subscriptionRow("UCfixtureGamma")].exists, "Second page must load")
        remove.tap()
        cancelConfirmation()
        XCTAssertTrue(row.exists)
        remove.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.subscriptionRow("UCfixtureBeta")].exists)
        UITestHelpers.tapTab(named: "Search", in: app)
        UITestHelpers.tapTab(named: "Home", in: app)
        XCTAssertTrue(app.buttons[AccessibilityID.subscriptionRow("UCfixtureGamma")].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists, "Removed membership must survive reloading")
    }

    func testSwipeRequestsConfirmationWithoutSwitchingSection() {
        launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        let action = app.buttons["Unsubscribe"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(row.exists)
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.subscriptionList].exists)
    }

    func testChannelUnsubscribeThenSubscribeUpdatesList() {
        launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let subscription = app.buttons[AccessibilityID.channelSubscriptionButton]
        XCTAssertTrue(subscription.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: subscription)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(subscription.label, "Unsubscribe")
        subscription.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        expectation(for: NSPredicate(format: "label == 'Subscribe'"), evaluatedWith: subscription)
        waitForExpectations(timeout: 5)
        subscription.tap()
        expectation(for: NSPredicate(format: "label == 'Unsubscribe'"), evaluatedWith: subscription)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testFailedMutationKeepsChannelAndShowsError() {
        launch(["--uitesting-subscriptions-mutation-error"])
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Subscription change rejected."].waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        XCTAssertTrue(remove.isEnabled)
    }

    func testLoadFailureCanRetryAndEmptyAccountStaysSignedIn() {
        launch(["--uitesting-subscriptions-load-error"])
        let retry = app.buttons[AccessibilityID.subscriptionRetry]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.terminate()
        launch(["--uitesting-subscriptions-empty"])
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign In"].exists)
    }

    func testLiveListAndChannelReturnWithoutChangingSubscriptions() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live account check runs on the connected physical iPad")
        #else
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            UITestHelpers.tapTab(named: "Home", in: app)
            let bar = app.scrollViews[AccessibilityID.homeChipBar].firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let channels = bar.buttons["Channels"]
            UITestHelpers.scrollChipIntoView(channels, in: bar, app: app)
            channels.tap()
            let rows = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.subscriptionRow("")))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "Account must have a loaded subscription list")
            let channel = rows.firstMatch
            channel.tap()
            let subscription = app.buttons[AccessibilityID.channelSubscriptionButton]
            XCTAssertTrue(subscription.waitForExistence(timeout: 30))
            expectation(
                for: NSPredicate(format: "enabled == true AND label == 'Unsubscribe'"), evaluatedWith: subscription)
            waitForExpectations(timeout: 30)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
            for destination in ["Settings", "Search", "Library"] {
                UITestHelpers.tapTab(named: destination, in: app)
                UITestHelpers.tapTab(named: "Home", in: app)
                XCTAssertTrue(channels.waitForExistence(timeout: 5))
                let searchTab = app.tabBars.buttons["Search"].firstMatch
                let topTab = searchTab.exists ? searchTab : app.buttons["Search"].firstMatch
                let separated = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in channels.frame.minY >= topTab.frame.maxY }, object: nil)
                XCTAssertEqual(XCTWaiter().wait(for: [separated], timeout: 5), .completed)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Live subscription list and menus"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func testLiveSubscribeUnsubscribeRestoresOriginalMembership() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live mutations require an explicitly selected physical-device channel")
        #else
        guard let target = ProcessInfo.processInfo.environment["SMARTTUBE_LIVE_SUBSCRIPTION_CHANNEL"], !target.isEmpty
        else {
            throw XCTSkip("Set an approved test channel explicitly; ordinary test runs never change real subscriptions")
        }
        func openChannel() {
            app.terminate()
            app.launchArguments = [
                "--uitesting", "--uitesting-deeplink-channel=\(target)",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ]
            app.launch()
        }
        let subscription = app.buttons[AccessibilityID.channelSubscriptionButton]
        func hasMembership(_ subscribed: Bool) -> Bool {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "exists == true AND enabled == true AND label == %@",
                    subscribed ? "Unsubscribe" : "Subscribe"), object: subscription)
            return XCTWaiter().wait(for: [ready], timeout: 30) == .completed
        }
        func unsubscribe() {
            subscription.tap()
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        }

        openChannel()
        XCTAssertTrue(subscription.waitForExistence(timeout: 30))
        guard hasMembership(false) else {
            throw XCTSkip(
                "The selected channel must start unsubscribed; existing subscription preferences are preserved")
        }
        var needsCleanup = true
        defer {
            if needsCleanup {
                openChannel()
                if hasMembership(true) { unsubscribe() }
                XCTAssertTrue(hasMembership(false), "The temporary subscription must be removed after a failed check")
            }
        }
        subscription.tap()
        XCTAssertTrue(hasMembership(true), "Subscribe must succeed")
        openChannel()
        XCTAssertTrue(hasMembership(true), "Subscription must persist in the account after relaunch")
        unsubscribe()
        XCTAssertTrue(hasMembership(false), "Unsubscribe must succeed")
        openChannel()
        XCTAssertTrue(hasMembership(false), "The original membership must be restored after relaunch")
        needsCleanup = false
        #endif
    }
}
