import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

@Suite("Offline screens: selection, status, actions, grouping and error text")
struct OfflinePresentationTests {
    private let picture = OfflineTrack(id: "720", kind: .video, label: "720p · H.264")
    private let muxed = OfflineTrack(id: "360", kind: .video, label: "360p · H.264", hasAudio: true)
    private let sound = OfflineTrack(id: "en", kind: .audio, label: "en · Original")
    private let package = OfflineTrack(id: "hls", kind: .hls, label: "HLS · H.264 + AAC", hasAudio: true)

    private func job(
        _ video: String, _ track: OfflineTrack, _ state: OfflineJob.State, progress: Double = 0,
        waitsUntil: Date? = nil, batch: UUID = UUID()
    ) -> OfflineJob {
        OfflineJob(
            id: UUID(), batch: batch, attempt: UUID(), videoID: video, track: track, state: state, progress: progress,
            nextResolutionAt: waitsUntil)
    }

    private func entry(_ id: String, title: String = "Title", _ tracks: [OfflineTrack] = []) -> OfflineEntry {
        OfflineEntry(
            video: Video(id: id, title: title, channelTitle: "Channel"),
            assets: tracks.map { OfflineAsset(track: $0, filename: "\($0.id).mp4", systemRelativePath: nil) })
    }

    @Test func selectionSurvivesReorderingAndChangesToSavedTracks() {
        #expect(OfflinePresentation.retainedSelection("a", entries: [entry("b"), entry("a", [muxed])]) == "a")
        #expect(OfflinePresentation.retainedSelection("a", entries: [entry("a", [muxed, sound])]) == "a")
        #expect(OfflinePresentation.retainedSelection("a", entries: [entry("a")]) == "a")
    }

    @Test func selectionDoesNotChooseAnotherVideoWhenDeletedOrInitiallyEmpty() {
        #expect(OfflinePresentation.retainedSelection(nil, entries: [entry("a")]) == nil)
        #expect(OfflinePresentation.retainedSelection("a", entries: [entry("b")]) == nil)
        #expect(OfflinePresentation.retainedSelection("a", entries: []) == nil)
    }

    @Test func columnsOpenOnTheFirstVideoUntilOneHasBeenShown() {
        func select(_ id: String?, _ entries: [OfflineEntry], columns: Bool = true, shown: Bool = false) -> String? {
            OfflinePresentation.columnSelection(id, entries: entries, showsColumns: columns, hasShownVideo: shown)
        }
        #expect(select(nil, [entry("a"), entry("b")]) == "a")
        #expect(select(nil, []) == nil)
        #expect(select(nil, [entry("a")], columns: false) == nil)
        // The person's choice is kept; a deleted choice leaves the detail empty instead of picking a neighbour.
        #expect(select("b", [entry("a"), entry("b")], shown: true) == "b")
        #expect(select("b", [entry("a")], shown: true) == nil)
        #expect(select(nil, [entry("a")], shown: true) == nil)
    }

    @Test func sixStatesAndWaitingForTranslationMapToTheirActions() {
        func expect(
            _ job: OfflineJob, _ status: OfflinePresentation.JobStatus, _ action: OfflinePresentation.JobAction
        ) {
            #expect(OfflinePresentation.status(job) == status)
            #expect(OfflinePresentation.action(job) == action)
        }
        expect(job("a", picture, .queued), .queued, .cancel)
        expect(job("a", .translation("ru"), .queued, waitsUntil: .distantFuture), .waitingForTranslation, .cancel)
        expect(job("a", picture, .resolving), .resolving, .cancel)
        expect(job("a", picture, .downloading, progress: 0.42), .downloading(0.42), .cancel)
        expect(job("a", picture, .completed, progress: 1), .completed, .none)
        expect(job("a", picture, .failed), .failed, .retry)
        expect(job("a", picture, .cancelled), .cancelled, .retry)
    }

