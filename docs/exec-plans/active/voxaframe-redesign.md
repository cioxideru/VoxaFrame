# PLAN-0027: VoxaFrame redesign in SwiftUI

Status: active

Owner: Claude Code for Ivan Baranov. Original Git boundary: local `master` at `0e81d8a`.
The 2026-10-17 consolidation into local `master` includes the remaining design export,
HTML/CSS boards, [reference screenshots](../../new-design-v1/README.md), and refreshed string catalog.
Saving these source materials does not accept unfinished redesign stages or close OQ-0019.
Basis: [design package](../../design/voxaframe-redesign/START-HERE.md) (DESIGN-0003) and the
[functional brief](../../design/VoxaFrame-Functionality.ru.md) (DESIGN-0002), which wins over a mockup on any disagreement.
Decisions: [ADR-0012](../../adr/0012-redesign-availability-and-tokens.md); accent and logic scope below.

## Scope and acceptance

- Re-skin the shell, Home and cards, player and panels, Shorts, Offline, Settings, Search, Library and RSS
  for iPhone, iPad, native macOS and Apple TV. Behaviour, queue, audio, subscriptions and files do not change.
- Accent "System" is coral (`#B83829` light, `#FF9988` dark) on iOS, iPadOS and tvOS; on macOS it stays the system accent.
- Logic changes in scope: B1 (confirm clearing device history), B2 (confirm Reset All Settings), B3 (confirm Clear Queue),
  A1 (permanent Queue entry), A2 (Play Next after the current item), A4 (guest local history in Library), A5 (search error screen).
  Everything else marked as logic in the mockups (A3, A6–A12, B4–B8, C1) stays a label and is not implemented.
- Each stage is accepted when: CI and strict SwiftLint pass, iOS/tvOS/macOS builds pass, the stage's screens are checked in
  light and dark, with Reduce Transparency, Increase Contrast, Reduce Motion and Dynamic Type up to AX5 where the stage has text.

## Constraints

- Minimum OS stays iOS/iPadOS 17, macOS 14, tvOS 17. Liquid Glass and iOS 18+/26+ navigation APIs sit behind `#available`.
  Update (2026-10-18): [ADR-0013](../../adr/0013-minimum-os-18.md) supersedes this baseline with iOS/iPadOS 18,
  native macOS 15 and tvOS 18; OS 26+ checks and fallbacks remain.
- Do not rename `AppSection` raw values or any accessibility identifier; do not touch `PlaybackViewModel*`.
- One source for symbols (`AppSymbol`), identifiers (`AccessibilityID`, mirrored in `UITestHelpers.swift`), timeouts (`PlaybackTuning`) and settings.
- No hand edits of `project.pbxproj`; new UI-test files are added in Xcode.

## Checkpoints

