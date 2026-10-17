# PLAN-0017: Working subscriptions and channel management

Status: completed
Resolution: account subscribe/unsubscribe, complete membership loading and confirmed row
removal are implemented and verified in unit tests, isolated UI tests and a real account.
The temporary NASA subscription was removed and absence was confirmed after relaunch.

## Scope and boundaries

Owner: primary Codex agent. The iPad menu task was delegated separately as PLAN-0016.
Work started in the dedicated subscriptions-ipad worktree from e7a2db1, then incorporated
concurrent master 5955a1b before the final package checks and platform builds. The original
checkout's staged localization and unstaged Xcode Run-scheme changes are outside this task.
PLAN-0017 was assigned before commit because the concurrent Shorts task occupied PLAN-0015.

The signed-in channel page hid the local Follow button and had no account mutation method.
The channel list was read-only; an empty list incorrectly requested sign-in. The old loader
tried TV guide, then inferred subscriptions from authors of recently loaded videos. Real-device
validation showed that guide contains navigation rather than complete membership.

Acceptance: authenticated subscribe/unsubscribe, accurate reloads, empty/error handling,
confirmed icon/swipe removal, retained state after failure, and passing required checks.
Constraints: Foundation-only Core, Swift 6, existing dependencies and UI-test target;
no manual project-file changes or remote publication. No implementation blocker remains.

## Delivered behavior

- Account mutations use TVHTML5 OAuth with a captured bearer token and visible HTTP/application
  errors. Signed-out following remains in LocalSubscriptionStore.
- Membership comes from FEsubscriptions secondary-navigation channel tabs, including channels
  without recent uploads. Decode channel parameters, normalize scheme-relative avatar URLs,
  follow channel continuations, deduplicate, and reject malformed/repeated continuation data.
  Video feed continuations cannot paginate the channel list.
- ChannelView shares the app API and loads authoritative membership. A completed mutation
  cancels stale refresh work so it cannot revert the visible state. Changes publish only after success.
- The list uses native swipe actions and a 44-point unsubscribe icon, both with confirmation.
  Failed requests retain the row; successful changes update/reload the list. Error, Retry and
  empty-account states are distinct. Avatar enrichment matches current IDs after list changes.

## Verification

| Check | Evidence | Result |
|---|---|---|
| Native gates after master integration | scripts/ci.sh: 1085 tests / 151 suites, secret/doc/import/format checks; strict SwiftLint: zero violations in 410 files | PASS |
| Platform compilation after integration | scripts/build-for-testing.sh: iOS and tvOS apps plus UI-test targets | PASS |
| Isolated subscription UI | smarttube-subscriptions-ui-final.xcresult: icon cancel/confirm, swipe confirm, channel unsubscribe/subscribe, rejected mutation, load error/retry/empty account | 5 passed, 0 skipped |
| Physical iPad | smarttube-subscriptions-live-final.xcresult: real list/channel/tab returns in portrait and landscape; temporary NASA subscribe/unsubscribe, both verified after relaunch | 2 passed, 0 skipped |
| Concurrency regression | Controlled continuations release an obsolete refresh after successful unsubscribe | PASS |

Bundles and logs are under /private/tmp. The real list repeatedly loaded 338 channels.
Final physical screenshots show avatars and separate top navigation rows. Device: iPad Pro
11-inch M5, iPadOS 27.0.1. Fixture UI: iPad Pro 13-inch M5 Simulator, iPadOS 26.5.

The live mutation test requires an explicitly approved SMARTTUBE_LIVE_SUBSCRIPTION_CHANNEL
runner environment variable, an initially unsubscribed channel, and a physical device. Ordinary
runs skip it. The fixture uses a fake in-memory session before Keychain loading and intercepted
requests; production networking remains exercised by the physical tests.

Diagnostic attempts are not acceptance: the guide-based live run showed an empty list;
its replacement exposed scheme-relative avatar URLs, fixed before final verification. An earlier
UI Retry scenario consumed its one-time error in the initial Home feed. Using the existing mixed-feed
fixture isolates Home from the subscription-list transport and the final five scenarios pass.
The live bundle records a Thread Performance Checker priority-inversion warning; no test failed.
No performance profiling was performed for that warning.

The separate rare iPad layout sequence remains tracked in
[OQ-0017](../../OPEN_QUESTIONS.md#oq-0017--subscription-and-rare-ipad-menu-live-acceptance).
