# PLAN-0033 — iPad sidebar launch warning

Status: completed
Resolution: sidebar launch warning and Queue identity regression fixed; the broader Split View test
still fails while preparing the two-app system scene and remains in OQ-0019.
Owner: UI maintainer
Date: 2026-10-20
Git boundary: `mac/ipad-sidebar-state-warning`, existing clean `p29-release` worktree, originally based on
local `master` `1a6deb9a`, updated to `5243b681` (PLAN-0031/0032). Preserve unrelated changes in the primary
checkout. Merge locally after acceptance.

## Scope and acceptance

Fix the iPadOS 27 SwiftUI warning on landscape launch without changing sidebar, Queue, navigation,
or window adaptation behavior. Use Xcode 27.0; no project-file edits, private APIs or warning suppression.
Acceptance requires a causal stack, warning-free focused iPad UI tests, CI, strict SwiftLint and platform builds.
Basis: the launch warning recorded by [PLAN-0030](worktree-release-5-18.md) and
[OQ-0019](../../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).

## Investigation

Expected: a new window starts with a sidebar in landscape and tabs in portrait; users can toggle it
afterward. The window supplies its initial shape, and the system tab controller owns sidebar visibility.
That visibility must not be written while SwiftUI is updating its view graph.

LLDB stopped inside SwiftUICore's `StoredLocationBase.set` at the branch emitting
`Modifying state during view update, this will cause undefined behavior.`
The caller is SwiftUI's `TabViewCoordinator_Phone.tabBarController(_:sidebarVisibilityWillChange:animator:)`,
through `UIKitTabBarController.updateSidebarToConfiguration` and `UIKitAdaptableTabView.updateUIViewController`.
The sidebar header geometry handler is not in the offending stack.

The trigger is `.defaultAdaptableTabBarPlacement(.sidebar)` updating UIKit configuration during a
SwiftUI update. UIKit synchronously calls SwiftUI's sidebar delegate, which writes its own binding
inside that update. Reading geometry earlier alone did not eliminate the warning on repeated launches.

The existing tab-bar UIKit bridge now applies `controller.sidebar.isHidden` once, using the attached
window's bounds, in a main-actor task after `updateUIView` returns. A weak controller reference in its
coordinator prevents appearance updates or rotation from overriding the user's later toggle.
The SwiftUI default-placement modifier is removed. Root layout and geometry observers stay unchanged.
The existing appearance scheduling uses `Task` instead of `DispatchQueue`.

The expanded window test exposed a second problem in the same tab container: changing to compact width
removed Queue with an `if`, resetting Home's selected section. UIKit also aborted in
`UITabBarController._tabs_rebuildTabBarItemsAnimated` during trait changes. The user-supplied crash report
at 15:52:27 matches the control run of the unchanged 5.18 app; the bridge-only candidate also hit this
separate crash during window-test teardown. Queue now stays in the hierarchy and uses
[`TabContent.hidden(_:)`](https://developer.apple.com/documentation/swiftui/tabcontent/hidden(_:)),
which preserves tab state. The existing selected-Queue fallback to Library remains in place.

The window test also needed a test-only correction: its fast form swipe skipped Visible Sections
entirely in the small floating window. Screenshots show the form moving from Feed Filters to
SponsorBlock, past the target row. The test now scrolls slowly and waits for the row's full frame to
enter the form before tapping; querying XCTest's hittability while the row is outside the window
produced an invalid-activation-point error on this runtime.
The system tiling button has no accessibility identifier; its selector accepts the observed Russian
label as well as the existing English label, so the window test does not require changing system language.

The scoped fix is accepted by the focused UI checks and build gates below. Full Split View acceptance
is separate: the system command places VoxaFrame on the left but leaves the right side empty rather
than pairing Settings. The test stops at its two-app geometry assertion; the 1/3, 2/3 and final full-screen
stages are not reached. No assertions are disabled or weakened.

## Checkpoints

| Check | Evidence / result |
|---|---|
| Baseline | Warning reproduced on 5.18; two LLDB stops have the same framework sidebar visibility stack. Local traces: `/private/tmp/voxaframe-sidebar-warning-stack.txt` and `-stack-2.txt`. |
| Focused iPadOS 27 UI checks | Five passed: repeated navigation in both orientations, portrait launch, manual sidebar hiding and selection across rotation, landscape launch, Queue default and setting. `ui-navigation-final.xcresult`: 5 passed / 0 failed / 0 skipped / 0 runtime warnings. |
| Extended window check | Navigation and Channels selection survive 375×585 and 993×779 floating windows. The whole test **failed** at the two-app Split View setup described above. `ui-window-accepted.xcresult`: 1 failed / 0 runtime warnings; no app crash. |
| CI after PLAN-0031/0032 integration | `scripts/ci.sh`: 1,352 unit tests / 181 suites passed. Strict SwiftLint passed; its existing invalid-rule configuration warning is unchanged. |
| Platform builds | Xcode 27.0: iOS and tvOS Release build-for-testing, plus native macOS Release build, passed on the integrated source. |
| Review | Self-review: public UIKit/SwiftUI APIs only, main-actor mutation outside the view update, weak per-controller initialization, stable tabs and existing Queue fallback retained. No project-file, storage or signing changes. |
| Delivery boundary | Local commit and merge into `master`; no new release or remote push in this task. |

UI runs cover the final sidebar/Queue production changes. Subsequent integration added PLAN-0032's
unrelated translation fix; the combined source passed CI and all three platform builds.
Local evidence: `/private/tmp/voxaframe-sidebar-20261020/` (xcresults, summaries, logs and screenshots).
Physical iPad and older iPadOS runtime checks were not rerun. Remaining multiwindow acceptance is
[OQ-0019](../../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).
