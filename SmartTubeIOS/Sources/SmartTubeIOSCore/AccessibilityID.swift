import Foundation

/// Accessibility identifiers used by app views.
public enum AccessibilityID {
    public static var playerStatsOverlay: String { "player.statsOverlay" }
    public static var playerHoldSpeedBadge: String { "player.holdSpeedBadge" }
    public static var playerMoreMenuCancelButton: String { "player.moreMenu.cancel" }
    public static var playerMoreMenuDescriptionRow: String { "player.moreMenu.descriptionRow" }
    public static var playerMoreMenu: String { "player.moreMenu" }
    public static var playerMoreMenuOpenChannel: String { "player.more.openChannel" }
    public static var playerOptionPanelCancel: String { "player.optionPanel.cancel" }
    public static var playerDescriptionPanel: String { "player.descriptionOverlay" }
    public static var playerDescriptionPanelCancel: String { "player.descriptionOverlay.cancel" }
    public static var playerCommentsPanel: String { "player.commentsOverlay" }
    public static var playerCommentsPanelCancel: String { "player.commentsOverlay.cancel" }
    public static var playerMoreMenuScrollView: String { "player.moreMenu.scrollView" }
    public static var playerMoreMenuLikeRow: String { "player.moreMenu.likeRow" }
    public static var playerMoreMenuDislikeRow: String { "player.moreMenu.dislikeRow" }
    public static var playerMoreMenuShareRow: String { "player.moreMenu.shareRow" }
    public static var playerShareSheet: String { "player.shareSheet" }
    public static var playerMoreMenuSpeedRow: String { "player.moreMenu.speedRow" }
    public static var playerMoreMenuQualityRow: String { "player.moreMenu.qualityRow" }
    public static var playerMoreMenuSleepTimerRow: String { "player.moreMenu.sleepTimerRow" }
    public static var playerMoreMenuAudioOnlyRow: String { "player.moreMenu.audioOnlyRow" }
    public static var playerMoreMenuQueueShuffleRow: String { "player.moreMenu.queueShuffleRow" }
    public static var playerMoreMenuDownloadButton: String { "player.moreMenu.downloadButton" }
    public static var playerMoreMenuCaptionsRow: String { "player.moreMenu.captionsRow" }
    public static var playerMoreMenuAudioTrackRow: String { "player.moreMenu.audioTrackRow" }
    public static var playerMoreMenuCommentsRow: String { "player.moreMenu.commentsRow" }
    public static var playerMoreMenuStatsForNerds: String { "player.moreMenu.statsForNerds" }
    public static var playerMoreButton: String { "player.moreButton" }
    public static var miniPlayerBar: String { "miniPlayer.bar" }
    public static var miniPlayerTitle: String { "miniPlayer.titleLabel" }
    public static var miniPlayerPlayPause: String { "miniPlayer.playPauseButton" }
    public static var miniPlayerClose: String { "miniPlayer.closeButton" }
    /// Content of a root tab; `name` is the `AppSection` raw value.
    public static func tab(_ name: String) -> String { "tab.\(name.lowercased())" }
    public static var uiTestingReopenDeeplinkVideo: String { "uitesting.reopenDeeplinkVideoButton" }
    public static var playerToast: String { "player.toast" }
    public static var playerProgressBar: String { "player.progressBar" }
    public static var playerBrightnessGesture: String { "player.brightnessGesture" }
    public static var playerVolumeGesture: String { "player.volumeGesture" }
    public static var offlinePlaybackStatus: String { "offline.playbackStatus" }
    public static var offlineFindVariants: String { "offline.findVariants" }
    public static func offlineDownload(_ id: String) -> String { "offline.download.\(id)" }
    public static func offlineSaved(_ id: String) -> String { "offline.saved.\(id)" }
    public static func offlineDownloadTranslation(_ language: String) -> String { "offline.translation.\(language)" }
    public static var offlineSelectionVideo: String { "offline.selection.video" }
    public static var offlineSelectionAudio: String { "offline.selection.audio" }
    public static var offlineSelectionTranslate: String { "offline.selection.translate" }
    public static var offlineSelectionLanguage: String { "offline.selection.language" }
    public static var offlineSelectionDownload: String { "offline.selection.download" }
    public static func offlineDeleteEntry(_ id: String) -> String { "offline.deleteEntry.\(id)" }
    public static func offlineDeleteJob(_ id: UUID) -> String { "offline.deleteJob.\(id)" }
    public static var offlineWatch: String { "offline.watch" }
    public static var offlinePage: String { "offline.page" }
    public static var offlinePagePicker: String { "offline.pagePicker" }
    public static var offlineLibraryList: String { "offline.libraryList" }
    public static var offlineJobsList: String { "offline.jobsList" }
    public static var offlineDetailList: String { "offline.detailList" }
    public static var offlineDeleteAll: String { "offline.deleteAll" }
    public static var offlineUpdateSponsorBlockAll: String { "offline.updateSponsorBlockAll" }
    public static var offlineUpdateSponsorBlock: String { "offline.updateSponsorBlock" }
    public static var offlineSponsorBlockStatus: String { "offline.sponsorBlockStatus" }
    public static var offlineAudioPicker: String { "offline.audioPicker" }
    public static var offlineTranslationPicker: String { "offline.translationPicker" }
    public static var offlineVideoPicker: String { "offline.videoPicker" }
    public static var offlinePlaySummary: String { "offline.playSummary" }
    public static func offlineQualityGroup(_ height: Int) -> String { "offline.quality.\(height)" }
    public static func offlineEntry(_ id: String) -> String { "offline.entry.\(id)" }
    public static func offlinePlay(_ id: String) -> String { "offline.play.\(id)" }
    public static func offlineJob(_ id: UUID) -> String { "offline.job.\(id)" }
    public static func offlineCancel(_ id: UUID) -> String { "offline.cancel.\(id)" }
    public static func offlineRetry(_ id: UUID) -> String { "offline.retry.\(id)" }

