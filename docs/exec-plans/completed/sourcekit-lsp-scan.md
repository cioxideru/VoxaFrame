# PLAN-0037 — SourceKit-LSP scan and platform fixes

Status: completed
Owner: Codex
Date: 2026-10-20
Git boundary: primary checkout on local `master`, starting at `4aa11d3c`. The pre-existing localization
changes were committed separately as `c0067fc6` during the scan. This task leaves that work and
Xcode project references unchanged. No remote push.

## Scope and acceptance

Scan Swift sources and tests with SourceKit-LSP from Xcode 27.0. Confirm diagnostics against the
correct platform build settings, fix compilation errors, and remove the unintended strong capture
in the full-screen player's dismissal callback. Preserve shared desktop tests and iOS-only rotation,
touch and hardware-calibration checks. Do not change signing, project references or playback policy.

The scan uses temporary compilation databases extracted from fresh Xcode build activity logs;
the unconfigured Xcode targets otherwise report false missing-module errors. SwiftPM diagnostics
use the package's native macOS build context. Temporary scan files are outside the repository.

Acceptance: no SourceKit-LSP errors in the scanned platform contexts, `scripts/ci.sh`, strict
SwiftLint, and iOS/tvOS/macOS build-for-testing. This task checks compilation; live network,
physical-device calibration and the complete UI suite are not acceptance claims.

## Findings and fixes

- macOS: 52 LSP errors across DownloadsPlayback, LibrarySubscriptions, MacWKHLSReplayRegression,
  PlayerDoubleTap, Settings and ShortsPlayer UI tests. iOS-only APIs lack platform guards; the Mac
  replay helper is attached to XCUIElement instead of its test case, which owns the application.
- iOS: `onDismiss` implicitly retains the root controller to create its nested weak capture.
  The presenter owns the hosted controller, so the stored callback must capture the root weakly too.
- Other compiler warnings (unused locals, deprecated route-button API, unreachable skipped test
  body) are outside the error fixes. No warning suppression or API migration is planned.

Added platform guards only around iOS rotation steps and the iPad/physical touch suites. Shared
subscription, download and Shorts checks still compile for macOS; the Shorts background test uses
Command-H on Mac. Confirmation cancellation follows the available Cancel button, with the existing
iPad popover dismissal as the fallback. Moved `clickVisibleBack` into its owning test case without
changing its waits or assertions. The player's stored dismissal callback now captures `root` weakly.
Reused the existing screenshot helper and compact accessor style to meet the existing file-size limit.

No dependency, signing, project-reference or persistent LSP-configuration changes were needed.

## Checkpoints

| Check | Evidence / result |
|---|---|
| Baseline package LSP | 264 source files, 150 test files and Package.swift: zero errors. |
| Baseline builds | iOS/tvOS build-for-testing passed; macOS failed on unsupported iOS APIs. |
| Baseline gates | 1,370 unit tests in 182 suites passed; SwiftLint: zero violations in 495 files. |
| Final LSP coverage | 500 unique tracked Swift files. All Swift files received confirmed diagnostics; zero errors after fixes. iOS: 333 Xcode inputs plus three files absent from the target list; four initially timed-out files succeeded on retry. tvOS: 264 package files and 14 app/test inputs. macOS: package diagnostics plus 77 UI-test files and three app sources. Package.swift and all 150 package test files also passed. |
| Capture warning | SourceKit-LSP with iOS compiler arguments: zero warnings or errors for LandscapeFullScreenCover.swift after the change. |
| Final gates | `scripts/ci.sh`: 1,370 unit tests in 182 suites passed. Strict SwiftLint: zero violations in 495 files. `git diff --check` passed. |
| Final platform builds | Xcode 27.0 build-for-testing passed for iOS Simulator, tvOS Simulator and native arm64 macOS, with code signing disabled. |
| Self-review | iOS assertions retained; shared Mac checks remain compiled. Helper move preserves validation and failure reporting. Only one production-code line changed; no playback policy or stored data changes. |
| Delivery | Commit directly on local `master`; no branch merge is needed. |

The directory-level initial scan also reached JavaScript/Python resources, which SourceKit-LSP does
not analyze. Those provider failures are outside the Swift coverage above. The final checks use
Swift files and the correct platform compiler arguments. Four pre-existing iOS compiler warnings
remain: unused `playerIDValue`, immutable `capturedPoToken`, deprecated `showsRouteButton`, and
the deliberately skipped non-tvOS test body. They are not compilation errors.

BotGuardWVAdaptiveUITests.swift, SIDScrubberUITests.swift and the HomeFeedNoDuplicatesUITests.swift
placeholder are not Xcode compilation inputs; LSP checked them separately, but build-for-testing
does not establish execution coverage for them. Project references were not edited.

UI tests were compiled, not executed. No physical-device behavior or memory-profile result is claimed.
Local diagnostics, summary and build logs: `/private/tmp/voxaframe-sourcekit.jjs1sf/`.
