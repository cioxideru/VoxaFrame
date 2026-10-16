# PLAN-0007: Player Fit / Fill control

Status: completed

Resolution: toolbar Fit / Fill control and simulator acceptance are delivered.

Owner: coding agent. Basis: user request, 2026-10-16.
Git boundary: `mac/feed-version-shorts` at `783f764`, with uncommitted PLAN-0006 changes retained.
Delivery: local `master`; remote publication remains a separate step.
Scope: expose the existing video-gravity setting as a player toolbar button; default Fit,
Fill crops to cover the view, and orientation changes preserve the chosen mode.
Constraints: use the existing SettingsStore and persistent AVPlayerLayer; do not replace or
seek the AVPlayerItem. Preserve the double-tap shortcut and platform support.
Dependencies: current simulator, a live H.264 stream for UI acceptance, existing UI-test target.
Acceptance: the button toggles Fit/Fill; the live playback timeline continues through both
transitions and portrait/landscape rotation. iOS/tvOS test targets compile; checks pass.
Next deliverable: none within this scope. Blockers: none.

| Checkpoint | Evidence |
|---|---|
| Implementation | Existing persisted setting reused; toolbar button, accessibility state and tvOS remote routing added. The default remains Fit. The button and centre double-tap share the same toggle. |
| Playback and rotation | `PlayerVideoScaleUITests.testZoomPreservesPlaybackAndSurvivesRotation` passed on iPad Pro 11-inch (M5) and iPhone 17 simulators, iOS 26.5, Debug. Both transitions retained the timeline; playback continued after portrait/landscape rotation and the chosen mode remained selected. No skipped tests. Full-screen iPad screenshots were visually checked. |
| Checks | iOS and tvOS build-for-testing passed with their UI-test targets. 953 tests in 136 suites, formatting, document links, source rules and SwiftLint passed on 2026-10-16. |
| Review and limits | Inspected the existing path from SettingsStore to AVPlayerLayer: the iOS update changes videoGravity without replacing or seeking the player item. No independent review or physical-device / tvOS runtime test was performed. Fill crops the video frame; it does not detect black bars encoded inside that frame. |
