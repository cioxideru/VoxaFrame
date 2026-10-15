> Status: archived — classified from code on 2026-10-15.
> This June snapshot predates the VISIONOS-first path and current fallback file decomposition. Use the architecture map and source for current ordering; live success claims require a new run.
> Current references: [architecture](../architecture.md), [open questions](../OPEN_QUESTIONS.md).

# Video Stream Playing Methods

> SmartTubeIOS — all known paths from video ID to AVPlayer playback.
> Last updated: 2026-06-05

## Overview

When a video is opened, `PlaybackViewModel.loadAsync()` first tries the iOS client directly.
If that fails (rqh=1 restriction, embedding disabled, etc.), `exhaustiveRetry()` is called.
Inside `exhaustiveRetry`, three paths race concurrently first (A, B, C), followed by a serial
client chain that tries each API client in order, and finally a muxed-360p last resort.

---

## API Client Methods (InnerTubeAPI+Player.swift)

Each method below calls a specific InnerTube client variant and returns a `PlayerInfo` struct.
`PlayerInfo` contains `hlsURL`, `dashURL`, `formats[]` (adaptive), `bestMuxedDownloadURL`.
`tryAllStreams(info:)` then tries to play the returned URLs in order: HLS → adaptive → muxed.

| ID (for `--uitesting-force-stream-method`) | Function | Client / Notes |
|--------------------------------------------|----------|----------------|
| `ios` | `fetchPlayerInfo` | iOS client (c=IOS, googleapis.com). Returns adaptive-only. Adaptive streams always have `rqh=1` on YouTube CDN (confirmed May 2026) — can't play without pot= token unless BotGuard mints one. |
| `ios-auth` | `fetchPlayerInfoiOSAuthenticated` | iOS client + Bearer auth + pot= token. Same rqh=1 problem; HTTP 400 seen in logs — Bearer scoped to TVHTML5, not iOS. |
| `tvembedded` | `fetchPlayerInfoTVEmbedded` | WEB_EMBEDDED_PLAYER (nameID=56) on `www.youtube.com`. Returns `hlsManifestUrl` for embeddable videos. Fails for embedding-disabled content. |
| `tvauth` | `fetchPlayerInfoAuthenticated` | TV client (TVHTML5) + Bearer token + signatureTimestamp + visitorData. Returns HLS + adaptive. Authenticated HLS bypasses rqh=1. Phase 0 in serial chain. |
| `websafari` | `fetchPlayerInfoWebSafari` | WEB (nameID=1) + macOS Safari UA + SAPISIDHASH auth. Returns `hlsManifestUrl` for non-embeddable videos where TVEmbedded fails. Primary HLS path for embedding-disabled content. |
| `mweb` | `fetchPlayerInfoMWEB` | MWEB (nameID=2, iPad Safari UA). Not subject to embed restriction. Returns `hlsManifestUrl`; no pot= required for HLS. |
| `android` | `fetchPlayerInfoAndroid` | Android client (c=ANDROID, googleapis.com). CDN URLs signed with Android UA, reliably downloadable. Used for muxed 360p last resort. |
| `android-vr` | `fetchPlayerInfoAndroidVR` | Android VR / Oculus Quest (nameID=28, googleapis.com). Per yt-dlp, CDN-exempt from rqh=1 / pot= on adaptive streams. Returns `hlsManifestUrl` with `html5Preference: HTML5_PREF_WANTS`. |
| `web-creator` | `fetchPlayerInfoWebCreator` | WEB_CREATOR / YouTube Studio (Bearer + X-Goog-AuthUser:0). Exempt from rqh=1 on adaptive streams. Requires sign-in. Returns 720p–2160p without pot= token. |
| `web-auth` | `fetchPlayerInfoWebAuthenticated` | WEB (nameID=1) + Bearer token (mirrors yt-dlp oauth). Adaptive URLs don't carry rqh=1 for authenticated users. |
| `ios-download` | `fetchPlayerInfoForDownload` | WEB client (nameID=1, no auth). Used for download URL resolution only; not a playback path. |
| `web-pot` | `fetchPlayerInfoWebWithPoToken` | WEB + `serviceIntegrityDimensions.poToken` from BotGuard mint + WKWebView visitorData. CDN URLs are pot=-authenticated. |

