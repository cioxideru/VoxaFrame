import Foundation

/// Accessibility identifiers used by app views.
public enum AccessibilityID {
    public static var homeSubscriptionsChannelFilter: String { "home.subscriptionsChannelFilter" }
    public static var parentalControlsConfirmNew: String { "parentalControls.confirmNew" }
    public static var parentalControlsEnterNew: String { "parentalControls.enterNew" }
    public static var parentalControlsVerifyCurrent: String { "parentalControls.verifyCurrent" }
    public static var pinKeypadDelete: String { "pinKeypad.delete" }

    public static func pinKeypadDigit(_ digit: Int) -> String {
        "pinKeypad.digit\(digit)"
    }
    public static var pinKeypadDots: String { "pinKeypad.dots" }
    public static var pinKeypadErrorMessage: String { "pinKeypad.errorMessage" }
    public static var playerAudioTrackPickerAuto: String { "player.audioTrackPicker.auto" }
    public static var playerAudioKeepOriginalAudioToggle: String { "player.audioTrackPicker.keepOriginalAudioToggle" }
    public static var playerAudioTrackPickerLivelyVoiceToggle: String { "player.audioTrackPicker.livelyVoiceToggle" }

    public static func playerAudioTrack(_ id: String) -> String {
        "player.audioTrackPicker.track.\(id)"
    }
    public static var playerAudioTrackPickerVoiceOverToggle: String { "player.audioTrackPicker.voiceOverToggle" }
    public static var playerVoiceOverCancelButton: String { "player.voiceOver.cancelButton" }
    public static var settingsAccentColorPicker: String { "settings.accentColorPicker" }
    public static var settingsChangePINButton: String { "settings.changePINButton" }
    public static var settingsClearLocalHistoryButton: String { "settings.clearLocalHistoryButton" }
    public static var settingsDisableLiquidGlassToggle: String { "settings.disableLiquidGlassToggle" }
    public static var settingsGridColumnsLandscapePicker: String { "settings.gridColumnsLandscapePicker" }
    public static var settingsGridColumnsPortraitPicker: String { "settings.gridColumnsPortraitPicker" }
    public static var settingsHistoryPicker: String { "settings.historyPicker" }
    public static var settingsH264Toggle: String { "settings.h264Toggle" }
    public static var settingsHideWatchedThresholdStepper: String { "settings.hideWatchedThresholdStepper" }
    public static var settingsHideWatchedVideosToggle: String { "settings.hideWatchedVideosToggle" }
    public static var settingsRemovePINButton: String { "settings.removePINButton" }
    public static var settingsSetPINButton: String { "settings.setPINButton" }
    public static var settingsThumbnailStylePicker: String { "settings.thumbnailStylePicker" }
    public static var settingsVp9Toggle: String { "settings.vp9Toggle" }
    public static var settingsYandexVOTKeepOriginalAudioToggle: String { "settings.yandexVOTKeepOriginalAudioToggle" }
    public static var settingsYandexVOTLivelyVoiceToggle: String { "settings.yandexVOTLivelyVoiceToggle" }
    public static var settingsYandexVOTToggle: String { "settings.yandexVOTToggle" }
    public static var settingsYandexVOTTokenField: String { "settings.yandexVOTTokenField" }
    public static var settingsPINLock: String { "settingsPINLock" }

    public static var homeCurrentQueueRow: String { "home.currentQueueRow" }

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

    public static func shortsCard(_ videoId: String) -> String {
        "shorts.card.\(videoId)"
    }
    public static var homeSectionFeed: String { "home.sectionFeed" }
    public static var shortsBackButton: String { "shorts.backButton" }
    public static var shortsIndexLabel: String { "shorts.indexLabel" }
    public static var shortsPlayPauseButton: String { "shorts.playPauseButton" }
    public static var shortsMuteButton: String { "shorts.muteButton" }
    public static var shortsSeekBar: String { "shorts.seekBar" }
    public static var shortsTimeLabel: String { "shorts.timeLabel" }
    public static var shortsTitleLabel: String { "shorts.titleLabel" }
    public static var shortsControlsOverlay: String { "shorts.controlsOverlay" }
    public static var shortsRetryButton: String { "shorts.retryButton" }
    public static var shortsErrorBanner: String { "shorts.errorBanner" }
    public static var playerBackButton: String { "player.backButton" }
    public static var playerPiPButton: String { "player.pipButton" }
    public static var playerVideoScaleButton: String { "player.videoScaleButton" }
    public static var playerQuickQualityButton: String { "player.quickAccess.quality" }
    public static var playerQualityPicker: String { "player.qualityPicker" }
    public static var playerNextButton: String { "player.nextBtn" }
    public static var playerCurrentTimeLabel: String { "player.currentTimeLabel" }
    public static var playerPlayPauseButton: String { "player.playPauseButton" }
    public static var playerProbeStreamResult: String { "player.probeStreamResult" }
    public static var playerQuickAccessRow: String { "player.quickAccessRow" }
    public static var playerRetryButton: String { "player.retryButton" }
    public static var playerSignInButton: String { "player.signInButton" }
    public static var playerTitleLabel: String { "player.titleLabel" }

}