| Stage | Content | Status / evidence |
| --- | --- | --- |
| 0 | This plan, ADR-0012, OQ-0019, document index | done: `452adac`; the remaining HTML/CSS mockups are now retained as design references. UI acceptance remains in OQ-0019 and the stage checks below |
| 1 | `Views/DesignSystem/`: tokens and glass modifier. Accent flip deferred to the button stage (see OQ-0019) | done: `e483ec1`. Package tests and SwiftLint (`scripts/ci.sh`: 1157 tests, 160 suites), iOS and tvOS builds pass; HIG static review advisory-pass, high=0. macOS app scheme is not built by `scripts/verify.sh` (package compiles on macOS); device and Dark Mode checks NOT RUN |
| 3a | `VFProminentButtonStyle` (fill `action`, label `onAction`), migrate the 15 `.borderedProminent` sites, then flip `.system` accent on iOS, iPadOS, tvOS | done on iPhone/iPad: `8d7c981`. 14 sites migrated (SponsorBlock toast keeps its segment tint); named accents use the vf.css pairs. `scripts/ci.sh` 1167 tests, iOS and tvOS builds pass; independent review round 3 blocking=0, HIG high=0. tvOS accent deferred (OQ-0019). Device, Dark Mode, AX5 and VoiceOver NOT RUN |
| 2b | Shell on macOS: sidebar, player in the content stack, inspector, View menu, Settings scene | done: `084cec3`. `scripts/ci.sh` 1172 tests (on top of 3a), iOS and tvOS builds pass; review round 3 blocking=0, HIG high=0. macOS app scheme not built by `scripts/verify.sh`; runtime checks NOT RUN (OQ-0019) |
| 2a | Shell on iPhone, iPad, tvOS: Tab API, sidebar-adaptable, search role, mini-player restyle (accessory spike rejected: overlay kept) | done: `0d446f6`. `scripts/ci.sh` 1179 tests (all of stage 2 and 3a), iOS and tvOS builds and UI-test compile pass; the new pushed-screen reserve UI test passed once on an iOS 26 iPhone simulator; review round 3 blocking=0, HIG high=0. iOS 17/18 paths, docked iPad sidebar, 600 pt window and rotation NOT RUN (OQ-0019) |
| 3 | Home, cards, A2 | done: `9f45149`. Play Next after the playing item; same-source selections adopt the new queue position without reload; Try Again keeps loaded cards. `scripts/ci.sh` 1191 tests in the worktree, iOS and tvOS builds and UI-test compile pass after rebase; `PlayerRouterQueueTests` 6/6 and `MixedFeedLayoutUITests` pass; review round 3 HIG high=0, the last two findings fixed and accepted by reading. Residual `hasNext` race and the Mac title check in OQ-0019 |
| 4 | Player and option panels | done with stage 5: `94c8efd`. Timeline with chapters and SponsorBlock, shared option panel, solid scrims behind bars over video (`VFColor.scrim`, unplayed track `VFColor.onMediaTrack`), AX layouts. `scripts/ci.sh` 1184 tests, iOS and tvOS builds and UI-test compile pass after rebase; review round 4 HIG high=0, its one finding fixed and accepted by reading. Rendered AX5, VoiceOver, tvOS focus and the Mac app NOT RUN |
| 5 | Shorts | done: `94c8efd` (with stage 4). Panel-open gate on vertical navigation, compact two-row rail at AX sizes and under 760 pt, UISlider-based seek bar on iOS. UI tests compiled, not run |
| 6 | Offline | done: `0fae78c`. List/detail layout on iPad and Mac deferred (OQ-0019) |
| 7 | Settings, B1, B2 | done: `4af6c28`. Review round 2 blocking=0, HIG high=0. Category navigation on iPad and tvOS deferred (OQ-0019) |
| 8 | Search, Library, RSS, channels, sign-in, A1, A4, A5, B3 | done: `daa217c`. Search request generations, guest History and Playlists cleared on sign-out, Queue screen hands the visible list to the store. `scripts/ci.sh` 1228 tests after rebase on stages 3–7, iOS and tvOS builds and UI-test compile pass; `PlayerRouterQueueTests` 7/7, touched Library and search UI tests pass; review round 3 HIG high=0, its one finding covered by a router test. Mac filter menu item deferred (OQ-0019) |

The coral accent is not switched on in stage 1: with the system prominent button, the dark-mode label would be white on `#FF9988` (2.07:1). It flips together with the button style in stage 3a.

Stages 0–2 run in order; stages 3–8 touch separate folders and may run in parallel once stage 2 is merged.

## Stage 6 basis: offline after PLAN-0028

Checked on 2026-10-17 against master `278111b`. The offline views are unchanged since the design snapshot `0e81d8a`;
PLAN-0028 changed only the transport, error text and cleanup. The boards go beyond the code in several places, so stage 6 follows the code:

- Six job states (`queued`, `resolving`, `downloading`, `completed`, `failed`, `cancelled`) plus "Waiting for translation" as a queued
  sub-state. One transfer runs at a time, so a translation is drawn as queued or waiting, never in parallel, and there is no queue position.
  Actions stay Cancel / Retry / Delete task and files; a completed job may link to its saved page.
- Progress is a percentage only. Retry, a system task lost across relaunch, or process death between ranges restart from zero,
  so no "resumes where it stopped" wording and no byte counts.
- Error text is a localized prefix plus the raw reason (HTTP status, error domain and code); no "out of space" promise.
- The yield banner appears only while the player starts or rebuffers; its copy says so.
- Deletion dialogs name the video or track; conflicting actions are disabled while a removal is pending; no sizes.
- A storage error replaces the empty state, and loading shows until the library is ready.
- Saved-video page: "Included audio" means the included or first saved audio; "Without translation" stays the default on re-entry;
  HLS cannot be paired with an external audio file, so that board frame is dropped.
- Offline strings are English-only today; stage 6 adds catalog entries. UI tests match English labels
  (`DownloadsPlaybackUITests.swift` 118–136 and 212–237): keep accessibility identifiers and update those tests with the copy.
- Board items that need logic stay labels (OQ-0019). tvOS stores offline media under Documents (`OfflineCoordinator.swift` 59–62);
  confirm tvOS keeps it before drawing the TV offline screen.