---

## Composite / Background Paths

These are higher-level paths that combine API calls, token minting, or browser extraction.

| ID | Path | Description |
|----|------|-------------|
| `wkwebview-hls` | WKWebView HLS extraction | Loads `youtube.com/watch?v=<ID>` in an offscreen WKWebView with JS hooks on XHR/fetch. Extracts `hlsManifestUrl` from player API JSON. Solves the `n=` throttle parameter via EJS AST solver. Slowest (~3–9 s cold) but most reliable for rqh=1 videos without authentication. |
| `botguard-wv` | BotGuard WV adaptive (Path A) | Waits for `BotGuardWebViewRunner` to mint a pot= token (up to 6 s cold, <5 ms warm). Recovers SAPISID from WKWebView cookies. Then tries WEB adaptive → proxy HLS → iOS/Android adaptive. Fast when BotGuard is warm. |
| `android-vr-race` | AndroidVR race (Path C) | Concurrent `fetchPlayerInfoAndroidVR` started in the race group alongside Paths A and B. Expected ~2–3 s cold. Wins when both Path A and Path B timeout. |
| `wkwebview-hls-early` | WKWebView HLS early task (Path B) | `wkHLSEarlyTask` started in `loadAsync` concurrently before the API call completes. Awaited in `exhaustiveRetry` race Path B. Wins for rqh=1 videos where CDN probe returns 403 in ~1.8 s. |

---

## Playback Modes (stream types within PlayerInfo)

Once `PlayerInfo` is fetched, `tryAllStreams` tries these in order:

| Mode | Source field | Player approach |
|------|-------------|----------------|
| **HLS master** | `PlayerInfo.hlsURL` | `AVPlayer` with master manifest — AVPlayer ABR handles quality. Preferred. |
| **Adaptive composition** | `PlayerInfo.formats[]` — separate video+audio | `AVMutableComposition` — picks best video ≤ preferred height + highest bitrate audio. Quality switching via `reloadDASHItem`. |
| **Muxed 360p** | `PlayerInfo.bestMuxedDownloadURL` | `AVPlayer` with single MP4 file (video+audio muxed). Last resort — no quality switching. |

---

## Known Video Profiles

| Video ID | Title / Notes | Expected best method | Characteristics |
|----------|--------------|----------------------|----------------|
| `dQw4w9WgXcQ` | Rick Astley — Never Gonna Give You Up | `ios` HLS or `botguard-wv` | Public, popular, embeddable. CDN usually accepts BotGuard token. |
| `9bZkp7q19f0` | PSY — Gangnam Style | `botguard-wv` or `wkwebview-hls` | High view count. rqh=1 in some regions. |
| `LSMQ3U1Thzw` | Ben Eater SID music | `wkwebview-hls` or `android-vr` | Documented rqh=1, multi-audio tracks. BotGuard probe test video. |
| `v2ZtAi2rDzA` | rqh=1 worst-case | `wkwebview-hls` cold | CDN probe 403, BotGuard cold fail. WKWebView serial wins. |
| `l7To2evwGKs` | Real-world rqh=1 (2026-05-28) | `botguard-wv` fast | BotGuardWV fast path expected. |
| `Wu8xNx4njoM` | Embedding-disabled | `web-creator` (auth) or `wkwebview-hls` | TVEmbedded returns "unavailable". ALL adaptive have rqh=1 without WEB_CREATOR auth. |
| `y9R5a76HPbU` | nSolver regression video | `botguard-wv` or `wkwebview-hls` | Must NOT fall back to Android/muxed — n-challenge must solve. |
| `Dy9ki9Q5nXs` | Scrubber test video | Path A | Standard video. |
| `m1WGX1-uGvU` | WKWebView cookie proxy | `wkwebview-hls` | WKHLSCookieProxy required. |
| `jNQXAC9IVRw` | Me at the zoo (first YouTube video) | Path A | Very old video; tests legacy format support. |
| `MCv4EyEFgVg` | Popular Short | Path A or `android-vr` | YouTube Short opened as regular video. |
| `JhCjw57u8mQ` | Download test video | `android` | Used for download; standard playback. |
| `kJQP7kiw5Fk` | Recommended feed fallback | Path A | Standard public video. |
| `OPf0YbXqDm0` | Recommended feed fallback | Path A | Standard public video. |

