# PLAN-0012: Account Shorts and shared playback controls

Status: completed

- Owner: Codex.
- Git boundary: `mac/shorts-controls`, based on local `master` `0456764`, in the existing
  `resource-quality` worktree. Initially clean. The main checkout's unrelated localization
  changes remain outside this task.
- Scope: use account sources for signed-in Shorts; continue the same feed when swiping;
  share the regular player's audio/translation picker; use the persisted Fit/Fill setting.
- Constraints: reuse playback and Yandex lifecycle; no extra parallel subscription fetch on
  Home/Recommended; no synchronous network work; Xcode-only project edits; no remote push.
- Basis: `fetchShorts` searched `#shorts` anonymously, overriding account Shorts.
  Both player pagination directions fetched the first page again. Shorts hard-coded Fill and
  omitted the existing audio picker. TV OAuth supports the subscriptions browse; account Home
  may also contain Shorts. This does not claim identical ranking to YouTube's mobile reel feed.
- Outcome: account source routing, bounded continuation and shared playback controls delivered.
- Dependencies: existing TVHTML5 OAuth, `PlaybackViewModel`, Yandex VOT, SettingsStore.
- Remaining acceptance: live account relevance, Yandex service audio/synchronization and
  physical-device checks are tracked in [OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).

## Acceptance

- Signed-in Shorts never silently fall back to global search; authenticated continuation
  retains its source, and Home/Recommended reuse the subscription response they already load.
- Shorts exposes original/dubbed audio and the same Yandex controls as the regular player;
  mute affects both audio players, and changing/closing a Short cancels translation.
- Fit/Fill uses the saved setting without replacing the AVPlayer item; it survives rotation,
  the next Short, and relaunch.
- Required native checks, iOS/tvOS build-for-testing, and focused iPad Simulator UI tests pass.
- Update version in Xcode, commit task changes, and merge into local `master`.

## Checkpoints

| Step | Evidence / review | Status |
|---|---|---|
| Source audit and implementation | Account-only authenticated requests, source-tagged continuation, empty/cyclic pages and bounded work covered by regression tests | complete |
| Shared audio/translation picker and Fit/Fill | One picker for both players; mute and translation cancellation tested; saved mode and language survive Next/relaunch | complete |
| Native tests and platform builds | 1050 tests / 146 suites, formatting, strict SwiftLint, repository rules and iOS/tvOS build-for-testing pass | complete |
| iPad Simulator controls, rotation and continuation | All 5 selected UI tests pass, no skips; real-stream time advances after scale/rotation | complete |
| Version and local integration | Xcode project updated to 5.9 (27); built iOS/tvOS apps and iOS extensions confirm the version; commit and local master integration authorized | complete |

## Verification and limits

Acceptance checks completed on 2026-10-16 using iPad Pro 11-inch (M5), iOS 26.5
Simulator. `ShortsAccountControlsUITests` passes all three tests: shared language
and Yandex controls in Shorts and the regular player; Fit/Fill across rotation,
Next and relaunch; real-stream playback continuity; continuation beyond the first
batch. Both `HomeShortsEndlessUITests` pass. Result bundle: `shorts-final-ipad.xcresult`.
Screenshots of the shared picker and landscape Fill playback were visually checked.

The first Home UI run exposed Shorts being truncated after 20 regular videos.
Home now keeps all Shorts from the initial account response while retaining the
regular-video limit. Sparse account pages do not trigger an unbounded scan or lose
their continuation: each request is bounded and the Shorts section offers More.

Signed-in request routing is tested with intercepted responses, not a live account.
Home and Recommended reuse account shelves; the dedicated feed uses subscription
Shorts. This does not reproduce YouTube's mobile reel ranking. The live video test
checks scaling and time continuity, not actual Yandex translation audio. These live
service and physical-device checks remain in OQ-0005. No remote push is included.
