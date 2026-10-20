# Changelog

All notable changes to VoxaFrame and its SmartTube predecessor are documented here.

---

## [Unreleased]

### Changed

- **Offline downloads:** audio and Yandex translation default to Default Audio Language from Settings. Matching audio prefers the lowest known bitrate; original audio is the fallback. Yandex is enabled even when a matching audio track exists, for supported target languages. Later manual choices remain unchanged.

### Fixed

- Offline audio choices without language metadata show their codec and bitrate instead of an "Unknown language" prefix, including the library's additional-download list and saved-audio picker.
- Offline original-audio choices also use YouTube's auto-generated caption language when stream metadata omits it, including Vert Dider uploads. Explicit dubbed languages and HLS selection identities are preserved; repeated normal/DRC encodings no longer create duplicate audio choices.
- The player's audio picker and quick-access button also resolve an unlabelled original track from source-language metadata. If no language is available, they show Audio instead of a raw `unknown` value; rendition identities and explicit dubbed languages are preserved.
- Offline Yandex translation uses the original audio or auto-generated caption language instead of relying on failed language detection. Live translation of a saved video uses its stored original-audio language before the first request; if that metadata is missing, an automatic-language refusal retries once with fresh original-language metadata. Download errors preserve Yandex's explanation.
- **iPad:** open the landscape sidebar after SwiftUI finishes updating, preserving the user's later choice. Keep the Queue tab's identity stable when hiding it so resizing preserves navigation state and avoids a UIKit tab-rebuilding crash.

## [5.18] – 2026-10-20

VoxaFrame 5.18 (40). Source release; no signed binaries are attached.

### Added
- **Offline SponsorBlock:** segments are saved with downloaded videos, used during offline playback and refreshed from a saved video's page or across the library. Automatic refresh on app activation runs at most once a day after a successful update and has its own setting.
- **Offline sizes:** saved video, audio and voice-over sizes, transfer byte progress and the total storage used appear in Offline videos. Estimates are marked; unknown sizes are not presented as measured values.
- **Player:** saved-offline badges, an Offline quick action and a channel link in More.

### Changed
- **Home:** shows only YouTube's recommendations; subscription videos are no longer mixed in. The separate Recommended chip is removed (saved section lists drop it; Subscriptions keeps its chip).
- **Home:** an empty account feed stays empty instead of showing a popular-search substitute; pages that add no new videos continue to the next page by themselves (bounded), and More appears when nothing is left to scroll.
- **Defaults:** Shorts are hidden for new settings, while existing choices are preserved. Queue stays available in Library; its iPad/Mac sidebar shortcut is hidden by default and can be enabled in Appearance.
- **Player:** redesigned Description and Comments panels; the sleep timer moves to More.
- The privacy policy describes automatic and manual SponsorBlock requests for saved videos.

### Fixed
- Home feed blocks stay stable when more videos are appended.
- Video cards keep their accessibility identifier when a feed block holds a single card.
- Offline SponsorBlock lookups share pending work and cannot replace the current video's segments with a late result.

## [5.17] – 2026-10-19

VoxaFrame 5.17 (39). Source release; no signed binaries are attached.

### Added
- **Mac:** full-screen playback, window size limits and a search filters menu.
- **iPad:** sidebar in landscape, offline list and detail side by side, settings categories on wide layouts.
- **Grid columns:** up to 4 in iPad landscape and up to 5 on Mac.
- **Offline:** parallel downloads with a simultaneous-downloads setting; variants grouped by video, audio and voice-over; a clearer saved-video page; compact list rows.
- **Shorts:** controls hide after a few seconds and toggle with a tap, like the regular player.

### Changed
- Minimum OS raised to iOS/iPadOS 18, macOS 15 and tvOS 18.
- The app shows its name as VoxaFrame; the bundle ID is unchanged, so sign-in and saved data stay.
- Redesigned player More menu; option panels stay on screen on iPad.

### Fixed
- Offline HLS downloads from the Offline section: variants are matched by size, codec, frame rate and peak bit rate when YouTube renews their URLs; dubbed variants and a single unnamed audio track are accepted; every refusal is logged with its reason.
- Saved Yandex voice-over plays back in sync; Next keeps the current queue position after re-selection.


### Fixed — 2026-10-17

- **VoxaFrame 5.16 (37), background offline transfers (PLAN-0028):** on iOS, a direct download
  switches from small foreground ranges to one remaining range after leaving the app. This
  avoids repeated background scheduling delays between parts; byte validation and cancellation
  still apply. Foreground throughput measurements do not predict background transfer speed.

- **VoxaFrame 5.16 (36), physical iPad offline cleanup (PLAN-0028):** restored protected HLS
  paths keep the physical app-container location instead of a `/var` symlink. Previously saved
  downloads can be played and deleted after relaunch; a pending failed deletion resumes on update.
  Storage failures log error codes without signed URLs or credentials.
- **Bounded offline downloads (PLAN-0028):** direct streams use sequential 10 MiB HTTP ranges
  with exact range/length validation and partial-file cleanup. A physical iPad downloaded the
  selected 732 MB video in about 82 seconds; the previous whole response transferred only
  366 MB in about 21 minutes. Cancellation cannot start another range after removing a task.
  HTTP failures retain their status rather than appearing as corrupt-media errors.

### Added — 2026-10-17

- **Design reference consolidation (PLAN-0027, PLAN-0028):** retained the original redesign
  export, component previews, canvas boards and iPhone/iPad screenshots in Git; synchronized
  the string catalog with existing offline and playback controls. Redesign stage acceptance
  remains in PLAN-0027 and OQ-0019.

- **VoxaFrame 5.16 (35), delete all offline media (PLAN-0026):** Offline videos has a confirmed
  Delete all action on both tabs. It cancels all offline transfers and removes saved video, audio,
  translations, protected HLS packages and unfinished transfer cache. Cleanup survives relaunch
  and disk-write failures; unrelated app data stays intact.

- **Claude Design handoff (DESIGN-0001):** VoxaFrame design-system specification,
  light/dark tokens, 23 component contracts, iPhone/iPad/Mac Catalyst/Apple TV patterns,
  Figma reference catalog and visual guide. These are design proposals and import materials;
  app behavior and the source Figma file are unchanged.

- **VoxaFrame 5.16 (34), offline choices and cleanup (PLAN-0025):** Offline watch now
  asks for video resolution/codec, a compatible audio track, and optional Yandex translation
  language. HLS downloads bind one video variant and one audio selection; direct downloads
  queue only the chosen files. File-size estimates use known content length or average
  bandwidth, never HLS peak bandwidth. Downloads can delete a task and its files; Library
  can remove a video with all saved tracks and pending jobs. Interrupted cleanup resumes
  after relaunch, and late transfer callbacks cannot restore a deleted entry. Saved HLS audio
  stays selected during playback instead of reverting to an unsaved global language preference.

- **Full-screen level gestures (PLAN-0024):** slow vertical drags adjust screen
  brightness on the left and system volume on the right. Control hints mark both
  halves, and a brief indicator shows the level. Brightness returns to its previous
  value when leaving the player or backgrounding its window. Fast downward swipes
  still minimize; horizontal navigation, scrubbing, taps and hold-to-speed remain separate.

- **VoxaFrame 5.15 (33) (PLAN-0020–0023):** new app name and two-voices/Play icon,
  preserving the installed app identity, account storage and deep links. Offline watch adds
  a durable background download queue, progress page, completion notifications, saved video
  qualities and audio tracks, and Yandex translation that can be downloaded initially or later.
  Saved media can be played after relaunch without requesting its original media URL.
