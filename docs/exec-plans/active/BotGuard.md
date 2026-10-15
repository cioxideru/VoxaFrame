# BotGuard / PoToken — State and Migration Plan

- ID: PLAN-0003
- Status: active
- Owner: maintainer; no new executor assigned by this documentation review
- Reviewed: 2026-10-15
- Git boundary: `master`, HEAD `23284b15d990607bbfcab0f7db1cf6d978229149`; working tree has existing uncommitted source changes. Evidence below refers to that tree, not a new commit or release.
- Scope: the original objective and tasks below; documentation reconciliation only on this date.
- Constraints: preserve existing playback behavior and platform boundaries; no source changes in this review.
- Basis: [architecture](../../architecture.md), [decisions](../../adr/README.md), [open questions](../../OPEN_QUESTIONS.md).

Current state: parsing and WebKit minting/injection exist; the original plan mixes implemented
work with unverified CDN, client/session binding, dubbed-audio, and latency claims. Those claims
are not accepted by source inspection. [OQ-0006](../../OPEN_QUESTIONS.md#oq-0006--botguard-acceptance)
owns the remaining conditions.
Next slice: define a reproducible signed-in/out live matrix and record token availability,
client/session binding, segment response, audio tracks, and timing without logging credentials.
Blockers: suitable authenticated test sessions and live execution are not supplied by this review.
Alternatives C/D remain unselected options, not authorized work.

## Acceptance and evidence

The checkpoint outcomes below define the reconciled scope. Expected new implementation commit:
none assigned in this review. The Git boundary above is the inspection baseline; it is not an
acceptance commit for the original work. Independent review of these documentation changes is
pending coordinator review. An active checkpoint closes only after its relevant checks and review.

## Reconciliation checkpoints

| Checkpoint | Scope / observable result | Evidence | Status |
|---|---|---|---|
| PLAN-0003.CP1 | Scrambled WAA challenge parsing | `BotGuardClient.swift`, `BotGuardClientTests.swift` | implemented; not rerun |
| PLAN-0003.CP2 | WebKit minting and token application | `BotGuardWebViewRunner`, `PlaybackViewModel+FallbackRace.racePathA`, `InnerTubeAPI` token methods | implemented; not rerun |
| PLAN-0003.CP3 | Token lifetime and client/session behavior | `poTokenExpiry` is declared but unused; token checks are keyed by video ID | open |
| PLAN-0003.CP4 | Adaptive playback, dubbed audio, timing and monitoring | live matrix and monitoring evidence absent from this checkout | open / NOT RUN |

Implementation order and dependencies are retained in the original record below.
No new implementation commit or independent runtime acceptance is claimed. Historical results
belong to their original revisions. Current builds, unit tests, UI tests, and device checks:
`NOT RUN` in this documentation-only review. Next steps and remaining conditions are in
[open questions](../../OPEN_QUESTIONS.md).

## Original record

The following is the original analysis and task sequence, retained for history. Its future
tense, line numbers, and example code are not instructions to undo the current implementation.

> **What it unlocks:** native adaptive streaming at any quality without the WKWebView extraction layer — the same CDN access Android has.

> **Baseline commit (SmartTube):** `bce51e1b3cc1c9483fdbc4a2c40f4c9ccd13b173` — "Enhance audio track handling for YouTube HLS manifests"

---

## 1. What BotGuard Is

YouTube's CDN uses a challenge-response system called **BotGuard** to gate adaptive stream access. Any URL that contains `rqh=1` in its path will return HTTP 403 on media segments unless the `/player` request body and every stream URL carry a **Proof-of-Origin (PO) token** (`&pot=<base64>`).

The token proves that a real browser (or an authorised client) produced the request. Without it:
- All `c=IOS` adaptive URLs are `rqh=1` → unusable
- All `c=ANDROID_VR` adaptive URLs are `rqh=1` → 8s `loadTracks` stall (#208)
- Only the WKWebView spc= HLS path bypasses enforcement (uses the browser's own session cookie)

Android solves this via `PoTokenGate.getPoToken(client, videoId)` — a full BotGuard attestation pipeline that appends `&pot=...` to every adaptive URL before ExoPlayer touches them.

---

## 2. What Is Already Built

### Protocol and injection plumbing (complete, wired up)

```
InnerTubeModels.swift
  ╠═ public protocol PoTokenProvider: Sendable
  ║      func token(for videoId: String) async throws -> String
  ╠═ PlayerInfo.applyingPoToken(_ token: String) -> PlayerInfo
  ║      appends &pot=<token> to every adaptiveFormats URL
  ╚═ (called in InnerTubeAPI+Player.swift when poToken != nil)

InnerTubeAPI.swift
  ╠═ var poToken: String?           // cached token
  ╠═ var poTokenVideoId: String?    // videoId the token was minted for
  ╠═ var poTokenExpiry: Date?       // (reserved, not yet used)
  ╚═ let poTokenProvider: (any PoTokenProvider)?   // injected at init
```

**Zero-behaviour-change gate:** every injection site is guarded by `if let pot = poToken`. If `poTokenProvider` is nil (the current production default), the pipeline is identical to before. Enabling BotGuard requires only passing a `BotGuardClient()` at `InnerTubeAPI` construction.

### BotGuardClient.swift — full 5-phase pipeline (exists, blocked on input)

| Phase | What it does | Status |
|---|---|---|
| 1 | `WAA/Create` → interpreter JS URL + program + globalName | **Blocked** (see §3) |
| 2 | Load interpreter JS into `JSContext`, call `vm.a(program, …)` | ✅ implemented |
| 3 | `asyncSnapshotFn(callback, params)` → `botguardResponse` string | ✅ implemented |
| 4 | `WAA/GenerateIT` (botguardResponse) → `integrityTokenB64` | ✅ implemented |
| 5 | `webPoSignalOutput[0](integrityBytes)` → minter → mint(videoId) → base64 | ✅ implemented |

Key implementation details already handled:
- All JSContext work runs on a dedicated `jsQueue` (real OS thread, not Swift cooperative pool) — `DispatchSemaphore.wait()` inside is safe
- `Promise` resolution via pure-JS `then` handler + microtask pumping (avoids unreliable Swift block callbacks during JSC microtask drain)
- Multiple WAA Create response format strategies (JSON-array layouts, JSPB binary proto, nested/flat fields, URL-scan fallback)
- Dynamic VM discovery when `globalName` is empty (scans `globalThis` for an object with `.a` method)
- Full BotGuardClientTests.swift with fake interpreter JS (synchronous minter, Promise minter, Promise init variants)
- Reference: https://github.com/LuanRT/BgUtils (MIT)

---

## 3. The Blocker: WAA Create API Response Format

The WAA Create endpoint (`jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/Create`) has changed its response format. The current `BotGuardClient.fetchChallenge()` tries five parse strategies in sequence:

1. `outer[1]` is an inner JSON array with 5 elements → `[msgId, hash, url, program, globalName]`
2. `outer[1]` is an inner JSON array with 4 elements → `[hash, url, program, globalName]`
3. `outer[1]` is a JSPB binary proto blob → flat fields at proto field numbers 2, 5, 6
4. `outer[1]` is a JSPB binary proto blob → nested message in field 1
5. **Fallback:** treat `outer[1]` as raw program; fetch the current interpreter JS from the YouTube homepage `/s/player/.../base.js`

None of these strategies currently produces a working interpreter JS + program pair. The BgUtils project (the canonical reference for this protocol) tracks these format changes — the last confirmed-working response format in the code dates from when BotGuardClient was first written.

**Exact failure mode:** Phase 1 completes without throwing (falls through to fallback), but the fetched YouTube player JS is not the BotGuard interpreter VM — it is the full YouTube player — and `vm.a()` in Phase 2 fails to find a callable VM object.

---

## 4. Approaches to Fix It

### Option A — Fix WAA Create parsing ✅ IMPLEMENTED — commit `7404f0b`

**What changed:** The WAA Create endpoint now returns a **scrambled** `outer[1]` string (BgUtils v3.2+ format). The old implementation treated it as a binary protobuf blob and failed all 5 parse strategies. The new implementation:
1. Base64-decodes `outer[1]`
2. Adds 97 to each byte (mod 256) — the inverse of YouTube's subtraction scramble
3. UTF-8-decodes → JSON-parses the inner challenge array
4. Reads `wrappedScript` (inline VM JS) or `wrappedUrl` (URL to fetch VM JS from) from the new 6-element inner layout

All 17 `BotGuardClient` unit tests updated to mock the new scrambled format. 17/17 pass.

**What to do:**
1. Make a raw `WAA/Create` request with the existing key and requestKey and log the full binary response
2. Compare against the current BgUtils `parseChallengeData` implementation
3. Update the parse strategy in `fetchChallenge()` to match the current field layout

**How to test without running the full pipeline:**
```swift
// In BotGuardClientTests.swift — add a live network test (disabled by default):
// let client = BotGuardClient()
// let challenge = try await client.fetchChallenge()   // make fetchChallenge() internal
// XCTAssertFalse(challenge.interpreterJS.isEmpty)
// XCTAssertFalse(challenge.program.isEmpty)
```

**Reference:** https://github.com/LuanRT/BgUtils/blob/main/lib/utils/Challenge.ts — `parseChallengeData()` is updated whenever YouTube changes the WAA format.

**Risk:** YouTube changes the format periodically. This requires ongoing maintenance.

---

### Option B — WKWebView pot= extraction (no format chasing) ✅ IMPLEMENTED — commit `4a044ea`

Instead of running the BotGuard pipeline natively, extract the `pot=` token that the YouTube JS player has already computed inside the hidden WKWebView that we already load for HLS extraction.

**How it works:**
- The WKWebView already loads the YouTube watch page and executes the real YouTube JS player
- The player calls `yt.config_.WEB_PLAYER_CONTEXT_CONFIGS` which contains a signed `po_token` after BotGuard passes in the browser context
- Extract this value via `WKWebView.evaluateJavaScript("yt.config_.WEB_PLAYER_CONTEXT_CONFIGS[...].poToken")` after `hlsManifestUrl` is available

**What needs to change:**
1. In `tryWebViewHLS` (after WKWebView extracts `hlsManifestUrl`), also extract `poToken` from the page JS context
2. Pass the token to `InnerTubeAPI` via `applyPoToken(_:forVideoId:)` (add this method)
3. In the iOS client fetch path, call `applyingPoToken` before returning `PlayerInfo`

**Advantage:** No WAA API format maintenance. The browser computes the token correctly by definition; we just read it.

**Limitation:** pot= token is tied to the WKWebView session. If adaptive streams from the iOS client (`c=IOS`) are also rqh=1, they may need the token to be re-minted per-session using the same credentials. Works well for the same video the WKWebView loaded; cross-video reuse needs investigation.

**Implementation effort:** ~50 lines in `PlaybackViewModel+Fallback.swift` + `InnerTubeAPI.swift`

---

### Option C — Server-side attestation proxy

Run BotGuardClient on a server; the app fetches a short-lived token per videoId via a private HTTPS endpoint.

**Concern:** Creates a centralised infrastructure dependency and a privacy risk (server sees every videoId lookup). Not recommended.

---

### Option D — Embed bundled interpreter JS

Bundle a pinned copy of the BotGuard interpreter JS with the app (updating it periodically via app releases or a CDN fetch at launch).

**Concern:** The interpreter hash rotates frequently (observed every few days in BgUtils). An out-of-date bundled JS causes silent token generation failure. Higher maintenance burden than Option A.

---

## 5. What Changes in the Playback Pipeline Once It Works

With a valid `pot=` token, the WKWebView extraction layer becomes optional:

| Scenario | Today | With BotGuard |
|---|---|---|
| iOS adaptive (`c=IOS`, rqh=1) | Skip → WKWebView HLS | Direct DASH adaptive via `AVURLAsset` composition |
| Quality picker | Rebuild AVPlayerItem + new proxy | In-situ `preferredMaximumResolution` hint on existing item |
| Audio tracks (dubbed) | HLS `YT-EXT-AUDIO-CONTENT-ID` variant filter | Standard `AVMediaSelectionGroup` (if DASH MPD includes them) or same HLS path |
| 4K on tvOS | Capped at 1080p (HLS manifest limit) | 1440p / 2160p adaptive formats available |
| Cold start latency | ~6–14s (WKWebView JS eval + manifest fetch) | ~1–2s (iOS client player API response) |
| WKWebView dependency | Required for all rqh=1 videos | Optional fallback only |

**Fallback chain with BotGuard:**
```
fetchPlayerInfo(c=IOS) → applyingPoToken(pot) → attemptComposition(adaptive)
  → success (direct DASH)
  → failure → tryWebViewHLS (WKWebView spc= HLS, as today)
  → failure → muxed 360p
```

**DASH composition path** (currently bypassed for rqh=1 — see `#208` guard): `qualityCapVideoURL + bestAdaptiveAudioURL` are passed to `AVMutableComposition`. With valid `pot=`, the `rqh=1` CDN gate is satisfied and segments are served normally.

---

## 6. Wiring BotGuardClient Into Production

Once Phase 1 is unblocked (either by fixing WAA parsing or by Option B WKWebView extraction):

```swift
// In PlaybackViewModel (or wherever InnerTubeAPI is initialised):
let api = InnerTubeAPI(
    authToken: authToken,
    poTokenProvider: BotGuardClient()   // add this
)
```

That single change enables the entire pipeline — all injection points are already gated on `poToken != nil` with zero-behaviour fallback.

**Token refresh strategy (to add):**
- Cache the minted token in `InnerTubeAPI.poToken` (already stored)
- Invalidate when `poTokenVideoId != currentVideoId` (already checked at call site)
- YouTube pot= tokens are tied to (videoId, session); safe to reuse for the same video across seeks/quality switches

---

## 7. Open Questions

1. **Does the pot= token from WKWebView (Option B) actually get produced?** First empirical test run (2026-05-26, video `LSMQ3U1Thzw`, iOS Simulator): YouTube player in WKWebView did NOT include `serviceIntegrityDimensions.poToken` in its `/player` request body. The JS interceptor confirmed: `URL captured source=apiResponse` with no pot field. This means BotGuard challenges are not always issued by YouTube's server — the challenge appears conditionally based on session fingerprint risk score. To observe a pot token, try: authenticated session, fresh simulator, or a video that YouTube's anti-bot heuristics flag more aggressively.

2. **Does the pot= token from WKWebView (Option B) satisfy the CDN for `c=IOS` adaptive URLs?** The WKWebView runs as `c=WEB_REMIX`; pot= tokens may be client-scoped. Needs a live test: extract the WKWebView pot=, append to an `rqh=1` adaptive URL, make a range request, check HTTP status code.

3. **Does DASH adaptive from iOS client include dubbed audio tracks?** Android's in-memory MPD construction merges separate video + audio `adaptiveFormats` entries. If dubbed audio is only in HLS manifests (as separate language stream variants), the HLS proxy path remains necessary even with BotGuard.

4. **How often does the WAA Create response format change?** If we go with Option A, we need a monitoring strategy (e.g. a nightly CI job that hits the endpoint and validates the challenge parse succeeds).
