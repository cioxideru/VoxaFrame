import AVFoundation
import Foundation
import Testing
import os

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

#if os(iOS)
import MediaPlayer
import UIKit
#endif

final class OfflineRequestLog: Sendable {
    private let paths = OSAllocatedUnfairLock(initialState: [String]())
    var count: Int { paths.withLock { $0.count } }
    var isEmpty: Bool { paths.withLock { $0.isEmpty } }
    func record(_ request: URLRequest) { paths.withLock { $0.append(request.url?.path ?? "") } }
    func reset() { paths.withLock { $0 = [] } }
}

final class OfflineDecisionURLProtocol: URLProtocol {
    static let log = OfflineRequestLog()
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.log.record(request)
        let data = Data(
            #"{"responseContext":{"visitorData":"fixture"},"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"online-id","title":"Fixture","author":"Test","lengthSeconds":"60"},"streamingData":{"hlsManifestUrl":"https://example.invalid/original.m3u8"},"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://example.invalid/captions","languageCode":"en-US","kind":"asr"}]}}}"#
                .utf8)
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Keeps saved-video playback away from the shared coordinator and its network source.
private struct NoStoredSponsorSegments: OfflineSponsorSegmentProviding {
    // swiftlint:disable:next async_without_await
    func sponsorSegmentsForPlayback(videoID: String) async -> OfflineSponsorSegments? { nil }
}

actor OfflineVOTProbe: YandexVOTServing {
    struct Request: Sendable {
        let videoID: String
        let language: String
        let sourceLanguage: String
        let lively: Bool
    }
    var requests: [Request] = []
    var uploads: [String] = []
    var responses: [YandexVOTClient.Status]
    let networkError: URLError.Code?
    let audioURL: URL?
    init(
        _ responses: [YandexVOTClient.Status] = [.failed], networkError: URLError.Code? = nil,
        audioURL: URL? = URL(string: "https://example.invalid/translation.mp3")
    ) {
        self.responses = responses
        self.networkError = networkError
        self.audioURL = audioURL
    }
    func translate(
        videoId: String, duration: TimeInterval, sourceLanguage: String, targetLanguage: String,
        livelyVoiceToken: String?
    ) throws -> YandexVOTClient.Translation {
        requests.append(
            Request(
                videoID: videoId, language: targetLanguage, sourceLanguage: sourceLanguage,
                lively: livelyVoiceToken != nil))
        if let networkError { throw URLError(networkError) }
        let status = responses.isEmpty ? .failed : responses.removeFirst()
        return .init(
            status: status, audioURL: audioURL,
            remainingTime: 5, translationId: "translation-session", isLivelyVoice: false, message: "Fixture failure")
    }
    func uploadOriginalAudio(
        videoId: String, translationId: String, directURL: URL?, hlsURL: URL?, userAgent: String
    ) {
        uploads.append(videoId)
    }
}

@MainActor
private final class SavedTranslationProbe: OfflineTranslationFinding {
    var requests: [String] = []
    var url: URL?
    func savedTranslation(videoID: String, language: String) -> URL? {
        requests.append("\(videoID)/\(language)")
        return url
    }
}

@MainActor
private final class SavedTranslationGate: OfflineTranslationFinding {
    var pending: CheckedContinuation<URL?, Never>?
    func savedTranslation(videoID: String, language: String) async -> URL? {
        await withCheckedContinuation { pending = $0 }
    }
    func finish() {
        pending?.resume(returning: nil)
        pending = nil
    }
}

private final class OfflineReadyItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}

@MainActor
final class LocalMediaProbe: OfflineMediaPreparing {
    let prepared: AVPlayerItem = OfflineReadyItem(asset: AVMutableComposition())
    var requests: [Video] = []
    var fails = false
    func item(video: Video) throws -> AVPlayerItem {
        requests.append(video)
        if fails { throw OfflineLibraryError.invalidFile }
        return prepared
    }
}