- **Playback priority (PLAN-0020):** speculative metadata, Shorts preparation and offline
  transfers yield while active playback starts or buffers. Explicit pause releases demand;
  resumed optional work is bounded, and shared requests retain their foreground consumers.
- **Initial stream source boundary (PLAN-0022):** metadata acquisition now has a small tested
  boundary while AVPlayer lifecycle and existing recovery order remain with the player.

- **Version 5.14 (32), independent Shorts speed (PLAN-0019):** Shorts has the same
  0.25–2× playback-speed picker as regular videos, with a separately saved choice.
  Upgrades copy the former shared speed once. Pause/resume, prepared next videos
  and relaunch retain the Shorts setting; Yandex voice-over follows the video's
  speed without restarting translation. Choosing a speed while paused keeps it paused.

### Fixed — 2026-10-17

- **Playback state after translation (PLAN-0019):** when AVPlayer resumes itself
  after an unexpected stall, playback controls now recognize the resumed video.
  Speed changes apply immediately; intentional pauses and translation holds stay paused.

- **Version 5.13 (31), watched-video settings (PLAN-0018):** Home and Shorts now
  apply Hide Watched Videos consistently with other feed sections. The threshold
  supports 5–100% in exact 5% steps, survives relaunch, and keeps History and unknown
  progress visible. Filtered pages retain a manual continuation. Settings' GitHub
  link and the tvOS QR code point to `cioxideru/SmartTubeIOS`.

- **Subscription management (PLAN-0017):** account channel pages can subscribe and
  unsubscribe through the current authenticated API. Channels offers an accessible
  removal button and swipe action with confirmation, refresh and visible failures.
  Membership comes from TV subscription navigation, including channels without
  recent uploads, with pagination and avatar URL normalization. Failed changes
  preserve the list; late refreshes cannot undo a successful change. Local following
  remains separate from the account.
- **iPad menu placement (PLAN-0016):** wide iPad layouts reserve the native top
  navigation region when returning to Home. iPadOS 26+ also reserves it in compact
  windows, where system window controls otherwise overlap the Home section button.
  Physical-iPad regression coverage checks floating-window resizing, three Split View
  sizes, full-screen restoration, channel/Settings round trips, tab changes and both
  orientations. The rare original wide-screen sequence remains unconfirmed.

- **Version 5.11 (29), account feed pagination (PLAN-0014):** Home, Recommended
  and subscription-backed Shorts keep the owning feed's continuation instead of
  following a nested shelf. Only the active navigation tab contributes videos;
  unrelated tabs no longer fill subsequent Shorts rows. An exhausted multi-shelf
  feed does not switch to a remaining shelf cursor.

### Changed — 2026-10-17

- **Channel controls (PLAN-0017):** removed the SponsorBlock exclusion toolbar icon
  that looked like a second subscription control, along with its obsolete Settings hint.
  The channel header retains Subscribe/Unsubscribe; saved SponsorBlock exclusions remain intact.

- **Version 5.12 (30), Shorts preloading (PLAN-0015):** prepare the next native video
  while the current Short plays, reuse its player and buffer on swipe, and release speculative
  work on background, memory pressure, expiry or dismissal. Retained feed/history/cursors stay
  bounded; speculative work does not translate, track viewing or write a media disk cache.
  The existing metadata cache now accounts for files from earlier sessions when enforcing its limit.
- **Version 5.10 (28) (PLAN-0013)** gives Shorts separate audio language,
  automatic Yandex translation, lively voices and original background audio settings.
  Existing translation choices are copied once on upgrade; later changes in either
  player stay independent. Shorts retains its choices across videos and relaunch,
  including Auto and disabled translation. Both players reuse the translation service
  and the device's Yandex Keychain token.

### Changed — 2026-10-16

- **Version 5.9 (27) (PLAN-0012)** adds the regular player's audio-track/Yandex
  controls and persisted Fit/Fill mode to Shorts. Mute also silences translated audio.
- **Account Shorts (PLAN-0012)** use Shorts from account recommendations and
  subscriptions when signed in. Home and Recommended reuse their loaded account
  shelves; anonymous `#shorts` search is reserved for signed-out discovery. Swiping
  follows continuation pages instead of repeatedly fetching the first batch. Sparse
  pages use bounded requests and retain a manual continuation; Home keeps Shorts
  even when their shelf appears after the initial regular-video limit.
- **Version 5.8 (26) (PLAN-0011)** identifies the resource and lifecycle fixes below.
  The iOS/Catalyst and tvOS apps and embedded extensions inherit the same project version.

### Fixed — 2026-10-16

- **Playback task ownership (PLAN-0011)** cancels background quality upgrades when
  stopping, pausing or replacing a video. Delayed results cannot restart playback
  or overwrite a newer session, including a restart of the same video.
- **BotGuard waiting (PLAN-0011)** lets a cancelled playback request stop waiting
  immediately while shared preparation continues for other callers. Timers and
  delayed WebView callbacks can only complete their original preparation attempt.
- **Local subscriptions (PLAN-0011)** load at most four channels concurrently.
  Cancellation stops queued work; failed RSS/fallback responses are not cached as
  empty channels. Valid empty feeds remain cacheable.
- **Voice-over audio upload (PLAN-0011)** downloads source audio to temporary files,
  assembles at most six HLS segments at a time and uploads one part at a time.
  It preserves byte order and short-tail handling, and removes temporary files
  after success, failure or cancellation.
- **WK-HLS cache (PLAN-0011)** shares the existing 30-video limit and removes URLs,
  tokens and extraction flags together on expiry or eviction. Token updates do not
  extend an old URL's lifetime; recently read entries retain priority.
- **Home history (PLAN-0011)** applies the saved History setting before loading the
  visible section. Disabling it clears that section, cancels pending requests and
  ignores late responses, including pagination.
- **Player metadata (PLAN-0011)** comes from the active playback model after Next,
  Previous and autoplay. Mini-player and fullscreen no longer retain a separate
  copy of the previous video; recovery can keep the ready item's metadata visible.
- **Home and widget ownership (PLAN-0011)** uses one Home model for the screen and
  widget snapshot. Startup waits for a usable token, foreground refresh does not
  duplicate authentication loading, and token rotation preserves the feed. Sign-out
  clears the snapshot; late feed or thumbnail results cannot restore the old account.
- **Core boundaries (PLAN-0011)** move the theme's SwiftUI mapping and SponsorBlock's
  native seek adapter into the UI/platform target. CI rejects new platform imports
  outside explicit legacy exceptions. Queue reordering preserves SwiftUI semantics
  without importing it into Core; stopped or replaced SponsorBlock seeks cannot
  update a newer playback session.
- **Idle resources (PLAN-0011)** release stopped player items and unused WebViews
  after a 60-second reuse window or a memory warning. Active playback and browser
  requests remain protected; expired resources are recreated on the next load.
  Stopping also cancels pending quality changes, and stale browser callbacks cannot
  complete work belonging to a new WebView.
- **Audio-session transitions (PLAN-0011)** run serially outside the UI actor and
  configure the system only when playback starts. Cancelled or superseded requests
  cannot resume a video or deactivate a newer session. Ready-state metadata remains
  available while activation is pending; native transition durations are logged.
  Delayed pause notifications cannot overwrite a newer resume, and lock-screen
  next/previous commands take their enabled state from the current queue on setup.
- **Feed loading (PLAN-0010)** no longer starts a hidden Home feed on sign-in or
  restarts a queued load when the app becomes active. Cancelled queued loads skip
  their requests. Token refresh keeps the current cards and pagination instead
  of clearing the section and fetching it again.
