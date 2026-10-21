# PLAN-0041: One card menu on every screen

Status: completed
Owner: Claude (coordinator); Opus 5.5 executor; GPT-6.0 Astra reviewer
Date: 2026-10-21

## Scope and boundary

The user saw a shortened, older card menu on the Home tab and asked that every screen use the full card menu
from [PLAN-0040](../completed/card-channel-subscription.md). Home already uses `VideoCardView` for regular
videos, but its Shorts rows use `ShortsCardView`, which builds its own reduced menu (no Offline Watch,
Copy to Playlist, Play Incognito or Move to Playlist). This plan makes all video cards — regular and Shorts,
on Home, Search, Library, Channel, Playlist, Browse and the player's related list — show one shared menu,
in the context menu, the More button, VoiceOver actions and the tvOS Play/Pause dialog.

Worktree `plan-0041/unified-card-menu` from local `master` at `f6eb74e4`; merge after review and gates.

## Acceptance

- One definition of the card commands; Shorts cards and video cards show the same items in the same order.
- Existing confirmations (Not Interested, Don't Recommend Channel, Unsubscribe), toasts and accessibility
  identifiers keep working; UI tests for feedback confirmation and Shorts pass.
- CI, strict SwiftLint, iOS/tvOS builds and build-for-testing pass; HIG commit gate high = 0.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Trace | Only `ShortsCardView` had a reduced menu (Home Shorts rows, Shorts chip); every other tile already used `VideoCardView` | done |
| Implementation | `VideoCardMenu.swift`: shared items, state, modifier and More button; Shorts get the full menu, a More button and a tvOS Button carrying menu and accessibility; Don't Like This Video confirmed for all videos | `48d0165c` |
| Review | Astra: Shorts More button added with a fixture UI test; HIG gate high=0 (tvOS nested button and Don't Like confirmation fixed) | passed |
| Checks | `./h check`, strict SwiftLint, iOS/tvOS builds and build-for-testing | passed |
| UI tests (iOS Simulator) | VideoFeedbackConfirmationUITests 7/7, MixedFeedLayout More button, HomeShortsEndless 2/2 | passed |
| Pre-existing failures | `HomeShortsCountUITests` (live feed, stale `home.shortsRow` lookup) and `MixedFeedLayoutUITests` history fixture fail on base `f6eb74e4` too | not caused here |
| tvOS UI, rendered menus | Not runnable through the scripts; build-verified only | NOT RUN |

Resolution: every video tile uses one menu. Open items are in [OQ-0020](../../OPEN_QUESTIONS.md#oq-0020--hig-review-findings-left-open).
