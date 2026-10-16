# PLAN-0009: Shorts and player presentation stability

Status: completed

Resolution: implementation and focused simulator/physical iPad acceptance are
complete. Wider device acceptance remains OQ-0005 and physical performance
measurement remains OQ-0013. This delivery is local; remote publication is not included.

Follow-up: the user confirmed system PiP and Shorts with a black screen or endless
loading. Item-readiness waits now have a deadline. Focused physical iPad PiP and
Shorts checks passed; long-session reliability and background recovery remain in
[OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).

Owner: Codex. Git boundary: `mac/player-shorts-stability`, based on clean
`master` at `d0de23f`. No unrelated changes were present.

## Scope and basis

The user reports unreliable Shorts loading, missing Shorts controls, a black
background when entering Picture in Picture, intermittent missing video after
returning to fullscreen, and the old Recommendations layout on iPad.

Trace playback and presentation ownership before editing. Keep one regular
player and video layer through presentation changes. Reuse existing playback
controls, feed layout, settings, accessibility identifiers and test seams.
Do not edit the Xcode project by hand or extend the legacy fallback cascade.

## Acceptance and next deliverable

- Shorts expose pause/play, mute and seeking, with retry after a load error.
- Changing Shorts cannot apply stale loading or resume state to another video.
- PiP reveals the previous app screen and restores fullscreen before confirming
  UI restoration. Mini-player transitions preserve the player item and time.
- Recommendations use the same mixed feed layout as Home.
- Package checks, iOS/tvOS test builds and focused iPad UI tests pass.

Dependencies: existing AVPlayer pipeline and authenticated YouTube responses.
Physical-device PiP and live stream availability require device verification;
simulator navigation tests alone cannot establish these outcomes.

## Checkpoints

| Step | Evidence / review | State |
| --- | --- | --- |
| Trace affected owners and callers | PiP delegate confirmed restoration immediately; controller belonged to a dismissible view; Shorts only had Back. Pending resume state survived a new load. | Complete |
| Controls and loading | Persistent accessible pause/mute/seek/retry controls; navigation gestures stay below the overlay so they cannot cancel slider editing. New loads clear pending seek/duration state; Shorts ignore saved watch position. Retry cancels superseded work. Initial/fallback item readiness is limited to 15 seconds per candidate. | Complete |
| Presentation | Store owns PiP and the persistent backing AVPlayerLayer. Only the active container may attach the layer. UIKit completion replaces delay-based presentation suppression and signals PiP UI restoration. | Complete |
| Recommendations | Shelf responses use the same interleaved video grid as Home; a regression test covers shelf-shaped data. | Complete |
| Unit/static checks | 968 tests in 139 suites, source/document/format checks and strict SwiftLint passed on 2026-10-16, including readiness deadline, cancellation and replacement-item isolation. | Passed |
| Build compatibility | Final iOS and tvOS build-for-testing passed with both UI-test targets using Xcode 27 after the readiness and physical-test follow-ups. | Passed |
| iPad simulator navigation and feeds | 11 Shorts navigation/control tests, 6 mixed-feed tests, live pause/mute/seek/next test, live Home → Shorts → next → previous test, and three fullscreen/mini-player cycles passed on iPad Pro 11-inch (M5), iOS 26.5. No skips in the final runs. | Passed |
| Video scale and rotation | Fit/Fill changes and portrait/landscape rotation preserve playback after the shared-layer change. Together with the scenarios above, 21 focused UI tests passed. | Passed |
| Physical iPad PiP | `SystemPiPRestorationUITests.testSystemPiPRevealsPreviousScreenAndRestoresPlayback` passed on iPad Pro 11-inch (M5), iPadOS 27.0.1: three PiP/fullscreen cycles, Home visible underneath, preserved time and continued playback. | Passed |
| Physical iPad Shorts | `ShortsLiveSwipeUITests.testLiveShortSwipeUpThenDown` passed on the same device: Home → Shorts → next → previous, advancing playback time, hittable pause/mute/seek controls. The two physical tests executed without skips on 2026-10-16. | Passed |
| Visual checks | Inspected actual video after each physical PiP return and on both Shorts plus the return to the first. Full-screen captures show the Shorts controls within the display. | Passed |
| Wider device acceptance | Long sessions, background/foreground recovery, the codec matrix and tvOS runtime were not tested by these focused scenarios. Physical performance remains OQ-0013. | NOT RUN |

The first live-feed test used the retired `video.card` identifier and skipped;
it was corrected to `AccessibilityID.shortsCard` and rerun successfully. The first
seek test exposed a gesture conflict; its passing rerun verifies continuing time
after seeking, rather than only a changed slider value. These earlier runs are
not counted as acceptance.

PiP follows Apple's [custom-player restoration contract](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player).
An immediate capture in an earlier PiP run was black while time advanced. The final
test waits for at least two seconds of playback after each restoration; all three
captures show video. This verifies recovery, not absence of a transient black frame.
Next deliverable: the wider device matrix in OQ-0005. No independent review, remote
publication or physical-device performance claim is included in this delivery.

## Clarification follow-up

- Confirmed: popup is system PiP; Shorts can remain black or loading without an error.
- Initial and fallback AVPlayer readiness waits had no deadline. Added a shared
  15-second limit per stream candidate, preserving the existing fallback order.
- Verified deadline completion, cancellation and replacement-item isolation without
  network or fixed sleeps in package tests; repeated live Shorts and system PiP on iPad.
- Physical system PiP evidence is recorded separately from simulator mini-player
  acceptance. Neither test establishes a whole-app performance improvement.
