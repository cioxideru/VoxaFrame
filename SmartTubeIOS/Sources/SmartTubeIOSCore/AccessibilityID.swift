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

    public static func videoCard(_ videoId: String) -> String {
        "video.card.\(videoId)"
    }

    public static func shortsCard(_ videoId: String) -> String {
        "shorts.card.\(videoId)"
    }
    public static var homeSectionFeed: String { "home.sectionFeed" }
    public static var playerBackButton: String { "player.backButton" }
    public static var playerProbeStreamResult: String { "player.probeStreamResult" }
    public static var playerQuickAccessRow: String { "player.quickAccessRow" }
    public static var playerRetryButton: String { "player.retryButton" }
    public static var playerSignInButton: String { "player.signInButton" }
    public static var playerTitleLabel: String { "player.titleLabel" }

}