    @Test func quickButtonStatesFollowTheLibraryNotThePlaybackSource() {
        func action(
            _ video: Video = Video(id: "a", title: "T", channelTitle: "C"), entries: [OfflineEntry] = [],
            jobs: [OfflineJob] = []
        ) -> OfflinePresentation.QuickAction {
            OfflinePresentation.quickAction(video: video, entries: entries, jobs: jobs)
        }
        #expect(action() == .offline)
        #expect(action(jobs: [job("a", picture, .downloading)]) == .queued)
        #expect(action(jobs: [job("b", picture, .queued)]) == .offline)
        #expect(action(jobs: [job("a", picture, .completed)]) == .offline)
        // Streamed playback of a video already saved: Saved and disabled.
        #expect(action(entries: [entry("a", [muxed])]) == .saved)
        #expect(action(entries: [entry("a", [muxed])], jobs: [job("a", picture, .queued)]) == .saved)
        // An entry that cannot play yet is not Saved.
        #expect(action(entries: [entry("a", [picture])]) == .offline)
        #expect(action(Video(id: "a", title: "T", channelTitle: "C", isLive: true)) == .unavailable)
        #expect(action(Video(id: "a", title: "T", channelTitle: "C", isUpcoming: true)) == .unavailable)
        #expect(OfflinePresentation.QuickAction.saved.isEnabled == false)
        #expect(OfflinePresentation.QuickAction.queued.isEnabled)
    }

    @Test func downloadFiltersKeepNewestFirstAndIncludeTranslationsWithAudio() {
        let jobs = [
            job("a", picture, .completed), job("b", sound, .failed),
            job("a", .translation("ru"), .queued), job("a", package, .cancelled),
        ]
        func ids(_ filter: OfflinePresentation.DownloadFilter, videoID: String? = nil) -> [UUID] {
            OfflinePresentation.downloadJobs(jobs, videoID: videoID, filter: filter).map(\.id)
        }
        #expect(ids(.all) == jobs.reversed().map(\.id))
        #expect(ids(.active) == [jobs[2].id, jobs[1].id])
        #expect(ids(.error) == [jobs[1].id])
        #expect(ids(.video) == [jobs[3].id, jobs[0].id])
        #expect(ids(.audio) == [jobs[2].id, jobs[1].id])
        #expect(ids(.audio, videoID: "a") == [jobs[2].id])
    }

