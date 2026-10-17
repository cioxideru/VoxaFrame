# PLAN-0019: Independent Shorts playback speed

Status: completed
Owner: primary Codex agent.
Resolution: independent speed and translation synchronization implemented and accepted on iPad Simulator;
Release builds pass for both platforms. Physical-device and live-service checks remain outside this acceptance.

## Scope and boundaries

- Reuse the resource-quality checkout on `mac/shorts-playback-speed`, from local master `145e0d3`.
- Integrate the concurrent iPad-menu follow-up `d9642a6` before final validation and delivery.
- Preserve the primary checkout's staged/unstaged localization, Release Run scheme and local signing settings.
- Add the existing 0.25–2× speed choices to Shorts with separate persisted preferences.
- Seed the new preference from the previous shared speed once on upgrade; later changes stay independent.
- Apply the selected speed to video and Yandex voice-over, including pause/resume, next/preloaded video and relaunch.
- Reuse the existing speed picker and translation synchronization; no new background worker or dependency.
- Keep Core Foundation-only and use Xcode 27.0 for project version changes.

## Acceptance and checkpoints

| Check | Evidence | State |
|---|---|---|
| Cause | Shorts uses the regular player's speed; voice-over already mirrors its video player | confirmed in source |
| Persistence | Separate field, backward-compatible decoding, independent round trip for all offered speeds | PASS |
| Player controls | Shared picker; iPad tests cover paused selection, prepared next video, relaunch and landscape | PASS |
| Translation | Real local video/audio players match selected rates, pause and resume together | PASS |
| Native validation | 1092 tests / 151 suites, strict lint and repository checks | PASS |
| Platform validation | Three iPad UI tests and iOS/tvOS Release app + UI-test builds, repeated after integrating `d9642a6` | PASS |
| Focused review | Independent settings ownership, shared picker, deliberate pause and cancellation, fixture gating | PASS |
| Delivery | Version 5.14 (32); commit and local master delivery, no remote push | local only |

Dependencies: installed Xcode 27.0, local media fixture. Blockers: none.
Version 5.14 (32) is set for both project configurations through Xcode 27.0.
Physical-device and live Yandex-service checks: NOT RUN.

## Execution evidence

- The first iPad run passed persistence/independence but exposed a translation-rate failure:
  native video was playing at 1× while the view model still reported a pause.
  Logs showed translation attachment, an unexpected rate-to-zero event, then native recovery
  before the delayed recovery task. The rate observer previously ignored that recovery.
- The observer now accepts a positive rate only for the same stalled item with an outstanding
  recovery task and an owned audio session. Deliberate holds cancel that task and remain paused.
  A parameterized native regression checks both cases.
- The corrected iPad Pro 11-inch (M5) run passed all three scenarios without skips:
  regular/Shorts independence; pause, prepared-next, rotation and relaunch; translated-audio
  speed, pause and synchronization. Playback uses generated local H.264/HLS and MP3 fixtures
  through the real AVPlayers and voice-over controller, with no external translation request.
- Evidence is retained under the checkout's ignored `.verification/`: `shorts-speed-check-final.log`,
  `shorts-speed-ipad-final.xcresult` (3 tests, 117.144 s), and both `shorts-speed-release-*.log` files.
  The landscape screenshot shows the 0.5× button beside Fit/Fill without overlapping controls.
- After integrating `d9642a6`, `shorts-speed-ipad-integrated.xcresult` passed the same three scenarios
  again (117.211 s). Both `shorts-speed-release-*-integrated.log` files record successful Release
  build-for-testing. Built iOS/tvOS apps and the iOS extensions report 5.14 (32).
- No account, token, live-service translation result or physical-device timing was used as fixture evidence.
