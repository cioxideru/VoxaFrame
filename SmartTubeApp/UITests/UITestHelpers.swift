import XCTest

// UI-test targets do not link SmartTubeIOSCore. Keep app identifiers in sync with its AccessibilityID.
enum AccessibilityID {
    static var playerStatsOverlay: String { "player.statsOverlay" }
    static var playerHoldSpeedBadge: String { "player.holdSpeedBadge" }
    static var playerMoreMenuCancelButton: String { "player.moreMenu.cancel" }
    static var playerMoreMenuDescriptionRow: String { "player.moreMenu.descriptionRow" }
    static var playerMoreMenu: String { "player.moreMenu" }
    static var playerOptionPanelCancel: String { "player.optionPanel.cancel" }
    static var playerMoreMenuScrollView: String { "player.moreMenu.scrollView" }
    static var playerMoreMenuLikeRow: String { "player.moreMenu.likeRow" }
    static var playerMoreMenuDislikeRow: String { "player.moreMenu.dislikeRow" }
    static var playerMoreMenuShareRow: String { "player.moreMenu.shareRow" }
    static var playerShareSheet: String { "player.shareSheet" }
    static var playerMoreMenuSpeedRow: String { "player.moreMenu.speedRow" }
    static var playerMoreMenuQualityRow: String { "player.moreMenu.qualityRow" }
    static var playerMoreMenuSleepTimerRow: String { "player.moreMenu.sleepTimerRow" }
    static var playerMoreMenuAudioOnlyRow: String { "player.moreMenu.audioOnlyRow" }
    static var playerMoreMenuQueueShuffleRow: String { "player.moreMenu.queueShuffleRow" }
    static var playerMoreMenuDownloadButton: String { "player.moreMenu.downloadButton" }
    static var playerMoreMenuCaptionsRow: String { "player.moreMenu.captionsRow" }
    static var playerMoreMenuAudioTrackRow: String { "player.moreMenu.audioTrackRow" }
    static var playerMoreMenuCommentsRow: String { "player.moreMenu.commentsRow" }
    static var playerMoreMenuStatsForNerds: String { "player.moreMenu.statsForNerds" }
    static var playerMoreButton: String { "player.moreButton" }
    static var miniPlayerBar: String { "miniPlayer.bar" }
    static var miniPlayerTitle: String { "miniPlayer.titleLabel" }
    static var miniPlayerPlayPause: String { "miniPlayer.playPauseButton" }
    static var miniPlayerClose: String { "miniPlayer.closeButton" }
    static func tab(_ name: String) -> String { "tab.\(name.lowercased())" }
    static var uiTestingReopenDeeplinkVideo: String { "uitesting.reopenDeeplinkVideoButton" }
    static var settingsVisibleSectionsLink: String { "settings.visibleSectionsLink" }
    static var settingsVisibleSectionsList: String { "settings.visibleSectionsList" }
    static var playerToast: String { "player.toast" }
    static var playerProgressBar: String { "player.progressBar" }
    static var playerBrightnessGesture: String { "player.brightnessGesture" }
    static var playerVolumeGesture: String { "player.volumeGesture" }
    static var offlineSelectionVideo: String { "offline.selection.video" }
    static var offlineSelectionAudio: String { "offline.selection.audio" }
    static var offlineSelectionTranslate: String { "offline.selection.translate" }
    static var offlineSelectionLanguage: String { "offline.selection.language" }
    static var offlineSelectionDownload: String { "offline.selection.download" }
    static func offlineDeleteEntry(_ id: String) -> String { "offline.deleteEntry.\(id)" }
    static func offlineDeleteJob(_ id: UUID) -> String { "offline.deleteJob.\(id)" }
    static var offlineWatch: String { "offline.watch" }
    static var offlinePage: String { "offline.page" }
    static var offlinePagePicker: String { "offline.pagePicker" }
    static var offlineLibraryList: String { "offline.libraryList" }
    static var offlineJobsList: String { "offline.jobsList" }
    static var offlineDetailList: String { "offline.detailList" }
    static var offlineDeleteAll: String { "offline.deleteAll" }
    static var offlineAudioPicker: String { "offline.audioPicker" }
    static var offlineTranslationPicker: String { "offline.translationPicker" }
    static var offlineVideoPicker: String { "offline.videoPicker" }
    static var offlinePlaySummary: String { "offline.playSummary" }
    static func offlineQualityGroup(_ height: Int) -> String { "offline.quality.\(height)" }
    static var offlinePlaybackStatus: String { "offline.playbackStatus" }
    static var offlineFindVariants: String { "offline.findVariants" }
    static func offlineEntry(_ id: String) -> String { "offline.entry.\(id)" }
    static func offlinePlay(_ id: String) -> String { "offline.play.\(id)" }
    static func offlineDownload(_ id: String) -> String { "offline.download.\(id)" }
    static func offlineSaved(_ id: String) -> String { "offline.saved.\(id)" }
    static func offlineDownloadTranslation(_ language: String) -> String { "offline.translation.\(language)" }

