# PLAN-0054: Resume follows YouTube's full completion

Status: completed (2026-11-20)
Resolution: resume follows YouTube's full completion; OQ-0025 closed. On-device check NOT RUN.

- Owner: playback maintainer; one commit, merged into `master`.
- Basis: OQ-0025 (closed by this plan), left open by [PLAN-0050](upstream-small-fixes.md) item 2.
- Decision (user, 2026-11-20): when YouTube reports a video as 100 % watched, playback starts from the beginning and
  the older position saved on the device is dropped, matching the 100 % that cards and Offline rows already show.
- Constraints: `SmartTubeIOSCore` stays Foundation-only; no new branches in the playback fallback cascade (ADR-0005).

## Change

`PlaybackViewModel` reads the position to restore from `VideoStateStore.resumeState(for:)` instead of
`state(for:)`. The new method returns nil and clears the saved entry when the opened `Video` carries YouTube's full
completion (`Video.isFullyWatchedOnYouTube`, the same threshold `displayedWatchProgress(saved:)` uses); otherwise it
returns the saved state as before. A video opened without YouTube progress (a link, a downloaded copy without
metadata) keeps the local position.

## Acceptance

- Swift Testing tests at the store seam: full remote completion drops a saved 30 s of 100 s; partial or missing
  remote progress keeps it. No live network, no `Task.sleep`.
- `scripts/ci.sh`, SwiftLint and the ast-grep rules before the commit; iOS, tvOS and macOS builds.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Resume decision | user chose "start from 0" | done |
| Resume change | `RemoteCompletionResumeTests`: a saved 30 s of 100 s is dropped and not restored when YouTube reports 100 %; with no, 50 % or 99 % YouTube progress the 30 s are restored and kept | done |
| Checks | `scripts/ci.sh`, SwiftLint, ast-grep rules; iOS, tvOS and macOS builds | done |
