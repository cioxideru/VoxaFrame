# PLAN-0043: Player controls placement

Status: completed
Owner: Codex
Date: 2026-10-22

## Scope and boundary

Branch `mac/player-controls-layout` from local master `df449941`. Preserve the existing uncommitted
localization catalog. Commit this task and merge locally after checks; no remote push.

Follow the user's annotated player image: center the whole transport group in the player, put the
elapsed/duration timer on the right above the timeline, lower the timeline, align both bottom button
groups, and move mobile Up Next from More to the quick-access row immediately after Offline.
Reuse the current panel, playback actions and measured caption clearance. When full labels do not fit,
all left buttons show icons only, retaining their VoiceOver names and minimum targets; if even the icons
do not fit they remain scrollable. The shared iPhone/iPad/Mac controls get the layout; tvOS keeps its own layout.

## Acceptance and checkpoints

| Step | Required result | Evidence |
|---|---|---|
| Trace | Controls, panel anchor/state, accessibility identifiers and previous Up Next tests | complete: shared overlay, quick-access row and existing local-media tests |
| Implementation | All five placement changes; Up Next opens from its new button | complete: centered transport, time above timeline, one bottom action row, direct Up Next panel anchor |
| UI checks | Center/bottom alignment and timer/timeline order in both orientations; queue, recommendations and empty-state behavior | passed: four iPhone and seven iPad cases; final layout and maximum Dynamic Type checks passed on both devices |
| Gates | CI, strict SwiftLint, iOS/tvOS build-for-testing | passed: 1,389 package tests in 186 suites, lint and both test builds with Xcode 27.1 |
| Review | Inspect touch targets, scrolling, caption clearance and preserved user changes | complete: screenshots inspected in both orientations, existing measured caption clearance retained, VoiceOver names and minimum targets preserved, user localization file unchanged |

Dependencies: Xcode 27.1, existing media fixture on localhost:18765. Blockers: none.

## Delivered behavior and evidence

- The transport group centers in the player independently of the top and bottom bars.
- Time occupies the right side above the timeline. Its reserved space scales with the caption font;
  the maximum accessibility size does not overlap the track. Scrubbing still uses the same gesture area.
- Both bottom button groups share a row. Up Next follows Offline and uses the existing queue/recommendation
  panel. The left group switches together to icons when labels do not fit, preserving accessible names.
- iPhone 17 and iPad Pro 11-inch (M5), iOS 26.5 simulators: ordinary layout passed in portrait and landscape;
  recommendations, duplicate queue positions, refreshed remainder, empty state and dismissal passed.
  iPad More, speed and quality panels also passed their bounds checks.
- Initial result bundles: `/private/tmp/voxaframe-controls-iphone.xcresult` (4 tests) and
  `/private/tmp/voxaframe-controls-ipad.xcresult` (7 tests). After adding scalable timer space,
  `/private/tmp/voxaframe-controls-iphone-final.xcresult` and
  `/private/tmp/voxaframe-controls-ipad-final.xcresult` each passed the layout and large-text cases.
- Native test, lint and build logs: `/private/tmp/voxaframe-controls-ci-final.log`,
  `/private/tmp/voxaframe-controls-lint-final.log`, `/private/tmp/voxaframe-controls-ios-final-build.log`
  and `/private/tmp/voxaframe-controls-tvos-final-build.log`.
- NOT RUN: physical devices, live YouTube/PiP/AirPlay, macOS and tvOS visual acceptance, iPad Split View.
  These checks used local fixture video. Native macOS package compilation and tvOS test compilation passed.
