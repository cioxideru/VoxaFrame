# PLAN-0016: Keep iPad navigation menus separate

Status: completed
Resolution: delegated layout correction and regression coverage delivered. Simulator and
physical-iPad navigation checks pass. The follow-up physical window-size matrix reproduced
and fixed a compact-window overlap; the original wide-screen intermittent sequence remains
unreproduced and is tracked in OQ-0017.

## Scope and boundaries

Owner: Codex colleague ipad_menu_overlap; verification and integration by the coordinator.
Work started in the managed subscriptions-ipad worktree from e7a2db1; the coordinator incorporated
concurrent master 5955a1b before final package and platform checks. Existing main-checkout edits
are outside this task. Subscription API and shared identifiers belong to PLAN-0017.

The user's screenshot shows the native Home/Search/Library/Settings bar overlapping the
Home/Subscriptions/Channels controls after navigation. Home hid its navigation bar while its
chips occupied the first content row. On wide iPad layouts the native tab and navigation bars
share a system region; reserving it avoids depending on a restored horizontal-scroll inset.

Constraints: retain native tabs and existing navigation stacks; no fixed bar heights, nested
NavigationStacks, project-file edits, or subscription API changes by the colleague.
Acceptance: channel/Settings round trips and tab switches preserve separate navigation rows
and the selected section in portrait and landscape. No implementation blocker remains.

## Delivered correction

Home keeps its native navigation bar visible and inline on regular-width iPadOS 18+ and
all iPadOS 26+ window widths. Older compact iPad layouts, iPhone, Catalyst, macOS and tvOS
keep their previous behavior.
The UI regression lives in existing SettingsUITests, so it needs no Xcode project edit.

## Verification

| Check | Evidence | Result |
|---|---|---|
| Original baseline | smarttube-ipad-menu-baseline-4.xcresult: portrait/landscape and Settings/Search/Library returns | PASS; intermittent defect not reproduced |
| Corrected simulator layout | IPadMenuLayoutUITests/testMenusRemainSeparateAfterNavigationRoundTrips in smarttube-subscriptions-ui-tvnav.xcresult: channel/back, Settings drill-down/back, tab changes, both orientations, selected Channels retained | PASS, 166.76 seconds, no skip |
| Physical iPad | smarttube-subscriptions-live-final.xcresult: actual account channels, channel/back, Settings/Search/Library returns, portrait and landscape | PASS, 2 bundle tests, no skips |
| Physical window-size follow-up | smarttube-ipad-window-matrix-1.xcresult: floating windows, three Split View sizes, full-screen restoration and both orientations; two navigation cycles per layout | PASS, 2 tests, 16 cycles, 1147.46 seconds |
| Integrated gates | scripts/ci.sh: 1085 tests / 151 suites; strict SwiftLint zero violations; iOS/tvOS build-for-testing | PASS |

Evidence is under /private/tmp. The simulator was iPad Pro 13-inch M5 / iPadOS 26.5;
the physical device was iPad Pro 11-inch M5 / iPadOS 27.0.1. Both orientations have screenshots.
The menu test's mixed bundle contained one subscription-fixture Retry failure; the menu result
was checked independently and the corrected subscription suite later passed all five scenarios.

Earlier harness attempts measured a ScrollView's safe-area container instead of its actual
buttons or encountered ancestor identifiers hiding descendants. The regression compares the
actual Channels and native Search buttons, supporting both top and bottom tab placement.
It also verifies that the section row is below system window controls and remains tappable.

## Window-size follow-up, 2026-10-17

The requested physical-device resizing check reproduced an additional overlap in a floating
375 × 496 pt window. The system Window Controls button occupied `(439, 133, 41, 22)` while
the Home section button occupied `(434, 132, 80, 37)`. Evidence:
`smarttube-ipad-window-probe-5.xcresult` and its retained screenshot. This is a concrete compact
window defect; it is not a reproduction of the original wide-screen intermittent sequence.

The compact-width branch hid Home's navigation bar, leaving no native region for iPadOS 26+
window controls. The correction preserves that region at every width on these OS versions.
The same 375 × 496 pt window then placed Home at y=186, below the controls ending at y=155
(`smarttube-ipad-window-probe-7.xcresult`). No fixed padding or custom window geometry is used
in production.

The regression uses native Windowed Apps controls and a Settings companion window, drags the
Split View divider and the floating-window corner, and checks two navigation cycles at each
size without restarting SmartTube. The shared chip-scroll test helper now accounts for the
window's screen-space origin, which can be nonzero. Physical tests preserve SmartTube settings
and restore the initial system multitasking mode in teardown.

The final follow-up ran on the same iPad Pro 11-inch M5 / iPadOS 27.0.1. Its window case
passed in 815.46 seconds, followed by the portrait/landscape case in 332.00 seconds.
The matrix covers floating windows of 375 × 496 and 833 × 609 pt, Split View at half,
roughly one third and two thirds, then full-screen restoration without app relaunch.
All 16 cycles preserve Channels selection, separate the controls and keep them tappable.
Full Screen Apps was the original system mode and its restoration was asserted in teardown.
Package tests, strict SwiftLint and iOS/tvOS build-for-testing passed again after the correction.

The requested Split View and window-size sequence passes on the affected iPad. The user's
original intermittent wide-screen sequence remains unreproduced; a finite passing matrix does
not establish coverage of every restoration sequence. That residual observation is tracked in
[OQ-0017](../../OPEN_QUESTIONS.md#oq-0017--subscription-and-rare-ipad-menu-live-acceptance).
Reference: [Apple's iPad tab-bar placement](https://developer.apple.com/documentation/uikit/elevating-your-ipad-app-with-a-tab-bar-and-sidebar).
