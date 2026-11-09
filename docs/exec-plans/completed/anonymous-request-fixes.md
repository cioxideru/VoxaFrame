# PLAN-0047: Features broken by anonymous or wrong-client requests

Status: completed

- Owner: coordinator (single session).
- Git boundary: local `master`, after PLAN-0046.
- Scope: five findings from the PLAN-0046 audit of every InnerTube request, chosen by the user ("Все пять"), and the
  live-tile finding from its iPad check.

## Basis (iPad logs, 2026-11-09, and anonymous probes from the Mac)

- **Related videos:** `fetchNextInfo` returned `related=0` in all 265 loads. The WEB `/next` response now lists related
  videos as `lockupViewModel` (20 for `_WwYb_Pa_10`, all `LOCKUP_CONTENT_TYPE_VIDEO` under
  `secondaryResults.secondaryResults.results`); `parseRelatedVideos` reads only `compactVideoRenderer`.
- **End cards:** `fetchEndCards` returned 0 cards in all 272 calls. The anonymous WEB `/player` answers `UNPLAYABLE`
  "Video unavailable" without `endscreen`. The account TV `/player` that PLAN-0046 fetches for tracking carries
  `endscreen`. Every prefetch sent that useless WEB `/player` as well.
- **Category sections:** TV `browse` answers HTTP 400 `INVALID_ARGUMENT` for `FEmusic_home`, `FEgaming`, `FElive_home`
  and `FEsportsau`: anonymously on www.youtube.com with both TV identities, and on googleapis with the account token
  (iPad log, first build of this plan). Music, Gaming, Live and Sports therefore silently showed search results, and
  News always searched. `FEtopics_music`, `FEtopics_gaming`, `FEtopics_news`, `FEtopics_sports` and `FEtopics_live`
  answer 200 with video tiles (channel and playlist tiles are dropped by the parser) and, except Gaming, continuations.
- **Live tiles as Shorts:** `FEtopics_live` tiles carry the Shorts `ustreamerConfig` (`GgIIBQ==`) and no duration;
  the parser trusts that signal when the duration is unknown, so 15 of 20 live and upcoming streams became Shorts.
- **Retry chain:** step 4 sends the TV device-code token to the iOS client, which rejects it with HTTP 400; the step then
  falls back to the anonymous iOS request.
- **Dead code:** `fetchHistoryTrackingURLs`, `fetchAuthenticatedTrackingURLs(videoId:usingToken:)` and
  `postWebSafari(allowBearerFallback:)` have no callers; the first tries the three rejected clients.

## Changes

1. Related videos: `parseRelatedVideos` also reads video `lockupViewModel`s through `parseLockupViewModel`.
2. End cards: the account TV `/player` response supplies tracking URLs and end cards together. Phase 2 takes end cards
   from the primary response, then the cache (non-empty only), then the account response. The WEB end-card request and
   its prefetch are removed.
3. Category sections load the `FEtopics_*` pages, News included. A signed-in account browses with the TV client and
   its token, like Home; without one the anonymous TV browse stays. Search remains the fallback for an empty or failed
   first page; continuations send their token instead of reloading page 1.
6. Tiles with a `LIVE` or `UPCOMING` time-status overlay are never Shorts by the duration-less signals.
4. Retry chain step 4 uses only the anonymous iOS request.
5. The dead functions and the unused parameter are removed.

## Acceptance

- Unit tests for lockup related videos, account end cards and the category request route and continuation.
- `scripts/ci.sh`, SwiftLint, iOS and tvOS builds.
- iPad: related videos and end cards appear for a signed-in account; the category sections log a TV browse instead of
  the search fallback; live streams in Live are not Shorts.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Findings | iPad logs and probes above | confirmed |
| Implementation | changes 1–5; category continuations send their token instead of reloading page 1 | done |
| Checks | `scripts/ci.sh` (1422 tests), SwiftLint, ast-grep rules | passed; verify: package tests, SwiftLint, iOS and tvOS builds (Smoke stage skipped, OQ-0003) |
| iPad: related, end cards | `LojWAvuHUkI`: `fetchNextInfo (auth) → related=20`, `tracking [tv-downgraded] … endscreen=true`, `endCards: 3 from account player response`, `activeTrackingURLs resolved: account-bound` | passed |
| iPad: category sections | `FEtopics_live`: 20 videos, next page loaded; `FEtopics_music`: 18 + 18 videos; both TV browse with the account, no search fallback | passed for Live and Music; Gaming, Sports and News were not opened on the iPad and rest on the same code path, unit tests and the anonymous probes |
| iPad: live tiles | `FEtopics_live`: 20 + 15 videos, 0 Shorts; 25 `LIVE` and 15 `UPCOMING` tiles logged `isShort=false` | passed |