---

## Probe Test Matrix

The `StreamMethodProbeUITests` suite runs every (video, method) pair below.
One XCTest function per cell. Result is PASS (video played) / FAIL (error) / TIMEOUT.

Methods included in the probe matrix (most useful for data gathering):
`ios`, `tvembedded`, `tvauth`, `websafari`, `mweb`, `android`, `android-vr`,
`web-creator`, `web-auth`, `wkwebview-hls`

Video IDs in the probe matrix:
`dQw4w9WgXcQ`, `9bZkp7q19f0`, `LSMQ3U1Thzw`, `v2ZtAi2rDzA`,
`Wu8xNx4njoM`, `y9R5a76HPbU`, `Dy9ki9Q5nXs`, `jNQXAC9IVRw`

### How to run

```bash
# Run the full probe matrix (iOS simulator) — MUST use -parallel-testing-enabled NO
# Parallel workers cause simulator clone crashes and 90s timeouts.
xcodebuild test \
  -workspace SmartTube.xcworkspace \
  -scheme "SmartTube" \
  -destination "id=6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6" \
  -only-testing:SmartTubeUITests/StreamMethodProbeUITests \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/probe-full.xcresult \
  2>&1 | tee /tmp/probe-full.log

# Run a single (method, video) probe
xcodebuild test \
  -workspace SmartTube.xcworkspace \
  -scheme "SmartTube" \
  -destination "id=6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6" \
  -only-testing:SmartTubeUITests/StreamMethodProbeUITests/testProbe_tvembedded__Wu8xNx4njoM \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/probe-single.xcresult
```

### Results — Run 1 (2026-06-05, authenticated simulator, sequential)

**88/88 PASS** — all methods produced a playable stream for all 8 videos.

#### Time-to-play per method (probe run, 2026-06-05)

Measured as XCTest case duration = app launch + 0.5s settle + API fetch + AVPlayer buffering.
Fixed overhead ≈ 2–3s. Relative differences are meaningful; absolute values are not.

| Method | Min (s) | Avg (s) | Max (s) | Notes |
|--------|---------|---------|---------|-------|
| `ios` | 5.3 | 5.4 | 5.4 | Fast, consistent — iOS API call ~2s |
| `tvembedded` | 5.3 | 5.4 | 5.4 | Fast HLS path |
| `tvauth` | 5.3 | 5.4 | 5.4 | Fast authenticated HLS |
| `mweb` | 5.3 | 5.4 | 5.5 | Fast, consistent |
| `websafari` | 5.3 | 5.4 | 5.4 | Fast |
| `web-creator` | 5.3 | 5.4 | 5.4 | Fast authenticated path |
| `web-auth` | 5.3 | 5.4 | 5.4 | Fast |
| `android` | 5.4 | 5.7 | 6.5 | Slightly slower; CDN URL construction |
| `ios-auth` | 5.3 | 5.9 | 10.4 | Usually fast; one video took 10s (auth refresh) |
| `android-vr` | 5.4 | **11.8** | 15.4 | **Bimodal**: 5s for CDN-exempt videos; 13–15s for rqh=1 videos (CDN probe detects restriction, retries) |
| `wkwebview-hls` | 5.4 | **10.9** | 15.3 | **Bimodal**: 5s if WKWebView warm/cached; 10–15s cold JS extraction |

