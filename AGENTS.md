# SmartTube — agent guide

Native Swift/SwiftUI YouTube client for iOS/iPadOS (17+), macOS Catalyst (14+) and tvOS (17+).
Package `SmartTubeIOS/` (targets `SmartTubeIOSCore` = Foundation-only models/API/stores,
`SmartTubeIOS` = SwiftUI views, view models, services) + Xcode project `SmartTubeApp/`
(iOS+Catalyst app, tvOS app, Share/Safari extensions, Download widget, UI-test targets).
Architecture map: [docs/architecture.md](docs/architecture.md) · Glossary: [CONTEXT.md](CONTEXT.md) · Decisions: [docs/adr/](docs/adr/) · Docs index: [docs/README.md](docs/README.md)
Overview: [README.md](README.md) · [CHANGELOG.md](CHANGELOG.md) · [PRIVACY_POLICY.md](PRIVACY_POLICY.md) · Claude Code: [CLAUDE.md](CLAUDE.md)

## Commands (scripts in `scripts/`, safe from any cwd)
- `scripts/ci.sh` — secrets + doc links + swift-format check + package unit tests. Run before every commit, with SwiftLint:
  `swiftlint lint --strict --baseline .swiftlint.baseline --config .swiftlint.yml` (fails only on new violations).
- `scripts/verify.sh` — ci + SwiftLint + iOS/tvOS simulator builds (+ Smoke UI plan once it exists); `VERIFY_SCOPE=fast|build` stop earlier.
- `scripts/build-for-testing.sh` — compile iOS/tvOS apps with their UI-test targets, no run.
- `cd SmartTubeIOS && swift test --filter <Name>` — one Swift Testing suite (no simulator).
- UI tests: docs/how-to/run-tests.md (many suites need a signed-in simulator; 3 workers max).
- `xcrun swift-format format --in-place --recursive --configuration .swift-format <paths from scripts/ci.sh>` — format.

## Rules that differ from defaults
- Swift 6 strict concurrency everywhere. View models are `@MainActor @Observable`. No `ObservableObject`, `@Published`, Combine, `DispatchQueue`, completion handlers in new code.
- `SmartTubeIOSCore` must stay Foundation-only (no SwiftUI/UIKit/AVFoundation/WebKit). Put platform code in `SmartTubeIOS`.
- One definition per constant/identifier/threshold. Accessibility identifiers come from `AccessibilityID`; SF Symbols from `AppSymbol`; playback timeouts from `PlaybackTuning`.
- Wrap UIKit-only API in `#if os(iOS)`; provide AppKit/tvOS branches. Never nest `NavigationStack`s.
- Never hand-edit `project.pbxproj` (a hook blocks it). New Swift files under synchronized folders are picked up automatically; UI-test files must be added in Xcode.
- Tests: Swift Testing for unit tests; no `Task.sleep`, no live network, fakes at protocol seams. UI tests use `AccessibilityID` and `waitForExistence`, never `sleep`.
- Logging via `os.Logger` (subsystem `AppSubsystem`), never `print`.
- Commits: Conventional Commits with the task ID, e.g. `fix(player): … (#312)`.

## Gotchas
- The Simulator cannot decode VP9/AV1 and cannot run PiP; assert stream *selection* in tests, not decoding.
- WKWebView `evaluateJavaScript` has no user activation: PiP/fullscreen cannot be triggered from Swift.
- Authenticated InnerTube calls use the TVHTML5 client on youtubei.googleapis.com with a Bearer token and no API key; the WEB client rejects Bearer tokens. Never call `/oauth2/v3/userinfo` for account info (the TV OAuth client isn't Data-API-v3-enabled) — use `account/accounts` with the TVHTML5 context instead.
- The 16 GB build Mac stalls with > 3 parallel simulator clones; the scripts cap UI workers at 3.
- Playback fallback code (`PlaybackViewModel+Fallback.swift`) is under active decomposition (WS4). Do not add branches there; add a `StreamSource`.
- Package tests run on native macOS: code under `#if !os(tvOS)` must also compile for AppKit (`TOSPlayerView` has an `NSViewRepresentable` branch; `NSImage.pngData()` is a local shim).
- `swift test --parallel` runs suites concurrently. Tests touching a shared static (`CurrentQueueStore.shared`, a test `URLProtocol`'s routes) must be `.serialized` — nest suites sharing the same global under one serialized parent (e.g. `CurrentQueueStoreSuites`). Poll for the expected state with a deadline instead of a fixed sleep.
- AVPlayer playback tries the VISIONOS client's HLS first (H.264-filtered master, 1080p cap, visionOS User-Agent); its responses are recognised by `c=VISIONOS` in format URLs (`PlayerInfo.isFromVisionOSClient`).
- Yandex voice-over (`VoiceOverTranslationController`) plays a voice-only MP3 in a second AVPlayer synced to the video. Hold/resume the video only via `setVideoPlaying` (keeps `isPlaying` in sync for the stall watchdog), and never load that MP3 with precise timing or seek it in a loop: mediaplaybackd times out and gets killed, and every AVPlayer then fails with -11819 until relaunch.
- The Yandex OAuth token (lively voices) lives in the Keychain via `TokenManager`; never log it or put it in settings JSON.

## Where things are
- Playback: [docs/architecture.md#playback](docs/architecture.md#playback) · Tests how-to: [docs/how-to/run-tests.md](docs/how-to/run-tests.md) · Device logs: [docs/how-to/device-logs.md](docs/how-to/device-logs.md) · Release: [docs/how-to/release.md](docs/how-to/release.md)