    @Test func compactChipsPreserveQualityCodecLanguageAndBitrate() {
        let audio = OfflineTrack(id: "ru", kind: .audio, label: "Russian · AAC 52kbps", language: "ru")
        #expect(OfflinePresentation.TrackBadge(track: audio, status: .completed).compactLabel == "🇷🇺 RU · AAC 52kbps")
        #expect(OfflinePresentation.TrackBadge(track: picture, status: .completed).compactLabel == "720p · H.264")
        #expect(
            OfflinePresentation.TrackBadge(track: .translation("ru"), status: .queued).compactLabel == "Yandex 🇷🇺 RU")
    }

    @Test func transferSummaryCountsFilesAndKeepsCompletedPartsOfActiveBatches() {
        let batch = UUID()
        let jobs = [
            job("a", picture, .completed, progress: 1, batch: batch),
            job("a", sound, .downloading, progress: 0.5, batch: batch),
            job("a", .translation("ru"), .queued, batch: batch),
            job("b", package, .resolving, batch: batch),
            job("old", picture, .completed, progress: 1),
            job("failed", sound, .failed),
            job("cancelled", sound, .cancelled, batch: batch),
        ]
        let summary = OfflinePresentation.transferSummary(jobs)
        #expect(summary.counts == [.video: 1, .audio: 1, .translation: 1])
        #expect(summary.failures == 1)
        #expect(summary.progress == 0.375)
        #expect(summary.isVisible)

    }

    @Test func summaryHandlesIdleFailureOnlyAndInvalidProgress() {
        let idle = OfflinePresentation.transferSummary([job("a", picture, .completed)])
        #expect(!idle.isVisible)
        #expect(idle.progress == nil)
        let failed = OfflinePresentation.transferSummary([job("a", picture, .failed)])
        #expect(failed.isVisible && failed.activeCount == 0 && failed.progress == nil)
        for progress in [-1.0, .nan, .infinity] {
            #expect(
                OfflinePresentation.transferSummary([job("a", picture, .downloading, progress: progress)]).progress == 0
            )
        }
        #expect(OfflinePresentation.transferSummary([job("a", picture, .downloading, progress: 2)]).progress == 1)
    }

    @Test func trackChipsMergeSavedFilesWithTheLatestAttemptWithoutDuplicates() {
        let saved = entry("a", [picture, sound])
        let jobs = [
            job("a", picture, .completed), job("a", sound, .cancelled),
            job("a", .translation("ru"), .failed), job("a", .translation("ru"), .downloading, progress: 0.4),
            job("other", package, .queued),
        ]
        let chips = OfflinePresentation.trackBadges(saved, jobs: jobs)
        #expect(chips.map(\.id) == [picture.id, sound.id, "vot-ru"])
        #expect(chips.map(\.status) == [.completed, .completed, .downloading(0.4)])
        #expect(chips[0].label == "720p · H.264")
        #expect(chips[1].label == "en · Original")
        var hls = package
        hls.audioLabel = "Russian · AAC"
        #expect(OfflinePresentation.TrackBadge(track: hls, status: .completed).label.hasSuffix("Russian · AAC"))
        let legacy = OfflineTrack(id: "legacy", kind: .translation, label: "Saved translation")
        #expect(OfflinePresentation.TrackBadge(track: legacy, status: .completed).label == legacy.label)
    }

    @Test func storageErrorReplacesEmptyAndLoadingLastsUntilReady() {
        typealias State = OfflinePresentation.PageState
        #expect(OfflinePresentation.pageState(ready: false, error: nil, isEmpty: true) == State.loading)
        #expect(OfflinePresentation.pageState(ready: false, error: nil, isEmpty: false) == State.loading)
        #expect(OfflinePresentation.pageState(ready: false, error: "disk", isEmpty: true) == State.storageError("disk"))
        #expect(OfflinePresentation.pageState(ready: true, error: "disk", isEmpty: true) == State.storageError("disk"))
        #expect(OfflinePresentation.pageState(ready: true, error: "disk", isEmpty: false) == State.content)
        #expect(OfflinePresentation.pageState(ready: true, error: nil, isEmpty: true) == State.empty)
        #expect(OfflinePresentation.pageState(ready: true, error: nil, isEmpty: false) == State.content)
    }

    @Test func changesWaitForBlockedStorageAndAnyPendingRemoval() {
        let removal = OfflineRemoval(videoID: nil, jobIDs: [], assetIDs: [])
        #expect(!OfflinePresentation.isLocked(storageError: nil, persistenceBlocked: false, pendingRemovals: nil))
        #expect(!OfflinePresentation.isLocked(storageError: nil, persistenceBlocked: false, pendingRemovals: []))
        #expect(OfflinePresentation.isLocked(storageError: nil, persistenceBlocked: true, pendingRemovals: nil))
        // The coordinator accepts a second removal while one is pending, so an open confirmation must not submit it.
        #expect(OfflinePresentation.isLocked(storageError: nil, persistenceBlocked: false, pendingRemovals: [removal]))
    }

    @Test func storageFailureWithUnchangedSnapshotLocksAndShowsTheError() {
        // A failed write sets the observed `error` (and the unobserved block flag) without a new snapshot.
        let reason = "The file couldn’t be saved. (NSCocoaErrorDomain, 640)"
        #expect(OfflinePresentation.isLocked(storageError: reason, persistenceBlocked: false, pendingRemovals: nil))
        // With saved content the page keeps it and shows the reason above it; with none the error replaces it.
        #expect(OfflinePresentation.pageState(ready: true, error: reason, isEmpty: false) == .content)
        #expect(OfflinePresentation.pageState(ready: true, error: reason, isEmpty: true) == .storageError(reason))
    }

    @Test func yieldNoticeOnlyWhileADownloadWaitsForThePlayer() {
        let waiting = [job("a", picture, .queued)]
        let finished = [job("a", picture, .completed), job("a", sound, .failed)]
        #expect(OfflinePresentation.showsYieldNotice(isYielding: true, jobs: waiting))
        #expect(!OfflinePresentation.showsYieldNotice(isYielding: false, jobs: waiting))
        #expect(!OfflinePresentation.showsYieldNotice(isYielding: true, jobs: finished))
    }

    @Test func libraryBadgePrefersActivityThenFailureThenPlayability() {
        let saved = entry("a", [muxed])
        #expect(OfflinePresentation.entryStatus(saved, jobs: []) == .ready)
        #expect(
            OfflinePresentation.entryStatus(saved, jobs: [job("a", sound, .downloading, progress: 0.3)])
                == .downloading(0.3))
        #expect(OfflinePresentation.entryStatus(saved, jobs: [job("a", sound, .resolving)]) == .preparing)
        #expect(OfflinePresentation.entryStatus(saved, jobs: [job("a", sound, .queued)]) == .queued)
        #expect(OfflinePresentation.entryStatus(saved, jobs: [job("a", sound, .failed)]) == .failed)
        #expect(OfflinePresentation.entryStatus(saved, jobs: [job("other", sound, .failed)]) == .ready)
        #expect(OfflinePresentation.entryStatus(saved, jobs: [job("a", sound, .cancelled)]) == .ready)
    }

    @Test func playableMatchesWhatTheCoordinatorCanOpen() {
        #expect(OfflinePresentation.isPlayable(entry("a", [muxed])))
        #expect(OfflinePresentation.isPlayable(entry("a", [package])))
        #expect(OfflinePresentation.isPlayable(entry("a", [picture, sound])))
        #expect(!OfflinePresentation.isPlayable(entry("a", [picture])))
        #expect(!OfflinePresentation.isPlayable(entry("a", [sound, .translation("ru")])))
        #expect(OfflinePresentation.entryStatus(entry("a", [sound]), jobs: []) == .notReady)
    }

    @Test func partsListEachSavedKindOnceInDisplayOrder() {
        #expect(
            OfflinePresentation.parts(entry("a", [.translation("ru"), sound, picture, package])) == [
                .video, .audio, .translation,
            ])
        #expect(OfflinePresentation.parts(entry("a", [sound])) == [.audio])
        #expect(OfflinePresentation.parts(entry("a")).isEmpty)
    }

    @Test func failureTextKeepsTheRawReasonAfterAPrefix() {
        for reason in ["HTTP 403", "Download failed (NSURLErrorDomain, -1009). Retry when connected."] {
            let text = OfflinePresentation.failureText(reason)
            #expect(text.hasSuffix(reason))
            #expect(text.count > reason.count)
        }
    }
}

@Suite struct OfflineSavedIDTests {
    @Test func onlyPlayableEntriesAreSaved() {
        func entry(_ id: String, _ kind: OfflineTrack.Kind, audio: Bool = true) -> OfflineEntry {
            let track = OfflineTrack(id: id, kind: kind, label: id, hasAudio: audio)
            return OfflineEntry(
                video: Video(id: id, title: id, channelTitle: "c"),
                assets: [OfflineAsset(track: track, filename: id, systemRelativePath: nil)])
        }
        let ids = OfflinePresentation.savedVideoIDs([
            entry("hls", .hls), entry("video", .video), entry("silent", .video, audio: false),
            OfflineEntry(video: Video(id: "empty", title: "e", channelTitle: "c")),
        ])
        #expect(ids == ["hls", "video"])
    }
}