    // System-owned identifiers used only by iPad window-layout UI tests.
    static var systemVolumeSlider: String { "cc-volume-slider" }
    static var systemBrightnessSlider: String { "cc-brightness-slider" }
    static var systemControlCenterPages: String { "Page control" }
    static var systemSettingsSidebar: String { "com.apple.settings.sidebar.collectionView" }
    static var systemMultitasking: String { "com.apple.settings.multitaskingAndGestures" }
    static var systemFullScreenApps: String { "com.apple.settings.multitaskingAndGestures.fullScreenApps" }
    static var systemWindowedApps: String { "com.apple.settings.multitaskingAndGestures.windowedApps" }
    static var systemStageManager: String { "com.apple.settings.multitaskingAndGestures.stageManager" }
    static var systemSmartTubeWindowControls: String { "window-controls:com.ibaranov.smarttube.app" }
    static var systemWindowZoom: String { "Zoom-button" }
    static var popoverDismissRegion: String { "PopoverDismissRegion" }
    static var homeChipBar: String { "home.chipBar" }
    static func homeSectionChip(_ title: String) -> String { "chip.\(title)" }
    static var channelSubscriptionButton: String { "channel.followButton" }
    static var channelHeader: String { "channel.header" }
    static var channelTitle: String { "channel.title" }
    static var subscriptionConfirm: String { "subscription.confirm" }
    static var subscriptionCancel: String { "subscription.cancel" }
    static var subscriptionRetry: String { "subscription.retry" }
    static var subscriptionList: String { "subscription.list" }
    static func subscriptionRow(_ id: String) -> String { "subscription.row.\(id)" }
    static func subscriptionRemove(_ id: String) -> String { "subscription.remove.\(id)" }
    static var homeSubscriptionsChannelFilter: String { "home.subscriptionsChannelFilter" }
    static var searchBar: String { "search.bar" }
    static var searchClearButton: String { "search.clearButton" }
    static var searchFilterButton: String { "search.filterButton" }
    static var searchFilterSheet: String { "search.filterSheet" }
    static var searchResults: String { "search.results" }
    static var searchSuggestionsContainer: String { "search.suggestionsContainer" }
    static var searchHistoryClearAll: String { "search.history.clearAll" }
    static func searchHistory(_ query: String) -> String { "search.history.\(query)" }
    static func searchSuggestion(_ text: String) -> String { "search.suggestion.\(text)" }
    static var searchNoResults: String { "search.noResults" }
    static var searchFailed: String { "search.failed" }
    static var searchRetryButton: String { "search.retryButton" }
    static var parentalControlsConfirmNew: String { "parentalControls.confirmNew" }
    static var parentalControlsEnterNew: String { "parentalControls.enterNew" }
    static var parentalControlsVerifyCurrent: String { "parentalControls.verifyCurrent" }
    static var pinKeypadDelete: String { "pinKeypad.delete" }

    static func pinKeypadDigit(_ digit: Int) -> String {
        "pinKeypad.digit\(digit)"
    }
    static var pinKeypadDots: String { "pinKeypad.dots" }
    static var pinKeypadErrorMessage: String { "pinKeypad.errorMessage" }
    static var playerAudioTrackPicker: String { "player.audioTrackPicker" }
    static var playerTranslationLanguagePicker: String { "player.translationLanguagePicker" }
    static var playerAudioTrackPickerAuto: String { "player.audioTrackPicker.auto" }
    static var playerAudioKeepOriginalAudioToggle: String { "player.audioTrackPicker.keepOriginalAudioToggle" }
    static var playerAudioTrackPickerLivelyVoiceToggle: String { "player.audioTrackPicker.livelyVoiceToggle" }

