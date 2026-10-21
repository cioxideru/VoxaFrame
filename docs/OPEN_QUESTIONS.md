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
- [PLAN-0014](exec-plans/completed/shorts-feed-pagination.md) fixes active-tab and
  continuation ownership after the report of unrelated Shorts on later rows.
  Nested-response fixtures, three authenticated pages and four iPad Simulator feed
  tests pass; live account recommendation relevance still needs confirmation.
- [PLAN-0013](exec-plans/completed/shorts-translation-settings.md) separates Shorts
  translation preferences. Migration, persistence and isolation are covered by native
  tests and iPad Simulator controls checks; live Yandex audio/synchronization and
  physical-device acceptance remain unverified.
- [PLAN-0012](exec-plans/completed/shorts-account-controls.md) adds account-sourced
  Shorts and the regular player's translation/audio and Fit/Fill controls. Live
  signed-in recommendation relevance, Yandex service audio/synchronization and
  physical-device acceptance of these controls remain unverified. Request-routing
  tests and Simulator UI checks do not establish those results.
- [PLAN-0011](exec-plans/completed/resource-quality.md) passes package and UI checks
  on iPad Simulator. Its new audio-session ownership and idle player/WebView cleanup
  still need physical-device playback, interruption, voice-over and PiP acceptance;
  earlier device results below do not cover these changes.
- [PLAN-0009](exec-plans/completed/player-shorts-stability.md) adds persistent Shorts
  controls and repairs loading state, video-layer attachment and PiP restoration.
  iPad simulator checks cover real feed Shorts, seeking, mute, pause and repeated
  mini-player transitions. On 2026-10-16, the candidate working tree also passed two
  physical iPad Pro 11-inch (M5), iPadOS 27.0.1 tests without skips: three system PiP
  entry/return cycles with Home visible underneath and preserved playback, and real
  Shorts next/previous navigation with accessible controls. Restored video was
  visually confirmed after two seconds of playback; transient black frames are not excluded.
  Background recovery, long-session reliability, the codec matrix and tvOS runtime
  remain unverified; test these before closing this entry.
- **Historical 2026-10-15 review, before the focused checks above — NOT RUN:** iOS regular-video and Shorts playback through AVPlayer after the
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
- Version settings are now inherited from the Xcode project for all shipping targets. The stale
  values in the unused `Base.xcconfig` and the iOS target's build override were removed in PLAN-0006.
- Signing, archive, and TestFlight/App Store upload have no public end-to-end runbook. Private
  material and live signing/upload were **NOT CHECKED**. Capture actual release steps on the next
  authorized release; do not invent account-specific procedure.

## OQ-0008 — Shorts follow-ups

- Status: deferred; owner: playback maintainer; basis: [ADR-0010](adr/0010-remove-iframe-player.md).
- Shorts now play through `PlaybackViewModel` on every platform, with playback controls
  delivered in PLAN-0009. Like/dislike and comments UI in the Shorts overlay remain deferred.
  Lookahead fetches metadata for the next two Shorts; instant decoded-frame readiness is unverified.
  Decide which follow-ups are still wanted before making an execution plan; runtime verification
  is OQ-0005.

## OQ-0009 — Architecture debt

- Status: open; owner: architecture maintainer; basis: [architecture](architecture.md),
  [ADR-0004](adr/0004-plain-init-injection.md), WS5/WS6/WS7/WS8.
- The Foundation-only Core rule is not yet achieved. PLAN-0011 moved the theme's SwiftUI
  mapping and SponsorBlock's AVPlayer adapter into `SmartTubeIOS`. The Core import check
  permits only specific remaining legacy files: Network in `InnerTubeAPI`/`VideoPreloadCache`,
  JavaScriptCore in `BotGuardClient`, ActivityKit in `DownloadActivityAttributes`, and
  ImageIO/UniformTypeIdentifiers in `HomeWidgetSnapshot`. Source boundaries, not the
  package target name, determine portability.
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

- [PLAN-0015](exec-plans/completed/shorts-preloading.md) adds bounded native next-Short preparation.
  Local iPad Simulator latency and memory evidence is recorded there; live YouTube and physical
  iPad performance remain a separate acceptance step.