/// One serialized parent owns the URLProtocol's request log.
@Suite("Offline playback decisions (PLAN-0029)", .serialized)
@MainActor
struct OfflinePlaybackDecisionTests {
    func api() -> (InnerTubeAPI, URLSession) {
        OfflineDecisionURLProtocol.log.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineDecisionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return (InnerTubeAPI(authToken: nil, session: session), session)
    }

    func video() -> Video {
        var video = Video(id: "online-id", title: "Saved", channelTitle: "Test", duration: 60)
        video.localFileURL = URL(fileURLWithPath: "/saved/video.mp4")
        return video
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    func voiceFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        try #require(buffer.floatChannelData?.pointee).initialize(repeating: 0, count: 8_000)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test("Local preparation and local failure never request online metadata or translation", arguments: [false, true])
    func localStartsWithoutNetwork(fails: Bool) async throws {
        let (api, session) = api()
        var settings = AppSettings()
        settings.yandexVOTEnabled = true
        settings.preferredAudioLanguage = "ru"
        let model = PlaybackViewModel(
            api: api, sponsorBlock: SponsorBlockService(session: session), deArrow: DeArrowService(session: session),
            settings: settings)
        let media = LocalMediaProbe()
        media.fails = fails
        model.offlineSponsor = NoStoredSponsorSegments()
        let vot = OfflineVOTProbe()
        model.voiceOver = VoiceOverTranslationController(api: api, client: vot)
        model.offlineMedia = media
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        defer { model.stop() }
        model.load(video: video(), incognito: true)
        #expect(await eventually { fails ? model.error != nil : model.player.currentItem === media.prepared })
        #expect(media.requests.count == 1)
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
        #expect(await vot.requests.isEmpty)
        #expect(model.playerInfo == nil)
        #expect(model.phase2Task == nil)
        #expect(model.prefetchTask == nil)
        if fails { #expect(model.player.currentItem == nil) }
    }

    @Test(
        "The library selection and an explicit language lookup use saved audio without Yandex",
        arguments: [false, true])
    func savedTranslationWins(manual: Bool) async throws {
        let (api, _) = api()
        let url = try voiceFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let vot = OfflineVOTProbe()
        let lookup = SavedTranslationProbe()
        lookup.url = url
        let model = PlaybackViewModel(api: api)
        model.voiceOver = VoiceOverTranslationController(api: api, client: vot, localFileAllowed: { $0 == url })
        model.offlineTranslations = lookup
        var saved = video()
        saved.localTranslationFileURL = url
        saved.localTranslationLanguage = "ru"
        model.currentVideo = saved
        model.settings.preferredAudioLanguage = "ru"
        defer { model.stop() }
        if manual {
            model.setVoiceOverForCurrentVideo(true)
            await model.offlineTranslationTask?.value
        } else {
            model.applyAudioLanguagePolicy()
        }
        #expect(model.voiceOver.state == .playing(livelyVoice: false))
        #expect(model.voiceOver.videoId == saved.id)
        #expect(lookup.requests == (manual ? ["online-id/ru"] : []))
        #expect(await vot.requests.isEmpty)
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
        model.setVoiceOverForCurrentVideo(false)
        #expect(model.voiceOver.state == .idle)
    }

    @Test(
        "A local video's live translation fails on the first network error and waits for an explicit retry",
        arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost])
    func liveTranslationOfLocalVideo(networkError: URLError.Code) async throws {
        let (api, _) = api()
        let vot = OfflineVOTProbe(networkError: networkError)
        let lookup = SavedTranslationProbe()
        let model = PlaybackViewModel(api: api)
        model.voiceOver = VoiceOverTranslationController(api: api, client: vot)
        model.offlineTranslations = lookup
        model.currentVideo = video()
        model.settings.preferredAudioLanguage = "en"
        defer { model.stop() }
        model.setVoiceOverForCurrentVideo(true)
        #expect(await eventually { if case .failed = model.voiceOver.state { true } else { false } })
        let request = try #require(await vot.requests.first)
        #expect(request.videoID == "online-id")
        #expect(request.language == "en")
        #expect(model.voiceOver.videoId == "online-id")
        #expect(lookup.requests == ["online-id/en"])
        #expect(OfflineDecisionURLProtocol.log.isEmpty)  // No PlayerInfo before Yandex asks for source audio.
        if case .failed(let message) = model.voiceOver.state { #expect(!message.isEmpty) }
        let failed = model.voiceOver.state
        for _ in 0..<3 { model.applyOfflineTranslation() }
        #expect(model.voiceOver.state == failed)
        #expect(model.offlineTranslationTask == nil)
        #expect(await vot.requests.count == 1)
        #expect(lookup.requests.count == 1)
        model.setVoiceOverForCurrentVideo(true)
        #expect(await eventually { if case .failed = model.voiceOver.state { true } else { false } })
        #expect(await vot.requests.count == 2)
    }

    @Test("Cancelling translation while the library is read cannot start a late Yandex request")
    func cancellationDuringLookup() async throws {
        let (api, _) = api()
        let vot = OfflineVOTProbe()
        let lookup = SavedTranslationGate()
        let model = PlaybackViewModel(api: api)
        model.voiceOver = VoiceOverTranslationController(api: api, client: vot)
        model.offlineTranslations = lookup
        model.currentVideo = video()
        model.settings.preferredAudioLanguage = "ru"
        defer {
            lookup.finish()
            model.stop()
        }
        model.setVoiceOverForCurrentVideo(true)
        let task = try #require(model.offlineTranslationTask)
        try #require(await eventually { lookup.pending != nil })
        model.setVoiceOverForCurrentVideo(false)
        lookup.finish()
        await task.value
        #expect(model.voiceOver.state == .idle)
        #expect(await vot.requests.isEmpty)
    }

    @Test("Live translation resolves source audio only after Yandex requests it")
    func liveSourceAudioOnDemand() async {
        let (api, _) = api()
        let vot = OfflineVOTProbe([.audioRequested, .failed])
        let model = PlaybackViewModel(api: api)
        model.voiceOver = VoiceOverTranslationController(api: api, client: vot)
        model.offlineTranslations = SavedTranslationProbe()
        model.currentVideo = video()
        model.settings.preferredAudioLanguage = "ru"
        defer { model.stop() }
        model.setVoiceOverForCurrentVideo(true)
        #expect(await eventually { if case .failed = model.voiceOver.state { true } else { false } })
        #expect(await vot.uploads == ["online-id"])
        #expect(OfflineDecisionURLProtocol.log.count == 3)  // Source upload, then language recovery after refusal.
    }

    @Test("An online translation with no audio URLs does not acquire extra VISIONOS metadata")
    func onlineSourceResolutionIsUnchanged() async {
        let (api, _) = api()
        let vot = OfflineVOTProbe([.audioRequested, .failed])
        let controller = VoiceOverTranslationController(api: api, client: vot)
        defer { controller.stop() }
        controller.start(
            .init(
                videoId: "online-id", duration: 60, sourceLanguage: "auto", targetLanguage: "ru",
                livelyVoiceToken: nil, originalAudioURL: nil, originalAudioHLSURL: nil,
                originalAudioUserAgent: InnerTubeClients.iOS.userAgent),
            mainPlayer: AVPlayer(), setVideoPlaying: { _ in })
        #expect(await eventually { if case .failed = controller.state { true } else { false } })
        #expect(await vot.uploads == ["online-id"])
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
    }

    @Test("MP3 drift recovery is spaced and bounded, while explicit jumps still align")
    func boundedVoiceDrift() {
        var correction = VoiceOverDriftCorrection()
        let start = ContinuousClock.now
        #expect(!Bool(correction.shouldSeek(drift: 0, explicitlyRequested: true, now: start)))
        #expect(!Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: start + .seconds(9))))
        #expect(!Bool(correction.shouldSeek(drift: 1.4, explicitlyRequested: false, now: start + .seconds(10))))
        for seconds in [10, 20, 30] {
            #expect(Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: start + .seconds(seconds))))
            #expect(
                !Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: start + .seconds(seconds + 1))))
        }
        #expect(!Bool(correction.shouldSeek(drift: 5, explicitlyRequested: false, now: start + .seconds(60))))
        #expect(Bool(correction.shouldSeek(drift: 5, explicitlyRequested: true, now: start + .seconds(61))))
        #expect(!Bool(correction.shouldSeek(drift: 5, explicitlyRequested: false, now: start + .seconds(90))))
        correction = VoiceOverDriftCorrection()
        #expect(Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: start + .seconds(100))))
    }

    @Test("Local preparation does not make translation downloads yield to a network player")
    func localPlaybackDoesNotReserveNetwork() {
        let (api, _) = api()
        let model = PlaybackViewModel(api: api)
        let demand = PlaybackDemandCoordinator(waitForRecovery: {}, waitForBudget: {})
        model.playbackDemand = PlaybackDemandAdapter(coordinator: demand)
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        model.currentVideo = video()
        #expect(model.hasAudioOptions)
        model.beginPlaybackAudioSession()
        model.isLoading = true
        #expect(!demand.isYielding)
        model.currentVideo?.localFileURL = nil
        #expect(demand.isYielding)
        model.stop()
    }

    @Test("Saved translation errors belong to the current video and leave its audio alone")
    func missingTranslationHasVisibleStatus() {
        let controller = VoiceOverTranslationController(localFileAllowed: { _ in true })
        let player = AVPlayer()
        var changes: [Bool] = []
        controller.startLocal(
            url: URL(fileURLWithPath: "/missing/translation.mp3"), videoID: "local", mainPlayer: player,
            setVideoPlaying: { changes.append($0) })
        #expect(controller.videoId == "local")
        if case .failed = controller.state {} else { Issue.record("Expected a visible translation failure") }
        #expect(changes.isEmpty)
        #expect(player.volume == 1)
        controller.stop()
    }

    @Test("Reopening a parked local item restores its selected translation")
    func parkedItemRestoresTranslation() async throws {
        let (api, _) = api()
        let url = try voiceFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = PlaybackViewModel(api: api)
        let vot = OfflineVOTProbe()
        model.voiceOver = VoiceOverTranslationController(client: vot, localFileAllowed: { $0 == url })
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        var saved = video()
        saved.localTranslationFileURL = url
        model.currentVideo = saved
        model.isIncognito = true
        let item = OfflineReadyItem(asset: AVMutableComposition())
        model.player.replaceCurrentItem(with: item)
        model.parkedVideoId = saved.id
        defer { model.stop() }
        model.load(video: saved, incognito: true)
        await model.audioPlaybackTask?.value
        #expect(model.player.currentItem === item)
        #expect(model.parkedVideoId == nil)
        #expect(model.voiceOver.state == .playing(livelyVoice: false))
        #expect(await vot.requests.isEmpty)
    }

    @Test("Offline jobs wait for a complete track and do not re-upload on every poll")
    func savedTranslationResolution() async throws {
        let (api, _) = api()
        let vot = OfflineVOTProbe([.audioRequested, .audioRequested, .partContent, .finished])
        let resolver = OfflineSourceResolver(api: api, vot: vot)
        let track = OfflineTrack.translation("ru")
        let attempt = UUID()
        for _ in 0..<3 {
            await #expect(throws: OfflineResolutionDeferred.self) {
                try await resolver.resolve(video: video(), track: track, attempt: attempt)
            }
        }
        let resolved = try await resolver.resolve(video: video(), track: track, attempt: attempt)
        #expect(resolved.track == track)
        #expect(resolved.url.absoluteString == "https://example.invalid/translation.mp3")
        #expect(await vot.uploads == ["online-id"])
        #expect(await vot.requests.count == 4)
        #expect(await vot.requests.allSatisfy { $0.videoID == "online-id" && !$0.lively })
        #expect(await vot.requests.allSatisfy { $0.sourceLanguage == "en" })
        #expect(OfflineDecisionURLProtocol.log.count == 5)  // visitor_id and fresh source metadata for each poll.
    }

    @Test("Repeated AUDIO_REQUESTED re-uploads once, then fails visibly; an explicit retry can start again")
    func translationUploadHasBoundedRetries() async throws {
        let (api, _) = api()
        let vot = OfflineVOTProbe(Array(repeating: .audioRequested, count: 8))
        let resolver = OfflineSourceResolver(api: api, vot: vot)
        let track = OfflineTrack.translation("ru")
        let attempt = UUID()
        for poll in 1...6 {
            await #expect(throws: OfflineResolutionDeferred.self) {
                try await resolver.resolve(video: video(), track: track, attempt: attempt)
            }
            #expect(await vot.uploads.count == (poll < 4 ? 1 : 2))
        }
        await #expect(throws: OfflineTranslationUploadError.self) {
            try await resolver.resolve(video: video(), track: track, attempt: attempt)
        }
        #expect(await vot.uploads.count == 2)
        #expect(!OfflineTranslationUploadError().localizedDescription.isEmpty)
        await #expect(throws: OfflineResolutionDeferred.self) {
            try await resolver.resolve(video: video(), track: track, attempt: UUID())
        }
        #expect(await vot.uploads.count == 3)
    }

    @Test(
        "Cancelled and removed translation jobs cannot consume a replacement's upload budget", arguments: [false, true])
    func translationUploadBelongsToJobAttempt(removed: Bool) async throws {
        let (api, _) = api()
        let vot = OfflineVOTProbe(Array(repeating: .audioRequested, count: 6))
        let resolver = OfflineSourceResolver(api: api, vot: vot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineLibraryStore(directory: directory)
        let track = OfflineTrack.translation("ru")
        let original = try #require(try await store.enqueue(video: video(), tracks: [track]).jobs.first)
        for _ in 0..<4 {
            await #expect(throws: OfflineResolutionDeferred.self) {
                try await resolver.resolve(video: video(), track: track, attempt: original.attempt)
            }
        }
        #expect(await vot.uploads.count == 2)
        let replacement: OfflineJob
        if removed {
            try await store.beginRemoval(videoID: original.videoID)
            try await store.completeRemovals()
            replacement = try #require(try await store.enqueue(video: video(), tracks: [track]).jobs.first)
        } else {
            try await store.update(attempt: original.attempt, state: .cancelled)
            replacement = try #require(try await store.retry(id: original.id).jobs.first)
        }
        #expect(replacement.attempt != original.attempt)
        for _ in 0..<2 {
            await #expect(throws: OfflineResolutionDeferred.self) {
                try await resolver.resolve(video: video(), track: track, attempt: replacement.attempt)
            }
            #expect(await vot.uploads.count == 3)
        }
    }

}

