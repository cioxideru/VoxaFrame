import AVFoundation
import SmartTubeIOSCore

// MARK: - Audio Track Selection (thin wrapper — logic lives in AudioTrackManager)

extension PlaybackViewModel {

    var originalAudioLanguage: String? {
        playerInfo?.originalAudioLanguageCandidates.first
    }

    public func selectAudioTrack(_ track: AudioTrack?) {
        audioManager.selectAudioTrack(track)
    }
}
