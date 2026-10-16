import AVFoundation
import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

#if canImport(WebKit)
import WebKit
#endif

@MainActor
private final class IdleGate {
    var waits: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { waits.append($0) } }
    func fire() { waits.removeFirst().resume() }
    func drain() { while !waits.isEmpty { fire() } }
}

@MainActor
private func eventually(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    #expect(predicate())
    try #require(predicate())
}

@Suite("Idle resource retention")
@MainActor
struct IdleResourceCleanupTests {
    @Test func cancelledTimerCannotReleaseNewLease() async throws {
        let gate = IdleGate()
        let cleanup = IdleResourceCleanup(wait: { await gate.wait() })
        var releases = 0
        cleanup.schedule { releases += 1 }
        try await eventually { gate.waits.count == 1 }
        cleanup.beginUse()
        cleanup.releaseNow()
        #expect(releases == 0)
        cleanup.endUse { releases += 10 }
        try await eventually { gate.waits.count == 2 }
        gate.fire()
        await Task.yield()
        #expect(releases == 0)
        gate.fire()
        try await eventually { releases == 10 }
    }

    @Test func pressureAndTimerDoNotRetainOwner() async throws {
        let gate = IdleGate()
        let name = Notification.Name(UUID().uuidString)
        var cleanup: IdleResourceCleanup? = IdleResourceCleanup(pressureNotification: name, wait: { await gate.wait() })
        weak var reference = cleanup
        var released = false
        cleanup?.schedule { released = true }
        try await eventually { gate.waits.count == 1 }
        NotificationCenter.default.post(name: name, object: nil)
        try await eventually { released }
        cleanup?.schedule {}
        try await eventually { gate.waits.count == 2 }
        cleanup = nil
        #expect(reference == nil)
        gate.drain()
    }

