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

- [PLAN-0027: VoxaFrame redesign](active/voxaframe-redesign.md) — staged SwiftUI rollout of the new interface; stage 0 in progress.

- [PLAN-0004: Firebase removal review fixes](active/firebase-review-fixes.md) — review findings 2–6; coordinator owns build/test acceptance.

- [PLAN-0005: Home feed review fixes](active/home-review-fixes.md) — implementation and coordinator acceptance.

- [PLAN-0003: BotGuard / PoToken](active/BotGuard.md) — implemented foundations; live acceptance and token lifetime remain open.

## Completed

- [PLAN-0035: Audio and translation grouping](completed/audio-translation-grouping.md) — separate YouTube/Yandex groups in both dialogs; visually verified and accepted on iPad.

- [PLAN-0034: Offline language defaults](completed/offline-russian-defaults.md) — settings-based audio/Yandex defaults and lower bitrate; download and player labels, absent duplicate choices and working audio confirmed on iPad.

- [PLAN-0032: Saved translation language](completed/offline-translation-language.md) — original-language selection fixed; repaired saved Russian audio, pause and seeking confirmed on iPad.

- [PLAN-0033: iPad sidebar launch warning](completed/ipad-sidebar-state-warning.md) — warning and Queue identity regression fixed; five focused iPad UI tests pass, broader Split View acceptance remains in OQ-0019.

- [PLAN-0031: Offline Yandex translation](completed/offline-yandex-translation.md) — original-language fix verified on iPad; Kazakh service refusal tracked in OQ-0018.

- [PLAN-0030: Resume worktrees and release 5.18](completed/worktree-release-5-18.md) — four pending tasks integrated; 1,347 unit tests, 16 iPad UI tests and all platform builds passed; v5.18 published.

- [PLAN-0028: Physical iPad offline cleanup](completed/offline-ipad-cleanup.md) — protected-package deletion, foreground transfers and background video completion; remaining hardware acceptance in OQ-0018.

- [PLAN-0026: Delete all offline videos](completed/offline-delete-all.md) — confirmed bulk cancellation and cache cleanup.

- [PLAN-0025: Offline selection and deletion](completed/offline-selection-cleanup.md) — explicit video/audio/translation choices and file cleanup.

- [PLAN-0024: Full-screen level gestures](completed/player-level-gestures.md) — brightness/volume adjustment, iPhone/iPad gesture conflict checks and physical iPad calibration.
- [PLAN-0023: VoxaFrame identity](completed/voxaframe-branding.md) — app name, original icon and platform acceptance.
- [PLAN-0020: Playback priority](completed/playback-priority.md) — shared playback demand and bounded optional transfers.
- [PLAN-0022: Initial stream source boundary](completed/stream-source-boundary.md) — isolate initial metadata acquisition without changing fallback order.
- [PLAN-0021: Offline library](completed/offline-library.md) — background media downloads and saved audio translations.


- [PLAN-0019: Independent Shorts playback speed](completed/shorts-playback-speed.md) — separate persisted speed, synchronized translation and native-resume fix; 1092 native tests, three iPad UI tests and iOS/tvOS Release app + UI-test builds.

- [PLAN-0018: Watched-video settings and fork link](completed/hide-watched-settings.md) — consistent feed filtering, 5–100% thresholds and fork URL; 1088 native tests, three iPad UI tests and iOS/tvOS Release builds.

- [PLAN-0017: Subscriptions](completed/subscriptions.md) — account operations and complete channel lists; five fixture UI tests, live subscribe/unsubscribe with restoration, native checks and platform builds.

- [PLAN-0016: iPad menu overlap](completed/ipad-menu-overlap.md) — delegated correction; simulator and physical navigation checks pass, rare sequence remains OQ-0017.

- [PLAN-0015: Bounded Shorts preloading](completed/shorts-preloading.md) — native next-video preparation, bounded retention; 1069 native tests, five iPad UI tests, four memory graphs and iOS/tvOS builds.

- [PLAN-0014: Preserve account feed pagination](completed/shorts-feed-pagination.md) — active-tab and continuation ownership; native checks, four iPad UI tests and iOS/tvOS builds pass.

- [PLAN-0013: Independent Shorts translation settings](completed/shorts-translation-settings.md) — separate persisted preferences; native checks, four focused iPad UI tests and iOS/tvOS builds pass.

- [PLAN-0012: Account Shorts and shared playback controls](completed/shorts-account-controls.md) — account sources, bounded continuation, shared translation/audio and Fit/Fill; native checks, five iPad UI tests and iOS/tvOS builds pass.

- [PLAN-0011: Resource ownership and lifecycle](completed/resource-quality.md) — twelve sequential fixes; native and iPad Simulator package tests, nine iPad UI tests and iOS/tvOS builds pass; physical device checks remain deferred.

- [PLAN-0010: iPad performance](completed/ipad-performance.md) — redundant feed loads fixed; physical launch, scrolling, navigation and PiP checks passed, broader performance acceptance remains OQ-0013.

- [PLAN-0009: Shorts and player presentation stability](completed/player-shorts-stability.md) — controls, bounded readiness and presentation fixes; focused physical iPad PiP and Shorts checks passed, wider acceptance remains OQ-0005.

- [PLAN-0008: Remember playback quality](completed/remember-playback-quality.md) — saved intent, resolution-first fallback and persistence checks.

- [PLAN-0007: Player Fit / Fill control](completed/player-video-scale.md) — toolbar toggle, playback continuity and rotation checks.

- [PLAN-0006: Feed spacing, app version and AVPlayer Shorts](completed/feed-version-shorts.md) — delivered code and simulator checks; physical performance acceptance remains OQ-0013.

- [PLAN-0001: TOS player iOS port](completed/tos-player-ios-plan.md) — historically delivered; superseded by [ADR-0010](../adr/0010-remove-iframe-player.md).
- [PLAN-0002 / #89: Shorts duration guard](completed/task-89-short-detection-issue.md) — fix and regression tests present.

Reviewed against the working tree on 2026-10-17. Historical closure is not a fresh test result.
