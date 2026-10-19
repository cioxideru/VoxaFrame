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
        waitsUntil: Date? = nil
    ) -> OfflineJob {
        OfflineJob(
            id: UUID(), batch: UUID(), attempt: UUID(), videoID: video, track: track, state: state, progress: progress,
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
        expect(job("a", picture, .completed, progress: 1), .completed, .open)
        expect(job("a", picture, .failed), .failed, .retry)
        expect(job("a", picture, .cancelled), .cancelled, .retry)
    }

    @Test func jobsStayUnderTheirVideoInQueueOrder() {
        let jobs = [
            job("b", picture, .downloading), job("a", sound, .queued), job("b", sound, .queued),
            job("a", .translation("ru"), .queued),
        ]
        let groups = OfflinePresentation.groups(
            jobs: jobs, entries: [entry("a", title: "First"), entry("b", title: "")])
        #expect(groups.map(\.videoID) == ["b", "a"])
        #expect(groups.map { $0.jobs.map(\.id) } == [[jobs[0].id, jobs[2].id], [jobs[1].id, jobs[3].id]])
        // A deep-linked video can be saved without a title; the ID stands in for it.
        #expect(groups.map(\.title) == ["b", "First"])
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
