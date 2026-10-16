# PLAN-0008: Remember playback quality across videos

Status: completed

Resolution: remembered quality and resolution-first fallback are implemented and verified in simulators.

Owner: coding agent. Basis: user request, 2026-10-16.
Git boundary: `mac/feed-version-shorts` at `783f764`; existing uncommitted PLAN-0006/0007 work retained.
Delivery: local `master`; remote publication remains a separate step.
Scope: persist the last explicit quality choice, including Auto, and apply it on the next video.
Resolve unavailable choices by nearest resolution, then matching codec. A temporary fallback
must not overwrite the user's saved preference. Device and stream codec restrictions still apply.
Constraints: reuse SettingsStore and PlaybackQualityManager; keep Auto's existing policy,
avoid additional network requests, and keep candidate selection linear and in memory.
Dependencies: existing player metadata, HLS manifests, simulator runtimes and Swift Testing fakes.
Acceptance: persistence across resets and settings round trips; exact and nearest selection;
resolution before codec; Auto preserved; iOS/tvOS build and checks pass.
Next deliverable: none within this scope. Blockers: none.

| Checkpoint | Evidence |
|---|---|
| Cause | The picker stores a per-video override which reset clears. Resolution-only caps and codec-first DASH ordering also differ from the requested matching rule. |
| Implementation | SettingsStore persists the explicit resolution and codec, or Auto. Reset and temporary stream fallbacks preserve that intent. HLS selection uses actual manifest tracks and cached codec metadata; DASH uses the same resolution-first matcher. Existing codec/device restrictions and Auto policy remain. |
| Matching | Exact resolution/codec, resolution before codec, nearest higher resolution, equal-distance ties, non-standard heights, old settings migration, unknown codec decoding, Auto, and temporary fallback/recovery are covered by unit tests. Matching is linear and in memory; manifest metadata reuses the existing request/cache. |
| UI acceptance | `PlayerVideoScaleUITests.testQualitySelectionSurvivesNextVideoAndRelaunch` passed on iPad Pro 11-inch (M5), iOS 26.5 Simulator, Debug. 720p persisted through relaunch and Next; Auto persisted through relaunch. Playback time continued after each selection/load. No skipped tests. |
| Checks | 962 tests in 137 suites, formatting, document links, source rules and SwiftLint passed on 2026-10-16. iOS and tvOS build-for-testing passed with their UI-test targets. |
| Review and limits | Inspected preference writes and native HLS, WebView HLS, DASH, audio-only restore and quality recovery callers. No independent review or physical-device codec/performance test was performed. General physical-device performance acceptance remains [OQ-0013](../../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance). |