    public static var homeChipBar: String { "home.chipBar" }
    public static func homeSectionChip(_ title: String) -> String { "chip.\(title)" }
    public static var channelSubscriptionButton: String { "channel.followButton" }
    public static var channelHeader: String { "channel.header" }
    public static var channelTitle: String { "channel.title" }
    public static var subscriptionConfirm: String { "subscription.confirm" }
    public static var subscriptionCancel: String { "subscription.cancel" }
    public static var subscriptionRetry: String { "subscription.retry" }
    public static var subscriptionList: String { "subscription.list" }
    public static func subscriptionRow(_ id: String) -> String { "subscription.row.\(id)" }
    public static func subscriptionRemove(_ id: String) -> String { "subscription.remove.\(id)" }
    public static var homeSubscriptionsChannelFilter: String { "home.subscriptionsChannelFilter" }
    /// tvOS text field; iPhone, iPad and Mac use the system search field.
    public static var searchBar: String { "search.bar" }
    public static var searchClearButton: String { "search.clearButton" }
    public static var searchFilterButton: String { "search.filterButton" }
    public static var searchFilterSheet: String { "search.filterSheet" }
    public static var searchResults: String { "search.results" }
    /// The idle list: recent searches and topics.
    public static var searchSuggestionsContainer: String { "search.suggestionsContainer" }
    public static var searchHistoryClearAll: String { "search.history.clearAll" }
    public static func searchHistory(_ query: String) -> String { "search.history.\(query)" }
    /// A live suggestion or matching recent search under the search field.
    public static func searchSuggestion(_ text: String) -> String { "search.suggestion.\(text)" }
    public static var searchNoResults: String { "search.noResults" }
    public static var searchFailed: String { "search.failed" }
    public static var searchRetryButton: String { "search.retryButton" }
    public static var parentalControlsConfirmNew: String { "parentalControls.confirmNew" }
    public static var parentalControlsEnterNew: String { "parentalControls.enterNew" }
    public static var parentalControlsVerifyCurrent: String { "parentalControls.verifyCurrent" }
    public static var pinKeypadDelete: String { "pinKeypad.delete" }

    public static func pinKeypadDigit(_ digit: Int) -> String {
        "pinKeypad.digit\(digit)"
    }
    public static var pinKeypadDots: String { "pinKeypad.dots" }
    public static var pinKeypadErrorMessage: String { "pinKeypad.errorMessage" }
    public static var playerAudioTrackPicker: String { "player.audioTrackPicker" }
    public static var playerTranslationLanguagePicker: String { "player.translationLanguagePicker" }
    public static var playerAudioTrackPickerAuto: String { "player.audioTrackPicker.auto" }
    public static var playerAudioKeepOriginalAudioToggle: String { "player.audioTrackPicker.keepOriginalAudioToggle" }
    public static var playerAudioTrackPickerLivelyVoiceToggle: String { "player.audioTrackPicker.livelyVoiceToggle" }