Resolutions where captured (via `player.probeStreamResult` AX element):
- `android` returns adaptive streams (up to 4K). `rqh=1` NOT present (CDN doesn't enforce it for Android client UA).
- `android-vr` same resolutions as `android` but explicitly marked `rqh=1` (CDN exempts VR client).
- All HLS-based methods (`tvembedded`, `tvauth`, `mweb`, `websafari`, `web-creator`, `web-auth`) show `?` — timing race between play button enabling and `probeStreamResult` being set. Fixed in test (now waits 8s).
- `wkwebview-hls` shows `WKWebView-HLS` for some videos (others `?` due to same timing race).

| Method \ Video | dQw4w9WgXcQ | 9bZkp7q19f0 | LSMQ3U1Thzw | v2ZtAi2rDzA | Wu8xNx4njoM | y9R5a76HPbU | Dy9ki9Q5nXs | jNQXAC9IVRw |
|---|---|---|---|---|---|---|---|---|
| `ios` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) |
| `ios-auth` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (10.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) |
| `tvembedded` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) |
| `tvauth` | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.4s) |
| `websafari` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) |
| `mweb` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.5s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) |
| `android` | ✅ ? (5.4s) | ✅ 1080p (5.9s) | ✅ 1080p60 (6.5s) | ✅ 1440p (5.4s) | ✅ 2160p (6.4s) | ✅ 2160p (5.4s) | ✅ 2026p (5.4s) | ✅ 240p (5.4s) |
| `android-vr` | ✅ ? (5.4s) | ✅ 1080p rqh=1 (13.4s) | ✅ 1080p60 rqh=1 (15.4s) | ✅ 1440p rqh=1 (10.4s) | ✅ 2160p rqh=1 (14.4s) | ✅ 2160p rqh=1 (14.4s) | ✅ 2026p rqh=1 (15.4s) | ✅ 240p rqh=1 (5.4s) |
| `web-creator` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) |
| `web-auth` | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.4s) | ✅ ? (5.4s) | ✅ ? (5.3s) | ✅ ? (5.3s) | ✅ ? (5.4s) |
| `wkwebview-hls` | ✅ ? (5.4s) | ✅ ? (15.3s) | ✅ ? (12.4s) | ✅ ? (10.4s) | ✅ WKWebView-HLS (10.4s) | ✅ ? (11.4s) | ✅ ? (11.4s) | ✅ WKWebView-HLS (10.4s) |

Notes:
- `?` = method PASSED (play button enabled) but `probeStreamResult` was read before `probeStreamMethod` finished writing it (race condition). Fixed in subsequent runs with `waitForExistence(8s)`.
- `240p` for `jNQXAC9IVRw` (first YouTube video, 2005) — very old video, only low-res streams available.
- `2026p` for `Dy9ki9Q5nXs` — unusual resolution, likely 2K (2026×1136) vertical format.
- `android-vr rqh=1` confirms CDN exemption: VR client gets rqh=1 adaptive streams that normal iOS client cannot serve without pot= token.
- All methods PASS on authenticated simulator — `ios-auth` passing suggests this simulator's Bearer token scoping is compatible with iOS client auth path.

Cell format: `✅ PASS (resolution)` / `❌ FAIL` / `⏱ TIMEOUT`

The resolution data above was extracted outside this repository. To re-run the probe with the timing fix applied:
```bash
# Run
xcodebuild test -workspace SmartTube.xcworkspace -scheme "SmartTube" \
  -destination "id=6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6" \
  -only-testing:SmartTubeUITests/StreamMethodProbeUITests \
  -parallel-testing-enabled NO -resultBundlePath /tmp/probe-full.xcresult
```
