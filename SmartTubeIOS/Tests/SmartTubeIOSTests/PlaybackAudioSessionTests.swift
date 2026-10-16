import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// NSLock protects the event log and one-shot hook used by the synchronous fake driver.
private final class AudioSessionDriverProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var mainThreadCalls = 0
    private var activationHook: (@Sendable () -> Void)?

    var driver: PlaybackAudioSession.Driver {
        .init(configure: { self.record("configure") }, setActive: { self.setActive($0) })
    }

    var snapshot: [String] { lock.withLock { events } }
    var calledOnMain: Bool { lock.withLock { mainThreadCalls > 0 } }

    func onNextActivation(_ hook: @escaping @Sendable () -> Void) {
        lock.withLock { activationHook = hook }
    }

    private func record(_ event: String) {
        lock.withLock {
            events.append(event)
            if Thread.isMainThread { mainThreadCalls += 1 }
        }
    }

    private func setActive(_ active: Bool) {
        record(active ? "activate" : "deactivate")
        if active {
            let hook = lock.withLock {
                let hook = activationHook
                activationHook = nil
                return hook
            }
            hook?()
        }
    }
}

@Suite("Serialized playback audio session (PLAN-0011)")
struct PlaybackAudioSessionTests {
    @Test @MainActor func deferredConfigurationAndOffMainOrdering() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        #expect(probe.snapshot.isEmpty)
        let id = session.begin()
        #expect(try await session.activate(id))
        #expect(try await session.activate(id))
        #expect(probe.snapshot == ["configure", "activate"])
        #expect(try await session.activate(id, force: true))
        session.invalidate(id)
        await session.release(id)
        #expect(probe.snapshot == ["configure", "activate", "activate", "deactivate"])
        #expect(!probe.calledOnMain)
    }

    @Test func delayedOldStopAndActivationCannotAffectNewOwner() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        let old = session.begin()
        #expect(try await session.activate(old))
        session.invalidate(old)
        let new = session.begin()
        #expect(try await session.activate(new))
        await session.release(old)
        #expect(try await session.activate(old) == false)
        #expect(session.isCurrent(new))
        #expect(probe.snapshot == ["configure", "activate", "activate"])
        await session.release(new)
    }

    @Test func cancelledBeforeNativeCallDoesNotConfigure() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        let id = session.begin()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.activate(id)
        }
        #expect(try await task.value == false)
        #expect(probe.snapshot.isEmpty)
    }

    @Test func stoppedReplacementBeforeActivationReleasesPreviousNativeOwner() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        let old = session.begin()
        #expect(try await session.activate(old))
        let replacement = session.begin()
        session.invalidate(replacement)
        await session.release(replacement)
        #expect(probe.snapshot == ["configure", "activate", "deactivate"])
    }

    @Test func cancellationDuringNativeActivationReleasesBeforeReplacement() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        let old = session.begin()
        probe.onNextActivation {
            withUnsafeCurrentTask { $0?.cancel() }
            session.invalidate(old)
        }
        let task = Task { try await session.activate(old) }
        #expect(try await task.value == false)
        let new = session.begin()
        #expect(try await session.activate(new))
        #expect(probe.snapshot == ["configure", "activate", "deactivate", "activate"])
        await session.release(old)
        #expect(probe.snapshot.last == "activate")
        await session.release(new)
    }

    @Test @MainActor func stoppedPendingActivationCannotResumeSameVideo() async throws {
        let probe = AudioSessionDriverProbe()
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: probe.driver)
        vm.currentVideo = Video(id: "same", title: "Same", channelTitle: "Test")
        vm.isIncognito = true
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.requestAudioPlayback()
        let old = try #require(vm.audioPlaybackTask)
        #expect(!vm.isPlaying)
        vm.stop()
        let release = vm.audioPlaybackTask
        await old.value
        await release?.value
        #expect(!vm.isPlaying)
        #expect(vm.player.rate == 0)
        #expect(probe.snapshot.isEmpty)
        vm.togglePlayPause()
        await vm.audioPlaybackTask?.value
        #expect(vm.isPlaying)
        vm.stop()
        await vm.audioPlaybackTask?.value
    }

    @Test @MainActor func pauseCancelsPendingResume() async throws {
        let probe = AudioSessionDriverProbe()
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: probe.driver)
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.requestAudioPlayback()
        let task = try #require(vm.audioPlaybackTask)
        vm.togglePlayPause()
        await task.value
        #expect(!vm.isPlaying)
        #expect(vm.player.rate == 0)
        #expect(probe.snapshot.isEmpty)
    }

    @Test @MainActor func cancellationInsideNativeDriverCannotStartPlayer() async {
        let probe = AudioSessionDriverProbe()
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: probe.driver)
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        probe.onNextActivation { withUnsafeCurrentTask { $0?.cancel() } }
        vm.requestAudioPlayback()
        await vm.audioPlaybackTask?.value
        #expect(!vm.isPlaying)
        #expect(vm.player.rate == 0)
        #expect(probe.snapshot == ["configure", "activate", "deactivate"])
        vm.stop()
        await vm.audioPlaybackTask?.value
    }

    @Test func replacementIntentDuringNativeCallRejectsStaleCompletion() async throws {
        let probe = AudioSessionDriverProbe()
        let session = PlaybackAudioSession(driver: probe.driver)
        let old = session.begin()
        probe.onNextActivation { _ = session.begin() }
        #expect(try await session.activate(old) == false)
        #expect(probe.snapshot == ["configure", "activate", "deactivate"])
        let latest = session.begin()
        #expect(try await session.activate(latest))
        await session.release(old)
        #expect(probe.snapshot.last == "activate")
        await session.release(latest)
    }

    @Test @MainActor func nativeFailureDoesNotPlayOrLeaveLoadingSpinner() async {
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(
            driver: .init(configure: {}, setActive: { _ in throw CocoaError(.featureUnsupported) }))
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.isLoading = true
        vm.requestAudioPlayback()
        await vm.audioPlaybackTask?.value
        #expect(vm.error != nil)
        #expect(!vm.isLoading)
        #expect(!vm.isPlaying)
        #expect(vm.audioPlaybackTask == nil)
    }

    @Test @MainActor func voiceOverCannotBypassPendingActivationOrSuspension() async {
        let probe = AudioSessionDriverProbe()
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: probe.driver)
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.requestAudioPlayback()
        vm.setPlayingForVoiceOver(true)
        #expect(!vm.isPlaying)
        #expect(vm.player.rate == 0)
        await vm.audioPlaybackTask?.value
        #expect(vm.isPlaying)
        vm.suspend()
        vm.setPlayingForVoiceOver(true)
        #expect(!vm.isPlaying)
        #expect(vm.player.rate == 0)
        vm.stop()
        await vm.audioPlaybackTask?.value
    }

    @Test @MainActor func sameIntentItemReplacementPlaysAfterPendingActivation() async {
        let probe = AudioSessionDriverProbe()
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: probe.driver)
        let video = Video(id: "replacement", title: "Replacement", channelTitle: "Test")
        vm.currentVideo = video
        vm.isIncognito = true
        vm.duration = 1
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.requestAudioPlayback()
        let replacement = AVPlayerItem(asset: AVMutableComposition())
        vm.player.replaceCurrentItem(with: replacement)
        vm.isLoading = true
        let info = PlayerInfo(
            video: video, formats: [], hlsURL: URL(fileURLWithPath: "/dev/null"), dashURL: nil,
            captionTracks: [], trackingURLs: nil, endCards: [])
        vm.attemptItemBecameReady(replacement, video: video, info: info, label: "test", isMuxedFallback: false)
        vm.phase2Task?.cancel()  // Cancel before yielding; the ready callback must not reach the network.
        #expect(!vm.isLoading)
        #expect(vm.lastSuccessfulStreamType == "test")
        #expect(!vm.canResumeInAudioSession)
        #expect(!vm.isPlaying)
        await vm.audioPlaybackTask?.value
        #expect(vm.player.currentItem === replacement)
        #expect(vm.isPlaying)
        #expect(vm.canResumeInAudioSession)
        vm.stop()
        await vm.audioPlaybackTask?.value
    }
}
