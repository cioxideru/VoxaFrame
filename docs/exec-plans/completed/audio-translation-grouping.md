# PLAN-0035: Separate YouTube audio and Yandex translation controls

Status: completed
Owner: Codex
Date: 2026-10-20

## Scope and boundaries

The user's 19:55 screenshot shows the translation-language menu above the Yandex
heading, visually attached to YouTube's audio tracks. Group the controls by
provider in both the player audio panel and the Offline watch download sheet.

Work on local `master`, starting at `13c03335`, with Xcode 27.0. Preserve unrelated
`project.pbxproj` and `Localizable.xcstrings` changes. Commit task changes to local
master after required checks; no remote push. Kazakh service behavior is out of scope.

Use the two existing shared SwiftUI views: the audio panel also serves Shorts;
the download sheet is opened from both player and video cards. Keep selection
bindings, default-language policy, accessibility identifiers, download validation
and saved files unchanged. No new settings or dependencies.

## Acceptance

- YouTube audio choices and Yandex translation controls have separate headings.
- The player translation-language menu has a visible label inside the Yandex group.
- The download sheet separates source media choices from translation choices.
- Existing manual language/toggle choices survive quality changes.
- Panel controls and the Download button remain reachable.

## Checkpoints

| Check | Evidence | Result |
|---|---|---|
| Scope | Shared callers and screenshot inspected; language menu precedes Yandex heading | confirmed |
| Implementation | Separate YouTube/Yandex groups in both shared views; visible player language label; existing strings and state reused | complete |
| Required checks | CI: 1,361 tests in 181 suites; strict SwiftLint: zero violations in 492 files | passed |
| Platform compilation | Native macOS package, iOS UI-test build and tvOS Debug simulator build | passed |
| Download choices | Local-fixture UI test covers Russian/English defaults, manual target and toggle retained across quality changes | passed |
| Visual inspection | iPad Simulator: player panel, open language menu and download sheet; headings, language labels and Download button visible | passed |
| Shorts panel | First-open bounds and tappable Auto passed; later rotation expectation failed before post-rotation panel assertions | partial |
| Physical iPad | Xcode rebuilt the binary at 20:06 and reported Running SmartTube on iPad (Ivan); user confirmed both dialogs: "Да, теперь понятно сгруппировано" | accepted |

## Evidence and limits

Local diagnostic evidence is kept in the private
`/private/tmp/voxaframe-offline-defaults-20261020` folder: `grouping-ci.log`,
`grouping-lint.log`, `grouping-tvos.log`, `grouping-ui-test.log` and
`grouping-player.jpg`, `grouping-player-menu.jpg`, `grouping-offline.jpg`.

The UI run had one passing test and one failing test. In
`PlayerOptionPanelBoundsUITests.testShortsAudioPanelStaysInsideWindow`, the
portrait panel checks passed. After rotating, the helper at line 296 timed out
waiting for `app.frame.width > app.frame.height`. This does not establish
post-rotation panel behavior; the window-aware test setup remains a follow-up in
[OQ-0019](../../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).
No new rotation or window-management implementation was added for this grouping task.

User acceptance covers the two requested dialogs on the physical iPad.
VoiceOver navigation, large accessibility text and tvOS interaction were not run.