- Status: targeted physical-device checks complete; broader reported slowdown remains unconfirmed;
  owner: playback / release maintainer;
  basis: [ADR-0010](adr/0010-remove-iframe-player.md) and [PLAN-0006](exec-plans/completed/feed-version-shorts.md).
- [PLAN-0011](exec-plans/completed/resource-quality.md) fixes twelve resource and
  ownership issues and passes iPad Simulator acceptance. Before/after launch,
  scrolling, CPU and memory measurements on the physical iPad remain pending;
  the user deferred physical testing until all twelve implementation items were complete.
- PLAN-0006 removes recurring card-driven WebView/BotGuard warmup on iOS, starts card
  prefetch from scroll visibility on iOS 18+, and uses the same VISIONOS HLS client as playback.
  Browser extraction now starts only after native playback fails. iOS 17 retains the existing
  appearance/disappearance fallback for visibility.
- The tested iPad simulator Shorts path made no browser extractions or BotGuard requests;
  lookahead produced usable player info. A small before/after sample showed no meaningful
  cold-playback timing improvement. These results do not establish faster whole-app launch,
  smoother rendering, or lower resource use on the physical iPad.
- Physical profiling was attempted on the user's iPad Pro 11-inch (M5), iPadOS 27.0.1,
  with installed version 5.6 (24). The trace disconnected without usable samples, and later
  app-scoped attachment could not find the process. Version 5.7 (25) was tested in Simulator.
- The 2026-10-16 physical PiP/Shorts tests passed functionally but reported a runtime
  warning about synchronous AVAudioSession activation on the main thread; the PiP run
  also reported a priority inversion. These are profiling leads, not measured causes
  of the user's whole-app slowdown.
- [PLAN-0010](exec-plans/completed/ipad-performance.md) measured Debug 5.7 (25) on the same
  physical iPad and fixed redundant startup loads and feed resets on token refresh.
  `BrowseViewModel` Home fetch starts fell from three to one. Five-iteration launch and
  scrolling comparisons showed no meaningful speedup (launch 0.397 s before, 0.395 s after).
  All four physical launch/scroll/navigation/PiP tests passed; the final 20.71-second startup
  trace recorded no hangs or animation hitches. The broad slowdown was not reproduced.
- Next step for wider acceptance: compare an Xcode debugger-attached Run with standalone
  launch, longer sessions and cold/warm tap-to-play using the same account and network.
  Investigate the audio-session/priority-inversion leads if they recur in the slow scenario.
  The targeted fixes and short device checks do not prove the whole-app report resolved.

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

## OQ-0015 — Home feed review acceptance

- Status: awaiting verification; owner: coordinator; basis: [PLAN-0005](exec-plans/active/home-review-fixes.md).
- Six review findings have source fixes and regression coverage. Builds and tests were **NOT RUN**
  by the implementing agent, as instructed. Commit hooks were skipped to honor that restriction.
- Next step: compile under Swift 6 strict concurrency; run HomeRequestGenerationTests,
  HomeViewModelTests, HomeFeedSegmentTests, and HomeShortsEndlessUITests (Debug fixture).
  Verify refresh while switching chips, gesture arbitration, and tvOS focus separately.

## OQ-0016 — Voice-over after reopening a parked video

- Status: open; owner: playback maintainer; basis: independent review of `mac/feed-version-shorts`.
- `PlaybackViewModel.stop()` stops the voice-over controller. The same-video fast path in
  `resumeParkedItem(for:)` resumes the retained AVPlayerItem without reapplying the language /
  voice-over policy, so an enabled translation is not restored on reopening that video.
- Next step: restore the selected translation policy in the shared resume path without replacing
  the parked video item. Cover translation-enabled stop/reopen and the ordinary untranslated path.
- This separate review finding was not changed by PLAN-0006's feed, prefetch and Shorts fixes.

## OQ-0017 — Subscription and rare iPad menu live acceptance

- Status: subscription and requested iPad window acceptance complete; original rare wide-screen
  layout sequence remains unreproduced.
  Owner: navigation maintainer; basis: [PLAN-0017](exec-plans/completed/subscriptions.md)
  and [PLAN-0016](exec-plans/completed/ipad-menu-overlap.md).
