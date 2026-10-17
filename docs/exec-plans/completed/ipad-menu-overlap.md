# PLAN-0016: Keep iPad navigation menus separate

Status: completed
Resolution: delegated layout correction and regression coverage delivered. Simulator and
physical-iPad navigation checks pass; the original intermittent failure was not reproduced,
so broader device acceptance remains in OQ-0017.

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

Home keeps its native navigation bar visible and inline only on regular-width iPadOS 18+.
Compact widths, older iPadOS, iPhone, Catalyst, macOS and tvOS keep their previous behavior.
The UI regression lives in existing SettingsUITests, so it needs no Xcode project edit.

## Verification

| Check | Evidence | Result |
|---|---|---|
| Original baseline | smarttube-ipad-menu-baseline-4.xcresult: portrait/landscape and Settings/Search/Library returns | PASS; intermittent defect not reproduced |
| Corrected simulator layout | IPadMenuLayoutUITests/testMenusRemainSeparateAfterNavigationRoundTrips in smarttube-subscriptions-ui-tvnav.xcresult: channel/back, Settings drill-down/back, tab changes, both orientations, selected Channels retained | PASS, 166.76 seconds, no skip |
| Physical iPad | smarttube-subscriptions-live-final.xcresult: actual account channels, channel/back, Settings/Search/Library returns, portrait and landscape | PASS, 2 bundle tests, no skips |
| Integrated gates | scripts/ci.sh: 1085 tests / 151 suites; strict SwiftLint zero violations; iOS/tvOS build-for-testing | PASS |

Evidence is under /private/tmp. The simulator was iPad Pro 13-inch M5 / iPadOS 26.5;
the physical device was iPad Pro 11-inch M5 / iPadOS 27.0.1. Both orientations have screenshots.
The menu test's mixed bundle contained one subscription-fixture Retry failure; the menu result
was checked independently and the corrected subscription suite later passed all five scenarios.

Earlier harness attempts measured a ScrollView's safe-area container instead of its actual
buttons or encountered ancestor identifiers hiding descendants. The regression compares the
Channels button's top edge to the native Search tab's bottom edge.

Split View and the user's exact intermittent sequence remain unverified, not proven fixed by a
green test. They are tracked in [OQ-0017](../../OPEN_QUESTIONS.md#oq-0017--subscription-and-rare-ipad-menu-live-acceptance).
Reference: [Apple's iPad tab-bar placement](https://developer.apple.com/documentation/uikit/elevating-your-ipad-app-with-a-tab-bar-and-sidebar).
