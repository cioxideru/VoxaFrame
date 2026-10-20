import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Offline sizes: totals, transfer, disk bytes and the scanner lifecycle")
struct OfflineSizesTests {
    private func track(_ id: String, _ kind: OfflineTrack.Kind, bytes: Int64? = nil) -> OfflineTrack {
        var track = OfflineTrack(id: id, kind: kind, label: id)
        track.estimatedBytes = bytes
        return track
    }

    private func job(
        _ track: OfflineTrack, _ state: OfflineJob.State, progress: Double = 0, bytes: OfflineByteCounts? = nil
    ) -> OfflineJob {
        OfflineJob(
            id: UUID(), batch: UUID(), attempt: UUID(), videoID: "v", track: track, state: state, progress: progress,
            bytes: bytes)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func totalsSplitByKindAndCountActiveBytes() {
        let video = track("720", .video)
        let entry = OfflineEntry(
            video: Video(id: "v", title: "T", channelTitle: "C"),
            assets: [video, track("en", .audio), track("vot-ru", .translation)].map {
                OfflineAsset(track: $0, filename: "f", systemRelativePath: nil)
            })
        var sizes = OfflineDiskSizes()
        sizes.assets = [
            OfflineSizes.key(videoID: "v", trackID: "720"): 400, OfflineSizes.key(videoID: "v", trackID: "en"): 8,
            OfflineSizes.key(videoID: "v", trackID: "vot-ru"): 2,
        ]
        let counted = job(track("1080", .video), .downloading, bytes: OfflineByteCounts(done: 250, total: 1000))
        let hls = job(track("hls", .hls, bytes: 800), .downloading)
        sizes.partials[hls.attempt] = 100
        let totals = OfflineSizes.totals(
            entries: [entry], jobs: [counted, hls, job(video, .completed, progress: 1)], sizes: sizes)
        #expect(totals.video == 400 && totals.audio == 8 && totals.translation == 2)
        #expect(totals.saved == 410 && totals.downloading == 350 && totals.onDisk == 760)
        #expect(totals.remaining == 750 + 700)
    }

    @Test func firstDownloadAlreadyCountsFetchedBytes() {
        let running = job(track("t", .translation), .downloading, bytes: OfflineByteCounts(done: 5, total: 50))
        let totals = OfflineSizes.totals(entries: [], jobs: [running], sizes: OfflineDiskSizes())
        #expect(totals.saved == 0 && totals.onDisk == 5)
    }

    @Test func transferPrefersCountersThenPartialThenEstimate() {
        var sizes = OfflineDiskSizes()
        let counted = job(track("a", .translation), .downloading, bytes: OfflineByteCounts(done: 3, total: 9))
        #expect(
            OfflineSizes.transfer(of: counted, sizes: sizes) == OfflineTransfer(done: 3, expected: 9, isEstimate: false)
        )
        let hls = job(track("h", .hls, bytes: 100), .downloading, progress: 0.5)
        sizes.partials[hls.attempt] = 70
        #expect(
            OfflineSizes.transfer(of: hls, sizes: sizes) == OfflineTransfer(done: 70, expected: 100, isEstimate: true))
        #expect(OfflineSizes.transfer(of: job(track("u", .translation), .downloading), sizes: sizes) == nil)
    }

    @Test func unknownSizesShowNothing() {
        var sizes = OfflineDiskSizes()
        #expect(OfflinePresentation.jobSizeText(job(track("t", .translation), .downloading), sizes: sizes) == nil)
        let done = job(track("t", .video), .completed)
        sizes.assets["v|t"] = 0
        #expect(OfflinePresentation.jobSizeText(done, sizes: sizes) == nil)
        sizes.assets["v|t"] = 5_000_000
        #expect(OfflinePresentation.jobSizeText(done, sizes: sizes) != nil)
        #expect(OfflinePresentation.jobSizeText(job(track("t", .video, bytes: 9), .failed), sizes: sizes) == nil)
    }

    @Test func diskBytesSumsNestedPackageContents() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Data/segments", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 10).write(to: root.appendingPathComponent("a"))
        try Data(count: 5).write(to: nested.appendingPathComponent("b"))
        let top = try #require(try OfflineSizes.diskBytes(at: root.appendingPathComponent("a")))
        let inner = try #require(try OfflineSizes.diskBytes(at: nested.appendingPathComponent("b")))
        #expect(top >= 10 && inner >= 5)
        #expect(try OfflineSizes.diskBytes(at: root) == top + inner)
        #expect(try OfflineSizes.diskBytes(at: root.appendingPathComponent("missing")) == nil)
    }

    @Test func symlinksAreCountedAsLinksNotFollowed() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        try Data(count: 1_000_000).write(to: outside)
        let package = root.appendingPathComponent("p.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("l"), withDestinationURL: outside)
        let size = try #require(try OfflineSizes.diskBytes(at: package))
        #expect(size < 100_000)
        #expect(try OfflineSizes.diskBytes(at: package.appendingPathComponent("l")) == nil)
    }

    @Test func unreadablePackagePartIsUnknownNotSmaller() throws {
        let root = try directory()
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 10).write(to: root.appendingPathComponent("manifest"))
        try Data(count: 10).write(to: locked.appendingPathComponent("segment"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        #expect(try OfflineSizes.diskBytes(at: root) == nil)
    }

    @Test func scannerFollowsAPartialDownloadThroughCompletionAndDeletion() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let scanner = OfflineSizeScanner(store: store, partialInterval: .zero)
        let queued = try await store.enqueue(
            video: Video(id: "v", title: "T", channelTitle: "C"), tracks: [.automatic])
        let attempt = try #require(queued.jobs.first?.attempt)
        try await store.update(attempt: attempt, state: .downloading, progress: 0.5)
        let file = root.appendingPathComponent("\(attempt.uuidString).mp4")
        try Data(count: 4000).write(to: file)
        try OfflineTransferReceipt(attempt: attempt, url: file, systemPackage: false, isPartial: true).persist(in: root)
        let expected = try #require(try OfflineSizes.diskBytes(at: file))

        var sizes = try await scanner.sizes()
        #expect(sizes.partials[attempt] == expected && sizes.assets.isEmpty)

        try await store.finish(attempt: attempt, staged: file)
        sizes = try await scanner.sizes()
        let key = OfflineSizes.key(videoID: "v", trackID: OfflineTrack.automatic.id)
        #expect(sizes.partials.isEmpty && sizes.assets[key] == expected)

        try await store.beginRemoval(videoID: "v")
        try await store.completeRemovals()
        sizes = try await scanner.sizes()
        #expect(sizes == OfflineDiskSizes())
    }
}
