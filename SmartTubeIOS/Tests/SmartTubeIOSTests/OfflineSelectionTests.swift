import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Offline explicit selections and cleanup")
struct OfflineSelectionTests {
    private let video = Video(id: "selection", title: "Selection", channelTitle: "Test", duration: 120)
    private let picture = OfflineTrack(id: "720", kind: .video, label: "720p H.264")
    private let sound = OfflineTrack(id: "en", kind: .audio, label: "English")

    @Test func serverRejectionIsNotReportedAsCorruptMedia() throws {
        let url = try #require(URL(string: "https://example.invalid/video"))
        func response(_ code: Int) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
        }
        for code in [200, 206] {
            try OfflineDownloadTransport.validateDownload(response: response(code), fileSize: 1024)
        }
        do {
            try OfflineDownloadTransport.validateDownload(response: response(403), fileSize: 0)
            Issue.record("A rejected request must not become a saved media file")
        } catch APIError.httpError(let code) {
            #expect(code == 403)
        }
        #expect(throws: OfflineLibraryError.self) {
            try OfflineDownloadTransport.validateDownload(response: response(200), fileSize: 0)
        }
    }

    @Test func explicitVideoAudioAndOptionalTranslationNeverQueueTheCatalog() throws {
        let other = OfflineTrack(id: "fr", kind: .audio, label: "French")
        let catalog = [picture, sound, other, .automatic]
        let selected = try OfflineSelection.tracks(video: picture, audio: other, translation: "ru", catalog: catalog)
        #expect(selected.map(\.id) == ["720", "fr", "vot-ru"])
        #expect(
            try OfflineSelection.tracks(video: picture, audio: sound, translation: nil, catalog: catalog).count == 2)
        #expect(throws: OfflineLibraryError.self) {
            try OfflineSelection.tracks(video: picture, audio: .automatic, translation: nil, catalog: catalog)
        }
    }

    @Test func hlsLanguageChoosesExactlyOneRenditionAndRetainsCodecAlternatives() throws {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=8000000,AVERAGE-BANDWIDTH=8000000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
            original.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=8000000,AVERAGE-BANDWIDTH=8000000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",YT-EXT-AUDIO-CONTENT-ID="ru.1"
            russian.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1280x720,CODECS="vp09,mp4a.40.2"
            vp9.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=12000000,RESOLUTION=1920x1080,CODECS="avc1.4d401f,mp4a.40.2"
            fullhd.m3u8
            """
        let variants = offlineHLSVariants(
            manifest, baseURL: try #require(URL(string: "https://example.invalid/master.m3u8")), duration: 120)
        let catalog = variants.map(\.0)
        let videos = OfflineSelection.videos(in: catalog)
        #expect(videos.count == 3)
        #expect(OfflineSelection.audio(for: videos[0], in: catalog).count == 2)
        #expect(catalog[0].estimatedBytes == 120_000_000)
        let selected = try OfflineSelection.tracks(
            video: videos[0], audio: catalog[1], translation: nil, catalog: catalog)
        #expect(selected == [catalog[1]])
        #expect(variants.first { $0.0.id == selected[0].id }?.1.lastPathComponent == "russian.m3u8")
        #expect(throws: OfflineLibraryError.self) {
            try OfflineSelection.tracks(video: videos[0], audio: catalog[3], translation: nil, catalog: catalog)
        }
    }

    @Test func externalHLSGroupsExposeBothLanguagesWithoutUsingPeakAsSize() throws {
        let manifest = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",LANGUAGE="en-US",NAME="English dubbed",URI="en.m3u8",YT-EXT-AUDIO-CONTENT-ID="en-US.10",YT-EXT-XTAGS="ChQKBWFjb250EgtkdWJiZWQtYXV0bwoNCgRsYW5nEgVlbi1VUw"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",LANGUAGE="ru",NAME="Russian original",URI="ru.m3u8",YT-EXT-AUDIO-CONTENT-ID="ru.4",YT-EXT-XTAGS="ChEKBWFjb250EghvcmlnaW5hbAoKCgRsYW5nEgJydQ"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="unused",LANGUAGE="fr",NAME="French",URI="fr.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=118062796,RESOLUTION=3840x2160,FRAME-RATE=30,CODECS="vp09.00.50.08,mp4a.40.2",AUDIO="234"
            video.m3u8
            """
        let variants = offlineHLSVariants(
            manifest, baseURL: try #require(URL(string: "https://example.invalid/master.m3u8")), duration: 4793)
        let catalog = variants.map(\.0)
        #expect(catalog.count == 2)
        #expect(OfflineSelection.videos(in: catalog).count == 1)
        #expect(catalog.map(\.language) == ["en-US", "ru"])
        #expect(catalog.allSatisfy { $0.estimatedBytes == nil })
        #expect(catalog[1].hlsAudioName == "Russian original")
        #expect(catalog.map(\.isOriginalAudio) == [false, true])
        #expect(catalog[1].hlsPeakBitRate == 118062796)
        #expect(
            try OfflineSelection.tracks(video: catalog[0], audio: catalog[1], translation: nil, catalog: catalog) == [
                catalog[1]
            ])
    }

    @Test func dubbedHLSChoicesKeepDistinctIdentityAcrossFetches() throws {
        // YouTube repeats a video per audio group and gives dubbed muxed variants the original's peak.
        let manifest = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="233",LANGUAGE="ru",NAME="Русский - dubbed-auto",URI="ru-low.m3u8",YT-EXT-AUDIO-CONTENT-ID="ru.3"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",LANGUAGE="ru",NAME="Русский - dubbed-auto",URI="ru.m3u8",YT-EXT-AUDIO-CONTENT-ID="ru.3"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",LANGUAGE="en-US",NAME="English - original",URI="en.m3u8",DEFAULT=YES,YT-EXT-AUDIO-CONTENT-ID="en-US.4"
            #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720,FRAME-RATE=24,CODECS="avc1.4d401f,mp4a.40.5",AUDIO="233"
            video.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,FRAME-RATE=24,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="234"
            video.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=854x480,FRAME-RATE=24,CODECS="avc1.4d401f,mp4a.40.2"
            muxed-original.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=854x480,FRAME-RATE=24,CODECS="avc1.4d401f,mp4a.40.2",YT-EXT-AUDIO-CONTENT-ID="ru.3"
            muxed-ru.m3u8
            """
        let base = try #require(URL(string: "https://example.invalid/master.m3u8"))
        let first = offlineHLSVariants(manifest, baseURL: base)
        #expect(first.map(\.0.id) == offlineHLSVariants(manifest, baseURL: base).map(\.0.id))
        #expect(Set(first.map(\.0.id)).count == first.count)
        let external = first.filter { $0.0.hlsAudioName == "Русский - dubbed-auto" }
        #expect(external.map(\.0.hlsPeakBitRate) == [900_000, 1_000_000])
        #expect(external.allSatisfy { $0.0.language == "ru" && $0.0.isOriginalAudio == false })
        let muxed = first.filter { $0.0.videoSize?.height == 480 }
        // Equal peaks: only the variant URL tells these apart, so the transport qualifies the variant itself.
        #expect(muxed.map(\.1.lastPathComponent) == ["muxed-original.m3u8", "muxed-ru.m3u8"])
        #expect(muxed.map(\.0.hlsPeakBitRate) == [500_000, 500_000])
        #expect(muxed.map(\.0.isOriginalAudio) == [true, false])
    }

    @Test func hlsAudioOptionPicksTheNamedOrSingleLanguageRendition() {
        typealias Option = (name: String, tag: String?)
        func pick(_ options: [Option], name: String, language: String?) -> Option? {
            OfflineDownloadTransport.hlsAudioOption(
                options, name: name, language: language, displayName: \.name, languageTag: \.tag)
        }
        let dubbed: Option = ("Русский - dubbed-auto", "ru")
        let original: Option = ("English - original", "en-US")
        #expect(pick([original, dubbed], name: dubbed.name, language: "ru")?.name == dubbed.name)
        // The same rendition repeated across audio groups is not ambiguous.
        #expect(pick([dubbed, original, dubbed], name: dubbed.name, language: "ru")?.name == dubbed.name)
        // AVFoundation may localize the NAME; fall back to the one option in the language, case-insensitively.
        #expect(pick([("Russian", "RU"), original], name: dubbed.name, language: "ru")?.name == "Russian")
        #expect(pick([("Russian", "ru"), ("Russian original", "ru")], name: dubbed.name, language: "ru") == nil)
        #expect(pick([original], name: dubbed.name, language: nil)?.name == original.name)
        #expect(pick([original, dubbed], name: "Default", language: nil) == nil)
        #expect(pick([original], name: dubbed.name, language: "ru") == nil)
        // One name in two dialects is two renditions, not a repeat.
        #expect(pick([("English", "en-US"), ("English", "en-GB")], name: "English", language: nil) == nil)
    }

    @Test func estimateRejectsInvalidOrOverflowingMetadata() {
        #expect(OfflineTrack.estimatedSize(bitrate: 8_000_000, duration: 120) == 120_000_000)
        var first = picture
        first.estimatedBytes = Int64.max
        var second = sound
        second.estimatedBytes = 1
        #expect(OfflineSelection.estimatedBytes(for: [first, second]) == nil)
        #expect(OfflineSelection.estimatedBytes(for: [picture]) == nil)
        #expect(OfflineTrack.estimatedSize(bitrate: -1, duration: 120) == nil)
        #expect(OfflineTrack.estimatedSize(bitrate: 8, duration: .infinity) == nil)
        #expect(OfflineTrack.estimatedSize(bitrate: Int.max, duration: Double.greatestFiniteMagnitude) == nil)
    }

    @Test func deleteCompletedTaskKeepsOtherTracksAndDeletesItsFile() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let jobs = try await store.enqueue(video: video, tracks: [picture, sound]).jobs
        let files = try await complete(jobs, store: store, directory: root)
        try await store.beginRemoval(videoID: video.id, jobID: jobs[0].id)
        let snapshot = try await store.completeRemovals()
        #expect(snapshot.jobs.map(\.id) == [jobs[1].id])
        #expect(snapshot.entries[0].assets.map(\.id) == [sound.id])
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
        #expect(FileManager.default.fileExists(atPath: files[1].path))
    }

    @Test func deleteWholeVideoRemovesMediaHLSReceiptsAndJobsButKeepsAnotherVideo() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Documents/Offline")
        let store = OfflineLibraryStore(directory: directory, homeDirectory: root)
        let jobs = try await store.enqueue(video: video, tracks: [picture, sound, .translation("ru")]).jobs
        let files = try await complete(jobs, store: store, directory: directory)
        let hls = OfflineTrack(id: "hls", kind: .hls, label: "720 HLS", hasAudio: true)
        let hlsJob = try #require(try await store.enqueue(video: video, tracks: [hls]).jobs.last)
        let package = root.appendingPathComponent("Library/Media/offline.movpkg")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([1]).write(to: package.appendingPathComponent("segment"))
        try await store.update(attempt: hlsJob.attempt, state: .downloading)
        try await store.finish(attempt: hlsJob.attempt, staged: package, systemPackage: true)
        let pending = try #require(try await store.enqueue(video: video, tracks: [.translation("fr")]).jobs.last)
        let staged = try file(pending.attempt, in: directory)
        try OfflineTransferReceipt(attempt: pending.attempt, url: staged, systemPackage: false).persist(in: directory)
        let other = Video(id: "other", title: "Keep", channelTitle: "Test")
        let keep = try #require(try await store.enqueue(video: other, tracks: [picture]).jobs.last)
        let kept = try await complete([keep], store: store, directory: directory)[0]
        try await store.beginRemoval(videoID: video.id)
        // Simulates relaunch after cancellation has committed, before deleting the files.
        let restored = OfflineLibraryStore(directory: directory, homeDirectory: root)
        let removed = try await restored.completeRemovals()
        #expect(removed.entries.map(\.id) == [other.id])
        #expect(removed.jobs.map(\.id) == [keep.id])
        #expect(removed.pendingRemovals == nil)
        for url in files + [staged, package, OfflineTransferReceipt.location(pending.attempt, in: directory)] {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: kept.path))
        let late = try file(pending.attempt, in: directory)
        let after = try await restored.finish(attempt: pending.attempt, staged: late)
        #expect(after.entries.map(\.id) == [other.id])
        #expect(!FileManager.default.fileExists(atPath: late.path))
    }

    @Test func deleteAllResumesAfterFailedCommitAndRemovesOwnedOrphanCache() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Documents/Offline")
        let store = OfflineLibraryStore(directory: directory, homeDirectory: root)
        let jobs = try await store.enqueue(video: video, tracks: [picture, sound, .translation("ru")]).jobs
        let files = try await complete(jobs, store: store, directory: directory)
        _ = try await store.takeCompletedBatches()
        let other = Video(id: "other", title: "Other", channelTitle: "Test")
        let hls = OfflineTrack(id: "hls", kind: .hls, label: "HLS", hasAudio: true)
        let job = try #require(try await store.enqueue(video: other, tracks: [hls]).jobs.last)
        let package = root.appendingPathComponent("Library/Media/saved.movpkg")
        let partial = root.appendingPathComponent("Library/Media/partial.movpkg")
        let unrelated = root.appendingPathComponent("Library/Media/unrelated.movpkg")
        for url in [package, partial, unrelated] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1]).write(to: url.appendingPathComponent("segment"))
        }
        try await store.update(attempt: job.attempt, state: .downloading)
        try await store.finish(attempt: job.attempt, staged: package, systemPackage: true)
        let orphan = try file(UUID(), in: directory)
        let receipt = OfflineTransferReceipt(attempt: UUID(), url: partial, systemPackage: true, isPartial: true)
        try receipt.persist(in: directory)
        let intent = try await store.beginRemoval(videoID: nil)
        #expect(intent.jobs.allSatisfy { $0.state == .cancelled })
        await #expect(throws: OfflineLibraryError.self) {
            try await store.enqueue(video: Video(id: "new", title: "New", channelTitle: "Test"), tracks: [picture])
        }
        let failing = OfflineLibraryStore(
            directory: directory, homeDirectory: root,
            writeManifest: { _, _ in
                throw CocoaError(.fileWriteOutOfSpace)
            })
        await #expect(throws: (any Error).self) { try await failing.completeRemovals() }
        let restored = OfflineLibraryStore(directory: directory, homeDirectory: root)
        #expect(try await restored.snapshot().pendingRemovals?.count == 1)
        let result = try await restored.completeRemovals()
        #expect(result.entries.isEmpty && result.jobs.isEmpty && result.notifiedBatches.isEmpty)
        #expect(result.pendingRemovals == nil)
        for url in files + [package, partial, orphan, OfflineTransferReceipt.location(receipt.attempt, in: directory)] {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        try await restored.beginRemoval(videoID: nil)
        #expect(try await restored.completeRemovals().entries.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["manifest.json"])
    }

    @Test func partialHLSPackageIsNotCompletionAndDeletionRemovesItsCache() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Documents/Offline")
        let store = OfflineLibraryStore(directory: directory, homeDirectory: root)
        let job = try await store.enqueue(video: video, tracks: [picture]).jobs[0]
        try await store.update(attempt: job.attempt, state: .downloading)
        let package = root.appendingPathComponent("Library/Media/partial.movpkg")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([1]).write(to: package.appendingPathComponent("segment"))
        try OfflineTransferReceipt(attempt: job.attempt, url: package, systemPackage: true, isPartial: true).persist(
            in: directory)
        #expect(try await store.recover(activeAttempts: [job.attempt]).jobs[0].state == .downloading)
        try await store.beginRemoval(videoID: video.id)
        #expect(try await store.completeRemovals().entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(try await store.pendingReceipts().isEmpty)
    }

    @Test func deletingOldCompletedJobDoesNotDeleteItsReplacement() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let old = try await store.enqueue(video: video, tracks: [picture]).jobs[0]
        _ = try await complete([old], store: store, directory: root)
        let new = try #require(try await store.enqueue(video: video, tracks: [picture]).jobs.last)
        let replacement = try await complete([new], store: store, directory: root)[0]
        try await store.beginRemoval(videoID: video.id, jobID: old.id)
        let snapshot = try await store.completeRemovals()
        #expect(snapshot.entries[0].assets[0].attempt == new.attempt)
        #expect(FileManager.default.fileExists(atPath: replacement.path))
    }

    @Test func failedDeletionCommitKeepsRecoverableIntentAndIsIdempotent() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineLibraryStore(directory: root)
        let job = try await store.enqueue(video: video, tracks: [picture]).jobs[0]
        let downloaded = try await complete([job], store: store, directory: root)[0]
        try await store.beginRemoval(videoID: video.id)
        let failing = OfflineLibraryStore(
            directory: root, writeManifest: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await #expect(throws: (any Error).self) { try await failing.completeRemovals() }
        #expect(!FileManager.default.fileExists(atPath: downloaded.path))
        #expect(try await failing.snapshot().pendingRemovals?.count == 1)
        let restored = OfflineLibraryStore(directory: root)
        #expect(try await restored.completeRemovals().entries.isEmpty)
        #expect(try await restored.completeRemovals().entries.isEmpty)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func file(_ id: UUID, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(id.uuidString + ".mp4")
        try Data([1, 2, 3]).write(to: url)
        return url
    }
    private func complete(_ jobs: [OfflineJob], store: OfflineLibraryStore, directory: URL) async throws -> [URL] {
        var files: [URL] = []
        for job in jobs {
            try await store.update(attempt: job.attempt, state: .downloading)
            let url = try file(job.attempt, in: directory)
            try await store.finish(attempt: job.attempt, staged: url)
            files.append(url)
        }
        return files
    }
}
