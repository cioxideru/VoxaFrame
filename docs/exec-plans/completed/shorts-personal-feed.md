# PLAN-0052: Personalized Shorts feed for a signed-in account

Status: completed (2026-11-20)
Resolution: delivered with the titles and channels looked up in core (`reel/reel_item_watch`) instead of the
player, by the user's decision during review; the main player, history and SponsorBlock are unchanged. Codex
review (nine rounds, the last two narrowed by the user's decision) and Fable audit accepted. The signed-in device
check is NOT RUN and tracked in [OQ-0026](../../OPEN_QUESTIONS.md#oq-0026--personalized-shorts-feed-device-check).

- Owner: coordinator; one executor.
- Git boundary: worktree `wt/shorts-feed-0052` from `master` after `a4a5e7bc`.
- Basis: upstream pull request [milika/SmartTubeIOS#189](https://github.com/milika/SmartTubeIOS/pull/189), its feed
  part only (`InnerTubeAPI+Shorts.swift`, `ShortsSequence.swift`), review of 2026-11-20. Its player, tab, menus and
  translations are not ported.
- Constraints: our Shorts player, pager and settings stay as they are; the change is limited to the request and the
  parser in `SmartTubeIOSCore` plus the smallest hook where our Shorts feed asks for the next page. Foundation-only
  core; authenticated requests call `activeChannel.apply(to:)` (Brand Accounts).

## Scope

When the user is signed in, the next Shorts after the current one come from YouTube's TV `reel/reel_watch_sequence`
sent with the account's Bearer token and the selected Brand Account, so the feed follows that account's
recommendations. Signed out, or when YouTube rejects the signed-in request, the feed works as today. Opening a Short
from a shelf seeds the sequence with that Short.

## Acceptance

- Parser tests on recorded JSON fixtures; request tests at the API seam: Bearer and `X-Goog-Pageid` present when
  signed in, the current anonymous request when signed out, fallback to it on an error answer.
- No new paths in the main video playback; existing Shorts tests pass unchanged or with stated reasons.
- `scripts/ci.sh`, SwiftLint and the ast-grep rules; iOS, tvOS and macOS builds.
- A signed-in device check that the feed differs from the signed-out one is recorded as `NOT RUN` until done.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Review | PR #189 read on 2026-11-20 | done |
| Implementation | `fetchShortsFeed` + `ShortsSequence` in core (one account snapshot per page picks the source and signs the sequence and its title and channel lookups from `reel/reel_item_watch`, before one absolute deadline and within a concurrency limit; continuations bound to their Brand Account; the fallback search without cookies), a cursor per source read from the page's tokens and the IDs of Shorts kept in the window in `ShortsFeedWindow`, the player's `loadMore`; `ShortsSequenceTests` (parser, seed, ends, trimming), `ShortsFeedRequestTests` (request, Brand Account binding, fallback and its cookies, guest paging, a token set between pages, an ended search), `ShortsSequenceMetadataTests` (overlay parser, lookups: Brand Account, snapshot, identity change, failure, deadline, limit, known fields) and existing Shorts suites pass, 2026-11-20 | done |
| Review and audit | Codex review CLEAN (round 17), Fable audit ACCEPT (round 18), 2026-11-20 | done |
| Signed-in device check | OQ-0026 | NOT RUN |
