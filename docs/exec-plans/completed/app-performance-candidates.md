# PLAN-0044: App and interface performance candidates

Status: completed
Owner: Claude Code (coordinator); executor Opus 5.5, reviewer GPT-6.1 Sol, auditor Fable 5.1
Date: 2026-10-23

Resolution: two confirmed causes of redundant work fixed with regression tests; the other
candidates were measured or traced and left unchanged. No general speedup is claimed;
[OQ-0013](../../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance) stays open.

## Scope and boundary

Branch `wt/perf-0044` from local `master` `366f7859`. The user asked for better interface and
whole-app performance. A fix needs a confirmed cause: a test that fails before the change, or a
measurement before and after on the same scenario. Out of scope: the playback fallback cascade
(`PlaybackViewModel+Fallback*`, `+ExhaustiveRetry`, `+FallbackRace`, ADR-0005), storage
architecture (ADR-0017), new dependencies, translations.

## Candidates

Measurements: native macOS arm64, Debug, package tests, Xcode 27.1. No simulator or device profile.

| Candidate | Result | Evidence |
|---|---|---|
| Home feed preparation (filter, segments) | not confirmed, unchanged | 0.315 ms per body at 100 videos, 2.104 ms at 1,000, 6.142 ms at 3,000; runs on page or layout change, not per frame |
| Settings writes | fixed | a thumbnail-style or quality choice saved the whole `AppSettings` twice (~0.27 ms encode each); `SettingsStore.update(_:)` saves once |
| Channel page on token refresh | fixed | a token refresh in the same session called `fetchChannel` and `fetchSubscribedChannels` twice and reset paging; now once each |
| Widget snapshot write on the main actor | not confirmed, unchanged | median 3.1–3.7 ms, maximum 11.9 ms, once per changed Home update |
| Now Playing artwork | NOT RUN, unchanged | UIKit-only path; not executed by native package tests |
| Card thumbnail URL chains, non-iOS prewarm loop, player time observer | unchanged | no confirmed cause |

## Changes

- `SettingsStore.update(_:)` applies several changes with one save. `SettingsView` uses it for the
  thumbnail style (`ThumbnailStyle.init(_:)`/`apply(to:)`) and the tvOS/macOS quality picker.
  The stored key and JSON format are unchanged. `SettingsStore(defaults:)` makes writes countable.
- `ChannelViewModel.load(channelId:auth:)` skips a reload only for a token refresh in the same
  signed-in session while the page is on screen and fully loaded. `ChannelView` runs it on
  `auth.sessionState` and calls `screenDidDisappear()` when hidden, so returning to the page loads it
  again; a cancelled appearance task loads nothing and leaves that state cleared.
- Tests: `SettingsStoreSaveTests`; `tokenRefreshKeepsPage`, `accountChangesReloadPage`,
  `returnWithNewTokenReloadsPage`, `cancelledAppearanceLoadsOnReturn` in `SubscriptionStateTests`.
  The suites that write `iCloudSyncManager.shared.syncEnabled` run under the serialized
  `SyncEnabledSuites` parent.

## Checkpoints

| Step | Evidence / review | State |
|---|---|---|
| Research | read-only note with 18 items: candidates, registers, shapes to check | complete |
| Implementation | two fixes with before/after counters | complete |
| Review 1 | DEFECTS: stale channel page after returning with a new token; unserialized `syncEnabled` tests | fixed |
| Review 2 | DEFECTS: a cancelled appearance task restored the cleared state | fixed after escalation |
| Review 3 | CLEAN, no minor findings | complete |
| Audit | two-phase audit, ACCEPT | complete |
| Checks | `scripts/ci.sh` (1,395 tests in 188 suites), SwiftLint, iOS/tvOS/macOS app builds, UI-test build | passed |

The new cancellation test was run without the guard and failed on both expected assertions.

## Not verified

- UIKit-only package tests, the iPad performance UI tests (need a signed-in simulator),
  Instruments and physical-device profiles.
- Untested shapes noted by the audit: the settings `Binding` setters themselves, the
  `isSubscriptionLoaded` and `error == nil` conditions separately, and "Try Again" through the old
  `load(channelId:signedIn:)` path (correct because a failed load keeps `error` set).
- Out of scope finding: iCloud sync starts disabled after launch,
  [OQ-0021](../../OPEN_QUESTIONS.md#oq-0021--icloud-sync-disabled-after-launch).