    public static func playerAudioTrack(_ id: String) -> String {
        "player.audioTrackPicker.track.\(id)"
    }
    public static var playerAudioTrackPickerVoiceOverToggle: String { "player.audioTrackPicker.voiceOverToggle" }
    public static var playerVoiceOverCancelButton: String { "player.voiceOver.cancelButton" }
    public static var settingsCategories: String { "settings.categories" }
    public static var settingsForm: String { "settings.form" }
    public static func settingsCategory(_ group: String) -> String { "settings.category.\(group)" }
    public static var settingsSignInButton: String { "settings.signInButton" }
    public static var settingsHideShortsToggle: String { "settings.hideShortsToggle" }
    public static var settingsPreferredQualityPicker: String { "settings.preferredQualityPicker" }
    public static var settingsConcurrentDownloadsPicker: String { "settings.concurrentDownloadsPicker" }
    public static var settingsSeekBackRow: String { "settings.seekBackRow" }
    public static var settingsAccentColorPicker: String { "settings.accentColorPicker" }
    public static var settingsChangePINButton: String { "settings.changePINButton" }
    public static var settingsClearLocalHistoryButton: String { "settings.clearLocalHistoryButton" }
    public static var settingsClearLocalHistoryConfirm: String { "settings.clearLocalHistory.confirm" }
    public static var settingsClearLocalHistoryCancel: String { "settings.clearLocalHistory.cancel" }
    public static var settingsDisableLiquidGlassToggle: String { "settings.disableLiquidGlassToggle" }
    public static var settingsGridColumnsLandscapePicker: String { "settings.gridColumnsLandscapePicker" }
    public static var settingsGridColumnsPortraitPicker: String { "settings.gridColumnsPortraitPicker" }
    public static var settingsHistoryPicker: String { "settings.historyPicker" }
    public static var settingsH264Toggle: String { "settings.h264Toggle" }
    public static var settingsHideWatchedThresholdStepper: String { "settings.hideWatchedThresholdStepper" }
    public static var settingsHideWatchedVideosToggle: String { "settings.hideWatchedVideosToggle" }
    public static var settingsGitHubLink: String { "settings.githubLink" }
    public static var homeFilteredLoadMoreButton: String { "home.filteredLoadMoreButton" }
    public static var settingsRemovePINButton: String { "settings.removePINButton" }
    public static var settingsResetAllButton: String { "settings.resetAllButton" }
    public static var settingsResetAllConfirm: String { "settings.resetAll.confirm" }
    public static var settingsResetAllCancel: String { "settings.resetAll.cancel" }
    public static var settingsSetPINButton: String { "settings.setPINButton" }
    public static var settingsSponsorBlockToggle: String { "settings.sponsorBlockToggle" }
    public static var settingsOfflineSponsorBlockToggle: String { "settings.offlineSponsorBlockToggle" }
    public static var settingsThumbnailStylePicker: String { "settings.thumbnailStylePicker" }
    public static var settingsVp9Toggle: String { "settings.vp9Toggle" }
    public static var settingsVisibleSectionsLink: String { "settings.visibleSectionsLink" }
    public static var settingsVisibleSectionsList: String { "settings.visibleSectionsList" }
    public static var settingsYandexVOTKeepOriginalAudioToggle: String { "settings.yandexVOTKeepOriginalAudioToggle" }
    public static var settingsYandexVOTLivelyVoiceToggle: String { "settings.yandexVOTLivelyVoiceToggle" }
    public static var settingsYandexVOTToggle: String { "settings.yandexVOTToggle" }
    public static var settingsPreferredAudioLanguageRow: String { "settings.preferredAudioLanguageRow" }
    public static var settingsShortsAudioLanguageRow: String { "settings.shortsAudioLanguageRow" }
    public static var settingsShortsYandexVOTToggle: String { "settings.shortsYandexVOTToggle" }
    public static var settingsShortsLivelyVoiceToggle: String { "settings.shortsLivelyVoiceToggle" }
    public static var settingsShortsKeepOriginalAudioToggle: String { "settings.shortsKeepOriginalAudioToggle" }
    public static var settingsYandexVOTTokenField: String { "settings.yandexVOTTokenField" }
    public static var settingsPINLock: String { "settingsPINLock" }

    public static var homeCurrentQueueRow: String { "home.currentQueueRow" }
    public static var librarySectionPicker: String { "library.sectionPicker" }
    /// A Library segment; `section` is its raw value (`LibraryView.LibrarySection`).
    public static func libraryPicker(_ section: String) -> String { "library.picker.\(section.lowercased())" }
    public static var libraryChipBar: String { "library.chipBar" }
    /// A tvOS Library chip; `section` is its raw value.
    public static func libraryChip(_ section: String) -> String { "library.chip.\(section.lowercased())" }
    /// Sign In on the Playlists segment for a guest.
    public static var librarySignInButton: String { "library.signInButton" }
    /// The note above a guest's on-device History.
    public static var libraryGuestHistoryNote: String { "library.guestHistoryNote" }
    /// The Queue screen: Library › Queue, the iPad and Mac sidebar Queue item, Home's Current Queue row.
    public static var queueView: String { "queue.view" }
    public static var queueClearButton: String { "queue.clearButton" }
    public static var queueClearConfirm: String { "queue.clearConfirm" }

