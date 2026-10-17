> Status: current — general command/configuration review 2026-10-15; targeted physical iPad performance checks run 2026-10-16 and menu/window checks 2026-10-17, not a full UI-suite rerun.

# How to run tests

**When to use:** running unit or UI tests locally, or setting up a fresh simulator.

Run the commands below from the repository root.

## Local Shorts preloading measurements

Start `python3 scripts/shorts-media-fixture.py` in another terminal (requires an installed
FFmpeg; `--ffmpeg /absolute/path` selects it). The server generates a synthetic H.264 movie in
a temporary directory, binds only `127.0.0.1:18765`, adds fixed manifest/first-segment latency,
and removes the media on Ctrl-C. No YouTube account or remote media is involved.

Run `ShortsPreloadingUITests` on an iPad Simulator with the normal UI-test command below and
`-only-testing:SmartTubeUITests/ShortsPreloadingUITests`. The suite skips with an explicit reason
when this local fixture is absent. Attachments contain five cold and five prepared load-to-ready
samples. The sustained case exercises 60 swipes, background release, manual resume and reopening.
Load-to-ready is not a measure of first visible frame or live-network/device performance.

## Full-screen player gestures

`PlayerLevelGestureUITests` uses the same local server on Simulator and checks both orientations,
slow level drags, fast minimize, horizontal navigation, taps, hold-to-speed, buttons and scrubbing.

`PlayerLevelDeviceUITests` calibrates real brightness and volume on a connected iPad. It uses a
local movie through the downloaded-video path, retains account/settings/queue, and restores the
captured system levels. Prepare its file while the local server above is running:

```bash
mkdir -p /tmp/smarttube-gesture-fixture
ffmpeg -i http://127.0.0.1:18765/preload-0/master.m3u8 -c copy /tmp/smarttube-gesture-fixture/fixture.mp4
xcrun devicectl device copy to --device <device-UDID> \
  --source /tmp/smarttube-gesture-fixture --domain-type appDataContainer \
  --domain-identifier com.ibaranov.smarttube.app --destination Documents/SmartTubeDownloads/UITestMedia
xcodebuild test -workspace SmartTube.xcworkspace -scheme SmartTube \
  -destination 'platform=iOS,id=<device-UDID>' -parallel-testing-enabled NO \
  SYMROOT=/private/tmp/smarttube-gestures/Build/Products \
  OBJROOT=/private/tmp/smarttube-gestures/Build/Intermediates.noindex \
  -only-testing:SmartTubeUITests/PlayerLevelDeviceUITests
```

Unlock the iPad and leave its display and audio route unchanged during calibration. Simulator
cannot validate system levels. Hardware checks read Control Center's visible controls rather
than the separate test runner's cached audio-session volume. `SHORTS_TEST_MEDIA_URL=downloads`
is a DEBUG-only fixture selector; it does not register a download or replace the current queue.
The hardware suite disables UIKit animations with `--uitesting-disable-animations`: on iPadOS 27,
XCTest otherwise waits 60 seconds for an animation-completion notification even with no active
layer animations. The ordinary simulator gesture/conflict tests run with animations enabled.
Control Center is opened over the running player so measurements keep the same audio route.
Do not use `devicectl device copy to --remove-existing-content true` to clean a nested fixture
directory: on Xcode 27 this cleared the whole app data container despite the destination path.
Keep a device-container backup before hardware tests; remove only the exact fixture files from
the running app/debugger, or leave them for the next calibration.

## Target simulator

The following is the previously recorded development destination, not a portable requirement.
Its current availability was not checked. Select an installed iOS Simulator with
`xcrun simctl list devices available`; substitute its name or UDID in the commands below.

| Property | Value |
|---|---|
| Name | iPhone 17 |
| UDID | `6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6` |
| OS | iOS 26.4.1 |

### One-time simulator setup

Disable the crash dialog so a mid-test crash doesn't block subsequent tests (persists across
reboots, reset if the simulator is erased):

```bash
xcrun simctl boot 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 2>/dev/null; sleep 3
xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 \
  defaults write com.apple.CrashReporter DialogType none
```

Verify: `xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 defaults read com.apple.CrashReporter DialogType` should print `none`.

## Memory ceiling

16 GB Mac Mini. Each simulator clone adds ~500–750 MB RAM (copy-on-write). **3 workers is the
ceiling** — 5 stalls clone boot indefinitely with no output. `scripts/verify.sh` and the commands below use 3; don't raise
it without more RAM.

## Commands

