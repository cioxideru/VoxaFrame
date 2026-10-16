# PLAN-0006: Feed spacing, app version and AVPlayer Shorts

Status: completed

Resolution: the three code changes and simulator functional checks are delivered. Physical-iPad
performance acceptance remains open in [OQ-0013](../../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance).
The independent review's separate parked-item voice-over issue remains [OQ-0016](../../OPEN_QUESTIONS.md#oq-0016--voice-over-after-reopening-a-parked-video).

Owner: coding agent. Basis: user request, 2026-10-16.
Git boundary: `mac/feed-version-shorts`, starting at `783f764`; initially clean.
Delivery: local `master`; remote publication remains a separate step.
Scope, in order: replace mixed feeds with ten Shorts followed by six video-grid rows;
update the installed app version shown in Settings; diagnose and fix slow, unstable Shorts
after the AVPlayer migration. Channels and other distinct layouts retain their formats.
Constraints: reuse existing feed and playback owners; edit Xcode project settings through
Xcode; keep platform support, cancellation, error handling and accessibility intact.
Dependencies: existing Swift Testing fakes, UI-test fixtures, Xcode and an available runtime.
Acceptance: exact feed spacing across mixed sections and column counts, intact pagination
and distinct layouts; Settings reflects the updated bundle version/build; deterministic Shorts
regressions and actual-video navigation checks pass.
Next deliverable outside this implementation: physical-device measurements in OQ-0013.
Blockers to that evidence: the physical device profile disconnected or could not attach to the app.
Compilation and simulator checks do not establish physical-device speed or release acceptance.

| Checkpoint | Evidence and review |
|---|---|
| Feed layout | Ten Shorts / six video rows across mixed sections, preserving separate layouts. Unit coverage includes one through six columns. iPhone: Home, Subscriptions and Recommended spacing checks and both continuation checks passed. iPad: five mixed-feed tests passed, including vertical grid scrolling and horizontal section switching. Fixed missing initial Home loading and gesture arbitration. |
| Version | Xcode project owns 5.7 (25), inherited by shipping targets in Debug/Release. Removed stale xcconfig values and the iOS target override. All five shipping app/extension bundles contain 5.7 (25); Settings was visually checked. Release procedure updated. |
| Playback work | Removed recurring iOS card WebView/BotGuard warmup. Visible cards prefetch VISIONOS player info; Shorts lookahead starts on the first video. Cache publication no longer waits for optional metadata. Browser fallback starts only after native playback fails, and cancelled loads cannot replace the next video's item. |
| End events and gestures | Native item replacement installs end/stall observers with item-identity guards. Removed the obsolete window-level Shorts gesture bridge and the test-only black video substitute. One SwiftUI gesture handles visible/hidden controls; cancelled gestures reset the offset. Ten Shorts UI tests passed, including the short-swipe regression. |
| Actual playback | iPad simulator, iOS 26.5, Debug: real video frames, swipe forward, automatic advance at the end, swipe back, and another end-driven advance all worked. Lookahead returned usable player info; zero browser extractions and zero BotGuard log entries in this scenario. |
| Timing limits | Comparable first/second-video load-to-ready samples were 1679/644 ms before and 1667/641 ms after. This small uncontrolled sample demonstrates no meaningful speed gain; it is not launch time, first-frame latency, or an FPS benchmark. Physical iPad measurements remain OQ-0013. |
| Independent review | The delegated reviewer reported missing native end/stall observation and lost voice-over after reopening a parked video. The first has regression coverage and a fix here; the second is recorded separately in OQ-0016. No new independent review of the final implementation was performed. |
| Validation | iOS and tvOS build-for-testing passed with their UI-test targets. Final validation: 953 tests in 136 suites, formatting, document links, source rules and SwiftLint passed. Ten Shorts UI tests and five mixed-feed UI tests passed. |
