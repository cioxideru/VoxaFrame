> Status: archived — classified from code on 2026-10-15.
> The prohibition is obsolete: the current fallback race invokes BotGuardWebViewRunner and injects minted tokens. The 4.1 changelog records adoption; PLAN-0003 tracks remaining acceptance. Do not follow the old prohibition.
> Current references: [architecture](../architecture.md), [open questions](../OPEN_QUESTIONS.md).

# Do NOT use BotGuard / PoToken / rqh=1 streams

**Decision**: BotGuard-based poToken generation was tried and removed. Do not re-add it.

## rqh=1 streams — skip, do not attempt to play

- **Never** attempt to play adaptive stream URLs that contain `/rqh/1/` in their path.
- The CDN (`googlevideo.com`) enforces `rqh/1` at the **segment level** — even if the playlist (`.m3u8`) returns HTTP 200, the actual media segments return HTTP 403.
- There is no way to bypass this without a `pot=` (poToken) URL parameter embedded in each segment URL, which requires BotGuard.
- The current guard in `PlaybackViewModel+Fallback.swift` (`attemptComposition`) is correct: skip any client whose first adaptive URL contains `/rqh/1/`.
- This applies to: TVHTML5, MWEB, ANDROID_VR, and all non-embeddable video responses from any client.

## Why it was removed
- WAA Create (`jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/Create`) returns a ~79KB binary with only field 3103 — the expected BgChallengeData proto fields (interpreterUrl, program, globalName) are absent.
- The WAA Create binary format changed; old JSPB parser finds nothing useful.
- Fallback using YouTube homepage to get the player JS is too slow (~8–12 s) for the test window, and unreliable in simulator.
- BotGuardClient.swift remains in the codebase but is **not wired up** anywhere.

## What to use instead
- For rqh=1 streams: skip them (current guard in `PlaybackViewModel+Fallback.swift`).
- The fix for `testAutoQualityAbove360p` is to fix the **WebCreator auth** — that client is the intended path for non-embeddable videos and should return clean adaptive streams without rqh=1.
- WebCreator (nameID=62) belongs on `www.youtube.com` (NOT googleapis.com). googleapis.com rejects it with `400 INVALID_ARGUMENT`.
- WebCreator requires **cookie-based SAPISID auth** (yt-dlp approach) — our TV OAuth2 Bearer token is rejected by both endpoints (www.youtube.com + Bearer → 400; googleapis.com + Bearer → 400 INVALID_ARGUMENT).
- See also: `fetchAttestationToken` in `InnerTubeAPI+Networking.swift` (legacy att/get, returns botguardData but is not used for solving).

## Files left untouched
- `BotGuardClient.swift` — kept for reference, not invoked
- `PoTokenProvider` protocol — kept, no active conformers
