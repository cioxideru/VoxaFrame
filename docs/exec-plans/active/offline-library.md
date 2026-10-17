# PLAN-0021 — Offline watch and offline library

Status: active

- Owner: offline-library Astra; coordinator owns platform acceptance and integration.
- Git boundary: `mac/offline-library`, base `0049177`, dedicated clean-start worktree.
- Basis: user offline-watch requirements and the reference mechanism research below.
- Next deliverable: combined iPad Simulator and platform-build acceptance, then local master merge.

## Outcome

Accept Offline watch independently of the current player. Keep accepted requests durable,
show their progress on Offline videos → Downloads, and expose saved video variants,
original/dubbed audio and Yandex translation for local playback. Additional downloads must
not replace working files before their own successful commit.

## Ownership and storage

- Core: OfflineTrack/Entry/Job/Snapshot, actor-isolated OfflineLibraryStore, HLS variant policy.
- Platform: OfflineCoordinator owns scheduling and UI snapshots; OfflineDownloadTransport owns
  background URLSession and AVAssetDownloadURLSession callbacks; OfflineSourceResolver owns
  fresh signed-source resolution; OfflineMedia validates and composes local media.
- Direct media uses UUID filenames in Documents/SmartTubeOffline. HLS packages stay at the
  system-provided Library location, represented by a container-relative reference and an optional flag preserving Apple’s `/.nofollow` protection. The legacy
  DownloadStore, SmartTubeDownloads and Video.localFileURL path remain supported.
- Manifest writes are atomic. Monotonic revisions prevent older asynchronous snapshots from
  restoring cancelled attempts. An attempt UUID identifies each resolver and transfer callback.
- Completion receipts precede manifest publication and survive removal of the system task.
  Replacement cleanup happens after commit; stale completions can delete only their own files.
- Signed media URLs are re-resolved for a new attempt. OAuth credentials and feed feedback
  tokens are not written to the manifest.

## Scheduling and background behavior

One system media transfer runs at a time. PlaybackDemandCoordinator is the only playback-pressure
source; its signal suspends/resumes accepted system tasks. A single Yandex poll releases the
resolver slot while waiting. The next poll time and finite poll budget are durable; one timer
wakes due work without preventing other videos from downloading.

URLSession transport can continue after ordinary backgrounding. Translation preparation and
source resolution run only while the app executes; suspension preserves their accepted request
for relaunch. Force quit does not promise continued downloading. Background-session completion
handlers run only after preceding completion events have committed their state.

## UI and local playback

Offline watch appears in player and video-card menus. Offline videos has Library and Downloads
segments. Saved video variants are playable with selected saved audio and optional local Yandex
MP3. Online refresh lists downloadable alternatives; failures keep earlier variants intact.

A local playback request never falls through to a remote stream. Source identity includes local
video/audio/translation files, including when the YouTube video ID is unchanged. Local VOT uses
the existing controller and its pause/rate/seek synchronization, without precise MP3 timing.
HLS entries report adaptive or actual known variant metadata; an external audio-group playlist
is not offered as a standalone muxed variant.

## Acceptance evidence

- Added deterministic OfflineLibraryTests for restoration, stale completion, retry, additive
  failure, transactional replacement, completion receipts, notification batches, paths, source
  identity, transient local URLs, HLS metadata and audio metadata preservation.
- Added OfflineCoordinatorTests with fake transport/resolver/notifications and injected time.
- Targeted package compilation/tests: PASS, 24 tests in 3 suites (2026-10-17), including
  real local AV audio/VOT pause, rate and seek, no-network local failure, notification-marker
  persistence recovery, cancellation during companion-audio discovery, orphan transfer recovery
  replacement of a stalled resolver without waiting for its late response, actual HLS-size metadata
  compatibility, protected-path round trips and safe cleanup of equivalent local URLs.
- iOS build-for-testing: PASS on Xcode 27.0, iPad 11 M5 destination, existing UI-test target included.
- Full CI: PASS, 1126 tests in 156 suites, secrets/doc links/Core boundary/format passed.
- SwiftLint: PASS against existing baseline. tvOS build: NOT RUN.
- MP4 iPad UI: PASS for real background 360p/720p downloads, separate AAC, local VOT and replay.
  `/private/tmp/offline-ui-acceptance.xcresult` contains one passing MP4 scenario and the earlier
  HLS failure, subsequently fixed below; this bundle is not a combined passing result.
- HLS iPad UI: PASS, 1/1 in 75.8s, `/private/tmp/offline-hls-nofollow.xcresult`.
  Verified saved HLS, actual 360×640 metadata, local VOT, playback after relaunch and no original
  media requests. The fix retains protected `/.nofollow` I/O and uses playable-offline cache
  validation, because a downloaded HLS asset need not expose file/composition tracks.
- Separate audio-file overrides for HLS are explicitly unavailable; included audio and local
  VOT remain supported. Direct video files support the separately saved original/dubbed audio.
- Combined platform acceptance remains pending with the coordinator. Physical-device background
  recovery, actual airplane mode and physical-device VOT synchronization: NOT RUN.

## Reference use

Read-only comparison with AxrTube da25c6288103ec78296a12f7aeec5248180c83c4 informed queue invariants.
No substantial source was copied, and no external code or dependencies were executed.
