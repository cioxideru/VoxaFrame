import SmartTubeIOSCore

extension PlaybackViewModel {
    func updatePlaybackDemand() {
        playbackDemand.update(
            player: player, videoID: currentVideo?.id, isLoading: isLoading,
            isEnabled: currentVideo?.isDownloaded != true && error == nil && parkedVideoId == nil
                && ownsPlaybackAudioSession)
    }
}
