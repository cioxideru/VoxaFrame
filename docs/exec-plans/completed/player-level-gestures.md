# PLAN-0024: Full-screen brightness and volume gestures

Status: completed

Owner: Codex. Work is isolated in the attached subscriptions-ipad worktree from
6eb7158. The main checkout's localization and Xcode scheme edits are outside scope.

Scope: slow, single-finger vertical drags adjust screen brightness on the left and
system volume on the right of the regular full-screen iOS/iPadOS player. Show the
two zones briefly with level feedback; preserve taps, double taps, hold-to-speed,
horizontal navigation, fast downward minimize, scrubber and menu interactions.
Shorts, mini-player, tvOS and native macOS keep their existing gesture meanings.

Use the existing UIKit gesture surface, lock axis and side for each gesture, leave
system edges and controls alone, and remove the second competing drag handler.
Brightness is temporary to the full-screen foreground presentation; system volume
changes only in response to a user's drag. Existing translation mixing stays intact.

Basis: Apple's [gesture guidance](https://developer.apple.com/design/human-interface-guidelines/gestures),
[recognizer coordination](https://developer.apple.com/documentation/uikit/coordinating-multiple-gesture-recognizers),
[MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview), and
[UIScreen brightness](https://developer.apple.com/documentation/uikit/uiscreen/brightness).
System volume cannot be validated in Simulator; use the connected iPad for that layer.

Acceptance: deterministic intent/level tests, local-media UI conflict scenarios,
physical-device level calibration, package CI, strict SwiftLint and iOS/tvOS builds.
Dependencies: existing local HLS fixture and UI-test source files. No new dependency
or manual Xcode project edit. No implementation blocker identified.
Outcome: gestures and conflict handling are implemented and accepted on simulators and iPad.

| Checkpoint | Evidence | Result |
|---|---|---|
| Existing behavior | UIKit pan plus a separate SwiftUI drag; both minimize on any downward drag | inspected |
| Implementation | One UIKit pan locks the axis and starting half; native volume slider, temporary brightness, percentage feedback and localized hints | implemented |
| Conflict checks | Local HLS fixture: vertical drags in both orientations, transport buttons, scrubbing, double tap, horizontal navigation, two-finger tap, long press and fast minimize | passed |
| Native checks | 1100 tests in 152 suites; strict SwiftLint without new violations; iOS and tvOS simulator builds | passed |
| Hardware | Physical iPad: brightness 80% → 67% → 80%, system volume 54% → 68% → 54%; Home and Back restore brightness; 54-second run with no failures | passed |

The custom UIKit player host does not inherit SwiftUI's scene phase. Gesture gating
uses the actual window activation state, and a scene-deactivation notification
restores brightness. The existing show-controls test argument now also suppresses
the iOS hide timer. Short-drag feedback has its own dismissal regression.

The first UIKit pan velocity includes touch-down on a fast iPhone drag. Classification
waits one further vertical sample before locking speed; the regression and all five
UI conflict scenarios pass on both iPhone and iPad simulators.

Parallel work is coordinated with the Main task (offline playback and VoxaFrame).
PLAN-0024 avoids its plan IDs, and Xcode products/intermediates use explicit isolated
paths. The physical iPad is reserved for this calibration; Main uses a separate
simulator. An earlier test replaced the current queue with a fixture. The user asked
to leave it as-is; the final device scenario uses a deep link without queue injection.

Volume uses the same native slider for reads and writes, including before the
playback audio session is active. Hardware calibration compares against Control
Center; an inactive test runner's audio session returned a stale volume and is not
used as evidence. Bluetooth and AirPlay route changes are outside this calibration.

Evidence: `/private/tmp/smarttube-gestures-iphone-5.xcresult` (5/5),
`/private/tmp/smarttube-gestures-ipad-final.xcresult` (5/5), and
`/private/tmp/smarttube-gestures-device-21.xcresult` (1/1, physical iPad).
The device test keeps its audio session active when opening Control Center and
restores levels from actual control readings. A DEBUG-only UIKit-animation switch
avoids iPadOS 27 XCTest quiescence timeouts; production and simulator animation
behavior is unchanged. No diagnostic instrumentation remains in the player.

Cleanup incident: `devicectl copy to --remove-existing-content true` unexpectedly
cleared the app data container rather than the nested fixture directory. The saved
preferences were restored and verified equal (settings, queue, local watch history,
search history and video state). Keychain is outside that container. The installed
build had downloads compiled out; caches are rebuilt. Do not repeat that cleanup
option on a nested path; see the hardware-test instructions.