    static func playerAudioTrack(_ id: String) -> String {
        "player.audioTrackPicker.track.\(id)"
    }
    static var playerAudioTrackPickerVoiceOverToggle: String { "player.audioTrackPicker.voiceOverToggle" }
    static var playerVoiceOverCancelButton: String { "player.voiceOver.cancelButton" }
    static var settingsCategories: String { "settings.categories" }
    static var settingsForm: String { "settings.form" }
    static func settingsCategory(_ group: String) -> String { "settings.category.\(group)" }
    static var settingsSignInButton: String { "settings.signInButton" }
    static var settingsHideShortsToggle: String { "settings.hideShortsToggle" }
    static var settingsPreferredQualityPicker: String { "settings.preferredQualityPicker" }
    static var settingsConcurrentDownloadsPicker: String { "settings.concurrentDownloadsPicker" }
    static var settingsSeekBackRow: String { "settings.seekBackRow" }
    static var settingsAccentColorPicker: String { "settings.accentColorPicker" }
    static var settingsChangePINButton: String { "settings.changePINButton" }
    static var settingsClearLocalHistoryButton: String { "settings.clearLocalHistoryButton" }
    static var settingsClearLocalHistoryConfirm: String { "settings.clearLocalHistory.confirm" }
    static var settingsClearLocalHistoryCancel: String { "settings.clearLocalHistory.cancel" }
    static var settingsDisableLiquidGlassToggle: String { "settings.disableLiquidGlassToggle" }
    static var settingsGridColumnsLandscapePicker: String { "settings.gridColumnsLandscapePicker" }
    static var settingsGridColumnsPortraitPicker: String { "settings.gridColumnsPortraitPicker" }
    static var settingsHistoryPicker: String { "settings.historyPicker" }
    static var settingsH264Toggle: String { "settings.h264Toggle" }
    static var settingsHideWatchedThresholdStepper: String { "settings.hideWatchedThresholdStepper" }
    static var settingsHideWatchedVideosToggle: String { "settings.hideWatchedVideosToggle" }
    static var settingsGitHubLink: String { "settings.githubLink" }
    static var homeFilteredLoadMoreButton: String { "home.filteredLoadMoreButton" }
    static var settingsRemovePINButton: String { "settings.removePINButton" }
    static var settingsResetAllButton: String { "settings.resetAllButton" }
    static var settingsResetAllConfirm: String { "settings.resetAll.confirm" }
    static var settingsResetAllCancel: String { "settings.resetAll.cancel" }
    static var settingsSetPINButton: String { "settings.setPINButton" }
    static var settingsSponsorBlockToggle: String { "settings.sponsorBlockToggle" }
    static var settingsThumbnailStylePicker: String { "settings.thumbnailStylePicker" }
    static var settingsVp9Toggle: String { "settings.vp9Toggle" }
    static var settingsYandexVOTKeepOriginalAudioToggle: String { "settings.yandexVOTKeepOriginalAudioToggle" }
    static var settingsYandexVOTLivelyVoiceToggle: String { "settings.yandexVOTLivelyVoiceToggle" }
    static var settingsYandexVOTToggle: String { "settings.yandexVOTToggle" }
    static var settingsPreferredAudioLanguageRow: String { "settings.preferredAudioLanguageRow" }
    static var settingsShortsAudioLanguageRow: String { "settings.shortsAudioLanguageRow" }
    static var settingsShortsYandexVOTToggle: String { "settings.shortsYandexVOTToggle" }
    static var settingsShortsLivelyVoiceToggle: String { "settings.shortsLivelyVoiceToggle" }
    static var settingsShortsKeepOriginalAudioToggle: String { "settings.shortsKeepOriginalAudioToggle" }
    static var settingsYandexVOTTokenField: String { "settings.yandexVOTTokenField" }
    static var settingsPINLock: String { "settingsPINLock" }