#if os(iOS)
extension OfflinePlaybackDecisionTests {
    @Test("Offline lock-screen metadata clears online artwork and its in-flight identity")
    func localArtworkDoesNotUseNetwork() {
        let (api, _) = api()
        let model = PlaybackViewModel(api: api)
        var saved = video()
        saved.thumbnailURL = URL(string: "https://example.invalid/thumbnail.jpg")
        model.currentVideo = saved
        model.cachedArtwork = UIImage()
        model.cachedArtworkVideoID = saved.id
        defer { model.stop() }
        model.updateNowPlayingInfo()
        #expect(model.cachedArtwork == nil)
        #expect(model.cachedArtworkVideoID == nil)
        #expect(model.nowPlayingInfoCache[MPMediaItemPropertyArtwork] == nil)
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
    }

    @Test("Repeated expansion leaves the current cover's channel-navigation dismissal valid")
    func repeatedExpandKeepsDismissal() {
        let (api, _) = api()
        let state = PlayerStateStore(api: api)
        defer { state.stop() }
        state.expand()
        let request = state.fullScreenRequestID
        state.expand()
        #expect(state.fullScreenRequestID == request)
        state.fullScreenCoverDismissed(requestID: request)
        #expect(state.presentation == .miniPlayer)
    }

    @Test("A late PiP start cannot minimize an offline open; a current PiP start still can")
    func latePiPStartAfterOfflineOpen() {
        let (api, _) = api()
        let state = PlayerStateStore(api: api)
        state.vm.offlineMedia = LocalMediaProbe()
        state.vm.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        let router = PlayerRouter(playerState: state, settingsStore: SettingsStore())
        defer { state.stop() }
        state.expand()
        state.pictureInPictureWillStart()
        state.minimize(reason: "test-leave-old-cover")
        router.open(video: video(), api: api, incognito: true)
        state.pictureInPictureChanged(active: true)
        #expect(state.presentation == .fullScreen)
        state.pictureInPictureChanged(active: false)
        #expect(state.presentation == .fullScreen)
        state.pictureInPictureWillStart()
        state.pictureInPictureChanged(active: true)
        #expect(state.presentation == .pictureInPicture)
        state.pictureInPictureChanged(active: false)
        #expect(state.presentation == .miniPlayer)
    }