- The physical iPad loaded 338 subscriptions with avatars. An approved temporary NASA
  subscription persisted after relaunch, unsubscribe succeeded, and a further relaunch
  confirmed the original unsubscribed state. The final live bundle has two passes, no skips.
- The original rare overlap was not reproduced in the baseline Simulator round trips.
  Corrected simulator channel/Settings drill-down/back, tab changes and both orientations pass;
  physical channel/back and Settings/Search/Library returns also pass in both orientations.
- The physical window follow-up reproduced window controls overlapping Home in a 375 × 496 pt
  floating window. PLAN-0016 now reserves the native top region at compact widths on iPadOS 26+.
  Floating-window resizing, half/narrow/wide Split View with Settings, and full-screen restoration
  passed two channel/Settings/back and tab-return cycles per layout, without restarting SmartTube.
  The test restored the initial Full Screen Apps mode.
- If the original wide-screen overlap recurs, capture the exact navigation sequence, orientation
  and window mode before extending layout policy. The passing requested matrix does not prove
  that every possible restoration sequence is covered.

## OQ-0018 — Offline library and playback priority on physical iPad

- Status: partial physical acceptance; owner: playback maintainer.
  Basis: PLAN-0020, PLAN-0021 and [PLAN-0028](exec-plans/completed/offline-ipad-cleanup.md).
- On 2026-10-20, [PLAN-0031](exec-plans/completed/offline-yandex-translation.md) fixed
  discarded original-language metadata and hidden Yandex refusal reasons. The same failed
  English video's Russian translation completed on iPad (10,208,279 bytes); the user
  confirmed audible saved playback, pause and seeking. CI passed 1,351 tests / 181 suites,
  strict lint had no violations, and physical iOS / tvOS Simulator builds passed.
  The subsequent English-to-Kazakh request still returned a Yandex FAILED response before
  any audio URL, reproduced independently on the Mac. Explicit language, auto detection
  and diagnostic cache bypass did not resolve it; the internal service cause is unknown.
  Kazakh translation work is deferred at the user's request on 2026-10-20.
  Airplane-mode listening and long-duration synchronization remain open.
- On 2026-10-20, [PLAN-0032](exec-plans/completed/offline-translation-language.md) fixed
  local live requests ignoring the saved original language. For the reported UPI video,
  the old Russian-labelled MP3 exactly matched Yandex's `auto→ru` response and contained
  Ukrainian speech. Explicit `en→ru` returned Russian; the old file was backed up and
  replaced while the app was stopped, then verified by a round-trip SHA-256 check.
  Video and both English audio tracks were preserved. The user confirmed Russian
  playback, pause and seeking; device logs confirm local translation attachment.
  This legacy-file repair did not repeat an in-app download or verify long playback.
- On 2026-10-17, the physical iPad completed an explicitly selected 720p H.264 video,
  original Russian audio and Yandex English translation. The video played with Wi-Fi off;
  the saved translation attached locally. The user confirmed audible English after explicitly
  selecting it. Legacy protected HLS deletion and Delete all of the three new files passed;
  queue, receipts and owned media were empty afterward. Offline listening and synchronization
  still need confirmation beyond the remote video image; the user did not observe the last
  Wi-Fi-off listening check. Build 37 again played local video with the selected translation
  attached and Wi-Fi off at 23:04–23:07; audible English still lacks confirmation. Delete all
  then removed all three files and download cache; the library stayed empty after relaunch.
  The failed retry jobs and interrupted test media had also been removed at 22:13.
- Simulator fixtures exercise the real system download sessions and local AVPlayer; they do not
  establish current YouTube signed-URL availability, Yandex translation generation, physical
  background-session wakeup or audio synchronization under device load.
- Build 37 completed the remaining 291 MB of the selected video while suspended, then started
  original audio automatically. This removes the reproduced per-range wake delay, but large
  CDN responses remain slow (about 0.27 MiB/s video and 32 KB/s audio in this run). Audio was
  cancelled/retried after returning to the app; the complete batch finished in the foreground.
  An active remainder does not shrink back into chunks when the app returns to the foreground.