    /// Home feed Shorts rows: the first keeps the long-standing `home.shortsRow`.
    public static func homeShortsRow(_ index: Int) -> String {
        index == 0 ? "home.shortsRow" : "home.shortsRow.\(index)"
    }

    public static func sectionShortsRow(_ section: BrowseSection.SectionType, _ index: Int) -> String {
        let prefix = section == .recommended ? "recommended.shortsRow" : "browse.shortsRow"
        return index == 0 ? prefix : "\(prefix).\(index)"
    }

    public static func feedVideoBlock(_ section: BrowseSection.SectionType, _ index: Int) -> String {
        "feed.\(section.rawValue).videos.\(index)"
    }

    public static func videoCard(_ videoId: String) -> String {
        "video.card.\(videoId)"
    }

    /// The card's More button; outside the `video.card.` prefix so card queries never match it.
    public static func videoCardMenu(_ videoId: String) -> String {
        "videoCardMenu.\(videoId)"
    }

    /// The card's title text, exactly as shown; outside the `video.card.` prefix like `videoCardMenu`.
    public static var videoCardTitle: String { "videoCardTitle" }

    public static func shortsCard(_ videoId: String) -> String {
        "shorts.card.\(videoId)"
    }
    public static var homeSectionFeed: String { "home.sectionFeed" }
    public static var shortsBackButton: String { "shorts.backButton" }
    public static var shortsIndexLabel: String { "shorts.indexLabel" }
    public static var shortsPreloadStatus: String { "shorts.preloadStatus" }
    public static var shortsReopenTestButton: String { "shorts.reopenTestButton" }
    public static var shortsPlayPauseButton: String { "shorts.playPauseButton" }
    public static var shortsPreviousButton: String { "shorts.previousButton" }
    public static var shortsNextButton: String { "shorts.nextButton" }
    public static var shortsAudioTrackButton: String { "shorts.audioTrackButton" }
    public static var shortsSpeedButton: String { "shorts.speedButton" }
    public static var playerSpeedPicker: String { "player.speedPicker" }
    public static var playerQuickSpeedButton: String { "player.quickAccess.speed" }
    public static var playerQuickOfflineButton: String { "player.quickAccess.offline" }
    public static func playerSpeed(_ speed: Double) -> String { "player.speed.\(speed)" }
    public static var shortsVideoScaleButton: String { "shorts.videoScaleButton" }
    public static var shortsLoadMoreButton: String { "shorts.loadMoreButton" }
    public static var shortsMuteButton: String { "shorts.muteButton" }
    public static var shortsSeekBar: String { "shorts.seekBar" }
    public static var shortsTimeLabel: String { "shorts.timeLabel" }
    public static var shortsTitleLabel: String { "shorts.titleLabel" }
    public static var shortsControlsOverlay: String { "shorts.controlsOverlay" }
    public static var shortsRetryButton: String { "shorts.retryButton" }
    public static var shortsErrorBanner: String { "shorts.errorBanner" }
    public static var playerBackButton: String { "player.backButton" }
    public static var playerPiPButton: String { "player.pipButton" }
    public static var playerFullScreenButton: String { "player.fullScreenButton" }
    public static var playerInspectorToggle: String { "player.inspectorToggle" }
    public static var playerAirPlayButton: String { "player.airPlayButton" }
    public static var playerChannelName: String { "player.channelName" }
    public static var playerDurationLabel: String { "player.durationLabel" }
    public static var playerLandscapeLockButton: String { "player.landscapeLockButton" }
    public static var playerAudioOnlyButton: String { "player.audioOnlyButton" }
    public static var playerVideoScaleButton: String { "player.videoScaleButton" }
    public static var playerQuickAudioButton: String { "player.quickAccess.audioTrack" }
    public static var playerQuickQualityButton: String { "player.quickAccess.quality" }
    public static var playerQualityPicker: String { "player.qualityPicker" }
    public static var playerQualityPickerAuto: String { "player.qualityPicker.auto" }
    public static var playerSleepTimerPicker: String { "player.sleepTimerPicker" }
    public static var playerCaptionPicker: String { "player.captionPicker" }
    public static var playerCaptionPickerOff: String { "player.captionPicker.off" }
    public static func playerCaptionPickerTrack(_ id: String) -> String { "player.captionPicker.track.\(id)" }
    public static var playerNextButton: String { "player.nextBtn" }
    public static var playerCurrentTimeLabel: String { "player.currentTimeLabel" }
    public static var playerPlayPauseButton: String { "player.playPauseButton" }
    public static var playerProbeStreamResult: String { "player.probeStreamResult" }
    public static var playerQuickAccessRow: String { "player.quickAccessRow" }
    public static var playerRetryButton: String { "player.retryButton" }
    public static var playerSignInButton: String { "player.signInButton" }
    public static var playerTitleLabel: String { "player.titleLabel" }

}
