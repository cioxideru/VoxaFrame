# PLAN-0011: Resource ownership and lifecycle fixes

Status: active

Owner: Codex coordinator with Astra agents, one implementation task at a time.
Git boundary: `mac/resource-quality`, based on `9e82c1d`, in a managed worktree.
The main checkout's pre-existing localization edits are outside this task.

## Scope and acceptance

Implement the twelve findings from the architecture, concurrency and memory audit
in their numbered order. Each step needs a focused regression check and coordinator
review before the next begins. Preserve playback, pause, PiP, account isolation,
feed behavior and cross-platform builds. Architectural moves must remove concrete
ownership conflicts; no project-file hand edits or unrelated rewrites.

Use iPad Simulator for final UI validation. Physical iPad testing is explicitly
deferred by the user until every item is complete. Simulator results do not prove
physical PiP, hardware codec decoding or device performance.

After all checks pass, commit the scoped changes and merge into local `master`.
Do not push. Related device acceptance remains in
[OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance) and
[OQ-0013](../../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance).

## Ordered checkpoints

| # | Fix | Agent area | Evidence / status |
| --- | --- | --- | --- |
| 1 | Own/cancel background quality upgrade; preserve pause and session identity | Concurrency | Implemented and reviewed; 33 focused tests pass across 6 suites |
| 2 | Cancel individual BotGuard waiters without blocking fallback timeout | Concurrency | Implemented and reviewed; 4 waiter tests; full check passes, 983 tests |
| 3 | Bind BotGuard safety timer and completion to one attempt | Concurrency | Implemented and reviewed; controlled timer/stale callback tests and JS syntax check; full check, 986 tests |
| 4 | Separate subscription cancellation/failure from empty results; bound work | Concurrency | Implemented and reviewed; cancellation/retry and 4-channel/8-request bound tests; full check, 990 tests |
| 5 | Stream translation audio through bounded buffers and temporary files | Memory | Pending |
| 6 | Bound and atomically invalidate WK-HLS cache entries | Memory | Pending |
| 7 | Apply History settings to the actual Home section model | Architecture | Pending |
| 8 | Remove stale duplicated current-video state from presentation | Architecture | Pending |
| 9 | Share one Home feed result with its widget | Architecture | Pending |
| 10 | Move UI/AVPlayer responsibilities out of Core and check the boundary | Architecture | Pending |
| 11 | Release inactive parked player/WebView resources on idle/pressure | Memory | Pending |
| 12 | Measure and serialize audio-session transitions outside UI work | Concurrency | Pending |

## Verification

Use deterministic unit tests with fakes and controlled clocks for cancellation,
timers, buffering, eviction and state ownership. UI tests exercise the composition
on iPad Simulator. Run package checks, strict SwiftLint, iOS/tvOS builds including
UI-test targets, and selected iPad UI regressions before merging. Keep performance
measurements distinct from correctness tests and do not infer a device speedup.

## Ownership direction

- Runtime owners: playback view model, presentation store, feed models and platform services.
- First fix owners: the existing classes responsible for each checkpoint.
- Canonical long-term owners: playback session state owns its work; Home owns its feed;
  platform adapters own AVPlayer/WebView/audio session; Core owns pure decisions/models.
- Competing owners to remove: detached upgrade work, independent copies of current video,
  duplicate Home loading for widgets and settings wired to the wrong feed instance.
- Cleanup direction: prove behavior per step, then remove the replaced path in that same step.

Next deliverable: item 5, bounded translation audio transfer.
