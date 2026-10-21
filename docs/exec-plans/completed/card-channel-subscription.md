# PLAN-0040: Channel subscription in card menus

Status: completed
Owner: Claude (coordinator); Opus 5.5 executors; GPT-6.0 Astra reviewer
Date: 2026-10-21

## Scope and boundary

Follow-up to [PLAN-0039](../completed/hig-review-fixes.md), requested by the user:

1. The player More menu channel row shows only the channel avatar, not its name.
2. The video card context menu (Home and other card grids: Share … Save to Watch Later, Offline Watch,
   Not Interested) gets the same compact channel control: subscription status, subscribe/unsubscribe
   and Go to Channel in one compact line.

Two parallel worktrees from local `master` at `94110349`: `plan-0040/channel-avatar` (trivial, no external
review) and `plan-0040/card-subscription` (Astra review). Merge into `master` one at a time.

## Acceptance

- Avatar-only row keeps the channel name for VoiceOver.
- Card menus on iOS, macOS and tvOS show status, change it (Unsubscribe confirmed, bound to its channel)
  and open the channel; existing menu commands and accessibility actions keep working.
- CI, strict SwiftLint, iOS/tvOS builds and build-for-testing pass; HIG commit gate high = 0.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| channel-avatar | No external review; HIG gate high=0 (medium: no visible name on touch/tvOS, accepted as the user's choice; the menu header shows the channel) | `541b085a` |
| card-subscription | Astra, three rounds: updates during loading kept, per-session context for late results, expiry on reads, observable reload completion; HIG gate high=0 after the silent-unsubscribe toast and hiding unknown status | `b551c08b` |
| Checks | `./h check` (1,389 tests), strict SwiftLint, iOS/tvOS builds and build-for-testing | passed |
| UI tests (iOS Simulator) | VideoFeedbackConfirmation 4/4, PlayerMoreMenuOpenChannel | passed |
| Rendered menus, macOS app target | ControlGroup layout on iOS/macOS and the tvOS chained dialog not seen on screen; macOS app not built by the scripts | NOT RUN |

Resolution: both requests delivered. The player row still fetches status on its own (no shared cache) because its
API carries no session; external `subscriptionsDidChange` notifications drop the shared cache rather than applying.
Rendering gaps are recorded in [OQ-0020](../../OPEN_QUESTIONS.md#oq-0020--hig-review-findings-left-open).
