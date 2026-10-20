# PLAN-0036: iPad reading panels and offline library hierarchy

Status: completed
Owner: Codex (offline library and integration); GPT 6.1 Sol medium (reading panels)
Date: 2026-10-20

## Scope and boundaries

The user supplied four iPad screenshots and requested two independent changes.
Description and Comments are too narrow; that bounded task is delegated to the
explicitly requested model in the managed `ipad-player-panels` worktree.
The primary agent owns the Offline videos redesign in the main checkout.
Both start from local master `3c69a572`, using Xcode 27.0.
Preserve unrelated `project.pbxproj` and `Localizable.xcstrings` changes.
Integrate verified task commits into local master; no remote push.

## Intended behavior

- Description and Comments use a readable width on large windows and fit narrow
  windows; small player menus keep their current proportions.
- Offline library cards get the larger share of wide windows and show the
  actual saved/pending video, audio and translation variants with status.
- Play sits on each library card; its secondary button opens saved video/audio/Yandex
  choices and starts that selection. SponsorBlock is the last detail section.
- File tasks are a third level under a video, shown in a dialog. Completed
  file rows no longer open the entire video-management page.
- A compact floating header card shows active video/audio/translation counts and progress.
  Opening it shows only active and failed file tasks, with existing cancellation,
  retry and confirmed deletion. An always-visible global Downloads button opens all
  tasks newest first. Global/per-video dialogs offer All / Active / Error / Video / Audio;
  Audio includes Yandex files and Active includes errors; Error isolates failures.
- Chips use type icons, short quality/codec/language/bitrate labels and whole-chip
  wrapping, so their text does not wrap onto uneven rows. Russian uses a flag and RU.
- Description links to its channel. Shared player parsing retains channelId;
  short/long content fits the actual window and long text scrolls.
- Persisted media, selection policy, transport scheduling and deletion safeguards
  stay under their existing owners.

## Ownership and acceptance

The delegate owns the shared player-panel width and its callers/tests. The main
agent owns offline views, presentation mappings, related accessibility IDs,
localization additions, tests and integration documents. No simultaneous device
or Simulator control; builds are coordinated.

| Checkpoint | Evidence | Result |
|---|---|---|
| Delegation | GPT 6.1 Sol medium acknowledged the bounded reading-panel task in its own worktree; three readable patches independently inspected and integrated | complete |
| Reading panels | 640 pt readable width, 360 pt small menus; narrow/long-content rendering tests; short/long descriptions inspected in Simulator | passed |
| Channel link | Shared player parser preserves channelId; regression covers PlayerInfo, preload cache and channelVideo | passed |
| Physical reading acceptance | User confirmed wider Description, working channel navigation and height bounded by the screen | accepted |
| Offline layout | Library has the larger share of wide windows; compact single-line chips wrap as whole units; Play and saved playback choices live on each library card | implemented and visually checked |
| File dialogs | Global/per-video newest-first tasks; All / Active / Error / Video / Audio; scoped cancel, retry and confirmed deletion | passed |
| Required gates | CI: 1,368 tests in 182 suites; strict SwiftLint: zero violations in 495 files; iOS and tvOS simulator builds | passed |
| Playback journeys | Direct library Play, selection of saved Yandex audio, turning voice-over off, deleting one file and deleting its library entry | three distinct focused UI journeys passed across the final runs |
| Final device build | Xcode reports Running SmartTube on iPad (Ivan); executable built at 21:16:23 local time on 2026-10-20, including Error | installed and running |

The first updated UI run caught an initial-filter bug: the sheet captured All
when the progress summary intended Active. The filter itself is now the sheet's
presentation item, so it cannot diverge from the sheet's visible state. A separate
UI-test scrolling helper only moved down the library and missed a card above the
viewport; it now scrolls toward the target. Both failed journeys passed after
those corrections. The Error filter then passed a further focused UI run.

Local diagnostic evidence is under `/private/tmp/voxaframe-layout-PLAN-0036`.
XcodeBuildMCP result bundles (same project workspace):

- `test_sim_2026-10-20T18-05-05-056Z_pid52182_a46b9dab.xcresult`: direct Play and deletion passed; two failures identified above.
- `test_sim_2026-10-20T18-13-28-460Z_pid52182_58885d91.xcresult`: saved voice-over Off and the global Downloads journey passed.
- `test_sim_2026-10-20T18-16-39-096Z_pid52182_e9529cea.xcresult`: Downloads with the additional Error filter passed.

Progress gives each file equal weight within batches that still have active work;
completed files in those batches remain in the denominator. Old completed batches
and cancelled files do not inflate the summary. The summary opens the Active filter; cancelled and completed files remain reachable
through All in the global or per-video dialog. Tasks have no saved timestamps, so
newest-first order reverses the manifest append order, including after relaunch.

Delivered in the maintained local checkout; task changes are committed to local
master, without a remote push. No dependencies or persisted-manifest migrations.
The user's final Error-filter request is included; it was checked in Simulator
and installed on the iPad, but no separate physical Error-filter acceptance was
requested. iPhone and tvOS interaction were not exercised; tvOS was compiled and
native macOS package checks passed.

## Follow-up: floating download summary

The summary now sits in the top safe area as a rounded, raised card, bounded by
the existing readable-width metric. It stays visible while either column scrolls;
the library is clipped to its viewport so rows cannot paint over the title.
Counts, percentage, errors, the Active dialog and the hidden idle state keep
their existing policy. No persistence, scheduling or localization changes.

Verified in iPad Simulator in portrait and landscape, including library scrolling
and selection updating the detail column. The existing Downloads UI journey passed with all
filters and cancel/retry/delete actions (`test_sim_2026-10-20T18-27-19-415Z_pid52182_800018c2.xcresult`).
CI passed 1,368 tests in 182 suites; strict SwiftLint reported zero violations;
iOS and tvOS builds passed. Xcode reports Running SmartTube on iPad (Ivan), with
the updated executable built at 21:28:24 local time on 2026-10-20.
Logs and screenshots: `/private/tmp/voxaframe-floating-downloads-20261020`.
The physical layout awaits user observation; iPhone and tvOS interaction were
not exercised.
