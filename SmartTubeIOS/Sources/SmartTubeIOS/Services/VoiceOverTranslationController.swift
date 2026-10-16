import AVFoundation
import Foundation
import Observation
import SmartTubeIOSCore
import os

private let votLog = Logger(subsystem: appSubsystem, category: "VoiceOver")

// MARK: - VoiceOverTranslationController
//
// Plays a Yandex VOT translation alongside the main AVPlayer. While Yandex has no
// translation yet, the main player stays paused; once an audio URL arrives the video
// resumes with the original audio ducked. The translation MP3
// shares the video timeline, so syncing is: mirror rate (any speed) and pause, and seek the
// voice player whenever it drifts from the video.

@MainActor
@Observable
final class VoiceOverTranslationController {

    enum State: Equatable {
        case idle
        /// Waiting for Yandex; `remainingSeconds` is its ETA when known.
        case waiting(remainingSeconds: Int?)
        case playing(livelyVoice: Bool)
        case failed(String)
    }

    struct Request: Equatable {
        let videoId: String
        let duration: TimeInterval
        let sourceLanguage: String
        let targetLanguage: String
        let livelyVoiceToken: String?
        /// Smallest audio-only stream of the video, uploaded if Yandex asks for the audio.
        let originalAudioURL: URL?
        /// HLS master of the video: its audio rendition is the fallback when googlevideo
        /// refuses the direct stream (403 past the first ~256 KB without a PO token).
        let originalAudioHLSURL: URL?
        let originalAudioUserAgent: String
    }

    private(set) var state: State = .idle
    private(set) var videoId: String?

    /// Original-audio volume under the translation (music and effects stay audible).
    private static let duckedVolume: Float = 0.2
    /// Off: the original audio is muted while the translation plays.
    var keepsOriginalAudio = true {
        didSet { if case .playing = state { mainPlayer?.volume = originalAudioVolume } }
    }
    private var originalAudioVolume: Float { keepsOriginalAudio ? Self.duckedVolume : 0 }
    /// Re-seek the voice when it drifts further than this from the video.
    private static let maxDrift: Double = 0.35
    private static let pollInterval: ClosedRange<Int> = 5...30
    /// Consecutive network errors tolerated before giving up on the translation.
    private static let maxRequestErrors = 3

    @ObservationIgnored private let client = YandexVOTClient()
    @ObservationIgnored private let voicePlayer = AVPlayer()
    @ObservationIgnored private weak var mainPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var mainVolume: Float = 1
    /// Pauses/resumes the video through its view model, so the stall watchdog doesn't
    /// mistake the hold for a stall and "recover" by restarting playback.
    @ObservationIgnored private var setVideoPlaying: (Bool) -> Void = { _ in }
    /// A voice seek is in flight; don't stack another one on top of it.
    @ObservationIgnored private var isSeekingVoice = false
    @ObservationIgnored private var seekTask: Task<Void, Never>?