- Next checks: confirm offline translation listening/synchronization, an entire multi-file batch
  and completion notification in the background, then add another quality/audio track online.
  Separately compare startup/buffering with competing downloads on the same connection.
- Source resolution and translation preparation need a running app. Accepted media transfers
  use system background sessions; force-quitting the app does not promise continued downloads.
- HLS uses its included audio with optional local VOT. External audio-file overrides require a
  direct video file; the UI explains this platform limit rather than attempting HLS composition.
- PLAN-0029 OFFLINE follow-up: local starts now avoid a separate duration load before item
  installation, queue prefetch and network artwork; local Next checks the current queue's successor
  without delaying item preparation and rechecks context after a suspended lookup. The library
  does not persist thumbnail bytes, so local lock-screen metadata has no artwork. Local preparation does not reserve network
  priority. Saved translation selection survives parked-item reopening; an explicit player request
  prefers the saved target-language track, then uses the original YouTube ID for live translation.
  Live output is not saved automatically. A local live request stops on its first network error,
  resumes original audio and keeps the error visible until an explicit retry. Online source-audio
  acquisition is unchanged: the extra VISIONOS lookup is limited to local videos.
  Offline AUDIO_REQUESTED polling re-uploads after three repeated polls, then fails with a localized
  retry message after three more (two uploads per job attempt). Cancel/retry and removal/re-enqueue
  start a fresh upload budget even if Yandex reuses its translation ID. At the existing 5–30-second poll delay this
  adds 30–180 seconds before failure, excluding request/upload time. Item details expose waiting,
  failure and retry states. Voice drift corrections require more than 1.5 seconds, a 10-second
  cooldown and a budget of three per audio item; attachment, pause/resume and timeline jumps align separately.
- Verification pending: the new protocol-fake unit tests and extended DownloadsPlaybackUITests
  have not been run. Confirm full-screen opening from a mini player and after Stop on iPhone/iPad;
  a late PiP didStart from before a new full-screen request is now rejected. Normal PiP entry
  still minimizes. PiP stop clears an unfinished restoration so later PiP entry is not vetoed.
  Repeated expand preserves the active cover's dismissal identity. Every minimize
  logs its caller reason. The offline detail play action does not pop navigation or dismiss a sheet;
  stale-cover dismissal remains hardening. Neither that dismissal nor the PiP race has been
  established as the original device trigger; capture the new caller logs if collapse recurs.
  Listen to saved/live translation, seek and change speed, then repeat without internet.
  `[offline-start]` logs mark tap, file lookup, audio-session activation, asset preparation, item
  installation, readiness and the first displayable iOS frame. Elapsed playback values start at
  `load`; use log timestamps for tap-to-frame latency. No new latency/throughput measurement is
  claimed, and the large background-response limitation above remains open.

## OQ-0019 — VoxaFrame redesign follow-ups

- Status: open; owner: UI maintainer; basis: [PLAN-0027](exec-plans/active/voxaframe-redesign.md), [ADR-0012](adr/0012-redesign-availability-and-tokens.md), [ADR-0013](adr/0013-minimum-os-18.md).
- iPadOS 27 multiwindow acceptance: [PLAN-0033](exec-plans/completed/ipad-sidebar-state-warning.md) fixes
  the sidebar launch warning and Queue identity regression; five focused UI tests pass without runtime warnings.
  The expanded test verifies navigation in 375×585 and 993×779 floating windows, then fails preparing
  Split View: the system places VoxaFrame on the left but does not pair Settings on the right.
  Repair the two-app scene setup and verify 1/2, 1/3, 2/3 and full-screen restoration; those stages are not accepted.
- The [PLAN-0035](exec-plans/completed/audio-translation-grouping.md) Shorts audio-panel check passed
  first-open bounds but timed out in the rotation helper waiting for a landscape-shaped app window.
  Make that setup account for iPadOS 27 windows before claiming post-rotation panel acceptance.
