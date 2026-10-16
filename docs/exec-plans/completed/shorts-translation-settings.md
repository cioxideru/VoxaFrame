# PLAN-0013: Independent Shorts translation settings

Status: completed

- Owner: Codex.
- Git boundary: `mac/shorts-translation-settings`, based on `master` `fa1c145` in
  the existing managed worktree. Initially clean; primary-checkout localization
  changes remain outside this task.
- Scope: independent Shorts audio language, automatic Yandex translation, lively
  voices and original background audio; use the same translation service and picker.
- Constraints: copy existing choices once on upgrade, preserve subsequent Auto and
  disabled choices, retain shared Keychain credentials, no new background workers,
  Xcode-only project edits, commit and merge locally after checks, no remote push.
- Basis: PLAN-0012's shared picker writes the regular player's preferences; the user
  now wants to configure translation separately for Shorts.
- Outcome: independent persisted translation preferences, scoped player controls and
  migration delivered; required native and Simulator checks pass.
- Dependencies: AppSettings, SettingsStore, PlaybackViewModel and the existing Yandex service.
- Remaining acceptance: live Yandex audio and physical-device checks remain
  [OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).

## Acceptance

- Settings exposes a separate Shorts translation group. Its values do not modify
  the regular player's settings, and the Shorts picker edits only its own values.
- The selected Shorts preferences apply on each new video and after relaunch.
- Existing JSON preserves all settings and seeds Shorts from the old translation
  choices; Auto and disabled settings survive later saves.
- Native checks, iOS/tvOS UI-target builds and focused iPad Simulator tests pass.
- Update the version, commit and merge into local master.

## Checkpoints

| Step | Evidence | Status |
|---|---|---|
| Stored settings and runtime scope | Legacy migration, Auto/disabled round trips and runtime scope tested | complete |
| Settings and player controls | Separate group and scoped writes in the shared picker | complete |
| Native and Simulator checks | 1053 tests / 146 suites, formatting, strict SwiftLint and repository rules pass; four focused iPad UI tests pass across targeted runs; iOS/tvOS UI-target builds pass | complete |
| Version and local integration | Xcode project updated to 5.10 (28); built iOS/tvOS apps and iOS extensions confirm the version; local commit/merge authorized | complete |

## Verification and limits

Checks completed on 2026-10-17 using iPad Pro 11-inch (M5), iOS 26.5 Simulator.
`SettingsUITests.testShortsTranslationDefaultsAreIndependentAndPersist` confirms
separate enable/original-audio choices survive relaunch. The Shorts controls test
confirms language/lively/original-audio choices survive Next, rotation and relaunch,
then changes the regular player's language and confirms Shorts retains its choices.
The existing real-stream Fit/Fill continuity and pagination tests also pass.

The initial UI failures were test interaction assumptions: switch rows need a tap
on the switch itself, and a single-track regular video with Auto language does not
show the audio shortcut. Tests now tap the switch and select a regular-player language
through Settings before opening its picker. The failing scenarios pass on rerun.
Result bundles: `shorts-isolation-ipad.xcresult` (continuity/pagination),
`shorts-isolation-persistence-ipad.xcresult` (Settings), and
`shorts-isolation-players-ipad.xcresult` (both players). The separate Settings group
and player controls were visually inspected.

No additional playback workers or translation service were introduced. Credentials
remain shared in the Keychain. Live Yandex audio/synchronization and physical-device
behavior were not tested; no remote push is included.
