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

## OQ-0004 — Reviewer notes and privacy statements

- Status: open; owner: maintainer / release owner; review before reusing submission text.
- [Archived reviewer notes](archive/reviewer-notes.md) say no personal data is stored or shared;
  the [published privacy policy](../PRIVACY_POLICY.md) also claims no network transmission or
  telemetry. Source inspection contradicts those blanket statements: `TokenManager` persists
  credentials/account metadata in Keychain; local stores retain watch/settings data; APIs send
  network requests; `CrashlyticsLogger` forwards diagnostics when enabled by app startup.
- Next step: inventory actual data flows and settings, then reconcile reviewer text, privacy
  disclosures, and the overview's "no tracking" claim with the release owner. Source inspection
  does not establish server retention or the contents of an App Store submission; those were
  **NOT CHECKED**. Do not submit the archived notes as current copy.

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
  `ShortsEmbedPauseControlsUITests`, `ShortsEmbedSrcSwapSpikeUITests`, `ShortsEmbedPlayerUITests`).
- "Watch in incognito" (#94) no longer suppresses watch history or resume position: only the
  removed embed player honored it, and `PlayerRouter.open` ignores `incognito`. Wire it into the
  AVPlayer path or remove the action.

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