    static var homeCurrentQueueRow: String { "home.currentQueueRow" }
    static var librarySectionPicker: String { "library.sectionPicker" }
    static func libraryPicker(_ section: String) -> String { "library.picker.\(section.lowercased())" }
    static var libraryChipBar: String { "library.chipBar" }
    static func libraryChip(_ section: String) -> String { "library.chip.\(section.lowercased())" }
    static var librarySignInButton: String { "library.signInButton" }
    static var libraryGuestHistoryNote: String { "library.guestHistoryNote" }
    static var queueView: String { "queue.view" }
    static var queueClearButton: String { "queue.clearButton" }
    static var queueClearConfirm: String { "queue.clearConfirm" }

    static func homeShortsRow(_ index: Int) -> String {
        index == 0 ? "home.shortsRow" : "home.shortsRow.\(index)"
    }

    static func sectionShortsRow(_ section: String, _ index: Int) -> String {
        let prefix = section == "recommended" ? "recommended.shortsRow" : "browse.shortsRow"
        return index == 0 ? prefix : "\(prefix).\(index)"
    }

    static func feedVideoBlock(_ section: String, _ index: Int) -> String {
        "feed.\(section).videos.\(index)"
    }

    static func videoCard(_ videoId: String) -> String {
        "video.card.\(videoId)"
    }

    static func videoCardMenu(_ videoId: String) -> String {
        "videoCardMenu.\(videoId)"
    }

    static var videoCardTitle: String { "videoCardTitle" }

    static func shortsCard(_ videoId: String) -> String {
        "shorts.card.\(videoId)"
    }
    static var homeSectionFeed: String { "home.sectionFeed" }
    static var shortsBackButton: String { "shorts.backButton" }
    static var shortsIndexLabel: String { "shorts.indexLabel" }
    static var shortsPlayPauseButton: String { "shorts.playPauseButton" }
    static var shortsPreviousButton: String { "shorts.previousButton" }
    static var shortsNextButton: String { "shorts.nextButton" }
    static var shortsPreloadStatus: String { "shorts.preloadStatus" }
    static var shortsReopenTestButton: String { "shorts.reopenTestButton" }
    static var shortsAudioTrackButton: String { "shorts.audioTrackButton" }
    static var shortsSpeedButton: String { "shorts.speedButton" }
    static var playerSpeedPicker: String { "player.speedPicker" }
    static var playerQuickSpeedButton: String { "player.quickAccess.speed" }
    static func playerSpeed(_ speed: Double) -> String { "player.speed.\(speed)" }
    static var shortsVideoScaleButton: String { "shorts.videoScaleButton" }
    static var shortsLoadMoreButton: String { "shorts.loadMoreButton" }
    static var shortsMuteButton: String { "shorts.muteButton" }
    static var shortsSeekBar: String { "shorts.seekBar" }
    static var shortsTimeLabel: String { "shorts.timeLabel" }
    static var shortsTitleLabel: String { "shorts.titleLabel" }
    static var shortsControlsOverlay: String { "shorts.controlsOverlay" }
    static var shortsRetryButton: String { "shorts.retryButton" }
    static var shortsErrorBanner: String { "shorts.errorBanner" }
    static var playerBackButton: String { "player.backButton" }
    static var playerPiPButton: String { "player.pipButton" }
    static var playerFullScreenButton: String { "player.fullScreenButton" }
    static var playerInspectorToggle: String { "player.inspectorToggle" }
    static var playerAirPlayButton: String { "player.airPlayButton" }
    static var playerChannelName: String { "player.channelName" }
    static var playerDurationLabel: String { "player.durationLabel" }
    static var playerLandscapeLockButton: String { "player.landscapeLockButton" }
    static var playerAudioOnlyButton: String { "player.audioOnlyButton" }
    static var playerVideoScaleButton: String { "player.videoScaleButton" }
    static var playerQuickAudioButton: String { "player.quickAccess.audioTrack" }
    static var playerQuickQualityButton: String { "player.quickAccess.quality" }
    static var playerQualityPicker: String { "player.qualityPicker" }
    static var playerQualityPickerAuto: String { "player.qualityPicker.auto" }
    static var playerSleepTimerPicker: String { "player.sleepTimerPicker" }
    static var playerCaptionPicker: String { "player.captionPicker" }
    static var playerCaptionPickerOff: String { "player.captionPicker.off" }
    static func playerCaptionPickerTrack(_ id: String) -> String { "player.captionPicker.track.\(id)" }
    static var playerNextButton: String { "player.nextBtn" }
    static var playerCurrentTimeLabel: String { "player.currentTimeLabel" }
    static var playerPlayPauseButton: String { "player.playPauseButton" }
    static var playerProbeStreamResult: String { "player.probeStreamResult" }
    static var playerQuickAccessRow: String { "player.quickAccessRow" }
    static var playerRetryButton: String { "player.retryButton" }
    static var playerSignInButton: String { "player.signInButton" }
    static var playerTitleLabel: String { "player.titleLabel" }

}

