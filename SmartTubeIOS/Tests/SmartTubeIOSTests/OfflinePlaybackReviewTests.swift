import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@MainActor
private final class OfflinePlaybackQueueProbe: PlaybackQueue {
    var successors: [Int: Video] = [:]
    var lookups: [Int] = []
    var holdNextLookup = false
    var heldLookup: CheckedContinuation<Void, Never>?

    func videoAt(index: Int) async -> Video? {
        lookups.append(index)
        let result = successors[index]
        if holdNextLookup {
            holdNextLookup = false
            await withCheckedContinuation { heldLookup = $0 }
        }
        return result
    }

    func release() {
        let continuation = heldLookup
        heldLookup = nil
        continuation?.resume()
    }

    func remainingVideos(after index: Int) -> [Video] { [] }
    func clear() {}
}

// Extends the serialized suite that owns OfflineDecisionURLProtocol.log.
extension OfflinePlaybackDecisionTests {
    @Test("Local Next requires a queue successor and never starts online prefetch", arguments: [false, true])
    func localQueueKeepsNext(hasSuccessor: Bool) async {
        let (api, _) = api()
        let model = PlaybackViewModel(api: api)
        let queue = OfflinePlaybackQueueProbe()
        if hasSuccessor { queue.successors[1] = video() }
        model.queue = queue
        let media = LocalMediaProbe()
        model.offlineMedia = media
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        model.hasNext = true
        var saved = video()
        saved.playlistId = CurrentQueueStore.playlistID
        saved.playlistIndex = 0
        defer { model.stop() }
        model.load(video: saved, incognito: true)
        #expect(!model.hasNext)
        await model.loadTask?.value
        #expect(await eventually { model.player.currentItem === media.prepared && !model.isLoading })
        #expect(model.hasNext == hasSuccessor)
        #expect(queue.lookups == [1])
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
        #expect(model.prefetchTask == nil)
    }

    @Test("Local loading reads the current queue position after audio activation", arguments: [false, true])
    func localQueueUsesCurrentPosition(hasSuccessor: Bool) async {
        let (api, _) = api()
        let model = PlaybackViewModel(api: api)
        let queue = OfflinePlaybackQueueProbe()
        if hasSuccessor { queue.successors[3] = video() }
        queue.successors[1] = video()
        model.queue = queue
        model.offlineMedia = LocalMediaProbe()
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        var saved = video()
        saved.playlistId = CurrentQueueStore.playlistID
        saved.playlistIndex = 0
        defer { model.stop() }
        model.load(video: saved, incognito: true)
        model.currentVideo?.playlistIndex = 2
        await model.loadTask?.value
        #expect(queue.lookups == [3])
        #expect(model.hasNext == hasSuccessor)
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
    }

    @Test("A suspended local Next lookup rechecks queue context without delaying item installation")
    func localQueueRechecksAfterLookup() async throws {
        let (api, _) = api()
        let model = PlaybackViewModel(api: api)
        let queue = OfflinePlaybackQueueProbe()
        queue.successors[1] = video()
        queue.holdNextLookup = true
        model.queue = queue
        let media = LocalMediaProbe()
        model.offlineMedia = media
        model.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        var saved = video()
        saved.playlistId = CurrentQueueStore.playlistID
        saved.playlistIndex = 0
        defer {
            queue.release()
            model.stop()
        }
        model.load(video: saved, incognito: true)
        try #require(await eventually { queue.heldLookup != nil && model.player.currentItem === media.prepared })
        #expect(!model.hasNext)
        model.currentVideo?.playlistIndex = 2
        queue.release()
        await model.loadTask?.value
        #expect(queue.lookups == [1, 3])
        #expect(!model.hasNext)
        #expect(OfflineDecisionURLProtocol.log.isEmpty)
    }

    @Test("Pause/resume aligns once even after the automatic MP3 correction budget is exhausted")
    func voiceResumeAlignment() {
        var correction = VoiceOverDriftCorrection()
        let start = ContinuousClock.now
        for index in 0..<PlaybackTuning.voiceDriftCorrectionLimit {
            #expect(
                Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: start + .seconds(index * 20))))
        }
        let resumeTime = start + .seconds(100)
        #expect(!Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: resumeTime)))
        correction.playbackChanged(isPlaying: false)
        correction.playbackChanged(isPlaying: true)
        #expect(Bool(correction.shouldSeek(drift: 0.75, explicitlyRequested: false, now: resumeTime)))
        for _ in 0..<5 {
            correction.playbackChanged(isPlaying: true)
            #expect(!Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: resumeTime + .seconds(1))))
        }
        correction.playbackChanged(isPlaying: false)
        correction.playbackChanged(isPlaying: true)
        #expect(Bool(correction.shouldSeek(drift: 0.75, explicitlyRequested: false, now: resumeTime + .seconds(2))))
        #expect(!Bool(correction.shouldSeek(drift: 2, explicitlyRequested: false, now: resumeTime + .seconds(30))))
    }
}

#if os(iOS)
extension OfflinePlaybackDecisionTests {
    @Test("Stopping an unfinished PiP restore releases its completion and allows PiP again", arguments: [false, true])
    func pipStopClearsUnfinishedRestore(downloaded: Bool) {
        let (api, _) = api()
        let state = PlayerStateStore(api: api)
        var current = video()
        if !downloaded { current.localFileURL = nil }
        state.vm.currentVideo = current
        defer { state.stop() }
        state.expand()
        state.pictureInPictureWillStart()
        state.pictureInPictureChanged(active: true)
        var completions: [Bool] = []
        state.restorePictureInPicture { completions.append($0) }
        #expect(state.pipRestoreCompletion != nil)
        #expect(completions.isEmpty)
        state.pictureInPictureChanged(active: false)
        #expect(state.pipRestoreCompletion == nil)
        #expect(completions == [false])
        state.pictureInPictureChanged(active: false)
        #expect(completions == [false])
        state.pictureInPictureWillStart()
        state.pictureInPictureChanged(active: true)
        #expect(state.presentation == .pictureInPicture)
    }
}
#endif
