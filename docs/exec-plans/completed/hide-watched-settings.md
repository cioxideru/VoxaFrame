# PLAN-0018: Watched-video settings and fork link

Status: completed
Resolution: shared watched-video filtering, precise low thresholds and the fork link are
implemented and verified. Version 5.13 (31) was set through Xcode 27.0.
Owner: primary Codex agent.

## Boundary and scope

- Branch `mac/hide-watched-settings`, based on `bcc0dcf` after integrating the accepted subscription/iPad menu changes; reuse the resource-quality checkout.
- Primary checkout has user changes to localization and the Release/no-debugger Run scheme; preserve both.
- Repair Hide Watched Videos on Home and Shorts as well as existing section feeds.
- Offer 5–100% in 5% steps, keeping the 90% default and persisted fractional representation.
- Point Settings' GitHub link and tvOS QR code to `cioxideru/SmartTubeIOS`.
- Version 5.13 (31) set through the Xcode 27.0 project editor for all configurations.
- Preserve the existing YouTube-reported progress contract and History exemption.
  Local resume positions are not a completed-view history (finished positions are deleted).
- No new tracking, background workers, dependencies, or changes to account data.

## Acceptance and evidence

| Checkpoint | Evidence | State |
|---|---|---|
| Root cause | Home bypassed the filter; mixed/dedicated Shorts used unfiltered arrays; fractional Stepper drifted at exact boundaries | confirmed in source |
| Settings | 5–100% bounds, exact 5% steps, persistence across relaunch and unchanged 90% default | PASS |
| Feeds | Home, Recommended, Subscriptions and Shorts filter exact/above-threshold cards; History and unknown progress remain visible; disabling restores cards | PASS |
| Pagination | Fully watched Home/Recommended/Subscriptions pages retain More; the next unwatched page loads | PASS |
| GitHub | Link exposes the fork URL; tvOS QR shares that constant and compiles | PASS |
| Native checks | scripts/ci.sh: 1088 tests / 151 suites; secret, document, import and format checks; strict SwiftLint and repository rules | PASS |
| iPad Simulator | HideWatchedSettingsUITests: 3 passed, 0 failed, 0 skipped | PASS |
| Release compilation | iOS and tvOS Simulator builds; app and iOS extensions report 5.13 (31) | PASS |

## Evidence and limits

The final UI result is `hide-watched-ipad-isolated.xcresult`, with its build/test log
`hide-watched-ipad-isolated.log`. It explicitly compiles this checkout's SettingsUITests.swift.
The saved "Watched threshold minimum 5 percent" screenshot was visually checked.
Environment: Xcode 27.0 (27A266a), iPad Pro 11-inch M5 Simulator, iOS 26.5 (23F77).
Release logs are `hide-watched-release-ios.log` and `hide-watched-release-tvos.log`;
the final native-check log is `hide-watched-check-final.log`. Artifacts remain local.

Earlier UI attempts exposed an incorrect Stepper locator, a fixture page consumed by Shorts
prefetch and stale cached UI-test code. Those attempts are not acceptance. The final run
uses explicit derived-data selection and verifies the current test file was recompiled.

Physical-device and real-account progress checks: NOT RUN. Filtering still depends on
YouTube-reported progress; missing progress remains visible. Local resume positions are
not treated as durable watch history. No account data or additional tracking is introduced.

Delivery target is local master, with the primary checkout's staged/unstaged localization,
Release Run scheme and local signing settings preserved. No remote push is part of this task.
No implementation blocker remains.