- **Shorts playback (PLAN-0009)** has persistent play/pause, mute, seeking and retry
  controls. Swipe navigation no longer intercepts the progress slider. New Shorts
  start at the beginning, and pending seeks/duration observations from an outgoing
  video cannot overwrite the new video's state. Initial and fallback streams that
  never become ready yield after 15 seconds; failed local/audio loads leave loading state.
- **Player presentation (PLAN-0009)** retains PiP ownership when fullscreen closes,
  reveals the previous app screen on PiP entry and waits for the restored interface
  before completing the return. Fullscreen and mini-player share one video layer;
  inactive containers cannot move it. Three physical iPad PiP/fullscreen cycles
  passed with preserved time and restored video; wider device coverage remains in OQ-0005.
- **Recommendations (PLAN-0009)** uses Home's mixed grid even when video groups
  arrive with horizontal shelf layout.

### Fixed — 2026-10-15

- **Same-video privacy changes (#94)** now reset tracking when reopening a playing,
  loading or parked item. Returning from incognito to normal playback records local
  history and resume position again; entering incognito disables recording for the new session.
- **Shorts dismissal and navigation** cancel pending transitions, ignore end-of-video
  handling during an existing transition, and release the end handler when stopping.
- Preserved [ADR-0010](docs/adr/0010-remove-iframe-player.md)'s accepted text and appended
  a dated amendment for the subsequent incognito fix and identified gesture losses.

### Removed — 2026-10-15

- **IFrame (TOS) player and Shorts embed player** ([ADR-0010](docs/adr/0010-remove-iframe-player.md),
  superseding ADR-0006/0007/0008). All playback on iOS, iPadOS and macOS now uses the native
  AVPlayer pipeline that tvOS already used; Shorts play in `ShortsPlayerView` over
  `PlaybackViewModel` on every platform. Removed the "IFrame Player" setting (iOS and macOS),
  `TOSPlayerStateStore` and the TOS mini player, the WKWebView embed views/scripts, the Shorts
  src-swap spike, the `--uitesting-*-tos-player-on-ios` launch arguments, and their unit/UI tests.
  The quality picker, captions, PiP and Yandex voice-over are always available again; iOS HLS
  pre-warming on card appearance is re-enabled. Lost on iOS with the embed player: the
  brightness/volume edge-swipe gestures and the chapters overlay (not ported; see open questions).
- **Play Incognito (#94) on the AVPlayer path**: `PlayerRouter` → `PlayerStateStore.play` →
  `PlaybackViewModel.load(video:incognito:)`; the video is not recorded to local history,
  watchtime or resume position. Autoplay after it records normally.
- **End of a Short** replays, advances to the next Short or freezes (`ShortsEndOfVideoDecision`,
  via `PlaybackViewModel.onPlaybackEnd`) instead of autoplaying an unrelated video in the Shorts player.

### Removed

- The Send Diagnostic Report button in Settings and the Report ID row in Stats for Nerds.
- Firebase (Crashlytics and Analytics): no crash reports, breadcrumbs, non-fatal events
  (slow load, playback stalls/errors, wrong video, Shorts embed failures) or analytics leave the
  device. Logging stays in `os.Logger`. The "Disable Analytics & Crash Reporting" setting and
  the "Wrong video loaded — report sent" toast are gone; saved settings with the old key still
  load. `PrivacyInfo.xcprivacy` no longer declares crash data. Xcode project cleanup and the
  App Store privacy answers are tracked in OQ-0014.

### Documentation

- Privacy policy rewritten to list the services the app contacts (YouTube/Google, SponsorBlock,
  Yandex voice-over, an optional user PO-token server, optional iCloud sync) and local/Keychain
  storage. Closed OQ-0004 (privacy statements vs. Crashlytics and data flows).

### Documentation — 2026-10-15

- Added the [execution-plan lifecycle](docs/exec-plans/README.md) and [open-question register](docs/OPEN_QUESTIONS.md);
  normalized ADR metadata without changing decision meaning or numbers. Recorded implementation
  drift separately, including ADR-0006's exclusive-player wording versus the current engine setting.
- Classified the TOS iOS port and #89 as completed from release/source evidence; #89 already has
  the duration guard, long-video/180-second tests and duration logging. Removed its obsolete open-bug
  status; this is recognition of existing code, not a new fix or fresh test pass.
- Retained the Shorts document as design, with a current implementation note. Its src-swap spike
  and URL/end-decision helpers exist; removed their pending-implementation status. Device evidence
  remains separate. BotGuard's implemented pieces and remaining verification now have one active plan.
- Archived stale home-feed, playback-method, DASH-test, no-BotGuard, reviewer and TOS-worklog notes.
  Retired the no-BotGuard prohibition: adoption was already recorded in 4.1 and is wired in source.
  Historic playback pass counts are not current acceptance. Reviewer claims require reconciliation
  with actual data flows before reuse.
- Removed `docs/explanation/changelog-unreleased.md`: every entry already exists in release 2.6.
  Removed identical repeated 2.6 bullets without dropping unique release history.
- Removed the stale "AGENTS not yet created" task from current work tracking (the original ADR
  baseline remains historical), retired the package README's obsolete UserDefaults-token warning
  (TokenManager owns Keychain storage), and consolidated the index's missing/deferred-document
  lists into open questions. The private migration itself is not claimed complete.
- Corrected localization paths, catalog counts and the Xcode-only project-editing procedure;
  removed the unsupported claim that `extractionState: manual` protects forced retranslation.
  Corrected the device-log command continuation. Translation quality and device runs were not checked.

---

## [4.5] – 2026-06-11

### Added
- **TOS-compliant player is now the default on iOS** — playback uses an embedded YouTube IFrame player (WKWebView) with native SwiftUI controls, replacing the AVPlayer-based stream-extraction pipeline on iOS. Removes the entire class of playback failures caused by CDN/geo blocks, BotGuard/PO-token issues, and HLS/DASH manifest-parsing errors
- **Comments** added to the player's "..." overflow menu on iOS

### Changed
- Existing iOS installs are migrated automatically to the new default player; the experimental `useTOSPlayerOnIOS` toggle has been removed
- Video quality/ABR on iOS is now controlled entirely by YouTube's own player — manual quality and "max resolution" selection no longer apply on iOS
- Speed and "..." menu controls repositioned next to the back button on iOS

### Fixed
- **Mini-player** — video now keeps playing when minimized instead of stopping
- Playback speed pill stuck showing "Normal (1x)" after a speed change
- Audio occasionally cutting to silent shortly after auto-unmute
- Full-screen player no longer lingers after minimize/stop
- Safe-area inset double-counted on the back button

---

## [4.1] – 2026-05-27

### Added
- **BotGuard PO token pipeline** — complete WKWebView-based `pot=` token extraction with websafe base64 fallback; token injected into adaptive streaming requests to satisfy YouTube's enhanced bot-detection
- **AVC-only codec pinning** — "Prefer H.264" toggle in player settings pins DASH and HLS streams to AVC variants for maximum compatibility (#206)
- **Serbian & Croatian localizations** — two new languages added; 19 missing translation keys filled across all existing languages
- **HLS audio rendition proxying** — `#EXT-X-MEDIA` audio playlist URLs rewritten to `ytwebhls://` so the local proxy correctly forwards cookies to rendition segments

### Fixed
- **60 s `loadTracks` stall on SABR streams** — SABR stream detection added; `c=TVHTML5` URLs bypass the stall-prone audio-track load path (#204)
- **Dubbed audio broken via WKWebView** — HLS proxy now fetches the per-quality master URL rather than the generic master, restoring dubbed tracks (#205, #205b)
- **WKWebView cookies not forwarded to HLS proxy** — all `WKWebView` cookies, including the `googlevideo.com` domain, are now included in local proxy requests (#207)
- **8 s `loadTracks` stall** — `rqh=1` adaptive composition skipped when no `googlevideo.com` cookies are present, eliminating the hang (#208)
- **WKWebView HLS proxy silently skipped** — early `rqh=1` guard removed; proxy is now attempted regardless of cookie state at startup (#209)
- **Quality switch failed after muxed fallback** — fresh WKWebView extraction is now triggered whenever a quality change follows a muxed-only fallback (#210)
- **Stale WKWebView HLS URL used** — cached URL validity probed before constructing `AVPlayerItem`; expired URLs trigger immediate re-extraction (#211)
- **Quality button always visible** — changed from hidden-when-empty to disabled-when-empty; button remains visible but non-interactive when no quality options are available (#186)
- **Audio tracks not loaded after WKWebView HLS** — `loadAudioTracks(from:)` now called inside the `tryWebViewHLS` `readyToPlay` handler

---

## [3.0] – 2026-05-22

### Added
- **DASH adaptive quality switching** — selecting a quality tier for DASH streams rebuilds `AVMutableComposition` with the matching video track; a pending quality label is shown during the switch; the initial load is capped to the display's native resolution; VP9 variants excluded for device compatibility
- **macOS (Mac Catalyst) support** — `NSViewRepresentable` AVPlayerLayer renders in the macOS window; App Sandbox, Hardened Runtime, and `PrivacyInfo.xcprivacy` (network/API usage declarations) added; `SUPPORTED_PLATFORMS` updated; macOS build succeeds
- **TV client attestation token** — `fetchAttestationToken` injected into the TVHTML5 client authentication payload to satisfy YouTube's enhanced bot-detection for signed-in sessions
- **"Remove from Watch Later" action** — video cards inside the Watch Later playlist show a destructive remove option in the context menu; cards outside the playlist continue to show "Save to Watch Later"
- **Stats for Nerds** added to the player overflow menu on all platforms

### Fixed
- **tvOS settings tab required double-click to open** — `MainTVTabView` `TabView` now uses a selection binding; a single remote press selects the tab
- **tvOS video description and comments panels could not be closed** — `isAnyOverlayVisible` now includes both panel states so the player no longer intercepts the Menu button; each panel has its own `.focusScope` + `.onExitCommand`
- **tvOS quality preference reset to Auto on every launch** — `SettingsStore.init()` was unconditionally overwriting `preferredQuality` at startup
- **tvOS overflow menu text low contrast** — focused row highlight changed from `white.opacity(0.15)` to `gray.opacity(0.35)`
- **Playlist auto-advance not working from Search results** — `SearchView` now populates `CurrentQueueStore` before starting playback; macOS compact-grid path also fixed
- **HLS manifest cache** TTL raised from 5 min to 30 min; cache entry correctly invalidated on a 403 recovery path to prevent stale variant URLs

---

## [2.8] – 2026-05-19

### Added
- **Audio language selector in iOS fullscreen player** — speed, quality, and audio-track pill buttons in the quick-access row below the scrub bar for one-tap access without opening the overflow menu
- **tvOS player overflow menu expanded** — Captions and Audio Track rows added; Audio Only toggle available on tvOS; picker overlays no longer restricted to iOS
- **tvOS UI test coverage** — six new test suites: Settings (7 tests), Home Feed (5 tests), Library Navigation (8 tests), Player Controls (9 tests), Playback Regression (5 tests), Audio & Caption Pickers (6 tests)
- Library Subscriptions chip shortened to **"Subs"**

### Fixed
- **No audio after quality change in fullscreen** — quality-reload paths now call `loadAudioTracks(from:)` on every new `AVPlayerItem`
- **No audio when quality is not set to Auto** — audio track configuration was bypassed in manual quality selection paths
- **All audio tracks showing as "Original"** — `isOriginal` detection uses `hasMediaCharacteristic(.isMainProgramContent)` with `DEFAULT=YES` as fallback; per-track logging added
- **Caption track not remembered between videos** — last selected caption language persisted in `AppSettings` and re-applied on load
- **Captions obscuring the scrub bar** — caption overlay repositioned above the progress bar
- **Player controls hiding too quickly in fullscreen** — auto-hide timeout increased by 50%
- **Play/pause and navigation button tap targets too small** — enlarged from 44 pt to 68 pt
- **1440p quality not applied on initial load** — HLS variant fetch and `applyQualityPreference` added to all fallback entry points
- **tvOS settings missing seek-interval picker and preferred audio language selector** — `#if !os(tvOS)` guard removed from both pickers
- **tvOS long-press triggering both context menu and playback** — `onSelect` closure added to `VideoCardView`; `.onTapGesture` co-located with `.contextMenu` so the gesture arbiter suppresses playback on long-press
- **tvOS settings navigation bar hidden after scroll-down-then-up** — `.toolbar(.hidden)` guard changed from `#if os(iOS)` to `#if !os(macOS)`
- **tvOS SponsorBlock skip button not focusable** — `isSkipToastActive` gate routes focus to the skip button when a segment is detected and restores player focus on dismiss
- **Audio track selector missing from iOS overflow menu** — `moreMenuAudioTrackRow` restored (accidentally removed in a prior refactor)
- **Watch Later playlist playing videos in wrong order** — `CurrentQueueStore.replaceAll(with:)` now called before starting playback in all playlist entry points
- **Hide Shorts not filtering Subscriptions feed** — three detection gaps fixed: `parseVideoRenderer` Shorts signals, RSS feed detection via playlist enrichment, History view was incorrectly filtering non-Shorts
- **Intermittent "first video cannot be played" on launch** — stale iOS-client preload cache now invalidated before a fresh client fetch in the muxed-only fallback path
- **"Original Track" missing from tvOS preferred audio language picker**
- **Firebase network hardening**: VPN/IP-block banner suppresses "Try Again" button; Android muxed-only fallthrough no longer records a non-fatal; `NSURLError -999` (cancelled) added to transient-suppression list; request timeout raised from 20 s to 30 s

---

## [2.7] – 2026-05-16

### Added
- **Quick-access player controls** (iOS) — speed, quality, audio-track, and sleep-timer pill buttons below the scrub bar for one-tap access without opening the overflow menu
- **iCloud sync for local data** — subscriptions, watch state, current queue, and RSS feeds sync via `NSUbiquitousKeyValueStore`; opt-in toggle in Settings → General
- **Video publish date in search results** — upload age label shown in grid and compact card layouts for search results and playlist views
- **Shorts auto-pagination** — the home feed Shorts section automatically loads a second page when the initial batch is below 6 (iPhone) or 8 (tvOS)
- **Downloads screen** — Library → Downloads lists locally downloaded videos; tap to play offline, swipe to delete

### Fixed
- **OrientationManager crash on iOS 26** (EXC_BREAKPOINT, Crashlytics 1bce7ef1) — `requestGeometryUpdate` error handler was inheriting `@MainActor` isolation and invoked on a background GCD queue on iOS 26+; extracted as an explicit `nonisolated` file-scope function
- **Watch history not updating for signed-in users** — `PlaybackViewModel`'s own `InnerTubeAPI` instance was not receiving token refreshes; `WatchtimeTracker` was sending anonymous pings
- **Streaming spinner not dismissing after video loads** — `isLoading = false` moved into the `.readyToPlay` observer; audio-only path also fixed
- **App launch interrupting background audio** — premature `AVAudioSession.setActive(true)` removed from `PlaybackViewModel.init()`
- **Shorts not loading on cold launch** — `fetchShorts` and `fetchShortsMore` now use `postTV()` (TVHTML5 client) to match the TV OAuth token scope; WEB client was returning HTTP 400
- **Mini-player overlapping bottom tab bar** (iPhone portrait) — mini-player now rendered as `overlay(alignment: .bottom)` above the `TabView` safe area; `TabBarBottomInsetKey` preference captures the actual tab bar height
- **16 QPB-identified bugs**: `extractNumber` undercounting K/M/B view-count suffixes; `viewCount` always `nil` in all renderers; fallback paths (`retryWithFallbackPlayer`, `retryWith403Recovery`, `retryWithAdaptiveComposition`) dropping `playerInfo` / `availableFormats` / `availableCaptions`; `loadAsync` race on superseded tasks; `pingTrackingURL` silently discarding errors; `evictAuthSensitiveData` skipping `VideoDiskCache`; auth token captured at prefetch-task creation time (stale after refresh); `WatchtimeTracker` using stale URLs post-eviction; `phase2Task` skipped in all fallback paths; `tryLoadAudioURL` unconditionally resetting audio-only mode on any error; `itemObserverTask` race on item replacement; `endObserverTask` not restarted in audio-only mode; `parsePlaylistVideoRenderer` not implemented

---

## [2.6] – 2026-05-14

### Added
- **Safari Web Extension** — new `SafariExtension` target (`manifest.json` + `content.js`) intercepts YouTube watch, Shorts, youtu.be, and Music URLs in Safari and redirects them to `smarttube://video/<id>` without any user tap; `YouTubeLinkHandler` extended to recognise `music.youtube.com/watch?v=` URLs so the extension and the app URL handler stay in sync; `SafariExtensionURLCoverageTests` (7 tests) verify every manifest match pattern
- **Auto quality caps at display native resolution** — when `preferredQuality == .auto`, `PlaybackViewModel+Fallback.qualityCapVideoURL` now calls `displayMaxVideoHeight()` (returns `min(nativeBounds.width, nativeBounds.height)` on UIKit, 1080 on tvOS) and passes the result as `preferredMaxHeight` to `selectBestVideoFormat`; initial DASH composition and HLS `preferredMaximumResolution` hints use the same value; previously Auto unconditionally picked the highest available format regardless of screen pixel density

### Fixed
- **DASH manual quality switching broken for many videos** — `PlaybackQualityManager.reloadDASHItem` was resolving the video URL from `availableFormats` (populated by the TV auth / TVHTML5 client), whose adaptive entries use SABR-protocol URLs that `AVURLAsset.loadTracks` cannot open (AVFoundation error −11828); quality switches now resolve the video URL from `playerInfo.formats` (populated by the AndroidVR client, which returns standard CDN MPEG-4 URLs); a `selectBestVideoFormat(from:preferredMaxHeight:)` helper matches the requested quality tier to the closest available itag; the TVAuth `availableFormats` set is retained for the picker display only
- **DASH quality switch silently rebuilding at wrong resolution** — `reloadDASHItem` used `selectBestVideoFormat` without verifying the resolved height satisfied the request; when the requested tier (e.g. 480p) was absent from `playerInfo.formats`, `selectBestVideoFormat` fell back to the highest available format (e.g. 720p) and `AVMutableComposition` succeeded at that height while `selectedFormat` still reflected 480p; a `matchedFmt.height <= fmt.height` guard now rejects the fallback result and falls through to the `availableFormats` URL for proper error-recovery when the tier is absent from `playerInfo.formats`
- **Quality picker showing 144p/240p only for DASH videos** — TVAuth adaptive format entries had `height = 0` because TVHTML5 SABR responses omit the `height` field; `parseFormats` now extracts the height from the `qualityLabel` string (e.g. `"720p"` → 720) when `height == 0`, so all adaptive tiers appear correctly in the picker
- **AndroidVR client returning `LOGIN_REQUIRED` bot-detection error** — `postAndroidVR` now includes the `X-Goog-Visitor-Id` header populated from the `visitorData` field of the preceding TVAuth `/player` response; the shared `URLSession` (carrying YouTube authentication cookies from TV sign-in) is used instead of an ephemeral session; together these signals satisfy YouTube's bot-detection check for the AndroidVR client
- **Crash on age-restricted / region-locked videos** (1,048 iOS + 130 tvOS events, issue NW-3) — TV authenticated client sometimes returns a `PlayerInfo` with `hlsURL = nil` and no usable adaptive streams (muxed-only TVHTML5 URL); `PlaybackViewModel+Loading` now checks `tvInfo.hlsURL == nil && bestAdaptiveVideoURL == nil` immediately after the TV fetch and falls straight to `fetchPlayerInfoAndroid` before creating an `AVPlayerItem`, eliminating the `AVFoundationErrorDomain -11828` crash; `TVClientHLSNilFallbackTests` (8 tests) added
- **Audio-only mode silently stalling on playback start** — `tryLoadAudioURL(_:userAgent:)` now calls `setupAudioItemObserver(_:)` before `player.replaceCurrentItem(with:)`, wiring up `itemObserverTask` to catch `.failed` status (resets `isAudioOnlyMode = false` and propagates the error) and `.readyToPlay` (calls `loadAudioTracks(from:)`); previously a failed audio item had no observer and the player hung silently; `AudioOnlyModeUITests` (`testAudioOnlyModeOpensVideoWithoutError`) added
- **Mini player X button sometimes restoring fullscreen** — `fullScreenBinding` setter in `RootView` was calling `playerState.minimize()` whenever `currentVideo` cleared to `nil`; because `stop()` sets `presentation = .hidden` asynchronously, the setter raced and re-promoted state to `.miniPlayer`; setter is now a no-op (the `LandscapeFullScreenCover` UIKit coordinator already manages dismissal)
- **Audio track selection not working after fallback recovery** — `audioSelectionGroup` and `audioOptionsByID` were never refreshed when the Android fallback player, adaptive composition fallback, or 403-recovery path created a new `AVPlayerItem`; `retryWithFallbackPlayer`, `retryWithAdaptiveComposition`, and `retryWith403Recovery` in `PlaybackViewModel+Fallback` now call `loadAudioTracks(from:)` in their `.readyToPlay` observers, matching the existing pattern in the normal load and quality-change paths
- **More menu overflowing and unusable in landscape mode** (GitHub issue #45, contributor say4n) — `.frame(maxHeight: 520)` was too tall for compact vertical size class; `moreMenuOverlay` now uses 320 pt max-height in `verticalSizeClass == .compact`, adds `.safeAreaPadding(.horizontal)` plus 36 pt extra horizontal padding when landscape, keeping the menu within the live area and scrollable to the Cancel row; `player.moreMenu.scrollView` accessibility identifier added
- **"Hide Shorts" setting not filtering Shorts in Search, Library, and Channel views** (GitHub issue #41) — `AppSettings.hideShorts` was applied only in `HomeView` and `BrowseView`; `SearchView` and `LibraryView` now inject `SettingsStore` via `@Environment` and filter results before passing to `VideoGridSection`; `ChannelView.filteredVideos` extended to apply the same predicate; `RSSFeedsView.videoList` also updated for consistency; `HideShortsFilterTests` (6 tests) added

---

## [2.5] – 2026-05-12

### Added
- **Landscape lock button** (iOS) — rotation icon in the player top bar locks orientation in landscape; the "Landscape Always Play" toggle was removed from Settings
- **Audio-only button in player controls** (iOS) — waveform icon in the bottom player bar toggles audio-only mode; the Settings toggle was removed; tvOS retains the overflow menu row
- **Toast on mode switches** — "Audio-Only Mode" / "Video Mode" notification shown when toggling playback mode
- **DeArrow titles and thumbnails** — cached branding applied in `VideoCardView` grid and compact layouts and to `currentVideo` on load; respects the `deArrowEnabled` setting

### Fixed
- **Mini player "X" button not stopping audio** — `AVAudioSession.setActive(false)` called in `PlaybackViewModel.stop()` on dismiss
- **Overflow menu too wide and large in portrait** — `.font(.subheadline)` applied to all rows; max width constrained to 80% of screen width
- **Portrait player next/back buttons had small tap targets** — enlarged to 68 pt with circular background matching other control buttons
- **Shorts incorrectly included in playlists** — `displayVideos` filter added to `PlaylistView`
- **Video not reloading after stop and replay** — `itemObserverTask` and `endObserverTask` now cancelled in `stop()`
- **Preferred audio language ignored on AI-dubbed videos** — `DEFAULT=YES` HLS track priority corrected; device language preference evaluated before YouTube's marked default
- **Shorts visible despite "Hide Shorts" being enabled** — `parseLockupViewModel` guard relaxed to correctly detect `reelWatchEndpoint` as `isShort = true`
- **Pagination failing on transient network errors** — all 5 pagination entry points wrapped with `retryWithBackoff` (up to 3 attempts, 1–2 s exponential delay)

---

## [2.4] – 2026-05-10

### Fixed
- **Audio cutting out when manually changing video resolution** — `reloadHLSItem` and `reloadHLSItemH264Capped` in `PlaybackViewModel+Quality` created a new `AVPlayerItem` on quality switch but never called `loadAudioTracks(from:)`; `audioSelectionGroup` and `audioOptionsByID` stayed stale from the old item so `selectAudioTrack()` silently no-opped and AVPlayer fell back to muted defaults; one-line fix adds `loadAudioTracks(from: item)` in both `.readyToPlay` handlers
- **Audio quality improved to match official YouTube app** — `AVPlayerItem.audioTimePitchAlgorithm` defaulted to `.timeDomain` which introduces subtle artefacts at normal playback speeds; changed to `.spectral` in `PlaybackViewModel+Loading` when the `AVPlayerItem` is created (both HLS and adaptive paths)
- **tvOS video quality stuck at perceived ~420p despite 2160p setting** — `fetchHLSVariantURLs()` unconditionally replaced HEVC variants with H.264 for all platforms (added originally for Simulator compatibility); on tvOS HEVC is fully supported and YouTube lists it first in the manifest, so H.264 selection forced lower perceived quality; codec preference is now guarded `#if !os(tvOS)` so tvOS keeps the first (HEVC) variant while iOS/macOS still prefer H.264; `preferredPeakBitRate` hints added alongside `preferredMaximumResolution` in `reloadHLSItem` and initial load; `PlaybackQualityTests` (10 tests) added
- **Duplicate video cards causing blank cells in Home and Subscriptions feeds** — four separate deduplication gaps allowed duplicate `Video.id` values into `ForEach` arrays: (1) `fetchMoreVideos(.home)` returned `flatMap(\.videos)` with no dedup; (2) `HomeViewModel.loadMore` captured `existingIds` once before the append loop so intra-`newVideos` duplicates slipped through; (3) `BrowseViewModel.mergeIntoFirstGroup` had the same static-set gap; (4) `fetchNextPage(.home)` appended new groups without cross-group ID filtering; all four fixed with a growing-set pattern (`var seen = Set<String>(); filter { seen.insert($0.id).inserted }`); `mergedVideos` computed property gains a safety-net pass; `HomeFeedNoDuplicatesUITests` (3 tests) added
- **tvOS centre-zone double-tap and d-pad focus failures in player UI tests** — five UI tests were failing: `ToastModifier` had no accessibility identifier so toast queries raced against 2 s expiry; `ProgressView` spinner absorbed tap gestures; `SettingsStore` leaked persisted UserDefaults state between tests; SponsorBlock auto-seek disrupted player gesture tests; `testLandscapeAlwaysPlayBackButtonReturnsHome` used `guard` inside `defer` (compile-valid but never ran on error path); fixes: `.accessibilityIdentifier("player.toast")` on toast text; `.allowsHitTesting(false)` on spinner overlay; `--uitesting-reset-settings` launch-arg handler in `SettingsStore.init`; accessibility identifiers on SponsorBlock picker/NavigationLink; `testDoubleTapCentreZoneTogglesFitFill` converted from live Home feed to `--uitesting-deeplink-video=` fixed video ID to eliminate feed-timing flakiness; `guard`→`if` in defer block

---

## [2.3] – 2026-05-10

### Added
- **Shorts section on home screen** — `ShortsCardView` (portrait 9:16 thumbnail with dark gradient title overlay and duration badge) and `ShortsRowView` (horizontal `LazyHStack`, ~120 pt wide on iPhone) render above the main grid; `HomeViewModel` partitions `mergedVideos` into `homeVideos` (non-Shorts) and `homeShortsVideos` at the computed-property level with no extra network call; Shorts are identified by `Video.isShort` set at parse time from `reelWatchEndpoint`, `TILE_STYLE_YTLR_SHORTS`, or `parseReelItemRenderer`
- **Per-device YouTube recommendations setting** — `InnerTubeAPI.visitorData` (previously declared but never populated) is now extracted from `responseContext` on each browse/search response and injected into subsequent requests via `makeBody(includeVisitorData: true)`; different `visitorData` per device produces different recommendation graphs per device; toggle in Settings → Interface; disabled resets `visitorData = nil` on the next browse call

---

## [2.2] – 2026-05-06/07

### Added
- **Local Subscription Management** — follow/unfollow channels without a Google account; feeds backed by `LocalSubscriptionStore` (actor, UserDefaults persistence) and `LocalSubscriptionFeedService` (RSS fetch with InnerTube fallback); channels sorted alphabetically, feed videos sorted newest-first
- `YouTubeRSSParser` — XML-based RSS parser for YouTube channel feeds (`https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID`) using Foundation `XMLParser`; background refresh via `LocalSubscriptionFeedCache`
- **RSS Feeds feature** — users can add arbitrary YouTube channel RSS feed URLs; `RSSFeedInfo` model + `RSSFeedStore` actor (JSON in UserDefaults); `RSSFeedsViewModel` fetches all active feeds concurrently with `withTaskGroup`, deduplicates by video ID, sorts newest-first; `RSSFeedsView` (list with toolbar add button), `AddRSSFeedView` (sheet), `ManageRSSFeedsView` (delete/toggle); Share Extension detects RSS URLs and writes `pendingRSSFeedURLs` to shared UserDefaults app group for `AppEntry` to drain on launch; `RSSFeedStoreTests` unit tests
- **Audio-only playback mode** — `PlaybackViewModel+AudioOnly` provides `loadAudioOnlyItemIfEnabled()` with a three-step chain: (1) iOS-client `bestAdaptiveAudioURL` (zero extra network cost), (2) `fetchPlayerInfoAndroidVR()` using `ANDROID_VR` client (nameID 28, version 1.65.10, Oculus UA, no PO Token required), (3) silent HLS fallback with `isAudioOnlyMode = false` reset; live streams excluded; thumbnail overlay shown via `audioOnlyThumbnailOverlay` in `PlayerView+Lifecycle`; quality picker hidden in audio-only mode; "Audio Only" toggle in Settings (iOS)
- **Preferred Audio Language setting** — `Picker` in Settings → Player (iOS only) with options: System Default, English, Spanish, French, German, Japanese, Korean, Portuguese, Chinese (Simplified), Original Track; `autoSelectAudioTrack()` priority updated: saved explicit language → `"original"` sentinel selects HLS `DEFAULT=YES` track → exact language code match → prefix match (e.g. `"en"` matches `"en-US"`) → English fallback → tracks.first; `AudioTrackSelectionTests` extended (6 new tests)
- **Picture-in-Picture** (iOS) — PiP session management in `PlaybackViewModel`; toggle in Settings
- "Landscape Always Play" setting — auto-rotate to landscape when a video starts on iPhone
- **poToken groundwork** — `PoTokenProvider` protocol; `PlayerInfo.applyingPoToken(_:)` appends `&pot=<token>` to all format/HLS/DASH URLs; `InnerTubeAPI` stores `poToken`/`poTokenVideoId`/`poTokenExpiry`; `makeBody(includePoToken:)` injects `serviceIntegrityDimensions.poToken`; `ServerPoTokenProvider` (developer tool, hidden behind `poTokenServiceURL` setting) POSTs `{"videoId":"..."}` and expects `{"token":"..."}`; `PoTokenInjectionTests` (6 tests)
- **VPN "cannot play video" hardening** — `APIError.ipBlocked(String)` added; `InnerTubeAPI+Player.parsePlayerInfo` detects VPN/proxy/bot keywords in `playabilityStatus.reason` and throws `.ipBlocked` instead of `.unavailable`; `PlaybackViewModel+Loading` short-circuits the retry storm on `.ipBlocked` (one TV-auth attempt for signed-in users; Android fallback skipped); `NWPathMonitor` in `InnerTubeAPI` resets `visitorData = nil` on VPN connect/disconnect; inert "Force IPv4 (VPN users)" toggle in Settings; `CrashlyticsLogger` records `vpn_ip_block = true` non-fatal; `IPBlockDetectionTests` (12 tests)
- **VideoPreloadCache — advanced caching (Phases E–K)**:
  - *Phase E — Progressive `loadAsync`*: `loadAsync` split into Phase 1 (critical path: cache consume → `fetchPlayerInfo` retry chain → AVPlayer setup → `isLoading = false`) and Phase 2 (`.utility` Task running concurrently: SponsorBlock cache-miss fetch, `nextInfo`, `endCards`, `trackingURLs`, neighbour prefetch); `phase2Task` cancelled in `load()` and `stop()`; `ProgressiveLoadPhase2Tests` (7 tests)
  - *Phase F — Stale-while-revalidate (SWR)*: `CachedVideoData.DataType` enum (`.nextInfo`, `.endCards`, `.sponsorSegments`, `.deArrowBranding`); `staleFields: Set<DataType>` returned by `consume()`; stale values returned immediately (non-nil) while Phase 2 revalidates in background; `VideoPreloadCacheTTLTests` (16 tests)
  - *Phase G — Priority prefetch queue*: `PrefetchPriority` enum (`.speculative`, `.visible`, `.immediate`, `.userFocused`); `[PrefetchRequest]` queue bounded at 20 items; overflow evicts lowest-priority item; worker pool of 5 slots (WiFi) / 2 (cellular); `VideoCardView` passes `.visible`; neighbour prefetch passes `.speculative`; `PrefetchQueueTests` (5 tests)
  - *Phase H — In-flight coalescing*: `inFlightPlayerFetches: [String: Task<PlayerInfo?, Never>]` on `VideoPreloadCache`; `getOrFetchPlayerInfo(videoId:)` returns existing in-flight task or creates a new one; `loadAsync` coalesces against in-flight prefetch before falling to its own fetch; `InFlightCoalescingTests` (4 tests)
  - *Phase I — TTL tuning*: `nextInfoTTL` 5 min → 20 min; `sponsorTTL` 1 h → 2 h; `deArrowTTL` 1 h → 4 h; `endCardsTTL` 1 h → 4 h
  - *Phase J — Disk persistence*: `VideoDiskCache` writes `nextInfo`, `endCards`, `sponsorSegments`, `deArrowBranding` as JSON under `Caches/st-video-cache/<videoId>-<dataType>.json`; LRU eviction at 20 MB; `playerInfo` and `trackingURLs` never written (CDN/auth-sensitive); `Codable` added to `NextInfo`, `EndCard`, `EndCard.Style`, `Chapter`, `DeArrowService.BrandingInfo`; `VideoDiskCacheTests` (7 tests)
  - *Phase K — Network-aware throttling*: `NWPathMonitor` in `VideoPreloadCache`; offline → 0 workers (pauses all prefetches); cellular/constrained → 2 workers, `playerInfo`+`nextInfo`+`sponsorSegments` only; WiFi → 5 workers, all data types; `networkCap` and `allowedPrefetchDataTypes` computed properties
- `YouTubeRSSParserTests`, `LocalSubscriptionStoreTests`, `LocalSubscriptionFeedServiceTests` unit tests

### Fixed
- Shorts player section feed sometimes not visible when test starts — added explicit wait for section feed before asserting

---

## [2.1] – 2026-05-04/05

### Added
- **Landscape playback for iOS** — `OrientationManager` + `LandscapeAwareHostingController` replace SwiftUI's portrait-locked hosting controller so UIKit accepts `requestGeometryUpdate(.landscape)` while the player is on screen
- **tvOS PlayerView** (`PlayerView+tvOS`) — full d-pad navigation with `TVPlayerControl` focus model; Siri Remote play/pause, seek, menu/back handling
- **Now Playing** — lock screen and Dynamic Island metadata, artwork, and transport controls via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
- **Playback quality selection** — manual format override with `PlaybackViewModel+Quality`; HLS variant URL fetching; toast confirmation via `ToastModifier`
- **Previous/next video navigation** — history stack in `PlaybackViewModel+Navigation`; `playNext()` / `playPrevious()`
- **Caption track selection** — VTT fetch and live cue overlay in `PlaybackViewModel+Captions`
- **Sleep timer** — countdown task in `PlaybackViewModel+SleepTimer`
- **Like/Dislike actions** — `PlaybackViewModel+LikeDislike`
- **Stats for Nerds** overlay — `PlaybackViewModel+StatsForNerds`
- `PlayerView+Overlays` and `PlayerView+PickerOverlays` — player UI extracted into focused extension files
- `ToastModifier` — self-dismissing pill message (auto-clears binding after 2 s)
- `ScrollOffsetPreserver` — saves and restores LibraryView scroll position across tab switches
- `VideoDownloadUITests` — UI test for both download methods: (A) player more menu → "Download to Gallery" using `--uitesting-deeplink-video=JhCjw57u8mQ` launch arg; (B) video card long-press context menu → "Download to Gallery"; `player.moreMenu.downloadButton` accessibility identifier added to download button in `PlayerView+Overlays`
- Updated app icon (dark variant added)

### Changed
- `PlaybackViewModel` split into 14 focused extensions (Auth, AudioTracks, Captions, Controls, ControlsVisibility, Fallback, LikeDislike, Loading, Navigation, NowPlaying, Observers, Quality, SleepTimer, SponsorBlock, StatsForNerds)
- `InnerTubeAPI+VideoRenderers.swift` (~1,100 lines) split into `InnerTubeAPI+VideoGroupRows.swift` (multi-shelf home row parsing), `InnerTubeAPI+VideoRendererParsers.swift` (individual renderer parsers: `parseTileRenderer`, `parseLockupViewModel`, `parseReelItemRenderer`, `parseVideoRenderer`), and `InnerTubeAPI+VideoGroupFlat.swift` (flat video group fallback parsing); all other files kept under 1,000 lines
- Enhanced error handling and retry logic for failed stream requests
- BrowseViewModel recommended-video fetch deduplicates results
- Improved focus management for picker overlays on tvOS

### Fixed
- **Subscriptions feed not strictly sorted in chronological order** — YouTube returns each page sorted newest-first, but `BrowseViewModel.mergeIntoFirstGroup` and `HomeViewModel.loadMore` appended pages without global re-sort, so videos from page 2 appeared out of position relative to page 1; `videoGroups[0].videos` is now re-sorted by `publishedAt` descending after each `mergeIntoFirstGroup` call (subscriptions case) and after each `loadMore` append in `HomeViewModel`; `SubscriptionsSortTests` (pagination merge test) added

---

## [2.0] – 2026-05-03/04

### Added
- **Localisation** — `Localizable.xcstrings` string catalog covering the full app
- `InnerTubeAPIProtocol` — protocol abstraction over `InnerTubeAPI` enabling mock injection in tests
- `ViewModelLogger` — structured per-category logging routed to Crashlytics
- Sign-in UI: one-tap "Open Activation Page" button (opens pre-filled URL); "Or scan from another device" QR divider section
- Sign-in progress guard in `AuthService` — prevents concurrent device-code flows
- Comprehensive unit tests: `WebVTTParserTests`, `VideoStateStoreTests`, `ViewModelTests`, `VideoPreloadCacheTTLTests`, `SearchFilterUITests`, `YouTubeLinkHandlerTests`
- UI test suites: Channel, Library (History / Playlists / Subscriptions), Player controls, Recommended chip pagination, Search, Settings, Shorts, Audio track selection
- GitHub issue templates (bug report, feature request)

### Changed
- Updated Privacy Policy
- Various internal refactors for readability and maintainability

### Fixed
- **Login failures requiring multiple retries on iPhone** — `AuthService` gained `retryWithBackoff<T>()`: up to 3 attempts with 1–10 s exponential delay on transient `URLError` codes (timeout, connection lost, offline, SSL); `requestDeviceCode`, `fetchUserInfo`, `validAccessToken`, `refreshAccessToken` all wrapped; permanent OAuth errors (`invalid_grant`, `invalid_client`, `unauthorized_client`) are still propagated immediately without retry; `YouTubeClientCredentialsFetcher.fetchFromYouTube` retries twice before falling back to hardcoded credentials; `URLSession` in `InnerTubeAPI.init` now uses `waitsForConnectivity = true`, 20 s request timeout, 60 s resource timeout
- **SponsorBlock causing video playback to stall** — race condition between time observer ticks and async seek callback; debounce guard (`sponsorSkipDebounceTask`) prevents redundant seeks when multiple ticks fire on the same segment; seek-in-flight guard skips sponsor check while a seek is pending; exact seek (tolerance = zero) used for segment endpoints instead of fuzzy tolerance; segment-near-end threshold widened from 0.5 s to 2.0 s of video duration to prevent clamping to last frame; buffer-status verification logs warning when player is `.waiting` for >2 s after seek
- **Subscriptions feed showing videos out of chronological order** — `InnerTubeAPI+Browse.fetchSubscriptions()` now sorts each page's videos by `publishedAt` descending on arrival; `parseGuideChannels()` and `parseSubscribedChannels()` now sort channels alphabetically, matching `LocalSubscriptionStore`'s existing order
- **Apple TV fast-forward and rewind buttons showing white squares and not responding** — SF Symbol images in `seekButton` and `playPauseButton` rendered as white-on-white on tvOS focus engine due to `scaleEffect` + `shadow` + `buttonStyle(.plain)` interaction; fixed with `.renderingMode(.original)` + `.foregroundStyle(.white)`; reduced shadow intensity; Siri Remote gen 1 edge-tap left/right swipe gestures wired to `seekRelative` when controls are visible
- **Audio track language defaulting to wrong language for AI-dubbed videos** — when no `DEFAULT=YES` track is present in the HLS manifest, `index == 0` was incorrectly marked `isOriginal = true`; for AI-dubbed videos YouTube often lists the dubbed track first, causing the wrong track to be auto-selected; `isOriginal` is now only set when `group.defaultOption == option` (explicit HLS `DEFAULT=YES`); auto-selection waterfall reordered: (1) user's saved language preference, (2) HLS `DEFAULT=YES` original, (3) English track, (4) device locale, (5) first track
- **Videos unable to play / "reload page" error on iOS 18.7.2 and iOS 26** — hardcoded `"iOS 18_3_2"` User-Agent and client version string caused YouTube to detect a version mismatch on newer OS versions and return `UNPLAYABLE` or cipher-protected streams; User-Agent now uses `UIDevice.systemVersion` dynamically; SponsorBlock segment fetch moved to a detached background `Task` after `AVPlayerItem` is `.readyToPlay` so it no longer blocks stream setup on slow connections

---

## [1.9] – 2026-05-02

### Added
- Home feed staleness check — `HomeViewModel.refreshIfStale(threshold:)` reloads shelves when content is older than 15 minutes
- `InnerTubeAPI`: authenticated playback tracking URLs (`fetchAuthenticatedTrackingURLs`), TV-client endpoint (`postTV`), section-date and relative-date parsing
- Home feed fallback to popular videos when watch history is empty

### Changed
- HomeView replaced shelf rows with `VideoGridSection` grid layout
- `VideoCardView` layout and thumbnail improvements

---

## [1.8] – 2026-05-01

### Added
- Android-client HLS fallback in `PlaybackViewModel` — retries with Android credentials when the iOS HLS manifest returns a 404 due to IP-binding; last attempted URL stamped into Crashlytics non-fatal reports
- `VideoPlaybackRegressionUITests` — UI test coverage for core playback flows

### Changed
- `VideoPreloadCache` keeps its `InnerTubeAPI` access-token in sync with the signed-in session

---

## [1.7] – 2026-04-30

### Added
- `VideoPreloadCache` — background prefetch and cache of video stream data keyed by video ID
- `WatchtimeTracker` — reports playback position metrics to YouTube's watchtime endpoint
- `InnerTubeAPIKey` SwiftUI environment key — all views receive `InnerTubeAPI` via `@Environment(\.innerTubeAPI)` instead of constructor injection

### Changed
- Updated InnerTube client version strings

---

## [1.6] – 2026-04-28/29 — Initial Open Source Release

### Added
- Initial open source release of SmartTube for iPhone, iPad, macOS, and Apple TV
- **Audio track selection** — loads alternate HLS renditions (dubbed/translated tracks) from the manifest; auto-selects by device locale; persisted in `AppSettings`
- tvOS d-pad navigation in the player — custom `TVPlayerControl` enum; directional seek, play/pause, and back without SwiftUI focus engine
- tvOS Settings: Ko-fi and GitHub QR code sheets
- Firebase dSYM copy script for crash symbolication
- `CrashlyticsLogger` integration

### Changed
- `AuthService`: concurrent sign-in guard; automatic sign-out on permanent OAuth failures (`invalid_grant`, `invalid_client`, `unauthorized_client`); device code expiration clamped at server-reported `expiresIn`
- `VideoDownloadService` download-session and background-task code restricted to iOS with `#if os(iOS)` guards
- `PlaybackViewModel`: foreground/background audio session handling (`handleForeground()` / `handleBackground()`)
