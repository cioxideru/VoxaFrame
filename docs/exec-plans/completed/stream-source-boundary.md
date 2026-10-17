# PLAN-0022 — Initial stream metadata boundary

Status: completed

Resolution: scoped implementation accepted with native, platform-build and Simulator checks.
Physical and live-service acceptance remains tracked separately in OQ-0018.

- Owner: stream-source Astra; coordinator owns acceptance, shared documentation, commit and merge.
- Git boundary: `mac/stream-source-boundary`, base `6eb7158`, dedicated `stream-source-boundary/SmartTubeIOS` worktree. Initially clean.
- Priority: below playback demand and offline isolation work.
- Basis: [ADR-0005](../../adr/0005-stream-source-pipeline.md), [architecture](../../architecture.md); Aixile `20805ed7a0313b721f77fee1830daca4840fa367` supplies a narrow source-boundary idea only. Foreign code was read, not run.

## Scope and constraints

Extract the initial metadata source decision into `InitialPlayerInfoSource`: consumed cache,
shared in-flight task, direct VISIONOS with HLS, then the existing legacy metadata operation.
The source owns ordering, HLS acceptance, direct-error fallback and storage of new results.
Its four injected operations expose network/cache seams without a new protocol or dependency.

`PlaybackViewModel` retains legacy browser preparation, iOS/TV/Android error guards, stale-video
and cancellation checks before application, quality/codec/audio policies, resume, AVPlayer,
audio session and presentation. Shared requests are awaited but never cancelled by this source.
As before, cached/coalesced metadata need not contain HLS; only direct VISIONOS success sets the
explicit VISIONOS HLS hint. Cancellation after a successful fetch still reaches the caller's
existing guard; the source checks cancellation before entering legacy after a direct miss.

No changes to cache ownership, Shorts, offline code, shared VM files, project settings or
exhaustive retry. This is the first small boundary, not a completed ResolutionPipeline or
implementation of all ADR-0005. No performance improvement is claimed.

## Acceptance and next deliverable

- Characterize cache/coalescing/direct/fallback ordering, no-HLS and errors, storage, request
  identity and consumer cancellation without cancelling the shared metadata task.
- Review the unchanged VM stale-video/cancellation guards and legacy error logic by diff.
- Run focused Swift Testing, then coordinator-required CI/build checks in the allocated window.
- Coordinator links this plan in shared indexes before documentation checks.

## Checkpoints

| Checkpoint | Evidence | Result |
| --- | --- | --- |
| Scope | Only new source/tests, initialPlayerInfo segment and this plan | Accepted by coordinator |
| Implementation | Four-operation metadata source, no player ownership | Ready for review |
| Environment | Xcode 27.0, build 27A266a | Confirmed |
| Focused tests | `swift test --filter InitialPlayerInfoSourceTests`; 7 tests / 1 suite, including 3 two-case tests; `/private/tmp/plan0022-focused.log` | PASS |
| Project CI | `scripts/ci.sh`; secrets, doc links, Core imports, formatting and 1099 tests / 152 suites; `/private/tmp/plan0022-ci.log` | PASS |
| Strict SwiftLint | `swiftlint lint --strict --baseline .swiftlint.baseline --config .swiftlint.yml`; `/private/tmp/plan0022-swiftlint.log` | PASS |
| Whitespace | `git diff --check` | PASS |
| Platform builds / device playback | Not included in the allocated verification window | NOT RUN |
| VM stale-video integration behavior | Guards retained verbatim; no new VM injection seam | Runtime check NOT RUN |

## Dependencies and blockers

No public cache interface or shared-file edits required. Coordinator-authorized native checks
completed sequentially on Xcode 27.0. The source change is committed in `9a19054` and integrated with playback priority and branding
in `8a15d9b`. Full pipeline parity and hardware performance are outside this step.

## Combined integration checks — 2026-10-17

- Xcode 27.0: Release app and UI-test-target builds PASS for both iOS and tvOS.
  Logs: `/private/tmp/voxaframe-ios-release-build.log` and
  `/private/tmp/voxaframe-tvos-release-build.log`. Build output paths were isolated.
- iPad Pro 11-inch (M5) Simulator: both `DownloadsPlaybackUITests` scenarios PASS,
  zero failures/skips, 170.5 seconds; `/private/tmp/voxaframe-final-ui.xcresult`.
  These exercise real URLSession/AVAssetDownloadURLSession and AVPlayer with synthetic local media:
  additional quality/AAC/VOT, saved HLS resolution, rotation, relaunch and unchanged original-media request counts.
- Independent merge review found no loss of the stream-source boundary, playback-demand reset,
  local-source identity, cancellation guards or offline scheduling ownership.
- Built iOS/tvOS bundles report VoxaFrame 5.15 (33), retaining the existing bundle identifier.
  The chosen icon and VoxaFrame label were visually verified on the Simulator home screen.
- Physical background delivery, real YouTube/Yandex requests and measured playback-priority
  benefit remain in [OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad).

## Final gate

- Combined `scripts/ci.sh`: PASS, 1133 tests in 157 suites; secrets, links, Core imports
  and formatting pass. `/private/tmp/voxaframe-final-ci.log`.
- Strict baseline SwiftLint: PASS, zero violations across 429 files.
  `/private/tmp/voxaframe-final-lint.log`.
- Rotation follow-up: PASS, one scenario, zero skips, 96.2 seconds;
  `/private/tmp/voxaframe-rotation-final.xcresult`. The test waits for the app's landscape
  bounds and advancing playback. `XCUIScreen` capture confirms the final layout;
  the first XCTest window is an empty auxiliary window and must not be used for this assertion.