- `cd SmartTubeIOS && swift test --parallel` (`--filter <Name>` for one suite) — Swift Testing package tests, no simulator.
- UI tests (`SmartTube.xctestplan`, the scheme's only plan; `Smoke`/`Live` plans are absent; [OQ-0003](../OPEN_QUESTIONS.md#oq-0003--smokelive-test-plans-and-nightly)):

  ```bash
  xcodebuild test -workspace SmartTube.xcworkspace -scheme SmartTube -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled YES -maximum-parallel-testing-workers 3 -only-testing:SmartTubeUITests/<Suite>/<testMethod>
  ```

  Drop `-only-testing` for the whole UI suite (many suites need a signed-in simulator and network).
- Compile the apps with all UI-test targets without running them: `scripts/build-for-testing.sh`.
- Device/app log capture during a test run: [device logs](device-logs.md).
- Without `SmartTubeApp/Smoke.xctestplan`, `scripts/verify.sh` skips the UI stage after
  successful checks and simulator builds and exits successfully, even with the default full scope.
  No UI tests run on that path; this is the open gap in [OQ-0003](../OPEN_QUESTIONS.md#oq-0003--smokelive-test-plans-and-nightly).
  `VERIFY_SCOPE=fast` stops after CI/lint; `VERIFY_SCOPE=build` stops after simulator builds.
  None of these paths proves UI acceptance. Nightly Live remains disabled pending the plans and runner.
- Record `NOT RUN` with a reason and platform in the task evidence. Simulator checks do not
  establish physical-device decoding, PiP, or background-audio behavior; see [OQ-0005](../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).

## Package tests on iPad Simulator

The workspace's `SmartTubeIOS` product scheme has no Test action. Run the package's
own `SmartTubeIOS-Package` scheme from its directory to exercise iOS-only unit tests:

```bash
cd SmartTubeIOS
xcodebuild test -scheme SmartTubeIOS-Package -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<simulator-UDID>' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  '-skip-testing:SmartTubeIOSTests/TokenManagerTests/setTokenPersistsToKeychain()' \
  CODE_SIGNING_ALLOWED=NO
```

The one explicit exclusion is a Keychain integration test: the standalone iOS
test runner lacks its required entitlement (`SecItemAdd` returns -34018). It
remains enabled in the native macOS package checks. Do not treat an excluded
test as passed or weaken production Keychain security to accommodate this host.
The parentheses in the Swift Testing selector are required.

## Physical iPad performance

`IPadPerformanceUITests` measures five launches to the first responsive frame and five
four-swipe Home sequences (CPU, memory and scrolling hitches), then checks repeated tab
navigation. It retains the device's account and settings. The Home tests require a populated
feed and network access; launch measurements do not include waiting for the feed response.

```bash
xcodebuild test -workspace SmartTube.xcworkspace -scheme SmartTube \
  -destination 'platform=iOS,id=<connected-device-UDID>' \
  -only-testing:SmartTubeUITests/IPadPerformanceUITests \
  -parallel-testing-enabled NO -resultBundlePath iPadPerformance.xcresult
```

Use the same device, build configuration and account for comparisons, keep other profiling
sessions stopped, and do not interact with the iPad during measurements. The app runs without
an attached debugger in these tests. Compare network-dependent timings separately from
rendering; one short run does not establish sustained performance or a debugger's overhead.
See [PLAN-0010](../exec-plans/completed/ipad-performance.md) for measured evidence and limits.

## iPad menu restoration and window resizing

Run `IPadMenuLayoutUITests` with `-parallel-testing-enabled NO` on an iPad. The orientation
case requires iPadOS 18+. `testMenusAcrossSplitViewAndWindowResizing` requires iPadOS 26+
and English system UI for the window arrangement command. It temporarily selects Windowed
Apps in Settings and restores the original multitasking mode in teardown.

The window case uses system gestures and controls: floating-window resizing in both dimensions,
SmartTube and Settings side by side, dragging the divider to narrow and wide layouts, then
returning to full screen without relaunching SmartTube. Each layout runs two channel/back,
Settings drill-down/back and Search/Library return cycles. Assertions cover the actual section
buttons, native top or bottom tabs, system window controls and preserved section selection.
Screenshots and window/button geometry are retained in the result bundle.

Subscription content is a fixture. The suite retains the device's real account and does not
reset SmartTube settings on physical hardware. Do not interact with the iPad during the run.
See [PLAN-0016](../exec-plans/completed/ipad-menu-overlap.md) for evidence and remaining limits.