// MARK: - UITestHelpers
//
// Shared utilities reused across all UI test suites.
// Not a subclass of XCTestCase — import by value from any test file.
// Note: The enum body uses iOS-only XCUIElement APIs (tap, swipe, coordinate),
// so the entire declaration is excluded from the tvOS build.

#if !os(tvOS)
enum UITestHelpers {

    // MARK: - Search

    /// The Search screen's field: the system search field (`.searchable`) on iPhone and iPad. SwiftUI gives
    /// that field no identifier (`search.bar` is the Apple TV field), so it is found by type: the app has one.
    static func searchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields.firstMatch
    }

    /// The field's system clear button, found by type: its label is localized and it has no identifier.
    static func searchClearButton(in app: XCUIApplication) -> XCUIElement {
        searchField(in: app).buttons.firstMatch
    }

    /// Opens the Search tab. While a search is active, iOS 26 turns the search-role tab into the field itself
    /// and minimizes the tab bar: there is no Search tab to tap, and the field is already on screen.
    static func openSearch(in app: XCUIApplication) {
        if searchField(in: app).isHittable { return }
        tapTab(named: "Search", in: app)
    }

    /// Empties the search field with its system clear button, when it has text.
    static func clearSearchField(in app: XCUIApplication) {
        let field = searchField(in: app)
        // Empty shows the placeholder as the value; then the only button may be dictation, not clear.
        guard let text = field.value as? String, !text.isEmpty, text != field.placeholderValue else { return }
        let clear = searchClearButton(in: app)
        if clear.waitForExistence(timeout: 1) { clear.tap() }
    }

    // MARK: - Tab navigation

    private static func tabPredicate(named rawName: String) -> NSPredicate {
        let displayName = rawName == "Offline videos" ? "Offline" : rawName
        return NSPredicate(
            format: "identifier == %@ OR label IN %@", AccessibilityID.tab(rawName), [rawName, displayName])
    }

    /// Both destinations identify the native sidebar without matching a tab's content stack.
    static func sidebarItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.collectionViews
            .containing(tabPredicate(named: "Home"))
            .containing(tabPredicate(named: "Settings"))
            .descendants(matching: .any)
    }

    /// iPad's floating tabs need not be buttons or descendants of a TabBar in the accessibility tree.
    static func tabItem(named rawName: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement? {
        let predicate = tabPredicate(named: rawName)
        let candidates = app.descendants(matching: .any).matching(predicate)
        guard candidates.firstMatch.waitForExistence(timeout: timeout) else { return nil }

        let tabBarItems = app.tabBars.descendants(matching: .any).matching(predicate)
        let sidebarMatches = sidebarItems(in: app).matching(predicate)
        let navigationTitles = app.navigationBars.descendants(matching: .any).matching(predicate)
        var item: XCUIElement?
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                for query in [tabBarItems, sidebarMatches] {
                    if let match = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                        item = match
                        return true
                    }
                }

                // Bound the unscoped fallback to top chrome: content stacks share the tab identifiers.
                let window = app.frame
                let topArea = CGRect(
                    x: window.minX, y: window.minY, width: window.width, height: min(120, window.height / 4))
                let titleFrames = navigationTitles.allElementsBoundByIndex.map(\.frame)
                item = candidates.allElementsBoundByIndex.first { candidate in
                    let frame = candidate.frame
                    return !frame.isEmpty && topArea.contains(frame) && candidate.elementType != .navigationBar
                        && !titleFrames.contains(frame) && candidate.isHittable
                }
                return item != nil
            }, object: nil)
        guard XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed else { return nil }
        return item
    }

    /// Raw names keep identifiers stable even when the displayed tab label is shorter.
    static func tapTab(named rawName: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        guard let item = tabItem(named: rawName, in: app, timeout: timeout) else {
            XCTFail("'\(rawName)' hittable navigation item not found in tab bar, sidebar or top area")
            return
        }
        item.tap()
    }

    // MARK: - Settings navigation

    /// The settings form, excluding the adjacent category list on regular-width iPad.
    static func settingsForm(in app: XCUIApplication) -> XCUIElement {
        let table = app.tables[AccessibilityID.settingsForm].firstMatch
        return table.exists ? table : app.collectionViews[AccessibilityID.settingsForm].firstMatch
    }

    /// Compact windows keep the single form; a wide iPad first selects the control's category.
    static func selectSettingsCategory(_ group: String, in app: XCUIApplication) {
        XCTAssertTrue(
            settingsForm(in: app).waitForExistence(timeout: 5), "Settings must load before choosing a category")
        let table = app.tables[AccessibilityID.settingsCategories].firstMatch
        let categories = table.exists ? table : app.collectionViews[AccessibilityID.settingsCategories].firstMatch
        guard categories.exists else { return }
        let category = categories.buttons[AccessibilityID.settingsCategory(group)]
        for _ in 0..<8 where !(category.exists && category.isHittable) { categories.swipeDown() }
        scrollUntilVisible(category, in: categories)
        XCTAssertTrue(category.waitForExistence(timeout: 5), "Settings category \(group) must be reachable")
        category.tap()
        XCTAssertTrue(settingsForm(in: app).waitForExistence(timeout: 5))
    }

    // MARK: - Chip bar scrolling

    /// Scrolls `chip` into the fully-visible area of `chipBar` before tapping.
    /// Uses coordinate drags on the chip bar itself, checking frame bounds so
    /// the chip is never scrolled past.
    static func scrollChipIntoView(_ chip: XCUIElement, in chipBar: XCUIElement, app: XCUIApplication) {
        let viewport = chipBar.frame.intersection(app.windows.firstMatch.frame)
        let near = chipBar.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let far = chipBar.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))

        for _ in 0..<8 {
            let frame = chip.frame
            if frame.minX >= viewport.minX + 4 && frame.maxX <= viewport.maxX - 4 { break }
            if frame.minX < viewport.minX + 4 {
                near.press(forDuration: 0.05, thenDragTo: far)
            } else {
                far.press(forDuration: 0.05, thenDragTo: near)
            }
        }
    }

    // MARK: - Video cards

    /// Waits up to `timeout` for at least one `video.card.*` element to appear.
    /// Returns the first card element or `nil` if the feed stays empty.
    @discardableResult
    static func waitForVideoCards(in app: XCUIApplication, timeout: TimeInterval = 20) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: cards)
        guard XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed else {
            return nil
        }
        return cards.firstMatch
    }

    /// What VoiceOver reads for a `video.card.*` element ("Title, Channel, …"). On iPhone and iPad the card
    /// is a container whose first button is that summary (its More button follows); elsewhere it is the card.
    static func cardSummary(_ card: XCUIElement) -> String {
        let summary = card.buttons.firstMatch
        return summary.exists ? summary.label : card.label
    }

    // MARK: - Player

    /// Taps `card` and waits for `player.titleLabel` to appear.
    /// Returns `true` when the player opened successfully within `timeout`.
    @discardableResult
    static func openPlayer(from card: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        card.tap()
        return app.staticTexts[AccessibilityID.playerTitleLabel].firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - Scroll helpers

    /// Swipes up in `scrollView` until `element` exists and is hittable,
    /// or until `maxSwipes` attempts are exhausted.
    /// Waits up to `scrollViewTimeout` seconds for `scrollView` itself to appear
    /// before attempting any swipes — prevents "No matches found" on slow loads.
    ///
    /// Checking `isHittable` (not just `exists`) matters near the bottom of a
    /// scroll view: a row can already be present in the accessibility tree while
    /// still being visually covered by the tab bar, so taps on it land on the
    /// tab bar instead.
    static func scrollUntilVisible(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxSwipes: Int = 8,
        scrollViewTimeout: TimeInterval = 5
    ) {
        guard scrollView.waitForExistence(timeout: scrollViewTimeout) else { return }
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
    }

    // MARK: - Error assertions

    /// Fails the test if the standard "Error" feed alert is showing.
    static func assertNoErrorAlert(in app: XCUIApplication) {
        XCTAssertFalse(
            app.alerts["Error"].exists,
            "An unexpected 'Error' alert is visible")
    }

    /// Fails the test if `player.errorBanner` is visible in `PlayerView`.
    static func assertNoPlayerErrorBanner(in app: XCUIApplication, videoTitle: String = "") {
        let banner = app.otherElements["player.errorBanner"].firstMatch
        let context = videoTitle.isEmpty ? "" : " during '\(videoTitle)'"
        XCTAssertFalse(
            banner.exists,
            "player.errorBanner appeared\(context) — PlaybackViewModel.error was set")
    }

    /// Fails the test if `shorts.errorBanner` is visible in `ShortsPlayerView`.
    static func assertNoShortsErrorBanner(in app: XCUIApplication) {
        let banner = app.staticTexts["shorts.errorBanner"].firstMatch
        XCTAssertFalse(
            banner.exists,
            "shorts.errorBanner appeared — PlaybackViewModel.error was set for the Short")
    }
}
#endif  // !os(tvOS)

