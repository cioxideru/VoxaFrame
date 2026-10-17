# PLAN-0015: Bounded Shorts preloading

Status: completed

Owner: Codex. Branch: `mac/shorts-preloading`, based on local `master` at `e7a2db1`.
Work takes place in the attached resource-quality worktree. The primary checkout's
user localization and local signing settings must remain intact. Merge locally after checks; no push.

## Scope and basis

Full-screen swipes currently clear the player and resolve/load a fresh stream. The view's
unowned lookahead tasks warm general metadata, not media. Its video list, continuation history
and the regular player's navigation history also grow during a long Shorts session.

Keep the existing playback engine, quality policy, audio/translation controls and native video
surface. Prepare only the next Short in a session-owned muted native player. Do not add another playback
engine, speculative legacy source retries, a disk media cache or dedicated worker threads.

Runtime owner and first fix: `ShortsPreloader` beside the playback services, owned by the Shorts
`PlaybackViewModel`. Canonical policy owner: Foundation-only rolling-window state in Core;
AVFoundation preparation stays in the platform module. The view supplies navigation/lifecycle
intent. The shared feed metadata cache and individual cards must not own native media buffers.

## Acceptance

- The next Short is actually prepared by AVFoundation and its whole native player is adopted
  by the existing video surface on swipe. A miss uses ordinary playback recovery.
- At most one owned speculative task and one prepared media item; finite preparation time and
  buffer/quality hints; no speculative history, translation, tracking or persistent media writes.
- Rapid swipes, settings changes, background, memory pressure, account change and dismissal
  cancel/release stale work. A late completion cannot install an obsolete item.
- Retained feed/history/cursors stay bounded over a long viewing session.
- Deterministic tests cover limits, promotion, cancellation, stale completion and release.
  iPad Simulator playback measures cold versus warm switches and exercises sustained swiping;
  memory evidence checks live object ownership and cleanup rather than claiming from RSS alone.
- Existing controls and iOS/tvOS app/UI-test builds pass. Required native checks pass.
- Update app version through Xcode, document measured evidence, commit and merge local master.

## Checkpoints

| Work | Evidence / review |
|---|---|
| Inspect current owners and critical path | Complete; metadata lookahead is unowned, no native item reuse |
| Implement bounded preparation and rolling retention | Complete; [ADR-0011](../../adr/0011-bounded-native-shorts-preloading.md) records ownership and alternatives |
| Native regression and lifecycle tests | 1069 tests in 149 suites pass, including weak-reference destruction of VM/preloader/both items |
| iPad playback latency, sustained session and memory | Five UI tests pass: A/B, 60 swipes/background/resume/reopen, translation/scale persistence, pagination and backward navigation; four memory graphs report zero leaks |
| Required checks and platform builds | Secrets, links, formatting, source boundaries and strict lint pass; iOS/tvOS apps and UI-test targets build successfully |
| Version and final review | Xcode GUI set 5.12 (30); built apps/extensions confirm matching versions; concurrency, lifecycle and diff review complete |

Dependencies: existing VISIONOS HLS path and filtered master loader, local iPad Simulator.
Blockers: none. Delivery: commit this plan with the implementation and merge locally into `master`.
Physical iPad/live YouTube profiling remains separate acceptance in OQ-0013; no remote push.

## Measurement evidence

Xcode 27.0 (27A266a), iPad Pro 11-inch (M5) Simulator, iOS 26.5. A local generated
H.264/AAC stream adds fixed 350 ms manifest and 250 ms initial-segment latency;
[test instructions](../../how-to/run-tests.md#local-shorts-preloading-measurements) reproduce it.
Final cold load-to-ready samples: 1016, 1031, 1025, 1016, 1019 ms; prepared: 74, 62, 68, 64, 61 ms.
Median: 1019 → 64 ms (about 94% lower). The test also requires the playback clock to advance and next-item media
to be buffered; screenshots show rendered video. These are readiness measurements, not
first-frame, physical-device or live YouTube timing claims.

Memory graphs from the same process near transitions 10, 30 and 56 each contain two native
media items, three playback models and two preload coordinators (including SwiftUI's retained
initial view value); none of those counts grows. `leaks` reports zero leaks in all three graphs.
Physical footprint is 40.3, 50.0 and 49.8 MiB, peak 72.8 MiB; this short sample is not proof of
an absolute byte ceiling. Native retention tests separately cover 10,000 feed transitions and
1,000 playback resets, stale completion, deadline, memory pressure and explicit release.
The final run's capture after dismissal/reopening has two playback models (regular + Shorts),
one preloader, two media items and zero leaks, with a 39.6 MiB footprint. The prior presentation's
owners were released, rather than accumulating per opening.

The first sustained UI run reached 60 prepared transitions, then expected automatic resume
after backgrounding. Existing default behavior deliberately pauses without automatic resume;
the final test checks released preparation and explicitly presses Play before continuing.
