# PLAN-0042: Up Next on iPhone and iPad

Status: completed
Owner: Codex
Date: 2026-10-22

## Scope and boundary

Branch `mac/player-up-next` from local `master` at `8fceea7c`. Preserve the existing uncommitted
`Localizable.xcstrings` changes. Commit only this task and merge locally after checks; no push.

The Mac inspector has Up Next, but the mobile More menu exposes only Description and Comments.
Share its queue/recommendation list with an iOS option panel, add the More action, and remove the
repeated video title/channel heading from that menu as requested. Keep channel controls and the
existing Description/Comments panels. No new API, playback policy, settings or dependencies.

## Acceptance and checkpoints

| Step | Required result | Evidence |
|---|---|---|
| Trace | Identify all list callers, menu/panel lifecycle, identifiers and fixture hooks | Mac-only inspector; existing native option panels and local media/queue/related fixtures |
| Implementation | iPhone/iPad More opens Up Next; selecting a video plays it and dismisses the panel; Mac reuses the list | `PlayerUpNextList`, native option-panel handoff, menu header removed; queue-position identity preserves duplicates |
| Regression checks | Queue order and duplicates, recommendations, empty state, compact More header and dismissal | 4/4 `PlayerOptionPanelBoundsUITests` cases on each of iPhone 17 and iPad Pro 11-inch (M5), iOS 26.5; iPad portrait and landscape |
| Gates | CI, strict SwiftLint, iOS/tvOS builds and UI-test compilation | CI passed: 1389 native tests in 186 suites; SwiftLint exited 0 with its existing unknown-rule configuration warning; iOS/tvOS Debug build-for-testing passed on Xcode 27.1 |
| Review | Inspect final diff and preserve user catalog changes | Shared list callers, deferred menu-to-panel presentation, close/gesture state and matching app/test identifiers reviewed; existing catalog matches the pre-build copy byte for byte |

Dependencies: installed Xcode 27.1 and existing local media fixture on port 18765.
Blockers: none.

Resolution: mobile Up Next and the compact More menu are delivered. No new playback/API policy or
dependencies. The task-only commit is ready for local master integration. Logs and result bundles:
`/private/tmp/voxaframe-up-next-ci-final.log`, `voxaframe-up-next-ios-build.log`,
`voxaframe-up-next-tvos-build.log`, `voxaframe-up-next-ipad.xcresult` and
`voxaframe-up-next-iphone.xcresult` (all under `/private/tmp`). The More menu was also checked in
`/private/tmp/voxaframe-up-next-ipad-preview.png`.

NOT RUN: physical devices, live YouTube recommendations, iPhone landscape, Mac/tvOS UI execution.
General physical playback acceptance remains in [OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).
