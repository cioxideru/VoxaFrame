# PLAN-0046: Watch history sync with YouTube

Status: active

- Owner: coordinator (single session).
- Git boundary: local `master`.
- Scope: videos watched in VoxaFrame by a signed-in account appear in YouTube's watch history and resume progress.

## Problem

A video watched to 50% in VoxaFrame shows no progress in the official YouTube app, and the two histories differ for
the same account. The Hide Watched Videos filter therefore never sees that progress.

## Basis (iPad log, 2026-11-09, signed-in account)

- `[cookies] OAuthLogin did not redirect (HTTP 403)`, then Multilogin `403 INVALID_TOKENS`: the TV device-code token
  cannot be exchanged for a youtube.com SAPISID cookie, so `sapisid` stays nil.
- `POST /player [WebSafari] auth=Bearer` → `HTTP 400`: the WEB client rejects the TV Bearer token (the request also
  carries `?key=`). `fetchAuthenticatedTrackingURLs` returns nil.
- The player then falls back to `info.trackingURLs` from the anonymous VISIONOS/iOS player response. Their `ei`/`vm`/`of`
  belong to an anonymous visitor, so the pings are not credited to the account.
- `VideoPreloadCache` stores those anonymous URLs for every prefetched video. Opening a prefetched video logs
  `cache HIT: trackingURLs` and skips the authenticated fetch entirely.
- Android SmartTube (MediaServiceCore `VideoInfoService`, `TrackingService`, `RetrofitOkHttpHelper`) takes `ei`/`vm`/`of`
  from a TV-client `/player` on www.youtube.com with the Bearer token and no API key, and sends the stats pings to
  `www.youtube.com/api/stats/*` with the same Bearer token and `X-Goog-Visitor-Id`.
- Earlier live finding (2026-07-08): TV `/player` on youtubei.googleapis.com has no `playbackTracking`.
- The current 7.x TV identity on www.youtube.com answers `UNPLAYABLE` "The page needs to be reloaded." with no
  `playbackTracking`. Android's `TV_DOWNGRADED` identity (version `5.20260901`, an old Cobalt User-Agent) answers `OK`
  with `playbackTracking`.
- Even with account-bound URLs fetched, the player logged `activeTrackingURLs resolved: anonymous`. VISIONOS HLS wins
  the first stream attempt and starts Phase 2 through `launchPhase2(video:info:)`, which has no load context; the
  authenticated fetch travelled only in that context, so its result was dropped.
- The tracker marked the watch record open although its playback ping was skipped for lack of session params, and the
  player view's `updateAuthToken` on every appearance cleared the tracker's URLs as a "token refresh".

## Changes

1. `fetchAuthenticatedTrackingURLs`: the `TV_DOWNGRADED` identity on www.youtube.com with Bearer, no key, its
   User-Agent, visitor ID, the tracker's CPN and Android's playback context; then the WEB client only with a SAPISID
   cookie. No WEB Bearer attempt.
2. `PlaybackTrackingURLs.isAccountBound` marks URLs from an authenticated response. The player uses cached URLs only
   when they are account-bound; otherwise it fetches them, and still falls back to anonymous URLs.
3. `PlaybackViewModel.trackingURLSource` holds the load's cached URLs and authenticated fetch, so every Phase 2 launch
   uses them, whichever stream path won.
4. `WatchtimeTracker` opens a watch record only when the playback ping can go out, opens a new one when the session
   params change, and keeps it when the same params are set again. A token refresh no longer clears the current URLs,
   and the same token pushed again is not a refresh.
5. Logs name the source that supplied the URLs.

## Acceptance

- Unit tests: request host, client, auth and missing key; account-bound flag; anonymous cache entries do not skip the
  authenticated fetch; Phase 2 without the load context uses the account fetch; late and repeated URLs and the watch
  record.
- `scripts/ci.sh`, SwiftLint, iOS and tvOS builds.
- Live: a video watched in VoxaFrame on the iPad shows progress and appears in history in the official YouTube app.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Root cause | iPad log and Android sources above | confirmed |
| Implementation | changes 1–5 | done |
| Checks | `scripts/ci.sh` (1415 tests), SwiftLint, ast-grep rules; `scripts/verify.sh` | passed; verify: package tests, SwiftLint, iOS and tvOS builds (Smoke stage skipped, OQ-0003) |
| iPad log | `tracking [tv-downgraded] … status=OK playbackTracking=true`, `activeTrackingURLs resolved: account-bound`, `/api/stats/playback` then `/api/stats/watchtime` every 30 s | passed |
| Live acceptance | progress and history in the official YouTube app | NOT RUN |