// MARK: - XCTestCase diagnostic helpers

extension XCTestCase {

    /// Keeps diagnostic messages in the result bundle, including skipped tests and benchmark timings.
    func recordDiagnostic(_ message: String) {
        let attachment = XCTAttachment(string: message)
        attachment.name = String(message.prefix(120))
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures a screenshot and accessibility-tree dump, attaches both with
    /// `keepAlways` lifetime, then throws `XCTSkip` with the given reason.
    ///
    /// The `throws -> Never` signature lets Swift treat every call site as a
    /// guaranteed scope-exit, so no trailing `return` is needed in guard-else blocks:
    ///
    ///     guard card.exists else {
    ///         try captureAndSkip("Feed empty — network issue", in: app)
    ///     }
    func captureAndSkip(
        _ reason: String,
        in app: XCUIApplication,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Never {
        if app.state != .notRunning {
            let shot = app.screenshot()
            let shotAttachment = XCTAttachment(screenshot: shot)
            shotAttachment.name = "Skip state: \(reason.prefix(60))"
            shotAttachment.lifetime = .keepAlways
            add(shotAttachment)

            let treeAttachment = XCTAttachment(string: app.debugDescription)
            treeAttachment.name = "Accessibility tree at skip"
            treeAttachment.lifetime = .keepAlways
            add(treeAttachment)
        }

        throw XCTSkip(reason, file: file, line: line)
    }

    /// Captures a screenshot and accessibility-tree dump and attaches both with
    /// `keepAlways` lifetime. Call this immediately before an assertion that may
    /// fail to provide visual context in the result bundle.
    func captureState(_ label: String = "failure", in app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        let shot = app.screenshot()
        let shotAttachment = XCTAttachment(screenshot: shot)
        shotAttachment.name = "Screenshot: \(label)"
        shotAttachment.lifetime = .keepAlways
        add(shotAttachment)

        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name = "Accessibility tree: \(label)"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
    }

    /// Polls for an element's existence while guarding against app crashes.
    /// Unlike `waitForExistence(timeout:)`, this checks `app.state` before each
    /// accessibility query so an unexpected process termination returns `false`
    /// instead of triggering XCTest's crash-detection mechanism, which terminates
    /// the entire test case even with `continueAfterFailure = true`.
    func waitForExistenceGuarded(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard app.state == .runningForeground || app.state == .runningBackground else {
                return true
            }
            return element.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
        guard app.state == .runningForeground || app.state == .runningBackground else {
            return false
        }
        return element.exists
    }
}
