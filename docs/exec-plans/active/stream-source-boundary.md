# PLAN-0022 — Initial stream metadata boundary

Status: active

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
completed sequentially on Xcode 27.0. Changes remain uncommitted for acceptance. Full pipeline
parity and hardware performance are outside this step.
