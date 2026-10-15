> status: current (2026-09-11)

# How to run tests

**When to use:** running unit or UI tests locally, or setting up a fresh simulator.

Run the commands below from the repo root. Don't use
`mcp_xcode_RunAllTests`/`mcp_xcode_RunSomeTests` or any other `mcp_xcode_*` tool to run tests.

## Target simulator

Single source of truth for the iOS/Catalyst target simulator — don't copy this UDID into other
docs, link here instead.

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
- Smoke plan (hermetic): `VERIFY_SCOPE=full scripts/verify.sh` runs it after the gate and builds, or directly:

  ```bash
  xcodebuild test -workspace SmartTube.xcworkspace -scheme SmartTube -testPlan Smoke -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled YES -maximum-parallel-testing-workers 3 CODE_SIGNING_ALLOWED=NO
  ```

- Live plan (needs a signed-in simulator): the same command with `-testPlan Live` and without `CODE_SIGNING_ALLOWED=NO`.
- A single UI test: add `-only-testing:SmartTubeUITests/<Suite>/<testMethod>` and drop `-testPlan`.
- Device/app log capture during a test run: `docs/how-to/device-logs.md`.