- Mini-player: the tab-bar bottom accessory was rejected in stage 2a (`0d446f6`): it re-parented the persistent player
  layer on every tab switch, has a fixed height, no opaque fallback and needs iOS 26.1. The overlay stays on every version.
  Its space is reserved by a UIKit bridge (`NavigationBottomReserve`) that adds the bar height to each tab's navigation
  controller; it was run only on an iOS 26 simulator, so check iOS 18–25 (Tab API) and 26 on a runtime or device.
  On iPad the floating sidebar edge is estimated from a 1 pt sidebar header (about 10 pt past the real edge); the docked
  sidebar in landscape, a 600 pt window and rotation were not run. At AX5 the stacked bar still takes about a third of an
  iPhone screen. A `smarttube://video/<id>` link opens with an empty mini-player title (the handler builds the video without one).
- Not implemented, still labelled in the mockups: A3, A6–A12, B4–B8 (including the Mac keyboard map and shortcuts), C1.
  The macOS menu bar gets entries for existing actions only.
- Device-only checks, `NOT RUN`: VoiceOver order and the timeline adjustable action, tvOS focus restore after Back, glass
  legibility over bright frames, PiP, Dynamic Type up to AX5 on iPad, Mac and TV, RTL.
- Accent on tvOS: stage 3a (`8d7c981`) switched iPhone and iPad only. On tvOS `.system` keeps the platform accent and
  `.vfProminent` stays `.borderedProminent`: white on the dark coral and coral on the white focus platter are both 2.07:1.
  Switch only after checking focused and unfocused contrast and Back on a tvOS runtime or device (none is installed here).
  Confirm on an iPhone in Dark Mode that `.vfProminent` labels are plum on the coral and black on the named accents.
- Increase Contrast: the colour pairs in `VFColor` have light/dark variants only. Ask design for high-contrast values
  (the review suggested `#9A2819` light and `#FFBFB4` dark for `action`) and add a 7:1 test; `vfGlass` thickens its stroke
  and `.vfProminent` adds a 2 pt edge as the interim.
- One button keeps the system style on purpose: the SponsorBlock skip toast is tinted with the segment colour, whose
  label contrast is not tested.
- macOS shell (stage 2b, `084cec3`): `scripts/verify.sh` never builds the macOS app scheme, so the two `AppEntry.swift` lines
  that call `MacWindowCommands()` and `MacSettingsScene` are checked by reading only (the types compile in the package).
  Build and run the macOS scheme in Xcode: inspector at 1440, 1000 and 800 pt windows, View > Show/Hide Inspector,
  Settings window, and a deep link over a card-pushed player (card A → link B → link C → Back: visible video,
  previous player stopped, navigation state). `InspectorCommands()` was replaced by one menu item, so ⌃⌘I is gone until B8.
- Tab and sidebar labels on every platform use `AppSection.rawValue`, not localized strings (the value is also the
  UI-test identifier, so localize the label only). Stage 8 (`daa217c`) gave macOS Search the content-stack player
  route; open a result on the Mac app to confirm.
  `SmartTubeApp/UITests/MacWKHLSReplayRegressionUITests.swift:27` still describes the old ZStack overlay, and its title
  check looks for a `video.card.title` child the redesigned card no longer has, so on macOS the title comparison is
  skipped. The iOS suite asserts the exact title through `AccessibilityID.videoCardTitle`.
- Stages 3–8 deferred by the acceptor:
  - Offline list/detail layout on iPad and Mac; Settings category navigation on iPad and tvOS.
  - Mac Search filters live only in a toolbar popover: View > Hide Toolbar removes access. A menu item needs a sheet fallback.
  - Queue position race: when the same video is reopened from another list while it is still loading, the load later
    recomputes `hasNext` from its captured video (`PlaybackViewModel+Loading.swift`, the queue fallback after related
    videos). With no related videos it can switch Next back off. The fix is to read `currentVideo` there, which needs a
    `PlaybackViewModel` change (WS4).
  - Player logic the re-skin did not add: "now playing" next to the selected quality, buffering state and buffered range,
    sleep-timer remaining time, end-of-video countdown, queue position, live variants, inline watch-page layout.
  - Russian UI: older labels (`Text` without `bundle: .module`) look up translations in the main bundle and stay English;
    "Parental Controls" has no ru string. Mac Settings pane heights are estimates.
  - Stage 8 on iOS 26: Queue can appear in the iPad top tabs; check selection when the window narrows (Queue → Library ›
    Queue). The queue has no "open offline" action and no now-playing mark.
  - Shorts seek bar on iOS is a `UISlider` wrapper (the SwiftUI `Slider` cannot tint its track); on macOS the SwiftUI
    slider keeps the system track colour. Check the rail at AX5 on a 375×667 device and the 760 pt threshold.
  - UI tests: `testDownloadsSegmentExistsInLibrary` fails because `ENABLE_DOWNLOADS` is never defined; the tvOS lookup
    `library.chip.subscriptions` never matches the real `library.chip.subs`, so that test skips.
  - `PlayerRouterQueueTests` is iOS-only, so `scripts/ci.sh` (native macOS) skips it; run it on an iOS simulator.
