# Open questions

Reviewed: 2026-10-15 against the current working tree (`master`, HEAD
`23284b15d990607bbfcab0f7db1cf6d978229149`, with pre-existing uncommitted changes).
This is the single register of unfinished work, debt, unverified conditions, and decisions.
An entry does not authorize implementation. Remove a closed entry and record its outcome in
[CHANGELOG](../CHANGELOG.md) or an [ADR](adr/README.md); never reuse its ID.
`NOT RUN` is a verification result, not a passing check or an implementation status.
Owners below are roles for follow-up, not evidence that someone has accepted a new assignment.

## OQ-0001 — Public documentation migration

- Status: open; owner: maintainer / documentation owner; basis: [ADR-0009](adr/0009-docs-live-with-code.md), WS2-T2.6.
- The former index listed `docs/modernization/**`, `docs/RULES.md`, `docs/project.md`,
  `docs/running-tests.md`, `docs/tasks-log.md`, `docs/planning.md`, `.github/skills/*`, and about
  20 benchmark worklogs/feature plans as deliberately retained in a private repository.
  None was inspected in this public-checkout review. The old "moving mid-task is risky"
  explanation is not proof that continued deferral is necessary.
- Next step: inventory the private material, redact sensitive content, and classify each item as
  current guidance, execution plan, decision, archive, or duplicate. Preserve task IDs and useful
  history; do not publish secrets or link nonexistent public paths. Acceptance: record each
  disposition and make retained public documents reachable from the agent guide.

## OQ-0002 — Stream pipeline and contributor guide

- Status: open; owner: playback maintainer; basis: [ADR-0005](adr/0005-stream-source-pipeline.md), WS4-T4.6/T4.7.
- Source evidence: `PlaybackViewModel+ExhaustiveRetry.swift`, `+FallbackRace.swift`, and stream
  helpers split the former fallback file, but no `StreamSource` or `ResolutionPipeline` exists.
  Moving branches into files does not prove behavioral parity with the proposed pipeline.
- `docs/how-to/add-a-stream-source.md` is absent. Write it when the actual extension point exists;
  until then the ADR is a proposal, not a usable API. Acceptance: pipeline parity evidence,
  independent review, and a contributor guide matching the implementation.

## OQ-0003 — Smoke/Live test plans and nightly

- Status: blocked; owner: test/CI maintainer; basis: WS3-T3.4 and [test guide](how-to/run-tests.md).
- The checkout contains only [SmartTube.xctestplan](../SmartTubeApp/SmartTube.xctestplan),
  not `Smoke.xctestplan` or `Live.xctestplan`. Without `SmartTubeApp/Smoke.xctestplan`,
  [verify.sh](../scripts/verify.sh) skips the UI stage after successful checks and simulator builds
  and exits successfully, even with the default full scope. No UI tests run on that path;
  this missing UI execution is the open gap.
- [Nightly Live](../.github/workflows/nightly-live.yml) is disabled with `if: false` and requests
  `-testPlan Live`. Its comment says no self-hosted runner is registered. Remote runner
  registration was **NOT CHECKED** here; absence is a recorded prerequisite, not a live account finding.
- Next step: create stubbed Smoke and network-dependent Live plans through Xcode, verify scheme
  membership, then provision/confirm a signed-in runner before enabling nightly. Acceptance:
  actual Smoke execution and a recorded Live run; compiling UI tests alone is insufficient.

## OQ-0005 — Playback device acceptance

