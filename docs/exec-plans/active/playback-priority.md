# PLAN-0020 — Active playback priority

Status: active

- Owner: playback-priority agent; coordinator owns integration and acceptance.
- Git boundary: `mac/playback-priority`, base `6eb7158`, isolated `playback-priority/SmartTubeIOS` worktree.
- Initial working tree: clean.
- Scope: shared playback-demand signal, bounded metadata queue, native Shorts preparation, deterministic tests.
- Constraints: preserve shared stream requests, fallback order, quality, speed and voice-over; no dependencies or project-file edits.
- Basis: [architecture](../../architecture.md), [ADR-0011](../../adr/0011-bounded-native-shorts-preloading.md); read-only AxrTube mechanism research supplied by coordinator.
- Dependencies: shared playback integration points and offline subscriber contract coordinated with parent agent.
- Next deliverable: coordinator review and platform-build acceptance; implementation and native gates are complete.
- Acceptance: startup and later buffer wait yield optional work; cancellation/video changes cannot revive stale work; resume is bounded and coalesced requests survive promotion; sustained buffer pressure cannot starve optional work.
- Blockers: none for native verification; simulator builds and physical measurements remain coordinator-owned.

## Policy

One Foundation-only coordinator owns the decision. Owner-specific leases prevent a stopped player from clearing another player's demand. Initial preparation yields until actual playback, error or cancellation. A stable recovery delay prevents flapping; a maximum continuous buffering yield releases optional work for the rest of a prolonged episode. These timings are policy defaults, not measured performance claims.

## Checkpoints

| Check | Evidence | Result |
| --- | --- | --- |
| Initial inspection | Cache uses separately owned player fetches; Shorts owns one task and player | Complete |
| Focused native tests | `swift test --filter 'PlaybackDemandTests|PlaybackPriorityCacheTests|ShortsPreloadingTests'`; final 17 tests / 4 suites | PASS |
| Complete native gate | `scripts/ci.sh`; final 1100 tests / 153 suites, secrets, links, Core imports, format; `/private/tmp/playback-priority-ci.log` | PASS |
| Strict SwiftLint | `swiftlint lint --strict --baseline .swiftlint.baseline --config .swiftlint.yml`; 0 violations; `/private/tmp/playback-priority-swiftlint.log` | PASS |
| Simulator builds | Serialized with coordinator | NOT RUN |
| Physical iPad comparison | No device experiment in this task | NOT RUN |

## Implementation and interface

`PlaybackDemandCoordinator` is Foundation-only and `@MainActor`. The UI extension owns its shared instance and uses `PlaybackTuning` for a one-second recovery delay and ten-second later-buffering budget. `update(owner:phase:)` accepts `inactive`, `preparing`, `buffering`, or `playing`; `remove(owner:)` releases a lease. `changes()` replays the current `Bool` and buffers only the newest value. Offline consumers subscribe to that stream and must not derive their own pressure policy.

The AVPlayer adapter reads actual `timeControlStatus`, keeps startup demand after item readiness until playback starts, and follows the audio-session ownership/lifecycle. Metadata cancellation stops only optional children, preserves shared stream fetches, retains bounded queued work, and counts surviving streams against speculative admission. Shorts retains only the latest target with a weak outgoing-item anchor, cancels preparation while yielding, and preserves background/memory/expiry cancellation. Promotion removes speculative ownership before any later pressure can affect the adopted player.

New deterministic tests cover recovery hysteresis, initial playback, repeated buffer waits, owner removal, replacement and teardown, starvation budget, deferred Shorts cancellation and memory pressure, shared stream promotion, and surviving-stream concurrency bounds. The fake transport awaits teardown between cases; no new tests use live network or fixed sleeps.

## Post-gate review correction

Coordinator review requested an explicit demand reset in `resetPlaybackForLoad`, immediately before assigning the new video after the old player is paused/cleared. This also handles a fresh load of the same ID. It deliberately does not reset in `currentVideo.didSet`, because mutations of video metadata also invoke that observer. The adapter reset clears its preparation latch. The adapter test now covers both same-ID and different-ID replacement. The first integration rerun exposed a test-only stale timer: `DemandGate` deliberately ignores cancellation, and the additional stop left an old recovery continuation queued. The regression now explicitly delivers that cancelled continuation and checks that new preparation still owns priority before testing the next stop. No production change was needed for this failure. Final focused tests (17 / 4 suites), complete CI (1100 / 153 suites), strict SwiftLint (0 violations), and diff checks passed after this correction.

## Remaining evidence

No device speedup, bandwidth reduction or battery improvement is claimed. Existing in-flight shared stream requests intentionally finish, because a foreground consumer may already depend on them. Initial preparation has no separate pressure timer and relies on the existing playback timeout/error/cancellation lifecycle. Simulator builds, PiP on hardware, and a live iPad comparison have not been run in this workstream.