    @Test("Picking the same saved item again reapplies the library translation without reloading video")
    func reselectingSavedTrack() throws {
        let (api, _) = api()
        let url = try voiceFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = PlayerStateStore(api: api)
        state.vm.voiceOver = VoiceOverTranslationController(localFileAllowed: { $0 == url })
        var saved = video()
        saved.localTranslationFileURL = url
        saved.localTranslationLanguage = "ru"
        state.vm.currentVideo = saved
        state.vm.isIncognito = true
        state.vm.voiceOverOverride = false
        let item = OfflineReadyItem(asset: AVMutableComposition())
        state.vm.player.replaceCurrentItem(with: item)
        state.vm.isPlaying = true
        var settings = AppSettings()
        settings.preferredAudioLanguage = "de"
        defer { state.stop() }
        state.play(video: saved, settings: settings, incognito: true)
        #expect(state.vm.player.currentItem === item)
        #expect(state.vm.voiceOverOverride == nil)
        #expect(state.vm.voiceOver.state == .playing(livelyVoice: false))
        #expect(state.vm.voiceOverTargetLanguage == "ru")
        #expect(state.presentation == .fullScreen)
    }

    @Test("Opening offline always expands; an older cover cannot collapse that request", arguments: [false, true])
    func offlinePresentation(parked: Bool) {
        let (api, _) = api()
        let state = PlayerStateStore(api: api)
        state.vm.offlineMedia = LocalMediaProbe()
        state.vm.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        state.expand()
        let oldRequest = state.fullScreenRequestID
        state.minimize(reason: "test-offline-open")
        if parked {
            state.vm.currentVideo = video()
            state.vm.parkedVideoId = video().id
            state.vm.voiceOverOverride = true
        }
        let router = PlayerRouter(playerState: state, settingsStore: SettingsStore())
        defer { state.stop() }
        router.open(video: video(), api: api, incognito: true)
        #expect(state.presentation == .fullScreen)
        #expect(state.currentVideo?.isDownloaded == true)
        #expect(state.vm.voiceOverOverride == nil)
        state.fullScreenCoverDismissed(requestID: oldRequest)
        #expect(state.presentation == .fullScreen)
        state.fullScreenCoverDismissed(requestID: state.fullScreenRequestID)
        #expect(state.presentation == .miniPlayer)
        state.stop()
        state.fullScreenCoverDismissed(requestID: state.fullScreenRequestID)
        #expect(state.presentation == .hidden)
    }
}
#endif