    @Test(arguments: [false, true])
    func parkedItemReleasedWithoutClearingStoppedMarker(pressure: Bool) async throws {
        let gate = IdleGate()
        let vm = PlaybackViewModel()
        vm.parkedResourceCleanup = IdleResourceCleanup(wait: { await gate.wait() })
        vm.currentVideo = Video(id: "parked", title: "Parked", channelTitle: "Test")
        vm.isIncognito = true
        vm.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        vm.stop()
        #expect(vm.player.currentItem != nil)
        try await eventually { gate.waits.count == 1 }
        if pressure { vm.parkedResourceCleanup.releaseNow() } else { gate.fire() }
        try await eventually { vm.player.currentItem == nil }
        #expect(vm.parkedVideoId == "parked")
        vm.togglePlayPause()
        vm.resume()
        #expect(!vm.isPlaying)
        #expect(vm.parkedVideoId == "parked")
        vm.load(video: try #require(vm.currentVideo), incognito: true)
        let load = try #require(vm.loadTask)
        load.cancel()  // Cancel before the first yield, so the real load cannot reach the network.
        #expect(vm.isLoading)
        #expect(vm.parkedVideoId == nil)
        #expect(vm.player.currentItem == nil)
        await load.value
        gate.drain()
    }

    @Test func reopeningCancelsOldCleanup() async throws {
        let gate = IdleGate()
        let vm = PlaybackViewModel()
        vm.parkedResourceCleanup = IdleResourceCleanup(wait: { await gate.wait() })
        vm.currentVideo = Video(id: "parked", title: "Parked", channelTitle: "Test")
        vm.isIncognito = true
        let item = AVPlayerItem(asset: AVMutableComposition())
        vm.player.replaceCurrentItem(with: item)
        vm.stop()
        try await eventually { gate.waits.count == 1 }
        vm.togglePlayPause()
        gate.fire()
        await Task.yield()
        vm.parkedResourceCleanup.releaseNow()
        #expect(vm.player.currentItem === item)
        #expect(vm.parkedVideoId == nil)
        vm.player.pause()
    }

    @Test(arguments: ["paused", "suspended", "active"])
    func nonStoppedSessionSurvivesPressure(state: String) {
        let vm = PlaybackViewModel()
        let item = AVPlayerItem(asset: AVMutableComposition())
        vm.player.replaceCurrentItem(with: item)
        vm.isPlaying = state != "paused"
        if state == "suspended" { vm.suspend() }
        vm.parkedResourceCleanup.releaseNow()
        #expect(vm.player.currentItem === item)
        #expect(vm.parkedVideoId == nil)
        vm.player.pause()
    }

    @Test func stopCancelsQualityWork() async throws {
        let vm = PlaybackViewModel()
        let task = Task { @MainActor in #expect(Task.isCancelled) }
        vm.qualityManager.qualityTask = task
        vm.stop()
        #expect(task.isCancelled)
        #expect(vm.qualityManager.qualityTask == nil)
        await task.value
    }

    @Test func cleanupDoesNotKeepViewModelAlive() async throws {
        let gate = IdleGate()
        var vm: PlaybackViewModel? = PlaybackViewModel()
        weak var reference = vm
        vm?.parkedResourceCleanup = IdleResourceCleanup(wait: { await gate.wait() })
        vm?.stop()
        try await eventually { gate.waits.count == 1 }
        vm = nil
        #expect(reference == nil)
        gate.drain()
    }

    #if canImport(WebKit)
    @Test func extractionProtectsActiveViewAndCanRestartAfterRelease() async throws {
        let gate = IdleGate()
        let extractor = YouTubeWebViewHLSExtractor()
        extractor.idleCleanup = IdleResourceCleanup(wait: { await gate.wait() })
        weak var view: WKWebView?
        extractor.loadRequest = { webView, _ in view = webView }
        for cycle in 0..<2 {
            let task = Task { await extractor.extractHLSURL(videoId: "idle-test") }
            try await eventually { view != nil && extractor.currentExtractionVideoId != nil }
            extractor.idleCleanup.releaseNow()
            #expect(view != nil)
            extractor.cancelCurrentExtraction(for: "idle-test")
            #expect(await task.value == nil)
            try await eventually { gate.waits.count == 1 }
            if cycle == 0 { gate.fire() } else { extractor.idleCleanup.releaseNow() }
            try await eventually { view == nil }
            gate.drain()
        }
    }

    @Test func releasedWebViewCallbacksCannotFinishNewExtraction() async throws {
        let extractor = YouTubeWebViewHLSExtractor()
        var capturedView: WKWebView?
        extractor.loadRequest = { webView, _ in capturedView = webView }
        let first = Task { await extractor.extractHLSURL(videoId: "first") }
        try await eventually { capturedView != nil }
        let oldView = try #require(capturedView)
        extractor.cancelCurrentExtraction(for: "first")
        _ = await first.value
        extractor.idleCleanup.releaseNow()
        capturedView = nil
        let next = Task { await extractor.extractHLSURL(videoId: "next") }
        try await eventually { capturedView != nil }
        #expect(capturedView !== oldView)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        extractor.webView(oldView, didFail: nil, withError: error)
        extractor.webView(oldView, didFailProvisionalNavigation: nil, withError: error)
        #expect(extractor.currentExtractionVideoId == "next")
        extractor.cancelCurrentExtraction(for: "next")
        _ = await next.value
        extractor.idleCleanup.releaseNow()
    }

    @Test func extractionResultSurvivesPressureUntilNextRequest() async throws {
        let extractor = YouTubeWebViewHLSExtractor()
        extractor.loadRequest = { _, _ in }
        let url = URL(string: "https://example.com/manifest.m3u8")!
        let task = Task { await extractor.extractHLSURL(videoId: "result") }
        try await eventually { extractor.currentExtractionVideoId == "result" }
        extractor.finishWithURL(url, poToken: "fake-result-token")
        #expect(await task.value == url)
        extractor.idleCleanup.releaseNow()
        #expect(extractor.extractedPoToken == "fake-result-token")
        let next = Task { await extractor.extractHLSURL(videoId: "next") }
        try await eventually { extractor.currentExtractionVideoId == "next" }
        #expect(extractor.extractedPoToken == nil)
        extractor.cancelCurrentExtraction(for: "next")
        _ = await next.value
        extractor.idleCleanup.releaseNow()
    }

    @Test func preparationAndWaitingCallersProtectView() async throws {
        let gate = IdleGate()
        let preparation = IdleGate()
        let runner = BotGuardWebViewRunner()
        runner.idleCleanup = IdleResourceCleanup(wait: { await gate.wait() })
        weak var view: WKWebView?
        runner.loadRequest = { webView, _ in view = webView }
        for _ in 0..<2 {
            var attempt: UUID?
            let task = Task {
                await runner.prepare {
                    let result = await runner.runPreparation { id in
                        attempt = id
                        runner.launchWebView(attemptID: id)
                    }
                    // Models the cookie propagation await after prepareCont is already nil.
                    await preparation.wait()
                    return result
                }
            }
            try await eventually { attempt != nil && view != nil }
            let joiner = Task {
                await runner.prepare {
                    Issue.record("joined preparation must not restart")
                    return result()
                }
            }
            try await eventually { runner.prepareWaiters.count == 2 }
            runner.idleCleanup.releaseNow()
            #expect(view != nil)
            runner.finishPreparation(attemptID: try #require(attempt), result: result())
            try await eventually { preparation.waits.count == 1 }
            runner.idleCleanup.releaseNow()
            #expect(view != nil)
            preparation.fire()
            _ = await task.value
            _ = await joiner.value
            try await eventually { gate.waits.count == 1 }
            #expect(runner.webVisitorData == "fake-visitor")
            runner.idleCleanup.releaseNow()
            try await eventually { view == nil }
            #expect(runner.webVisitorData == "fake-visitor")
            #expect(!runner.isReady)
            gate.drain()
        }
    }

    private func result() -> BotGuardWebViewRunner.PrepareResult {
        .init(hasMinter: false, websafeToken: nil, ttl: 60, integrityTokenLen: 0, webVisitorData: "fake-visitor")
    }
    #endif
}