    init() {
        voicePlayer.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - Interface

    /// Starts translating `request.videoId`. A no-op when that video is already handled.
    func start(_ request: Request, mainPlayer: AVPlayer, setVideoPlaying: @escaping (Bool) -> Void) {
        guard videoId != request.videoId else { return }
        stop()
        videoId = request.videoId
        self.mainPlayer = mainPlayer
        self.setVideoPlaying = setVideoPlaying
        mainVolume = mainPlayer.volume
        setVideoPlaying(false)
        state = .waiting(remainingSeconds: nil)
        task = Task { [weak self] in await self?.run(request) }
    }

    /// Pauses I/O while the video awaits audio-session activation, retaining the translation.
    func pauseAudio() {
        voicePlayer.pause()
    }

    /// Detaches from the main player and restores its audio. Leaves the video's play state alone.
    func stop() {
        task?.cancel()
        task = nil
        if let timeObserver, let mainPlayer { mainPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        cancelVoiceSeek()
        voicePlayer.pause()
        voicePlayer.replaceCurrentItem(with: nil)
        if videoId != nil { mainPlayer?.volume = mainVolume }
        mainPlayer = nil
        videoId = nil
        state = .idle
    }

    /// "Watch without translation": stops and resumes the video if it was held for Yandex.
    func cancelAndResume() {
        let resume = setVideoPlaying
        let wasWaiting = if case .waiting = state { true } else { false }
        stop()
        if wasWaiting { resume(true) }
    }

    // MARK: - Translation loop

    private func run(_ request: Request) async {
        var token = request.livelyVoiceToken
        var uploadedAudio = false
        var playingURL: URL?
        var requestErrors = 0
        while !Task.isCancelled {
            let translation: YandexVOTClient.Translation
            do {
                translation = try await client.translate(
                    videoId: request.videoId, duration: request.duration,
                    sourceLanguage: request.sourceLanguage, targetLanguage: request.targetLanguage,
                    livelyVoiceToken: token)
                requestErrors = 0
            } catch {
                // Cancelled by stop()/restart: a newer translation may own the state now.
                if Task.isCancelled { return }
                requestErrors += 1
                guard requestErrors < Self.maxRequestErrors else {
                    return fail("Yandex request failed: \(error)")
                }
                votLog.notice("Yandex request failed (\(requestErrors)/\(Self.maxRequestErrors)) — retrying: \(error)")
                try? await Task.sleep(for: .seconds(Self.pollInterval.lowerBound))
                continue
            }
            guard !Task.isCancelled else { return }

            // Lively voices unavailable for this video — fall back to the classic voice.
            if token != nil, translation.status == .failed || translation.status == .sessionRequired {
                votLog.notice("lively voice refused (\(translation.message ?? "-")) — retrying with classic voice")
                token = nil
                continue
            }

            switch translation.status {
            case .finished, .partContent:
                if let url = translation.audioURL, url != playingURL {
                    playingURL = url
                    attach(url, livelyVoice: translation.isLivelyVoice)
                }
                if translation.status == .finished { return }
            case .audioRequested where !uploadedAudio:
                uploadedAudio = true
                do {
                    try await uploadOriginalAudio(request, translationId: translation.translationId)
                } catch {
                    if Task.isCancelled { return }
                    return fail("Audio upload failed: \(error)")
                }
                continue
            case .waiting, .longWaiting, .audioRequested:
                if playingURL == nil { state = .waiting(remainingSeconds: translation.remainingTime) }
            case .failed, .sessionRequired:
                return fail(translation.message ?? "Yandex couldn't translate this video")
            }
            let delay = (translation.remainingTime ?? Self.pollInterval.lowerBound)
                .clamped(to: Self.pollInterval)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func fail(_ message: String) {
        votLog.error("\(message, privacy: .public)")
        let wasWaiting = if case .waiting = state { true } else { false }
        if let timeObserver, let mainPlayer { mainPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        cancelVoiceSeek()
        voicePlayer.replaceCurrentItem(with: nil)
        mainPlayer?.volume = mainVolume
        state = .failed(message)
        if wasWaiting { setVideoPlaying(true) }
    }

    /// Downloads the original audio to disk and uploads bounded parts.
    private func uploadOriginalAudio(_ request: Request, translationId: String) async throws {
        try await client.uploadOriginalAudio(
            videoId: request.videoId, translationId: translationId,
            directURL: request.originalAudioURL, hlsURL: request.originalAudioHLSURL,
            userAgent: request.originalAudioUserAgent)
    }

    // MARK: - Playback sync

    private func attach(_ url: URL, livelyVoice: Bool) {
        guard let mainPlayer else { return }
        let resume = if case .waiting = state { true } else { false }
        // No AVURLAssetPreferPreciseDurationAndTimingKey: on an hour-long streamed MP3 a precise
        // seek makes mediaplaybackd scan the file, its RPC times out and the system kills it,
        // taking every AVPlayer in the app down with it (-11819 until relaunch).
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        cancelVoiceSeek()
        voicePlayer.replaceCurrentItem(with: item)
        mainPlayer.volume = originalAudioVolume
        if timeObserver == nil {
            timeObserver = mainPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            }
        }
        state = .playing(livelyVoice: livelyVoice)
        votLog.notice("translation attached (lively=\(livelyVoice)) — \(resume ? "resuming video" : "swapped audio")")
        if resume { setVideoPlaying(true) }
        sync()
    }

    /// Drops the pending voice seek; replacing the item cancels the AVPlayer seek itself.
    private func cancelVoiceSeek() {
        seekTask?.cancel()
        seekTask = nil
        isSeekingVoice = false
    }

    /// Mirrors the main player's state onto the voice player: any playback rate, pause, seeks.
    private func sync() {
        guard let mainPlayer, let voiceItem = voicePlayer.currentItem else { return }
        if voiceItem.status == .failed {
            return fail("Translation audio failed: \(voiceItem.error?.localizedDescription ?? "unknown error")")
        }
        guard mainPlayer.timeControlStatus == .playing, mainPlayer.rate > 0 else {
            if voicePlayer.rate != 0 { voicePlayer.pause() }
            return
        }
        guard voicePlayer.currentItem?.status == .readyToPlay, !isSeekingVoice else { return }
        let videoTime = mainPlayer.currentTime()
        // A PART_CONTENT translation ends early: past its end there is nothing to seek to.
        if voiceItem.duration.isNumeric, videoTime >= voiceItem.duration {
            if voicePlayer.rate != 0 { voicePlayer.pause() }
            return
        }
        if abs(voicePlayer.currentTime().seconds - videoTime.seconds) > Self.maxDrift {
            isSeekingVoice = true
            let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
            seekTask = Task { [weak self, voicePlayer] in
                await voicePlayer.seek(to: videoTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                // A seek on a replaced item must not unlock the new item's in-flight seek.
                guard let self, !Task.isCancelled, voicePlayer.currentItem === voiceItem else { return }
                isSeekingVoice = false
                seekTask = nil
            }
        }
        if voicePlayer.rate != mainPlayer.rate { voicePlayer.rate = mainPlayer.rate }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
