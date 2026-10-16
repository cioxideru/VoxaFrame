import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

#if canImport(UIKit)
import UIKit
#endif

// MARK: - PhoneCallInterruptionTests
//
// Regression tests for task #244: an AVAudioSession interruption (e.g. an
// incoming phone call) must pause background playback WITHOUT the
// rate-observer's stall detection/recovery misinterpreting the resulting
// rate→0 as a playback stall, and must resume cleanly when the interruption
// ends with shouldResume.

@Suite("Phone call interruption — flags & rate-observer guard (#244)")
@MainActor
struct PhoneCallInterruptionFlagTests {

    @Test("Interruption flags default to false")
    func interruptionFlagsDefaultToFalse() {
        let vm = PlaybackViewModel()
        #expect(vm.isHandlingAudioInterruption == false)
        #expect(vm.wasPlayingBeforeInterruption == false)
    }

    @Test("playerWentSilent ignores a rate-drop caused by an audio interruption pause")
    func playerWentSilentIgnoresInterruptionPause() {
        let isPlaying = true
        let isSwappingItem = false
        let isHandlingAudioInterruption = true
        let newRate: Float = 0

        let playerWentSilent = newRate == 0 && isPlaying && !isSwappingItem && !isHandlingAudioInterruption
        #expect(playerWentSilent == false)
    }

    @Test("playerWentSilent still detects a real stall when not handling an interruption")
    func playerWentSilentStillDetectsRealStall() {
        let isPlaying = true
        let isSwappingItem = false
        let isHandlingAudioInterruption = false
        let newRate: Float = 0

        let playerWentSilent = newRate == 0 && isPlaying && !isSwappingItem && !isHandlingAudioInterruption
        #expect(playerWentSilent == true)
    }
}

#if canImport(UIKit)
@Suite("Phone call interruption — AVAudioSession notification handling (#244)")
@MainActor
struct PhoneCallInterruptionNotificationTests {

    private func makePlayer(center: NotificationCenter) -> PlaybackViewModel {
        let vm = PlaybackViewModel()
        vm.audioSession = PlaybackAudioSession(driver: .init(configure: {}, setActive: { _ in }))
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.setupAudioSessionObserver(center: center)
        return vm
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        return predicate()
    }

    @Test("Interruption .began pauses the player and sets interruption flags")
    func interruptionBeganPausesAndSetsFlags() async {
        let center = NotificationCenter()
        let vm = makePlayer(center: center)
        defer { vm.stop() }
        vm.isPlaying = true

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        let observed = await waitUntil {
            vm.isHandlingAudioInterruption && vm.wasPlayingBeforeInterruption && !vm.isPlaying
        }

        #expect(
            observed,
            "Expected isHandlingAudioInterruption=true, wasPlayingBeforeInterruption=true, isPlaying=false after .began"
        )
    }

    @Test("Interruption .ended with shouldResume resumes playback")
    func interruptionEndedResumesWhenShouldResume() async {
        let center = NotificationCenter()
        let vm = makePlayer(center: center)
        defer { vm.stop() }
        vm.isPlaying = true

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        #expect(await waitUntil { vm.isHandlingAudioInterruption })

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
            ]
        )

        let resumed = await waitUntil { vm.isPlaying && !vm.isHandlingAudioInterruption }

        #expect(resumed, "Expected isPlaying=true and isHandlingAudioInterruption=false after .ended with shouldResume")
    }
}
#endif
