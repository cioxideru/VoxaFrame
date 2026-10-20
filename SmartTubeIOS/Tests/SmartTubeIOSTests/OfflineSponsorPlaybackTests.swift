import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

/// Counts every request made through the test session; saved-video playback must make none.
private final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    // Written by the session's callbacks, read by the serialized suite after each await.
    nonisolated(unsafe) static var requests = 0
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Holds its answer until `release()`, to change settings while a lookup is in flight.
@MainActor private final class SuspendedSegments: OfflineSponsorSegmentProviding {
    let value: OfflineSponsorSegments?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var lookups = 0
    init(_ value: OfflineSponsorSegments?) { self.value = value }
    func sponsorSegmentsForPlayback(videoID: String) async -> OfflineSponsorSegments? {
        lookups += 1
        await withCheckedContinuation { waiter = $0 }
        return value
    }
    func release() {
        waiter?.resume()
        waiter = nil
    }
}

private struct StoredSegments: OfflineSponsorSegmentProviding {
    let value: OfflineSponsorSegments?
    // swiftlint:disable:next async_without_await
    func sponsorSegmentsForPlayback(videoID: String) async -> OfflineSponsorSegments? { value }
}

@MainActor @Suite("Offline SponsorBlock playback", .serialized)
struct OfflineSponsorPlaybackTests {
    private let stored = OfflineSponsorSegments(
        segments: [
            SponsorSegment(start: 1, end: 10, category: .sponsor),
            SponsorSegment(start: 20, end: 21, category: .intro),
            SponsorSegment(start: 30, end: 50, category: .outro),
        ], fetchedAt: Date(timeIntervalSince1970: 1))

    private func makeModel() -> PlaybackViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingURLProtocol.self]
        let session = URLSession(configuration: config)
        CountingURLProtocol.requests = 0
        let model = PlaybackViewModel(
            api: InnerTubeAPI(authToken: nil, session: session), sponsorBlock: SponsorBlockService(session: session),
            deArrow: DeArrowService(session: session), settings: AppSettings())
        model.offlineSponsor = StoredSegments(value: stored)
        return model
    }

    private func savedVideo() -> Video {
        var video = Video(id: "saved", title: "Saved", channelTitle: "C", channelId: "chan", duration: 100)
        video.localFileURL = URL(fileURLWithPath: "/saved/video.mp4")
        return video
    }

    @Test func repeatedLookupRequestsShareOneScheduledLookup() async {
        let model = makeModel()
        let source = SuspendedSegments(stored)
        model.offlineSponsor = source
        model.currentVideo = savedVideo()
        model.startOfflineSponsorLookupIfNeeded()
        model.reuseOfflineSponsorSegments()
        await waitForTasks { source.lookups > 0 }
        #expect(source.lookups == 1)
        source.release()
        await waitForTasks { !model.sponsorSegments.isEmpty }
        #expect(model.sponsorSegments.map(\.category) == [.sponsor, .intro])
    }

    @Test func lookupForAnOldVideoCannotClearTheCurrentSegments() async {
        let model = makeModel()
        let video = savedVideo()
        model.currentVideo = video
        await model.applyOfflineSponsorSegments(for: video)
        let segments = model.sponsorSegments
        var oldVideo = Video(id: "old", title: "Old", channelTitle: "C")
        oldVideo.localFileURL = URL(fileURLWithPath: "/old/video.mp4")
        await model.applyOfflineSponsorSegments(for: oldVideo)
        #expect(model.sponsorSegments == segments)
        #expect(model.offlineSponsorLookupID == video.id)
    }

    @Test func storedSegmentsFollowSettingsWithoutRequestsAndSurviveReuse() async {
        let model = makeModel()
        let video = savedVideo()
        model.currentVideo = video
        await model.applyOfflineSponsorSegments(for: video)
        // Defaults: sponsor skips, intro toasts, outro does nothing.
        #expect(model.sponsorSegments.map(\.category) == [.sponsor, .intro])
        #expect(model.checkSponsorSkip(at: 5))
        model.checkSponsorSkip(at: 20.5)
        #expect(model.currentToastSegment?.category == .intro)

        var settings = model.settings
        settings.sponsorBlockMinSegmentDuration = 2
        model.updateSettings(settings)
        #expect(model.sponsorSegments.map(\.category) == [.sponsor])

        settings.sponsorBlockActions[.outro] = .skip
        model.updateSettings(settings)
        #expect(model.sponsorSegments.map(\.category) == [.sponsor, .outro])

        settings.sponsorBlockExcludedChannels["chan"] = "C"
        model.updateSettings(settings)
        #expect(model.sponsorSegments.isEmpty)
        settings.sponsorBlockExcludedChannels = [:]

        // A parked item that comes back after settings changed while it was parked.
        settings.sponsorBlockActions[.outro] = .nothing
        model.settings = settings
        model.reuseOfflineSponsorSegments()
        #expect(model.sponsorSegments.map(\.category) == [.sponsor])

        settings.sponsorBlockEnabled = false
        model.updateSettings(settings)
        #expect(model.sponsorSegments.isEmpty)
        #expect(CountingURLProtocol.requests == 0)
    }

    @Test func settingsChangedDuringTheLookupWinOverItsResult() async {
        let model = makeModel()
        let provider = SuspendedSegments(stored)
        model.offlineSponsor = provider
        let video = savedVideo()
        model.currentVideo = video
        let lookup = Task { await model.applyOfflineSponsorSegments(for: video) }
        while provider.lookups == 0 { await Task.yield() }
        var settings = model.settings
        settings.sponsorBlockExcludedChannels["chan"] = "C"
        model.updateSettings(settings)
        provider.release()
        await lookup.value
        #expect(model.sponsorSegments.isEmpty)
        #expect(provider.lookups == 1)  // excluded: no second lookup
    }

    @Test func enablingSponsorBlockDuringPlaybackLoadsStoredSegmentsWithoutReloading() async {
        let model = makeModel()
        var off = model.settings
        off.sponsorBlockEnabled = false
        model.updateSettings(off)
        let video = savedVideo()
        model.currentVideo = video
        await model.applyOfflineSponsorSegments(for: video)
        #expect(model.sponsorSegments.isEmpty)
        var on = off
        on.sponsorBlockEnabled = true
        model.updateSettings(on)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.sponsorSegments.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        #expect(model.sponsorSegments.map(\.category) == [.sponsor, .intro])
        #expect(model.currentVideo?.hasSamePlaybackSource(as: video) == true)
        #expect(CountingURLProtocol.requests == 0)
    }

    @Test func staleToastAndManualSkipAreRemovedWhenSettingsMakeTheSegmentIneligible() async {
        let model = makeModel()
        let video = savedVideo()
        model.currentVideo = video
        await model.applyOfflineSponsorSegments(for: video)
        model.checkSponsorSkip(at: 20.5)
        #expect(model.currentToastSegment?.category == .intro)
        var settings = model.settings
        settings.sponsorBlockMinSegmentDuration = 5  // the 1 s intro is now too short
        model.updateSettings(settings)
        #expect(model.currentToastSegment == nil)

        // A toast shown before a change that this path did not re-filter still cannot seek.
        settings.sponsorBlockMinSegmentDuration = 0
        model.updateSettings(settings)
        model.checkSponsorSkip(at: 20.5)
        let toast = model.currentToastSegment
        #expect(toast != nil)
        model.settings.sponsorBlockActions[.intro] = .nothing
        model.currentTime = 3
        model.skipToastSegment()
        #expect(model.currentTime == 3)
    }
}