- Status: open; owner: playback/test maintainer; basis: [ADR-0010](adr/0010-remove-iframe-player.md).
- **NOT RUN in this review:** iOS regular-video and Shorts playback through AVPlayer after the
  embed players were removed (ADR-0010), including swipe navigation, end-of-Short behavior and
  per-Short load errors (the embed path's auto-advance-on-error is gone); minimize/expand/stop
  audio continuity, background/foreground recovery, physical-device PiP;
  AVPlayer HLS/DASH quality switching and CDN segment playback. Existing UI suites and old pass
  counts do not establish current results for this dirty working tree.
- Simulator selection checks cannot establish VP9/AV1 decoding or PiP. Follow the
  [test guide](how-to/run-tests.md) and [device-log guide](how-to/device-logs.md), recording exact
  revision, platform, suite, executed test count, result bundle and logs; zero executed tests is
  not acceptance.
- UI-test target cleanup: the removed embed-player UI-test files are still listed in the
  `UITests` group and Sources build phase of `SmartTubeApp.xcodeproj` until removed in Xcode
  (`TOSPlayerUITests`, `TOSPlayerIOSUITests`, `TOSPlayerSwipeNavigationUITests`,
  `ShortsEmbedPauseControlsUITests`, `ShortsEmbedSrcSwapSpikeUITests`, `ShortsEmbedPlayerUITests`,
  `ShortsVisualPlaybackUITests` — 7 files; deleted from disk, references remain).

## OQ-0006 — BotGuard acceptance

- Status: open; owner: playback maintainer; plan: [PLAN-0003](exec-plans/active/BotGuard.md).
- Minting and token-injection code exists. **NOT RUN:** a current signed-in/out matrix proving
  token availability, client/session binding (including reuse with iOS adaptive URLs), media
  segment success, dubbed-audio availability, and the original latency/quality claims.
- `InnerTubeAPI.poTokenExpiry` is declared but not read or updated; current cache checks use
  video ID. Define and validate expiry/invalidation behavior before treating token reuse as proven.
- WAA response-format monitoring is not configured in the nightly workflow. Decide whether it is
  needed, then record the probe and owner separately from unit tests (which must remain offline).
  Acceptance: reproducible live evidence without logged tokens, plus an explicit cache policy.

## OQ-0007 — Release runbook and version settings

- Status: open; owner: release maintainer; basis: [release guide](how-to/release.md), WS1-T1.4.
- `Base.xcconfig` defines versions, but `project.pbxproj` still carries hardcoded version settings
  and no `baseConfigurationReference`. Do not claim config centralization is finished. Reconcile
  through Xcode and verify resolved build settings for every shipping target/configuration.
- Signing, archive, and TestFlight/App Store upload have no public end-to-end runbook. Private
  material and live signing/upload were **NOT CHECKED**. Capture actual release steps on the next
  authorized release; do not invent account-specific procedure.

## OQ-0008 — Shorts follow-ups

- Status: deferred; owner: playback maintainer; basis: [ADR-0010](adr/0010-remove-iframe-player.md).
- Shorts now play through `PlaybackViewModel` on every platform. Like/dislike and comments UI in
  the Shorts overlay, and pre-warming the next Short for instant swipes, are not implemented.
  Decide which follow-ups are still wanted before making an execution plan; runtime verification
  is OQ-0005.

## OQ-0009 — Architecture debt

- Status: open; owner: architecture maintainer; basis: [architecture](architecture.md),
  [ADR-0004](adr/0004-plain-init-injection.md), WS5/WS6/WS7/WS8.
- The Foundation-only Core rule is not yet achieved: examples include SwiftUI in `AppSettings`,
  AVFoundation in `SponsorBlockSkipManager`, JavaScriptCore in `BotGuardClient`, and Network in
  `InnerTubeAPI`. Source boundaries, not the package target name, determine portability.
- `PlaybackSession`, the proposed resolver target and shared app navigation/composition are not
  present as the planned abstractions. Existing entry points and player types still own their
  own setup. Preserve behavior while defining the next authorized slice; do not treat the private
  modernization roadmap as accepted/current evidence from this checkout.
- Close each debt only with scoped source changes, relevant checks and independent review;
  file decomposition alone is not closure.

## OQ-0011 — Localization coverage and review

- Status: open; owner: localization maintainer; basis: [localization guide](how-to/localization.md).
- The current catalog has 345 keys and 275 locale entries for each of the 15 translated
  languages; entry presence is not translation-quality acceptance. The older 261-key/99% claim
  is retired. Native-language review and a translation run were **NOT RUN** in this review.
- Next step: classify untranslated keys (including intentionally skipped format-only keys),
  fill required UI translations, and review them before release. Preserve existing/plural entries
  when using forced retranslation; `extractionState: manual` alone does not protect them.

## OQ-0012 — iOS player gestures lost with the embed player

- Status: deferred; owner: playback maintainer; basis: [ADR-0010](adr/0010-remove-iframe-player.md).
- The removed TOS player had left/right edge swipes for screen brightness and system volume
  (`GestureAdjustmentHUD`, `SystemVolumeControl`) and a chapters overlay (`ChaptersOverlayView`).
  `PlayerView` has none of these, so iOS users lost them. The code is in git history before ADR-0010.
- Next step: decide whether `PlayerView` should get them; if so, port with tests rather than
  restoring the embed-player wiring.

## OQ-0013 — iOS HLS prewarm on card appearance

- Status: open; owner: playback / release maintainer; basis: [ADR-0010](adr/0010-remove-iframe-player.md).
- `VideoCardView` starts HLS prewarm when non-Shorts cards appear. This was formerly the main
  source of SlowLoad; its effect on iOS after the embed-player removal is **NOT MEASURED**.
- Next step: before release, compare prewarm enabled and disabled on a physical iOS device
  with the same feed and network conditions, covering cold and warm caches. Record card
  appearance/scroll responsiveness, tap-to-play latency and SlowLoad frequency, with the exact
  revision, device, sample counts and logs. Acceptance: measured results and a recorded decision
  to retain, limit or disable prewarm; source inspection alone does not establish a performance gain.

## OQ-0014 — Firebase removal: Xcode project and App Store follow-up

- Status: open; owner: maintainer / release owner; basis: Firebase removal (CHANGELOG, Unreleased).
- Source no longer imports Firebase and `SmartTubeIOS/Package.swift` has no dependencies, so the
  firebase-ios-sdk package (and its transitive Google packages) is no longer resolved for the app.
  The Xcode project still holds Firebase leftovers that must be removed in Xcode
  (`project.pbxproj` is never hand-edited). Until then a build on a machine without a cached
  firebase-ios-sdk checkout fails in the Crashlytics run script, and the iOS app still bundles a
  local `GoogleService-Info.plist` when one exists on disk.
- Steps in Xcode (`SmartTube.xcworkspace`, project `SmartTubeApp`):
  1. Target **SmartTube** (iOS/native macOS) → Build Phases: delete the Run Script phase that runs
     `.../firebase-ios-sdk/Crashlytics/run -gsp ${SRCROOT}/SmartTubeApp/GoogleService-Info.plist`
     (shown as "Run Script", object `67F34A972FA0A6A200EA6054`).
  2. Same target → Build Phases: delete "Copy Firebase Binary dSYMs" (`FFDDBB9900112233445566AA`).
  3. Same target → Build Phases → Copy Bundle Resources: remove `GoogleService-Info.plist`; then in
     the navigator delete the `SmartTubeApp/GoogleService-Info.plist` reference (group `SmartTubeApp`,
     "Remove Reference"), and delete local copies of that file from each checkout.
  4. Target **Smart Tube** (tvOS) → Build Phases: delete the Crashlytics Run Script phase
     (`674707572FB7AD00005095A5`, same command as step 1).
  5. Project → Package Dependencies: confirm firebase-ios-sdk is not listed (the project only
     references the local `../SmartTubeIOS` package; no target links a Firebase product). Both
     `Package.resolved` files were deleted with the removal because every pin was a Firebase/Google
     package; if Xcode recreates the workspace one, it should list no remote packages.
  6. Optional: `NSApplicationCrashOnExceptions` in `SmartTubeApp/SmartTubeApp/Info-macOS.plist`
     was a Crashlytics recommendation; it only changes local exception handling on native macOS.
- App Store Connect: update the App Privacy answers (crash data no longer collected) and replace
  the obsolete [reviewer notes](archive/reviewer-notes.md) with text matching the
  [privacy policy](../PRIVACY_POLICY.md). Server-side state was **NOT CHECKED**.
- Acceptance: a clean checkout (no DerivedData, no `GoogleService-Info.plist`) builds iOS, tvOS and
  the UI-test targets, and the built app contains no `Firebase_*` bundles.
