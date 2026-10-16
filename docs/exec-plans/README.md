# Execution plans

Multi-step implementation work lives here. Design descriptions belong in [design](../design/),
decisions in [ADRs](../adr/README.md), and historical investigations in [archive](../archive/).
The [document index](../README.md) lists every document; [open questions](../OPEN_QUESTIONS.md)
tracks unfinished work, debt, missing verification, and decisions.

## Lifecycle

- Give a plan a permanent `PLAN-NNNN` ID; preserve existing issue/task IDs.
- Put it in `active/` with a plain `Status: active` or `Status: blocked` line (a list prefix is allowed).
- Record owner, Git boundary and working-tree state, scope, constraints, basis, next deliverable,
  acceptance criteria, dependencies, blockers, and a checkpoint table with evidence and review results.
- Keep execution evidence distinct from the original design. `NOT RUN` describes a check, not success.
- Move to `completed/` and set `Status: completed` when accepted work is delivered. For a historical,
  cancelled, superseded, or partial delivery, add `Resolution:` explaining the outcome, evidence,
  replacement, and any remaining items in the open-question register. Moving a file alone proves nothing.
- Directory `README.md` files are indexes, not plans. Do not reuse IDs or invent commit/review evidence.

## Active

- [PLAN-0004: Firebase removal review fixes](active/firebase-review-fixes.md) — review findings 2–6; coordinator owns build/test acceptance.

- [PLAN-0005: Home feed review fixes](active/home-review-fixes.md) — implementation and coordinator acceptance.

- [PLAN-0003: BotGuard / PoToken](active/BotGuard.md) — implemented foundations; live acceptance and token lifetime remain open.

## Completed

- [PLAN-0012: Account Shorts and shared playback controls](completed/shorts-account-controls.md) — account sources, bounded continuation, shared translation/audio and Fit/Fill; native checks, five iPad UI tests and iOS/tvOS builds pass.

- [PLAN-0011: Resource ownership and lifecycle](completed/resource-quality.md) — twelve sequential fixes; native and iPad Simulator package tests, nine iPad UI tests and iOS/tvOS builds pass; physical device checks remain deferred.

- [PLAN-0010: iPad performance](completed/ipad-performance.md) — redundant feed loads fixed; physical launch, scrolling, navigation and PiP checks passed, broader performance acceptance remains OQ-0013.

- [PLAN-0009: Shorts and player presentation stability](completed/player-shorts-stability.md) — controls, bounded readiness and presentation fixes; focused physical iPad PiP and Shorts checks passed, wider acceptance remains OQ-0005.

- [PLAN-0008: Remember playback quality](completed/remember-playback-quality.md) — saved intent, resolution-first fallback and persistence checks.

- [PLAN-0007: Player Fit / Fill control](completed/player-video-scale.md) — toolbar toggle, playback continuity and rotation checks.

- [PLAN-0006: Feed spacing, app version and AVPlayer Shorts](completed/feed-version-shorts.md) — delivered code and simulator checks; physical performance acceptance remains OQ-0013.

- [PLAN-0001: TOS player iOS port](completed/tos-player-ios-plan.md) — historically delivered; superseded by [ADR-0010](../adr/0010-remove-iframe-player.md).
- [PLAN-0002 / #89: Shorts duration guard](completed/task-89-short-detection-issue.md) — fix and regression tests present.

Reviewed against the working tree on 2026-10-16. Historical closure is not a fresh test result.