- Glass modifier leftovers: the glass and opaque branches are different view types, so toggling Reduce Transparency live resets content
  state; no `.interactive()` variant and no `GlassEffectContainer` guidance for adjacent glass shapes (mini-player plus bar).
  The macOS `surface` is a translucent fill (`quaternarySystemFill`) and is untested; `elevated` has no shadow.
- `AGENTS.md` and `HANDOFF.ru.md` still say Catalyst for Mac; the target is native macOS.
- Assumption to confirm: the iPhone/iPad tab order puts Search last on every OS version, not only where the search role renders apart.
- The design package now includes its own copy of the functional brief (`278111b`); DESIGN-0002 stays the maintained source,
  so a brief change must update both files or drop the copy.
- Offline boards drawn before PLAN-0028 show things the code does not do (PLAN-0027, "Stage 6 basis").
  PLAN-0030 adds sizes, storage totals and byte progress. Remaining gaps include deleting one saved track apart
  from its job, audio-only listening, re-download of a saved variant, saved date, queue position,
  cached covers for offline use and remembering the translation choice.
  Design docs to correct: `02-feature-coverage.md` §14 (storage error board, re-download status, notification not drawn),
  `05-developer-notes.md` offline notes (one transfer at a time, yield only on start/rebuffer, HTTP status, restart from zero),
  component READMEs DownloadRow (`cancelled`, `hls`, percent), OfflineAssetRow (`hls`, size only when known), ConfirmDeletion (job/video/library).
- tvOS offline media lives under Documents, which tvOS may not keep; the TV offline path has been built but never run.
- `docs/design/claude-design/HANDOFF.ru.md` still says "Mac Catalyst"; the target is native macOS.

## OQ-0020 — HIG review findings left open

- Status: open; owner: UI maintainer; basis: [PLAN-0039](exec-plans/completed/hig-review-fixes.md).
- Not taken in PLAN-0039 by the user's decision (2026-10-21): the iOS player hides its controls under VoiceOver with
  no way back; tvOS overlay controls (`tvOverlayControl`) have no accessibility labels; Channel Shorts and compact
  cards do not open on tvOS (no `onSelect`); tvOS sign-in text and activation code are unreadable in Light theme;
  load failures in comments, Home recommendations, Library feeds and RSS are shown as empty states.
- Larger platform work, not started: the system player (`AVPlayerViewController`) and system search page on tvOS.
- Known placement limits of the app-level toast: it can briefly cover the iPhone tab bar, and a toast from a card
  action appears beneath the full-screen iOS player.
- [PLAN-0040](exec-plans/completed/card-channel-subscription.md): check the card-menu ControlGroup on iOS and macOS and the
  tvOS Play/Pause → Unsubscribe chained dialog on screen; a failed subscription lookup only hides the control.
- [PLAN-0041](exec-plans/completed/unified-card-menu.md): on macOS the hover-only More button is hidden with opacity and may
  still take Full Keyboard Access focus; the tvOS Play/Pause dialog lists every command flat. `HomeShortsCountUITests`
  (live feed, stale `home.shortsRow` lookup) and the `MixedFeedLayoutUITests` history fixture test fail on master.
- Evidence gaps: every HIG finding and fix was judged from source; nothing was rendered for contrast, Dynamic Type
  at accessibility sizes, tvOS focus or the macOS menu bar. The macOS app target is not built by the scripts.
