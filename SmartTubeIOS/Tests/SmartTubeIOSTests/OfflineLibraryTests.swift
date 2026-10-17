import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Offline library durability")
struct OfflineLibraryTests {
    private let video = Video(id: "offline-test", title: "Offline", channelTitle: "Test", duration: 10)
    private let track = OfflineTrack(id: "720-h264", kind: .video, label: "720p H.264", hasAudio: true)
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func staged(_ attempt: UUID, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(attempt.uuidString + ".mp4")
        try Data([1, 2, 3]).write(to: url)
        return url
    }
    @Test func noFollowPackageKeepsProtectionAcrossManifestReloadAndRejectsEscapes() async throws {
        let physicalRoot = try #require(realpath(try directory().path, nil))
        defer { free(physicalRoot) }
        let root = URL(fileURLWithPath: String(cString: physicalRoot), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let package = library.appendingPathComponent("HLS%20sample.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let protected = URL(fileURLWithPath: "/.nofollow" + package.path, isDirectory: true)
        #expect(OfflineLibraryStore.isSystemPackage(protected, homeDirectory: home))
        let outside = root.appendingPathComponent("Outside.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        #expect(
            !OfflineLibraryStore.isSystemPackage(URL(fileURLWithPath: "/.nofollow" + outside.path), homeDirectory: home)
        )
        let escape = library.appendingPathComponent("escape.movpkg")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        #expect(
            !OfflineLibraryStore.isSystemPackage(URL(fileURLWithPath: "/.nofollow" + escape.path), homeDirectory: home))
        #expect(!OfflineLibraryStore.isSystemPackage(escape, homeDirectory: home))
        let directory = home.appendingPathComponent("Documents/Offline", isDirectory: true)
        let store = OfflineLibraryStore(directory: directory, homeDirectory: home)
        let hls = OfflineTrack(id: "hls", kind: .hls, label: "Adaptive", hasAudio: true)
        let job = try await store.enqueue(video: video, tracks: [hls]).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        try await store.finish(attempt: job.attempt, staged: protected, systemPackage: true)
        let restored = OfflineLibraryStore(directory: directory, homeDirectory: home)
        let asset = try await restored.snapshot().entries[0].assets[0]
        #expect(asset.systemNoFollow == true)
        #expect(asset.systemRelativePath == "Library/HLS%20sample.movpkg")
        let file = try await restored.fileURL(asset)
        #expect(file.path.hasPrefix("/.nofollow/"))
        #expect(file.path == protected.path)
        #expect(FileManager.default.fileExists(atPath: file.path))
        // A stale completion may spell the same published package without the protected prefix.
        await restored.discard(attempt: UUID(), url: package, systemPackage: true)
        #expect(FileManager.default.fileExists(atPath: package.path))
        let replacement = try await restored.enqueue(video: video, tracks: [hls]).jobs.last
        let next = try #require(replacement)
        try await restored.update(attempt: next.attempt, state: .downloading)
        try await restored.finish(attempt: next.attempt, staged: package, systemPackage: true)
        #expect(FileManager.default.fileExists(atPath: package.path))
        for badPath in ["/Library/file.movpkg", "Library/../Outside.movpkg"] {
            let invalid = OfflineAsset(
                track: hls, filename: "file.movpkg", systemRelativePath: badPath, systemNoFollow: true)
            await #expect(throws: OfflineLibraryError.self) { try await restored.fileURL(invalid) }
        }
    }

    @Test func protectedPackageDeletionUsesPhysicalHomeAfterReload() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let package = home.appendingPathComponent("Library/Media/Adaptive%20sample.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: package.appendingPathComponent("segment"))
        let protected = URL(fileURLWithPath: "/.nofollow" + package.path, isDirectory: true)
        let directory = home.appendingPathComponent("Documents/Offline", isDirectory: true)
        let store = OfflineLibraryStore(directory: directory, homeDirectory: home)
        let hls = OfflineTrack(id: "hls-auto", kind: .hls, label: "Adaptive", hasAudio: true)
        let job = try await store.enqueue(video: video, tracks: [hls]).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        try await store.finish(attempt: job.attempt, staged: protected, systemPackage: true)
        try await store.beginRemoval(videoID: nil)
        let restored = OfflineLibraryStore(directory: directory, homeDirectory: home)
        let result = try await restored.completeRemovals()
        #expect(result.entries.isEmpty && result.jobs.isEmpty && result.pendingRemovals == nil)
        #expect(!FileManager.default.fileExists(atPath: package.path))
    }

    @Test func relativeSystemPackageURLRetainsOwnershipAndLiteralPercentEncoding() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let url = try #require(
            URL(string: "Library/com.apple.UserManagedAssets.fixture/HLS%2520%25C2%25B7.movpkg/", relativeTo: home))
        #expect(url.baseURL != nil)
        #expect(OfflineLibraryStore.isSystemPackage(url))
        #expect(OfflineLibraryStore.isSystemPackage(url.absoluteURL.standardizedFileURL))
        #expect(url.absoluteURL.lastPathComponent == "HLS%20%C2%B7.movpkg")
        let outside = try #require(URL(string: "../Other/Library/package.movpkg/", relativeTo: home))
        #expect(!OfflineLibraryStore.isSystemPackage(outside))
    }
    @Test func selectedVideoSizesSurviveReceiptCommitAndLegacyDecoding() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let job = try await store.enqueue(video: video, tracks: [track]).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        let file = try staged(job.attempt, in: root)
        let sizes = [OfflineVideoSize(width: 640, height: 360), OfflineVideoSize(width: 1280, height: 720)]
        try OfflineTransferReceipt(attempt: job.attempt, url: file, systemPackage: false, savedVideoSizes: sizes)
            .persist(in: root)
        let receipt = try #require(try await store.pendingReceipts().first)
        #expect(receipt.savedVideoSizes == sizes)
        let completed = try await store.finish(
            attempt: receipt.attempt, staged: receipt.url, savedVideoSizes: receipt.savedVideoSizes)
        #expect(completed.entries[0].assets[0].savedVideoSizes == sizes)
        let restored = try await OfflineLibraryStore(directory: root).snapshot()
        #expect(restored.entries[0].assets[0].savedVideoSizes == sizes)
        var oldReceipt = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        oldReceipt.removeValue(forKey: "savedVideoSizes")
        #expect(
            try JSONDecoder().decode(
                OfflineTransferReceipt.self, from: JSONSerialization.data(withJSONObject: oldReceipt)
            ).savedVideoSizes == nil)
        var oldAsset = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(completed.entries[0].assets[0])) as? [String: Any])
        oldAsset.removeValue(forKey: "savedVideoSizes")
        #expect(
            try JSONDecoder().decode(OfflineAsset.self, from: JSONSerialization.data(withJSONObject: oldAsset))
                .savedVideoSizes == nil)
    }

    @Test func restoresAcceptedRequestAndProgress() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let first = try await store.enqueue(video: video, tracks: [track])
        let attempt = try #require(first.jobs.first?.attempt)
        try await store.update(attempt: attempt, state: .downloading, progress: 0.4)
        let restored = OfflineLibraryStore(directory: root)
        let live = try await restored.recover(activeAttempts: [attempt])
        #expect(live.jobs[0].attempt == attempt)
        #expect(live.jobs[0].progress == 0.4)
        let interrupted = try await restored.recover(activeAttempts: [])
        #expect(interrupted.jobs[0].state == .queued)
        #expect(interrupted.jobs[0].attempt != attempt)
    }
    @Test func staleCompletionCannotFinishRetry() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let first = try await store.enqueue(video: video, tracks: [track]).jobs[0]
        try await store.update(attempt: first.attempt, state: .cancelled)
        let retry = try await store.retry(id: first.id).jobs[0]
        try await store.update(attempt: retry.attempt, state: .downloading)
        let stale = try staged(first.attempt, in: root)
        let snapshot = try await store.finish(attempt: first.attempt, staged: stale)
        #expect(snapshot.jobs[0].attempt == retry.attempt)
        #expect(snapshot.jobs[0].state == .downloading)
        #expect(snapshot.entries[0].assets.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }
    @Test func failureOfAddedTrackPreservesWorkingVariant() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let first = try await store.enqueue(video: video, tracks: [track]).jobs[0]
        try await store.update(attempt: first.attempt, state: .downloading)
        let file = try staged(first.attempt, in: root)
        try await store.finish(attempt: first.attempt, staged: file)
        let added = try #require(try await store.enqueue(video: video, tracks: [.translation("ru")]).jobs.last)
        let snapshot = try await store.update(attempt: added.attempt, state: .failed, error: "Disk full")
        #expect(snapshot.entries[0].assets.count == 1)
        #expect(try await store.fileURL(snapshot.entries[0].assets[0]) == file)
    }
    @Test func replacesOnlyAfterManifestCommit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let first = try await store.enqueue(video: video, tracks: [track]).jobs[0]
        try await store.update(attempt: first.attempt, state: .downloading)
        let old = try staged(first.attempt, in: root)
        try await store.finish(attempt: first.attempt, staged: old)
        let second = try #require(try await store.enqueue(video: video, tracks: [track]).jobs.last)
        try await store.update(attempt: second.attempt, state: .downloading)
        let replacement = try staged(second.attempt, in: root)
        let manifest = root.appendingPathComponent("manifest.json")
        let saved = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await store.finish(attempt: second.attempt, staged: replacement) }
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(try await store.snapshot().entries[0].assets[0].filename == old.lastPathComponent)
        try FileManager.default.removeItem(at: manifest)
        try saved.write(to: manifest)
        try await store.finish(attempt: second.attempt, staged: replacement)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: replacement.path))
    }
    @Test func durableCompletionSurvivesSystemTaskRemoval() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let job = try await store.enqueue(video: video, tracks: [track]).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        let file = try staged(job.attempt, in: root)
        try OfflineTransferReceipt(attempt: job.attempt, url: file, systemPackage: false).persist(in: root)
        let restored = OfflineLibraryStore(directory: root)
        #expect(try await restored.recover(activeAttempts: []).jobs[0].attempt == job.attempt)
        let receipt = try #require(await restored.pendingReceipts().first)
        try await restored.finish(attempt: receipt.attempt, staged: receipt.url)
        #expect(try await restored.snapshot().jobs[0].state == .completed)
        #expect(try await restored.pendingReceipts().isEmpty)
    }
    @Test func notificationWaitsForEntireBatchAndIsConsumedOnce() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let jobs = try await store.enqueue(video: video, tracks: [track, .translation("ru")]).jobs
        for (index, job) in jobs.enumerated() {
            try await store.update(attempt: job.attempt, state: .downloading)
            try await store.finish(attempt: job.attempt, staged: staged(job.attempt, in: root))
            let batches = try await store.takeCompletedBatches()
            #expect(batches.count == (index == 0 ? 0 : 1))
        }
        #expect(try await store.takeCompletedBatches().isEmpty)
    }
    @Test func pathBoundaryRejectsSiblingDirectoryAndTraversal() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!OfflineLibraryStore.contains(URL(fileURLWithPath: root.path + "-evil/video.mp4"), in: root))
        #expect(!OfflineLibraryStore.contains(root.appendingPathComponent("../outside.mp4"), in: root))
        #expect(!OfflineLibraryStore.contains(try #require(URL(string: "https://example.com/video.mp4")), in: root))
    }
    @Test func localSourceIdentityIncludesAudioTranslationAndQuality() {
        var local = video
        local.localFileURL = URL(fileURLWithPath: "/tmp/video.mp4")
        #expect(!video.hasSamePlaybackSource(as: local))
        var other = local
        other.localAudioFileURL = URL(fileURLWithPath: "/tmp/audio.mp4")
        #expect(!other.hasSamePlaybackSource(as: local))
        other = local
        other.localTranslationFileURL = URL(fileURLWithPath: "/tmp/voice.mp3")
        #expect(!other.hasSamePlaybackSource(as: local))
        other = local
        other.localFileURL = URL(fileURLWithPath: "/tmp/high.mp4")
        #expect(!other.hasSamePlaybackSource(as: local))
        #expect(video.hasSamePlaybackSource(as: video))
    }
    @Test func localURLsNeverLeakIntoCachedVideoJSON() throws {
        var local = video
        local.localFileURL = URL(fileURLWithPath: "/tmp/private-video")
        local.localAudioFileURL = URL(fileURLWithPath: "/tmp/private-audio")
        local.localTranslationFileURL = URL(fileURLWithPath: "/tmp/private-voice")
        let encoded = try JSONEncoder().encode(local)
        let restored = try JSONDecoder().decode(Video.self, from: encoded)
        #expect(
            restored.localFileURL == nil && restored.localAudioFileURL == nil && restored.localTranslationFileURL == nil
        )
    }
    @Test func hlsCatalogExcludesExternalAudioGroupButKeepsLanguageMetadata() throws {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="external"
            silent.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",YT-EXT-AUDIO-CONTENT-ID="ru.1"
            russian.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=1920x1080,CODECS="avc1.4d401f"
            video-only.m3u8
            """
        let variants = offlineHLSVariants(
            manifest, baseURL: try #require(URL(string: "https://example.com/master.m3u8")))
        #expect(variants.count == 1)
        #expect(variants[0].0.language == "ru")
        #expect(variants[0].0.label.contains("Dubbed"))
        #expect(variants[0].1.lastPathComponent == "russian.m3u8")
    }
    @Test func audioMetadataSurvivesPlayerParsingAndPoToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflinePlayerResponse.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let info = try await InnerTubeAPI(authToken: nil, session: session).fetchPlayerInfo(videoId: "test")
        let patched = info.applyingPoToken("test-token")
        let format = try #require(patched.formats.first)
        #expect(format.audioTrackID == "en.0")
        #expect(format.audioLanguage == "en")
        #expect(format.isOriginalAudio == true)
    }
}

/// Each protocol instance emits immutable fixture bytes; it has no shared mutable state.
private final class OfflinePlayerResponse: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(
            #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"test","title":"Test","author":"Test","lengthSeconds":"10"},"streamingData":{"adaptiveFormats":[{"itag":140,"mimeType":"audio/mp4","url":"https://example.com/audio?itag=140","audioTrack":{"id":"en.0","displayName":"English (original)","audioIsDefault":true}}]}}"#
                .utf8)
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
