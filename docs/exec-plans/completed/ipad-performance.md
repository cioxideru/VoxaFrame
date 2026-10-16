# PLAN-0010: iPad launch and interaction performance

Status: completed

Resolution: confirmed redundant feed work fixed and measured on the physical iPad.
The broader report of slow behavior throughout the app remains unconfirmed and is
tracked in OQ-0013; these measurements do not establish a general speedup.

Owner: Codex. Git boundary: `mac/ipad-performance`, starting from clean `master`
at `558fba8`. Merge verified changes into local `master` when complete.

## Scope and acceptance

The user reports delays throughout the physical iPad app, including launch from
Xcode. Measure launch and feed scrolling before changing code; check live playback on the candidate.
Use app-scoped Instruments evidence to identify work on the main thread and
unnecessary updates. Preserve account, settings, feed behavior and playback.

Fix confirmed causes in their existing owners. Add focused regression coverage,
repeat the same device scenarios, and record measured changes and limitations.
Package checks and iOS/tvOS builds must pass. Do not edit the Xcode project by hand.

Dependencies: connected unlocked iPad, development signing, the user's existing
account and network. Separate Debug/Release and profiler overhead in comparisons.
Related gaps: [OQ-0013](../../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance).

## Checkpoints

| Step | Evidence / review | State |
| --- | --- | --- |
| Baseline | Physical iPad Pro 11-inch (M5), iPadOS 27.0.1, Debug 5.7 (25), five launch and five scrolling iterations. | Complete |
| Causes | Old integration checkout open in Xcode; hidden Home fetch; foreground/auth ordering races; token rotation replaces the current feed. Device logs and a failing regression test confirm the redundant work. | Complete |
| Fixes | Defer hidden/unauthenticated startup loads; mark queued loads synchronously; skip cancelled requests; preserve feeds on token refresh; clear signed-out widget data directly. | Implemented |
| Device comparison | Four physical iPad tests passed without skips: five launches, five scroll sequences, three tab-navigation loops and three live PiP/fullscreen cycles. | Complete |
| Compatibility | 975 package tests in 139 suites, formatting, source rules, SwiftLint and iOS/tvOS app/UI-test builds passed. | Complete |

## Baseline evidence

- Revision `558fba8`, physical iPad, Debug build, existing account/settings retained.
  Five measured launches to first responsive frame: mean 0.397 s, median 0.399 s.
  These timings exclude the later arrival of feed content and Xcode build/install time.
- Five four-swipe Home sequences: mean application CPU time 3.169 s, mean peak
  memory 71.075 MB, one 8.33 ms scrolling hitch across the five measured iterations.
- An app-scoped launch log recorded three `BrowseViewModel` Home fetch starts,
  alongside the visible Home feed. The foreground refresh could run before the queued task set `isLoading`,
  or start an anonymous request before sign-in replaced it. A hidden section model
  also loaded Home. Refresh now waits until the section has first been requested;
  sign-in/selection owns its initial load.
- A unit regression reproduced token rotation clearing the current cards,
  timestamp and continuation token, and issuing a second Home request.
- Xcode was open on the older integration checkout (`783f764`), which predates
  the merged card-prewarm and player fixes. Opened the main checkout's project.
  This establishes a stale build source, not proof that it caused every reported delay.
- A current-build SwiftUI trace found zero hangs and three short hitches (67 ms
  total). This recording also contains manual navigation, so its aggregate CPU
  and update counts are diagnostic evidence, not a controlled before/after benchmark.

## Device comparison

The baseline and final candidate use the same physical iPad, Debug configuration,
account and five-iteration tests. No debugger or Instruments session was attached
while XCTest measured them. The live feed is network-dependent and can return
slightly different cards; these are small samples, not a general speed guarantee.

| Measurement | Baseline | Final candidate |
| --- | ---: | ---: |
| Mean launch to first responsive frame | 0.397 s | 0.395 s |
| Mean CPU time per four-swipe sequence | 3.169 s | 3.164 s |
| Mean peak physical memory while scrolling | 71.075 MB | 69.486 MB |
| Mean scrolling frame rate | 88.75 fps | 88.58 fps |
| Scrolling hitches across five iterations | 1, 8.33 ms total | 3, 37.50 ms total |

The launch and scrolling differences do not establish a meaningful speedup.
An intermediate five-launch repeat averaged 0.563 s; subsequent repeats averaged
0.394 and 0.395 s. Memory differences may include the live feed's image mix.
The fixed behavior is unnecessary fetch/reload work; frame-perfect scrolling is
not claimed. The final test bundle has four passes, zero failures and zero skips.
Live PiP checks verified advancing playback time after each of three restores.

The final 20.71-second app-scoped startup trace recorded no hangs or animation
hitches. Its log contains one `BrowseViewModel` Home fetch start, down from three
in the baseline. The visible Home feed still has its separate load; the change
removes redundant requests, not all parallel Home networking. Visible feed loading
completed at 3.205 seconds in this trace, a network-dependent observation rather
than a controlled latency comparison.

## Verification and limits

- The original token-refresh regression failed before the fix (cards, timestamp,
  pagination and request-count assertions), then passed. New tests cover both
  foreground/sign-in orderings, cancellation, deferred authentication and widget clearing.
- Full package checks: 975 tests in 139 suites; formatting, source rules and
  SwiftLint passed. iOS and tvOS apps and UI-test targets compiled successfully.
- Xcode's main-checkout project is selected with the SmartTube scheme and physical
  iPad destination. Device tests use a development signing override; no personal
  team identifier or project-file edit is part of this change.
- No Release benchmark, debugger-attached A/B comparison, sustained thermal/memory
  session or systematic cold/warm tap-to-play benchmark was run. The previously
  observed synchronous audio-session warning remains a separate profiling lead.
- The broad report of slow behavior everywhere was not reproduced in these short
  current-build checks. Wider acceptance remains tracked in OQ-0013.

Further profiling scope is recorded in OQ-0013.
