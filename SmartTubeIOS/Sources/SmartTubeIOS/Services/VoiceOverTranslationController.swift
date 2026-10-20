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
// voice player on attachment, after a resume or timeline jump, or for bounded drift recovery.

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
        var isOfflineVideo = false
    }

    private(set) var state: State = .idle
    private(set) var videoId: String?

    /// Original-audio volume under the translation (music and effects stay audible).
    private static let duckedVolume: Float = 0.2
    /// Off: the original audio is muted while the translation plays.
    var keepsOriginalAudio = true {
        didSet { if case .playing = state { mainPlayer?.volume = originalAudioVolume } }
    }
    var isMuted: Bool {
        get { voicePlayer.isMuted }
        set { voicePlayer.isMuted = newValue }
    }
    #if DEBUG
    var testPlaybackRate: Float { voicePlayer.rate }
    var testPlaybackTime: Double { voicePlayer.currentTime().seconds }
    #endif
    private var originalAudioVolume: Float { keepsOriginalAudio ? Self.duckedVolume : 0 }
    private static let pollInterval: ClosedRange<Int> = 5...30
    /// Consecutive network errors tolerated before giving up on the translation.
    private static let maxRequestErrors = 3

    @ObservationIgnored private let localFileAllowed: (URL) -> Bool
    @ObservationIgnored private let client: any YandexVOTServing
    @ObservationIgnored private let api: InnerTubeAPI?
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
    @ObservationIgnored private var timeJumpTask: Task<Void, Never>?
    @ObservationIgnored private weak var observedVideoItem: AVPlayerItem?
    @ObservationIgnored private var needsVoiceAlignment = true
    @ObservationIgnored private var driftCorrection = VoiceOverDriftCorrection()

    init(
        api: InnerTubeAPI? = nil, client: any YandexVOTServing = YandexVOTClient(),
        localFileAllowed: @escaping (URL) -> Bool = OfflineMedia.validLocalURL
    ) {
        self.api = api
        self.client = client
        self.localFileAllowed = localFileAllowed
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

    /// Attaches a fully saved translation without contacting Yandex or YouTube.
    func startLocal(url: URL, videoID: String, mainPlayer: AVPlayer, setVideoPlaying: @escaping (Bool) -> Void) {
        stop()
        self.videoId = videoID
        guard url.isFileURL, localFileAllowed(url), FileManager.default.fileExists(atPath: url.path) else {
            state = .failed(
                String(
                    localized: "The saved translation is unavailable. Download it again in Offline videos.",
                    bundle: .module))
            return
        }
        self.mainPlayer = mainPlayer
        self.setVideoPlaying = setVideoPlaying
        mainVolume = mainPlayer.volume
        attach(url, livelyVoice: false)
    }

    func reportUnavailable(videoID: String, message: String) {
        cancelAndResume()
        videoId = videoID
        state = .failed(message)
    }

    /// Pauses I/O while the video awaits audio-session activation, retaining the translation.
    func pauseAudio() {
        voicePlayer.pause()
        driftCorrection.playbackChanged(isPlaying: false)
    }

    /// Detaches from the main player and restores its audio. Leaves the video's play state alone.
    func stop() {
        task?.cancel()
        task = nil
        timeJumpTask?.cancel()
        timeJumpTask = nil
        observedVideoItem = nil
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
        #if DEBUG
        if let url = ShortsPlaybackUITestFixture.translationAudioURL {
            guard !Task.isCancelled else { return }
            attach(url, livelyVoice: false)
            return
        }
        #endif
        var token = request.livelyVoiceToken
        var sourceLanguage = request.sourceLanguage
        var uploadedAudio = false
        var playingURL: URL?
        var requestErrors = 0
        while !Task.isCancelled {
            let translation: YandexVOTClient.Translation
            do {
                translation = try await client.translate(
                    videoId: request.videoId, duration: request.duration,
                    sourceLanguage: sourceLanguage, targetLanguage: request.targetLanguage,
                    livelyVoiceToken: token)
                try Task.checkCancellation()
                if let original = try await originalLanguageAfterRefusal(
                    translation.status, request: request, sourceLanguage: sourceLanguage)
                {
                    sourceLanguage = original
                    uploadedAudio = false
                    continue
                }
                requestErrors = 0
            } catch {
                // Cancelled by stop()/restart: a newer translation may own the state now.
                if Task.isCancelled { return }
                if request.isOfflineVideo, error is URLError {
                    return fail(
                        String(
                            localized:
                                "A new translation needs internet. Connect and retry, or choose a saved translation in Offline videos.",
                            bundle: .module), error: error)
                }
                requestErrors += 1
                guard requestErrors < Self.maxRequestErrors else {
                    return fail("Yandex request failed: \(error)", error: error)
                }
                let failure = error as NSError
                votLog.notice(
                    "Yandex request failed (\(requestErrors)/\(Self.maxRequestErrors)) — retrying domain=\(failure.domain, privacy: .public) code=\(failure.code)"
                )
                try? await Task.sleep(for: .seconds(Self.pollInterval.lowerBound))
                continue
            }
            guard !Task.isCancelled else { return }

            // Lively voices unavailable for this video — fall back to the classic voice.
            if token != nil, translation.status == .failed || translation.status == .sessionRequired {
                votLog.notice("lively voice refused — retrying with classic voice")
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
                    return fail("Audio upload failed: \(error)", error: error)
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

    private func originalLanguageAfterRefusal(
        _ status: YandexVOTClient.Status, request: Request, sourceLanguage: String
    ) async throws -> String? {
        guard status == .failed, request.isOfflineVideo, sourceLanguage == "auto", let api else { return nil }
        let info = try await api.fetchPlayerInfoVisionOS(videoId: request.videoId)
        try Task.checkCancellation()
        let original = info.voiceOverSourceLanguage
        guard original != "auto" else { return nil }
        votLog.notice("Auto language refused; retrying with original language \(original, privacy: .public)")
        return original
    }

    private func fail(_ message: String, error: (any Error)? = nil) {
        if let failure = error as NSError? {
            votLog.error("Translation failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        } else {
            votLog.error("Translation failed")
        }
        timeJumpTask?.cancel()
        timeJumpTask = nil
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
        // Local playback has no PlayerInfo. Resolve online audio only if Yandex asks for it.
        if request.isOfflineVideo, request.originalAudioURL == nil, request.originalAudioHLSURL == nil, let api {
            let info = try await api.fetchPlayerInfoVisionOS(videoId: request.videoId)
            try Task.checkCancellation()
            try await client.uploadOriginalAudio(
                videoId: request.videoId, translationId: translationId,
                directURL: info.bestAdaptiveAudioURL, hlsURL: info.hlsURL,
                userAgent: InnerTubeClients.VisionOS.userAgent)
            return
        }
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
        needsVoiceAlignment = true
        driftCorrection = VoiceOverDriftCorrection()
        mainPlayer.volume = originalAudioVolume
        observeVideoJumps()
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

    private func observeVideoJumps() {
        guard let videoItem = mainPlayer?.currentItem, observedVideoItem !== videoItem else { return }
        timeJumpTask?.cancel()
        observedVideoItem = videoItem
        needsVoiceAlignment = true
        let jumps = NotificationCenter.default.notifications(
            named: AVPlayerItem.timeJumpedNotification, object: videoItem)
        timeJumpTask = Task { [weak self, weak videoItem] in
            for await _ in jumps {
                guard let self, !Task.isCancelled, self.mainPlayer?.currentItem === videoItem else { return }
                self.needsVoiceAlignment = true
                self.sync()
            }
        }
    }

    /// Mirrors the main player's state onto the voice player: any playback rate, pause, seeks.
    func sync() {
        guard let mainPlayer, let voiceItem = voicePlayer.currentItem else { return }
        observeVideoJumps()
        if voiceItem.status == .failed {
            return fail(
                "Translation audio failed: \(voiceItem.error?.localizedDescription ?? "unknown error")",
                error: voiceItem.error)
        }
        // Rate records pause/resume intent; buffering with a nonzero rate is not another user action.
        driftCorrection.playbackChanged(isPlaying: mainPlayer.rate > 0)
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
        let drift = abs(voicePlayer.currentTime().seconds - videoTime.seconds)
        guard drift.isFinite else { return }
        let shouldAlign = driftCorrection.shouldSeek(drift: drift, explicitlyRequested: needsVoiceAlignment)
        needsVoiceAlignment = false
        // MP3 seeks can be approximate. Drift recovery has a cooldown and a per-item budget.
        if shouldAlign {
            isSeekingVoice = true
            let tolerance = CMTime(seconds: PlaybackTuning.voiceSeekTolerance, preferredTimescale: 600)
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

/// Explicit jumps always align; automatic corrections cannot turn into a repeated MP3 seek loop.
struct VoiceOverDriftCorrection {
    private var lastAlignment: ContinuousClock.Instant?
    private var corrections = 0
    private var wasPlaying = false
    private var needsResumeAlignment = false

    mutating func playbackChanged(isPlaying: Bool) {
        if isPlaying, !wasPlaying { needsResumeAlignment = true }
        wasPlaying = isPlaying
    }

    mutating func shouldSeek(
        drift: TimeInterval, explicitlyRequested: Bool, now: ContinuousClock.Instant = .now
    ) -> Bool {
        guard drift.isFinite else { return false }
        let needsAlignment = explicitlyRequested || needsResumeAlignment
        needsResumeAlignment = false
        if needsAlignment {
            lastAlignment = now
            return drift > PlaybackTuning.voiceAlignmentTolerance
        }
        guard drift > PlaybackTuning.voiceDriftThreshold,
            corrections < PlaybackTuning.voiceDriftCorrectionLimit,
            lastAlignment.map({ now - $0 >= PlaybackTuning.voiceDriftCorrectionInterval }) ?? true
        else { return false }
        lastAlignment = now
        corrections += 1
        return true
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
