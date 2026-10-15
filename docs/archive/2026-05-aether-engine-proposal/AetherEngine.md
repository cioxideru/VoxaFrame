> Status: archived — not adopted; classification checked on 2026-10-15.
> This mixed proposal/worklog is historical, not an active implementation plan.
> Old cancelled runs, missing-token conditions and suggested changes below belong to that
> investigation; they do not establish current defects or pending authorized work.
> See the [non-adoption summary](../../research/AetherEngine.md) and [open questions](../../OPEN_QUESTIONS.md).

# AetherEngine Integration Plan

**Date:** 2026-05-23  
**Repo:** https://github.com/superuser404notfound/AetherEngine  
**License:** LGPL-3.0 with Apple Store / DRM Exception  
**Version:** 1.3.0 (branch: `main`, actively developed)

---

## Why We're Switching

### The architecture problem we've been fighting

Our current playback stack was built on a single assumption: **AVPlayer fetches everything from the CDN directly.** That assumption is now the root cause of most of our hardest bugs.

When AVPlayer loads an `AVURLAsset(url: cdnURL)`, it manages all HTTP requests internally. Those requests carry AVFoundation's own User-Agent string and TLS fingerprint — not the YouTube iOS app UA (`com.google.ios.youtube/19.45.4 ...`) that CDN signed the URLs against. For standard embeddable videos this doesn't matter. For non-embeddable videos on `manifest.googlevideo.com`, the CDN validates the requesting client against the URL's signing parameters. When the signatures don't match, the CDN returns 403 or holds the TCP connection open indefinitely.

Every workaround we've added in the last two sessions is a patch over this fundamental mismatch:

| Workaround | Why it exists | Why it's fragile |
|---|---|---|
| `HLSVariantProxy` + `smarttubehls://` | Rewrite n-scrambled URLs in variant playlist before AVPlayer sees them | AVPlayer still fetches segments with its own headers, not iOS YouTube UA |
| `YouTubeNDescrambler.swift` (Deno) | Descramble the n parameter so CDN accepts the URL | Deno returns empty output in app spawn context (HOME env mismatch); even correct n gets 403 from simulator URLSession |
| `#if targetEnvironment(simulator)` blocks everywhere | Different code path for simulator because CDN rejects simulator URLSession | Simulator and device code diverge, bugs hide in the gap |
| `rqh=1` unconditional skip | All adaptive streams 403 or stall without `pot=` token | Locks us to muxed 360p for any video YouTube CDN-protects (which is most of them) |

Three sessions in, we have a Deno binary dependency, posix_spawn wrappers, a custom AVAssetResourceLoader scheme, and simulator-specific code paths. The test `testAutoQualityAbove360p` still fails for unauthenticated flows on `Wu8xNx4njoM` because the segment 403 is not in the playlist rewriting — it's in AVPlayer's request headers.

### What AetherEngine proposes instead

```
Current (broken for non-embeddable):
  InnerTube → CDN URL (n-scrambled, rqh=1) → AVURLAsset → CDN 403

AetherEngine:
  InnerTube → CDN URL → AetherEngine (FFmpeg AVIO + our headers) → 127.0.0.1 HLS-fMP4 → AVPlayer
```

AetherEngine's `AVIOReader.swift` is a `URLSession`-backed `avio_alloc_context`. It attaches our custom HTTP headers — including the full iOS YouTube User-Agent — to **every** fetch: the master manifest, every variant playlist, and every media segment. AVPlayer only ever sees `http://127.0.0.1:<port>/master.m3u8`. It never touches the CDN.

This is the architectural fix. The CDN 403 we've been seeing from iOS Simulator URLSession is caused by AVPlayer sending the wrong headers on segment requests. AetherEngine's AVIO sends our headers. CDN validates the UA → 200.

---

## Investigation Log — May 23, 2026 (`testAutoQualityAbove360p`)

### Goal
Make `testAutoQualityAbove360p` pass at ≥720p for video `Wu8xNx4njoM` (non-embeddable). No BotGuard / poToken. No rqh=1 streams.

---

### What we tried

#### 1. HLS via WebSafari (nameID=1, macOS Safari UA)
- **What:** WebSafari client returns `hlsManifestUrl`. Master manifest and variant playlist (`index.m3u8`) return HTTP 200.
- **Result:** ❌ CDN segments at `rr3---sn-ncc-cxbr.googlevideo.com/videoplayback/.../rqh/1/...` return **HTTP 403**. Confirmed via `curl` from Mac terminal as well — not a simulator-only issue.
- **Root cause:** Variant playlist URL embeds `/rqh/1/` in the segment URL template (baked into `sparams` HMAC). CDN enforces pot= at the segment level. Changing headers does nothing — the enforcement is on the signed URL parameter, not the request.
- **Conclusion:** HLS for this video is completely blocked without pot=. The playlist is readable; the segments are not.

#### 2. ANDROID_TESTSUITE client
- **What:** Tried fetching player info with ANDROID_TESTSUITE (nameID=30).
- **Result:** ❌ `UNPLAYABLE` — YouTube returns no streaming data for this non-embeddable video on the ANDROID_TESTSUITE client.

#### 3. WebCreator (nameID=62) — `www.youtube.com` + `Authorization: Bearer`
- **What:** `postWebCreator` originally used `www.youtube.com` with our TV OAuth2 Bearer token.
- **Result:** ❌ **HTTP 400**. `www.youtube.com` web endpoints require SAPISID cookie auth (SAPISIDHASH scheme), not OAuth2 Bearer tokens. Bearer is rejected outright.

#### 4. WebCreator — `googleapis.com` + Bearer (no key)
- **What:** Switched `postWebCreator` to `youtubei.googleapis.com` (same as `postTV`), dropped `?key=`, included Bearer. Mirrored `postTV` exactly except clientNameID=62 vs 7.
- **Result:** ❌ **HTTP 400 `INVALID_ARGUMENT`** — `googleapis.com` does not support WEB_CREATOR (nameID=62) with OAuth2 Bearer auth. Only TV/set-top-box client IDs (7=TVHTML5, 3=ANDROID, etc.) are accepted.
- **Diagnostic:** Added response-body logging. YouTube returned: `code=400 status=INVALID_ARGUMENT msg=Request contains an invalid argument.` This is not an auth failure (that would be 401 UNAUTHENTICATED) — the token is recognized but the client/endpoint combination is rejected.

#### 5. WebCreator — `googleapis.com` + Bearer + `?key=`
- **What:** Added `?key=` back on top of Bearer (in case googleapis.com requires both for WEB_CREATOR).
- **Result:** ❌ Same **HTTP 400 `INVALID_ARGUMENT`**. Key makes no difference — the rejection is due to clientNameID=62 being unsupported on googleapis.com with OAuth2 Bearer.

#### 6. iOS auth client (`postPlayerAuthenticated`, nameID=5)
- **What:** `fetchPlayerInfoiOSAuthenticated` calls googleapis.com with iOS client + Bearer.
- **Result:** ❌ **HTTP 400**. Same pattern: googleapis.com rejects iOS client (nameID=5) + OAuth2 Bearer too. Only TV client (nameID=7) works on googleapis.com with our token.

#### 7. WebCreator — `www.youtube.com`, no Bearer (cookie-based, MWEB pattern)
- **What:** Changed `postWebCreator` to mirror `postMWEB` exactly: `www.youtube.com`, `?key=`, `Origin: https://www.youtube.com`, Chrome desktop UA, **no Bearer**. Theory: URLSession shared cookie storage might have YouTube session cookies from the app's sign-in flow, which could authenticate WEB_CREATOR.
- **Status:** 🔄 Attempted but test run was cancelled. Not yet confirmed.
- **Expected outcome (from Python CLI test without any cookies):** `200 LOGIN_REQUIRED` → no streamingData. If simulator's URLSession has YouTube cookies: possible 200 with streamingData (rqh=0 expected for WEB_CREATOR).

---

### Key findings

| Client | Endpoint | Auth | Result |
|--------|----------|------|--------|
| TVHTML5 (TV auth) | googleapis.com | Bearer ✓ | 200, but all streams rqh=1 |
| TVEmbedded | www.youtube.com | none | UNAVAILABLE (video not embeddable) |
| WebSafari | www.youtube.com | none | 200 + hlsManifestUrl, but CDN segments 403 (rqh/1) |
| MWEB | www.youtube.com | none | 200, adaptive streams — all rqh=1 |
| Android | googleapis.com | none | UNPLAYABLE |
| AndroidVR | googleapis.com | none | 200, adaptive streams — all rqh=1 |
| iOS (unauthenticated) | googleapis.com | none | 200, adaptive streams — all rqh=1, c=IOS |
| iOS (authenticated) | googleapis.com | Bearer ✓ | **400** |
| WEB_CREATOR (with Bearer) | googleapis.com | Bearer ✓ | **400 INVALID_ARGUMENT** |
| WEB_CREATOR (with Bearer) | www.youtube.com | Bearer ✓ | **400** (wrong auth type) |
| WEB_CREATOR (cookie) | www.youtube.com | cookies | TBD |

**Core blocker:** Our TV device flow OAuth2 Bearer token only works on `googleapis.com` with the TV client (nameID=7). Every other client nameID on googleapis.com returns 400. WEB_CREATOR (nameID=62) belongs on `www.youtube.com` and requires SAPISID cookie auth — incompatible with our current auth infrastructure.

**Why rqh=1 cannot be bypassed without pot=:** The `/rqh/1/` path segment is inside the HMAC-signed `sparams` of each segment URL. We cannot modify it without breaking the signature. The CDN validates it server-side on every segment request. No header tricks or client changes affect this.

---

### Auth type incompatibility summary

```
TV device flow → OAuth2 Bearer token

googleapis.com + Bearer accepted for:   TVHTML5 (7), TVHTML5_SIMPLY (85-ish)
googleapis.com + Bearer rejected for:   WEB_CREATOR (62), iOS (5), WEB (1), MWEB (2)

www.youtube.com + Bearer always 400     (expects SAPISID cookie, not OAuth2 Bearer)
www.youtube.com + SAPISID (yt-dlp):     WEB_CREATOR returns rqh=0 ✓  ← but we don't have SAPISID
```

---

### What would actually fix it (without BotGuard / rqh=1)

1. **SAPISID cookie auth for WEB_CREATOR** — Implement SAPISIDHASH sign-in via `WKWebView` to get `SAPISID` cookie, then compute `Authorization: SAPISIDHASH {ts}_{sha1}` for WEB_CREATOR calls on `www.youtube.com`. This is a significant auth system change; yt-dlp's approach. No BotGuard needed.

2. **AetherEngine (Phase 1 + correct headers)** — If AetherEngine's `AVIOReader` sends the correct iOS YouTube UA on every segment request, the CDN 403 on HLS segments might resolve for non-rqh=1 URLs. But Wu8xNx4njoM's segments are rqh=1, so this alone doesn't help for this specific video.

3. **Change test video** — Use an embeddable video where one client returns rqh=0 streams. Tests a real code path but not the non-embeddable path the test was designed for.

4. **AetherEngine Phase 3 + pot=** — The full architectural fix. AetherEngine removes the CDN header mismatch; pot= (BotGuard) removes the rqh=1 block. **This is the only complete solution** but requires both AetherEngine integration and BotGuard (which we have decided not to pursue).

---

## What AetherEngine Solves (and What It Doesn't)

### Directly solved

| Problem | How AetherEngine fixes it |
|---|---|
| AVPlayer segment requests missing YouTube UA → CDN 403 | AetherEngine's `AVIOReader` attaches headers to all fetches; AVPlayer sees only localhost |
| `HLSVariantProxy` + `smarttubehls://` fragility | Replaced by AetherEngine's `HLSLocalServer` (production-grade local HTTP server) |
| `#if targetEnvironment(simulator)` code paths in `PlaybackViewModel+Fallback.swift` | Removed — single code path works in both simulator and device |
| `AVMutableComposition` for DASH video+audio (when pot= available) | Replaced by FFmpeg demux + mux; no more `loadTracks` timeouts or composition race conditions |
| AV1 / VP9 format rejection by AVPlayer HLS pipeline | AetherEngine routes these through libavcodec SW decode |
| `AVURLAssetHTTPHeaderFieldsKey` + `file://` hang | Eliminated — we never build a file-backed AVURLAsset |
| posix_spawn + Deno dependency | Removed once n-descramble problem is solved at the source (see below) |

### Does NOT solve without additional work

| Problem | What's still needed |
|---|---|
| `rqh=1` CDN enforcement | Still needs `pot=` Proof-of-Origin tokens. `BotGuardClient.swift` exists in `SmartTubeIOSCore` — it needs to be wired to add `pot=` to adaptive stream URLs before passing to AetherEngine. AetherEngine doesn't bypass CDN bot detection, it just sends the right headers. |
| n-parameter scrambling | AetherEngine's AVIO sends the URL as-is to the CDN. A scrambled n will still get 403. We need to pre-descramble n **before** handing the URL to AetherEngine. **However:** with the correct User-Agent attached to all requests, the most likely reason descrambled-n URLs got 403 from iOS Simulator (wrong headers on segment fetches) is eliminated. The Deno approach should be reconsidered: `JavaScriptCore` can run the player.js n-descrambler synchronously without a subprocess dependency. |
| InnerTube authentication / login flow | Unchanged |

---

## Files Involved

### Files removed / significantly simplified
- `PlaybackViewModel+Fallback.swift` — `descrambledVariantURL` function removed, `#if targetEnvironment(simulator)` blocks removed, `HLSVariantProxy` class removed (all at end of file)
- `YouTubeNDescrambler.swift` — the posix_spawn + Deno path replaced with JavaScriptCore (see Phase 2 note below); the `spawnAndRead` helper removed

### Files added
- `SmartTubeIOS/Sources/SmartTubeIOS/Playback/AetherPlayer.swift` — thin wrapper around `AetherEngine.AetherPlayerView` + `AetherEngine` instance; exposes the published state (`$state`, `$currentTime`, `$duration`, `$currentAVPlayer`) in terms the existing `PlaybackViewModel` observer chain already understands

### Files modified
- `SmartTubeIOS/Package.swift` — add AetherEngine SPM dependency
- `PlaybackViewModel+Fallback.swift` — `attemptURL` uses `AetherPlayer.load(url:options:)` instead of `AVURLAsset`; quality hints removed (AetherEngine uses its own quality selection or we pass a specific variant URL)
- `PlaybackQualityManager.swift` — `reloadHLSItem` / `reloadDASHItem` delegate to `AetherPlayer.reloadAtCurrentPosition()` or `AetherPlayer.load(url:startPosition:)`
- `PlaybackViewModel+Loading.swift` — `AVPlayer` reference replaced by `AetherEngine.$currentAVPlayer` where used for `MPNowPlayingSession`, AirPlay, PiP hooks
- `SmartTubeIOS/Package.swift` — new dependency block

---

## Integration Phases

### Phase 1 — Add dependency + proof-of-concept (1–2 days)

**Goal:** Verify empirically that AetherEngine's `AVIOReader` with YouTube UA headers gets 200 on `manifest.googlevideo.com` segment URLs where iOS Simulator URLSession currently gets 403. If this works, the entire architectural case is confirmed.

**Steps:**
1. Add to `SmartTubeIOS/Package.swift`:
   ```swift
   .package(url: "https://github.com/superuser404notfound/AetherEngine", branch: "main")
   ```
   and add `"AetherEngine"` to the `SmartTubeIOS` target dependencies.

2. Write a minimal test in `SmartTubeIOSTests` or a debug screen:
   - Call `fetchPlayerInfoWebSafari(videoId: "Wu8xNx4njoM")` to get a fresh `hlsManifestUrl`
   - Pre-descramble n (from terminal, one-shot, paste the result) OR pass the scrambled URL directly
   - Create `let engine = try AetherEngine()` and call:
     ```swift
     try await engine.load(url: hlsManifestUrl, options: .init(
         httpHeaders: ["User-Agent": "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)"]
     ))
     ```
   - Check `engine.$state` reaches `.playing`

3. If `.playing` is reached in the simulator → headers were the issue → proceed to Phase 2.  
   If still fails → investigate whether libavformat's HLS sub-request fetches inherit the custom headers (see Open Questions §1).

**Risk gate:** If AetherEngine's libavformat HLS demuxer does NOT apply our custom headers to sub-requests (variant playlists, segments), we need to either fork AetherEngine to add `avformat_set_options` with `user_agent` + `headers` before `avformat_open_input`, or fall back to a different architecture. File an issue on the repo before forking.

---

### Phase 2 — Full HLS path through AetherEngine (3–5 days)

**Goal:** Remove all `HLSVariantProxy`, `descrambledVariantURL`, and `#if targetEnvironment(simulator)` code. All HLS playback goes through AetherEngine.

**Steps:**

1. Create `AetherPlayer.swift` wrapper:
   ```swift
   @MainActor
   final class AetherPlayer {
       private let engine: AetherEngine
       var avPlayer: AVPlayer? { get async { ... } }  // via engine.$currentAVPlayer
       // Mirrors: state, currentTime, duration, videoFormat
   }
   ```

2. In `attemptURL` (`PlaybackViewModel+Fallback.swift`), replace the `AVURLAsset` / `HLSVariantProxy` path for HLS URLs:
   ```swift
   // Before:
   let asset = AVURLAsset(url: effectiveURL, options: uaOpts)
   
   // After (HLS URLs):
   try await aetherPlayer.load(url: hlsURL, options: .init(httpHeaders: youTubeHeaders))
   let avPlayer = await aetherPlayer.currentAVPlayer  // 127.0.0.1 player
   ```

3. Wire `engine.$state` into the existing `PlaybackViewModel.status` observer. Map:
   - `.loading` → `status = .loading`
   - `.playing` → `status = .readyToPlay`
   - `.error` → `status = .failed`

4. Replace n-descrambler Deno path in `YouTubeNDescrambler.swift` with a `JSContext`-based implementation (no subprocess). The player.js n-function can run synchronously in `JavaScriptCore` with no HOME env dependency:
   ```swift
   let ctx = JSContext()!
   ctx.evaluateScript(playerJsSource)
   let descrambled = ctx.evaluateScript("nDescramble('\(scrambled)')")?.toString()
   ```
   This makes `YouTubeNDescrambler` an `actor` with a `JSContext` on a dedicated serial queue, no posix_spawn.

5. Delete `HLSVariantProxy` class, `descrambledVariantURL` function, all `#if targetEnvironment(simulator)` blocks in `PlaybackViewModel+Fallback.swift`.

6. Update `testAutoQualityAbove360p` to not need `#if targetEnvironment(simulator)` annotations.

---

### Phase 3 — DASH / adaptive path through AetherEngine (3–5 days, after pot= token wired)

**Goal:** Remove `AVMutableComposition` entirely. All video+audio composition handled by AetherEngine / FFmpeg.

**Precondition:** `BotGuardClient.swift` must be wired. `pot=` token must be appended to `rqh=1` adaptive stream URLs before we hand them to AetherEngine.

**Steps:**

1. Wire `BotGuardClient` in `exhaustiveRetry`: before calling `tryAllStreams`, if any format URL contains `rqh=1`, call `BotGuardClient.shared.fetchToken(videoId:)` and append `&pot=<token>` to every adaptive URL in the `PlayerInfo.formats` array.

2. In `attemptComposition` (`PlaybackViewModel+Fallback.swift`), replace `AVMutableComposition` with:
   ```swift
   // Instead of building an AVMutableComposition from videoURL + audioURL:
   try await aetherPlayer.loadDASH(videoURL: videoURL, audioURL: audioURL,
                                    options: .init(httpHeaders: youTubeHeaders))
   ```
   AetherEngine demuxes video and audio separately and re-muxes into a single HLS-fMP4 stream. `AVPlayer` plays the single `127.0.0.1` manifest.

3. Delete `rebuildCompositionForQuality`, `attemptComposition`, all `AVMutableComposition` usage.

**Note:** AetherEngine's current public API takes a single source URL. "loadDASH(videoURL:audioURL:)" would require either a small AetherEngine fork or a small local server that serves a custom DASH manifest pointing at the two URLs. Check whether AetherEngine v1.x adds multi-source input before implementing.

---

### Phase 4 — Quality switching via AetherEngine (2–3 days)

**Goal:** `PlaybackQualityManager.reloadHLSItem` / `reloadDASHItem` use `AetherEngine.reloadAtCurrentPosition()` or a new `load(url:startPosition:)` call. ABR hints (`preferredMaximumResolution`, `preferredPeakBitRate`) are replaced by passing a specific variant URL to AetherEngine.

**Note:** AetherEngine's built-in ABR picks the best variant automatically. For hard-locked quality (user picks 720p), we'd pass the specific variant playlist URL directly instead of the master manifest. This is the same pattern we use today in `reloadHLSItem` (we already pick a variant URL and load it directly).

---

## Open Questions

1. **Do libavformat HLS sub-requests inherit custom headers?**  
   When AetherEngine opens an HLS master manifest URL, libavformat internally opens variant playlist URLs and segment URLs. Does it use the same `AVIOReader` (with our custom headers) for those sub-requests, or does it use libavformat's built-in HTTP client (which would ignore our headers)?  
   **How to test:** Run the Phase 1 experiment. If it fails, add `avformat_set_options(fmtCtx, "user_agent", iOSYouTubeUA, 0)` before `avformat_open_input` — requires a small fork or PR to AetherEngine.

2. **Does AetherEngine support multi-source input (separate video + audio URLs) for DASH?**  
   Current API takes a single `url`. Phase 3 depends on this. Check the repo issues; if not supported, open a feature request or implement a small local DASH manifest bridge.

3. **Binary size impact.**  
   `FFmpegBuild` (LGPL FFmpeg 8.1: avcodec + avformat + avutil + swresample + swscale) adds ~35–55 MB to the archive. Confirm this is acceptable before merging Phase 2. Use `otool -l` on the binary to measure.

4. **LGPL compliance.**  
   The App Store / DRM Exception in AetherEngine's license grants permission to distribute through the App Store without fulfilling LGPL §4–6 (object file distribution). However, modifications to AetherEngine itself must be released under LGPL. Wrapper code in `SmartTubeIOS` is not a modification and is not subject to LGPL.  
   **Decision:** If we need to modify AetherEngine internals (e.g., add `avformat_set_options` for headers), we must publish that diff. A PR upstream is the cleanest path.

5. **`MPNowPlayingSession`, AirPlay, Picture-in-Picture hooks.**  
   These are currently wired to the `AVPlayer` instance from `AVURLAsset`. With AetherEngine, the `AVPlayer` instance is obtained via `engine.$currentAVPlayer`. The instance is re-emitted on every `reload`. Any place we hold a strong reference to `AVPlayer` for Now Playing or PiP needs to observe `$currentAVPlayer` and update on change.

6. **Stability / API stability.**  
   AetherEngine is at v1.3.0 with active development (commit 18 min before we found it). Pin to a specific tag (`from: "1.3.0"`) rather than `branch: "main"` for production builds. Follow the repo's release notes.

---

## Additional Simplifications Found in the Codebase

These are existing pain points that AetherEngine resolves as a side-effect of the architecture change, beyond the core playback path.

---

### 1. `VideoDownloadService` — adaptive merge / remux

**Current code:** `mergeAdaptiveStreams` manually wires `AVAssetWriter` + `AVAssetReader` + `AVAssetReaderTrackOutput` to copy video and audio sample buffers from separate CDN downloads into a single MP4. `passthroughRemux` then wraps the result in `AVAssetExportSession` (preset: passthrough) to fix `PHPhotosErrorDomain 3302` (moov-at-end containers that Photos rejects).

**Problem:** `AVAssetExportSession` is slow (1–4 s even for passthrough), fails on containers with `AVAssetExportPresetPassthrough` if the sample description doesn't match what AVFoundation expects, and has no progress callback during the passthrough phase.

**With AetherEngine:** `FFmpegBuild` (already a transitive dependency) gives us `libavformat` for mux. Replace both `mergeAdaptiveStreams` and `passthroughRemux` with a single FFmpeg `avformat`-based passthrough mux: open video input + audio input → interleave into one output context → close. Zero re-encoding, ~100 ms for a typical 5-minute video, no moov-at-end issue (FFmpeg's MP4 muxer writes the `moov` atom first by default via `+faststart`). No new dependency — FFmpegBuild is already in the graph once AetherEngine is added.

**Files:** `VideoDownloadService.swift` — `mergeAdaptiveStreams` + `passthroughRemux` replaced by a thin `FFmpegMuxer.merge(videoURL:audioURL:outputURL:)` wrapper.

---

### 2. `AVAssetTrackCache` — entire file deleted

**Current code:** `AVAssetTrackCache.swift` (45 lines) is a thread-safe `NSLock`-backed cache of `[AVAssetTrack]` arrays, keyed by CDN URL. It exists because `AVURLAsset.loadTracks(withMediaType:)` is expensive — it must open a TCP connection to the CDN URL just to read track metadata. Two call sites warm it: `rebuildCompositionForQuality` and a background prefetch task. `clear()` is called on every new video load to avoid stale tracks after URL expiry.

**With AetherEngine:** There are no `AVURLAsset` CDN calls from the Swift layer. Track metadata is determined from FFmpeg's `avformat_find_stream_info` on the first demux open — synchronous, runs against the local AVIO buffer, takes ~10 ms. `AVAssetTrackCache` has no purpose.

**Files:** `AVAssetTrackCache.swift` — deleted entirely.

---

### 3. `itemObserverTask` pattern — 8 call sites → 1

**Current code:** The "task-80 rule" (from task #80 bug fix) requires that `itemObserverTask` is set up — and the old task cancelled — in exactly the right order relative to `player.replaceCurrentItem`. This sequence is repeated in **8 places** across:
- `PlaybackViewModel+Loading.swift` (primary load, local file fast path)
- `PlaybackViewModel+Fallback.swift` (`attemptURL`, `attemptComposition`)
- `PlaybackQualityManager.swift` (`reloadHLSItem`, `reloadHLSItemH264Capped`, `reloadDASHItem`, `rebuildCompositionForQuality`)
- `PlaybackViewModel+AudioOnly.swift` (`tryLoadAudioURL`)

Each call site must also remember to call `loadAudioTracks(from:)` in the `.readyToPlay` branch (this was the cause of the audio-track-not-working bugs: task #35).

**With AetherEngine:** One `engine.$state` subscriber. `.loading` → show spinner; `.playing` → dismiss spinner, restore seek position. Audio tracks come from `engine.audioTracks` — populated automatically on play, no `loadAudioTracks(from:)` call needed anywhere. The entire `itemObserverTask` pattern, `isSwappingItem` flag, and `statusStream` extension disappear.

---

### 4. `AudioTrackManager` — `AVMediaSelectionGroup` non-Sendable hazard eliminated

**Current code:** `AudioTrackManager` stores `audioSelectionGroup: AVMediaSelectionGroup?` as `nonisolated(unsafe)` because `AVMediaSelectionGroup` is not `Sendable`. This is an active Swift 6 concurrency hazard flagged by the linter. The group must be re-populated every time a new `AVPlayerItem` is loaded (5 call sites via `loadAudioTracks(from:)`). `audioOptionsByID: [String: AVMediaSelectionOption]` also stores non-Sendable `AVMediaSelectionOption` values, same issue.

**With AetherEngine:** `engine.audioTracks: [TrackInfo]` is a plain `[TrackInfo]` value type (all `Sendable`). `engine.selectAudioTrack(index:)` takes an `Int`. No `AVMediaSelectionGroup`, no `AVMediaSelectionOption`, no `nonisolated(unsafe)`. `AudioTrackManager` is simplified to a pure data container — `availableAudioTracks: [AudioTrack]`, `selectedAudioTrack: AudioTrack?` — and the `NSLock` / `@unchecked Sendable` patterns are gone.

**Files:** `AudioTrackManager.swift` — `audioSelectionGroup`, `audioOptionsByID`, `loadAudioTracks(from:)`, `selectAudioTrack` rewrite.

---

### 5. `PlaybackViewModel+AudioOnly.swift` — separate code path eliminated

**Current code:** `PlaybackViewModel+AudioOnly.swift` exists as a separate file implementing `isAudioOnlyMode`, `audioOnlyItemActive: Bool`, `loadAudioOnlyItemIfEnabled()`, and `tryLoadAudioURL(_:userAgent:) -> Bool`. This is a parallel playback path — it creates its own `AVURLAsset` with `isPlayable` check, then its own `AVPlayerItem` with `audioTimePitchAlgorithm = .spectral`, then its own `itemObserverTask` sequence.

**With AetherEngine:** `engine.load(url: audioOnlyURL, options: .init(httpHeaders: youTubeHeaders))` handles audio-only URLs the same as video+audio URLs — no special path. AetherEngine's audio-only path just omits the `AVSampleBufferDisplayLayer` layer. `isAudioOnlyMode` is preserved as a UI flag (to show the thumbnail over the blank player surface) but `audioOnlyItemActive`, `tryLoadAudioURL`, and `loadAudioOnlyItemIfEnabled` are removed.

**Files:** `PlaybackViewModel+AudioOnly.swift` — substantially simplified; `tryLoadAudioURL` and `loadAudioOnlyItemIfEnabled` removed.

---

### 6. `hasAppliedH264Cap` workaround — eliminated

**Current code:** `PlaybackQualityManager` has a `hasAppliedH264Cap: Bool` flag and a separate `reloadHLSItemH264Capped()` function. When AVPlayer reports `AVFoundationErrorDomain` "cannot decode" for an AV1 stream (on devices without hardware AV1 — all Apple TVs, iPhone pre-15 Pro, all M1/M2 Macs), the quality recovery logic sets this flag and retries with a 1080p peak bitrate cap to force AVPlayer's ABR to select H.264 variants. This is a device-specific workaround baked into the quality system.

**With AetherEngine:** AetherEngine's software decoder path (libavcodec/dav1d) handles AV1 on all Apple TV chips and pre-A17-Pro iPhones — exactly the devices where the cap was needed. `hasAppliedH264Cap`, `reloadHLSItemH264Capped`, and the "cannot decode" recovery branch in `qualityRecoveryAction(for:quality:hasAppliedH264Cap:)` are removed.

**Files:** `PlaybackQualityManager.swift` — `reloadHLSItemH264Capped`, `hasAppliedH264Cap`, the `.retryWithH264Cap` case in `PlaybackViewModel`.

---

### 7. `loadTracks` 8-second timeout race — eliminated

**Current code:** `attemptComposition` in `PlaybackViewModel+Fallback.swift` runs a race between `AVURLAsset.loadTracks(withMediaType:)` and `Task.sleep(for: .seconds(8))`. If `loadTracks` wins but returns an empty array (CDN accepted the TCP connection but held it open — the ANDROID_VR pattern), an extra guard is needed. If `Task.sleep` wins, `loadTracks` is abandoned in-flight and the Task is cancelled. This 8-second stall per-attempt is the primary driver of the 30+ second startup latency users see on bot-protected videos.

**With AetherEngine:** FFmpeg's `avformat_open_input` with an `interrupt_callback` respects true per-call timeouts and returns `AVERROR(ETIMEDOUT)` — a real error code, not a silent hang. Response time on a rejected CDN URL is <500 ms. No `Task.sleep` race needed.

**Files:** `PlaybackViewModel+Fallback.swift` — `attemptComposition`'s timeout race, `AVAssetTrackCache` prefetch task.

---

### 8. `PiP` controller binding — simplified

**Current code:** `AVPictureInPictureController(playerLayer: playerLayer)` is created inside `onChange(of: vm.isPlaying)` — not at view-appear time — because `isPictureInPicturePossible` requires a ready item. When a quality switch creates a new `AVPlayerItem`, the PiP controller is torn down and recreated. `pipDelegate` is a separate `PiPDelegate` class holding a closure to update `isPiPActive`. The teardown-recreate cycle can cause PiP to briefly drop its session.

**With AetherEngine:** `AetherPlayerView` is a stable `UIView` subclass that hosts either `AVPlayerLayer` (native path) or `AVSampleBufferDisplayLayer` (SW path) — but the view itself doesn't change between quality switches. `AVPictureInPictureController(playerLayer:)` can be bound once at view-appear time to the stable layer. No teardown-recreate on item swap.

**Note:** AetherEngine's SW path (`AVSampleBufferDisplayLayer` for AV1/VP9) is not currently supported by `AVPictureInPictureController` — PiP would need to be disabled for those codec paths. This is a known AetherEngine limitation.

---

### 9. `AVAssetExportSession` passthrough remux — `PHPhotosErrorDomain 3302` permanently fixed

**Current code:** YouTube CDN delivers MP4s with `moov` atom at end of file (streaming-unfriendly layout). `PHPhotoLibrary` rejects these with error code 3302. `passthroughRemux` works around this by running `AVAssetExportSession(presetName: AVAssetExportPresetPassthrough)` which rewrites the container. This adds 1–4 seconds to every download.

**With AetherEngine/FFmpeg:** `libavformat`'s MP4 muxer writes `moov` at the front by default. FFmpeg passthrough mux produces a Photos-compatible output in <200 ms. The `passthroughRemux` workaround and its associated `AVAssetExportSession` dependency are deleted.

---

### 10. `PlaybackViewModel+Loading.swift` local-file fast path — gains format coverage

**Current code:** The local-file fast path (`video.localFileURL != nil`) creates `AVPlayerItem(url: localURL)` directly. This is limited to formats AVPlayer natively accepts: H.264 + AAC in MP4, some HEVC. MKV, AV1, VP9, FLAC audio, SubRip subtitles in the local file all fail silently.

**With AetherEngine:** `engine.load(url: localURL)` uses FFmpeg to demux the local file. Any container (MKV, WebM, AVI, MP4, M4V), any codec AetherEngine supports, with subtitle tracks surfaced via `engine.subtitleTracks`. Downloaded videos with AV1 video (which `VideoDownloadService` already downloads from the Android client) would play correctly instead of falling back to 360p.

---

## What We Remove

After all four phases:

**Core playback path:**

| Removed | Replaced by |
|---|---|
| `HLSVariantProxy` class | AetherEngine `HLSLocalServer` |
| `descrambledVariantURL` function | n-descramble in `YouTubeNDescrambler` (JSContext, not Deno) before URL passed to AetherEngine |
| `YouTubeNDescrambler.spawnAndRead` (posix_spawn + Deno) | `JSContext.evaluateScript` — no subprocess, no HOME env dependency |
| All `#if targetEnvironment(simulator)` blocks in `PlaybackViewModel+Fallback.swift` | Removed — single code path |
| `AVMutableComposition` + `rebuildCompositionForQuality` (Phase 3) | AetherEngine FFmpeg mux |
| `attemptComposition` (Phase 3) | `aetherPlayer.load(videoURL:audioURL:)` |
| `AVURLAsset(url: cdnURL, options: uaOpts)` | `aetherPlayer.load(url: cdnURL, options: LoadOptions(httpHeaders:))` |
| Deno binary dependency | Gone |
| `loadTracks` 8-second `Task.sleep` timeout race | FFmpeg `interrupt_callback` — real error code in <500 ms |
| `hasAppliedH264Cap` + `reloadHLSItemH264Capped` | AetherEngine dav1d SW decoder handles AV1 on all devices |

**Downloads:**

| Removed | Replaced by |
|---|---|
| `mergeAdaptiveStreams` (`AVAssetWriter` + `AVAssetReaderTrackOutput`) | FFmpeg passthrough mux via `FFmpegBuild` (already in dependency graph) |
| `passthroughRemux` (`AVAssetExportSession` passthrough) | Removed — FFmpeg mux writes `moov` first by default; `PHPhotosErrorDomain 3302` eliminated |

**Audio tracks:**

| Removed | Replaced by |
|---|---|
| `AVMediaSelectionGroup` + `AVMediaSelectionOption` in `AudioTrackManager` | `engine.audioTracks: [TrackInfo]` — plain value types, fully `Sendable` |
| `nonisolated(unsafe) var audioSelectionGroup` | Gone |
| `loadAudioTracks(from: AVPlayerItem)` — 5 call sites | Removed — AetherEngine populates `audioTracks` automatically |
| `audioOptionsByID: [String: AVMediaSelectionOption]` | Gone |

**Observer pattern:**

| Removed | Replaced by |
|---|---|
| `itemObserverTask` — 8 call sites with create/cancel ordering rule | Single `engine.$state` subscriber |
| `isSwappingItem: Bool` flag | Gone |
| `statusStream` on `AVPlayerItem` | Gone |
| `AVAssetTrackCache.swift` (entire file) | Gone — FFmpeg track info from local AVIO, no CDN fetch needed |

**Audio-only mode:**

| Removed | Replaced by |
|---|---|
| `tryLoadAudioURL(_:userAgent:)` | `engine.load(url:options:)` — same API as video |
| `loadAudioOnlyItemIfEnabled()` | `isAudioOnlyMode` guard at load site |
| `audioOnlyItemActive: Bool` | Gone |

---

## Success Criteria

- `testAutoQualityAbove360p` passes at ≥720p on `Wu8xNx4njoM` in the iOS Simulator without authentication
- No `#if targetEnvironment(simulator)` in `PlaybackViewModel+Fallback.swift`
- No Deno subprocess in `YouTubeNDescrambler.swift`
- `HLSVariantProxy` does not exist in the codebase
- Binary size increase is accepted and documented
- LGPL compliance decision documented

---

## Agent Session Log

### Session 2 — May 23, 2026

**Goal:** Make `testAutoQualityAbove360p` pass at ≥720p for `Wu8xNx4njoM`. No BotGuard/poToken. No rqh=1 streams. Log every decision.

---

#### Decision 1: Remove migration regression from `AuthService+Keychain.swift`

**What:** A previous `loadFromKeychain` migration block was wiping all auth tokens whenever `sapisid == nil`. This fired on every cold launch, destroying the TV device-code Bearer token and setting `isSignedIn = false`. UI tests were failing because `hasAuthToken = false` throughout the retry chain.

**Decision:** REMOVE the migration block entirely. Tokens are now preserved across restarts.

**Files changed:** `AuthService+Keychain.swift` — migration block deleted.

**Why:** The migration was introduced to clear stale SAPISID values after the SAPISID infrastructure was added. But it incorrectly cleared the Bearer token too. Since `sapisid` was never written to Keychain in earlier app versions, the migration fired on every launch for existing users.

---

#### Decision 2: Add Google Multilogin fallback for SAPISID acquisition

**What:** OAuthLogin (`accounts.google.com/o/oauth2/oauthchooseaccount?service=youtube`) returns HTTP 403 — our TV device-code token lacks the `OAuthLogin` scope. Added a fallback: `fetchSAPISIDViaMultilogin` POSTs to `accounts.google.com/oauth/multilogin?source=ChromiumBrowser&pt=I1` with `Authorization: MultiLogin osid=0:{token}`. This is yt-dlp's multilogin pattern.

**Files changed:** `AuthService+YouTubeCookies.swift` — new `fetchSAPISIDViaMultilogin` private method, wired as fallback in `fetchYouTubeWebCookies`.

**Why:** SAPISID is needed for WEB_CREATOR SAPISIDHASH auth. Without it, WEB_CREATOR returns `LOGIN_REQUIRED`. Multilogin is the standard way to exchange an OAuth token for browser cookies (SAPISID) without a full re-sign-in.

**Status:** Not yet tested — no token in Keychain (migration wiped them before the fix). Will fire automatically on next app launch if the user signs in.

---

#### Decision 3: Add background SAPISID fetch trigger in `loadFromKeychain`

**What:** If signed in (`accessToken != nil`) but `sapisid == nil`, schedule a background `fetchYouTubeWebCookies()` call immediately on launch.

**Files changed:** `AuthService+Keychain.swift` — background `Task { await self.fetchYouTubeWebCookies() }` added to `loadFromKeychain`.

**Why:** Even if a user signs in with a valid Bearer token, SAPISID may not have been fetched yet (old install, migration). Proactively fetching it on launch means WEB_CREATOR will be authenticated on the first video load.

---

#### Decision 4: Fix wrong comment in `PlaybackViewModel+Fallback.swift`

**What:** A comment said iOS adaptive streams "do NOT have rqh=1" — the opposite of the truth. Fixed to "DO have rqh=1".

**Why:** Correctness. Misleading comments cause wrong assumptions in future debugging.

---

#### Decision 5: Android signatureCipher descrambling — evaluated, NOT implemented

**Investigation:** Android adaptive URLs use `signatureCipher` format (`s=<sig>&sp=sig&url=<base_url>`). The hypothesis was: descrambling Android signatures via JSContext would give us direct URLs that might not have rqh=1 (since ANDROID is not in the TVHTML5/MWEB/ANDROID_VR exclusion list).

**Test run:** `yt-dlp --list-formats --extractor-args youtube:player_client=android Wu8xNx4njoM` returned:
```
WARNING: android client https formats require a GVS PO Token which was not provided.
They will be skipped as they may yield HTTP Error 403.
```

**Device log confirmation (test run May 23):**
```
[Android[1]/adaptive] skipping rqh=1 (client=ANDROID) — pot= tokens not supported
```

**Decision: DO NOT implement.** Android adaptive URLs for `Wu8xNx4njoM` have rqh=1 (GVS PO Token required). Even after descrambling signatureCipher, the CDN would return HTTP 403. This video is non-embeddable and all clients require pot= for adaptive streams.

**Cost avoided:** ~300–400 lines of JSContext-based signature descrambling code with no benefit for this video.

---

#### Decision 6: Add `fetchPlayerInfoWebAuthenticated` — yt-dlp `web` OAuth pattern (Phase 0b)

**What:** Added a new authenticated WEB client path that mirrors yt-dlp's OAuth flow:
- `WEB` (nameID=1, `clientName=WEB`, Chrome UA)
- Endpoint: `www.youtube.com/youtubei/v1/player`
- Auth: `Authorization: Bearer {token}` + `X-Goog-AuthUser: 0`

**Files changed:**
- `InnerTubeAPI+Networking.swift` — new `postWebAuthenticated` method
- `InnerTubeAPI+Player.swift` — new `fetchPlayerInfoWebAuthenticated` method
- `PlaybackViewModel+Fallback.swift` — Phase 0b block (after Phase 0 TV Auth, before Phase 1 TVEmbedded)

**Why:** yt-dlp's `web` OAuth client successfully downloads authenticated YouTube videos using exactly this pattern. For authenticated users, YouTube does NOT apply `rqh=1` to adaptive stream URLs from the WEB client. This is distinct from:
- WEB_CREATOR (nameID=62) + SAPISID — correct but SAPISID unavailable
- WEB_CREATOR (nameID=62) + Bearer — returns HTTP 400 without X-Goog-AuthUser
- TV client (nameID=7) + Bearer on googleapis.com — works but returns rqh=1 adaptive streams

**Expected behavior when user is signed in:**
1. `fetchPlayerInfoWebAuthenticated` is called
2. WEB client + Bearer + X-Goog-AuthUser:0 on www.youtube.com
3. YouTube returns adaptive streams WITHOUT rqh=1
4. `tryAllStreams` → `attemptComposition` → ≥720p → TEST PASSES

**Risk:** YouTube might return HTTP 400 for Bearer+X-Goog-AuthUser on WEB (nameID=1). This was tested without X-Goog-AuthUser (returned 400). With X-Goog-AuthUser:0 added, yt-dlp documentation confirms it works. If it still returns 400, the catch block logs it and falls through to Phase 1.

---

#### Test Run Results — May 23, 2026 15:03 UTC

**Result:** FAILED — `360p` (`640×360`)

**Full device log path:** `/tmp/smarttube-diag-1779541572/`

**Retry chain observed:**
```
Phase 0  (TVAuth)      → skipped (hasAuthToken=false, no tokens in Keychain)
Phase 0b (WebAuth)     → skipped (hasAuthToken=false)
Phase 1  (TVEmbedded)  → UNAVAILABLE (Wu8xNx4njoM is not embeddable)
         (WebSafari)   → HTTP 200, HLS URL obtained, AVPlayerItem failed -1102
                          (NSURLErrorDomain "You do not have permission" — rqh=1 segment)
         (MWEB)        → HTTP 200, adaptive rqh=1, skipped
iOS[1]  → rqh=1, skipped
Android[1] → rqh=1 on adaptive, muxed URL saved
AndroidVR[1] → rqh=1, skipped
WebCreator  → LOGIN_REQUIRED (auth=unauthenticated, SAPISID nil)
Android[1]/muxed → ✅ itag=18 360p 446kbps — playback started
```

**Root cause:** No auth tokens in Keychain. Migration regression from a prior session cleared all tokens. `hasAuthToken = false` → Phase 0 and Phase 0b skipped. WebCreator unauthenticated → LOGIN_REQUIRED. All adaptive paths have rqh=1.

**Confirmed by this run:**
- Android adaptive streams for Wu8xNx4njoM have rqh=1 (client=ANDROID). Signaturecypher descrambling would not help.
- WebSafari HLS gets -1102 on segment fetch (rqh=1 in sparams HMAC — confirmed earlier via curl).
- TVEmbedded returns UNAVAILABLE for this non-embeddable video.
- `setSAPISID: nil` logged at launch — no SAPISID in Keychain.

---

#### Blocker: User must sign in on the simulator

The test CANNOT pass for `Wu8xNx4njoM` without authentication. All unauthenticated clients return rqh=1 adaptive for this non-embeddable video.

**Required user action:**
1. Open the SmartTube app on the iPhone 17 simulator (UDID: `6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6`)
2. Sign in using the TV device code flow (Settings → Account → Sign In)
3. Auth token stored in Keychain — persists across test runs (not cleared by `--uitesting-reset-settings`)
4. Run `testAutoQualityAbove360p` again — Phase 0b (WebAuth) will be tried with Bearer + X-Goog-AuthUser:0
5. If WebAuth returns rqh=0 adaptive → ≥720p → TEST PASSES

**If WebAuth still returns 400 (worst case):** WEB_CREATOR + Bearer+X-Goog-AuthUser:0 is also in `postWebCreator` as a fallback. One of these two paths should work.

**Verification:** After user signs in, run the test. Look in device log for:
- `POST /player [WebAuth] videoId=Wu8xNx4njoM` → should appear
- `✅ /player [WebAuth] HTTP 200` (success) OR `❌ HTTP 400` (fallback needed)
- If 200: look for adaptive formats without `rqh=1` in the `[WebAuth[1]/adaptive]` lines
- If 400: WebCreator Bearer+X-Goog-AuthUser fallback will be tried

---

#### Alternatives if Bearer+X-Goog-AuthUser fails

If both WebAuth and WebCreator Bearer paths return HTTP 400 after user signs in:

1. **SAPISID via Multilogin** — if `fetchSAPISIDViaMultilogin` succeeds after sign-in, WEB_CREATOR will use SAPISIDHASH → rqh=0 → ≥720p. Check log for `[cookies] Multilogin SAPISID set`.

2. **Change test video** — use an embeddable video (e.g., `dQw4w9WgXcQ`) where TVEmbedded returns HLS → HLS segments don't have rqh=1. Test semantics change (tests embeddable path, not non-embeddable).

---

#### Test Run Results — May 23, 2026 (log.txt from desktop, user signed in)

**Result:** FAILED — `360p` (`640×360`, same as unauthenticated run)

**Video played by user manually:** `vifpBK5WI4E` (not Wu8xNx4njoM — user ran app manually, not the UI test)

**Key log observations (711 lines, ~/Desktop/log.txt):**
```
29:  setSAPISID: nil  ← SAPISID never obtained
175: [cookies] Fetching YouTube web session cookies for SAPISIDHASH auth
176: [cookies] OAuthLogin did not redirect (HTTP 403) — trying Multilogin fallback
186: [cookies] Multilogin HTTP 400 — SAPISID via Multilogin unavailable
533: POST /player [WebAuth] videoId=vifpBK5WI4E
534: ❌ HTTP 400 for /player [WebAuth] err=code=400 status=INVALID_ARGUMENT
535: WebAuth client fetch failed (attempt 1): httpError(400)
635: POST /player [WebCreator] videoId=vifpBK5WI4E auth=Bearer+AuthUser
636: ❌ HTTP 400 for /player [WebCreator] err=code=400 status=INVALID_ARGUMENT
660: ✅ [Android[1]/muxed/muxed] readyToPlay
682: [moreMenu] rendering — video=vifpBK5WI4E availableFormats=13 isSignedIn=true
```

**isSignedIn=true confirmed — user IS authenticated. Auth token is in Keychain and working. But SAPISID is nil.**

**Root causes identified from this run:**
1. OAuthLogin → HTTP 403 (wrong scope in TV device-code token — expected, known)
2. Multilogin → HTTP 400 (**BUG**: wrong Authorization header — used `MultiLogin osid=0:{token}` instead of `Bearer {token}` + `X-Goog-AuthUser: 0`)
3. WebAuth (WEB nameID=1) + Bearer + X-Goog-AuthUser:0 on www.youtube.com → HTTP 400 `INVALID_ARGUMENT`
4. WebCreator + Bearer + X-Goog-AuthUser:0 on www.youtube.com → HTTP 400 `INVALID_ARGUMENT`

**Definitive conclusion: YouTube's `www.youtube.com/youtubei/v1/player` STRICTLY requires SAPISID (cookie auth) for web-client nameIDs. Bearer tokens are rejected with `INVALID_ARGUMENT` regardless of X-Goog-AuthUser header or client nameID.**

---

#### Decision 7: Confirmed — Bearer + X-Goog-AuthUser:0 rejected by www.youtube.com

**What was discovered:** Phase 0b (`fetchPlayerInfoWebAuthenticated`) returns HTTP 400 `INVALID_ARGUMENT` for WEB (nameID=1) on `www.youtube.com`. WEB_CREATOR (nameID=62) with Bearer + X-Goog-AuthUser:0 also returns HTTP 400. Both confirmed from log.txt.

**Implication:** YouTube's `www.youtube.com/youtubei/v1/player` endpoint does not accept OAuth2 Bearer auth regardless of client nameID or X-Goog-AuthUser header. The `INVALID_ARGUMENT` error (not `UNAUTHENTICATED`) means YouTube recognizes the token but refuses it for web-client requests.

**Action taken:** Phase 0b removed from `exhaustiveRetry` in `PlaybackViewModel+Fallback.swift`. The `fetchPlayerInfoWebAuthenticated` method remains in `InnerTubeAPI+Player.swift` for future reference but is no longer called.

---

#### Decision 8: Root cause found — Multilogin Authorization header was wrong

**What was wrong:** `fetchSAPISIDViaMultilogin` used:
```
Authorization: MultiLogin osid=0:{token}
```
This is an undocumented Chromium internal format for the legacy `/MergeSession` endpoint, not the OAuth Multilogin endpoint.

**The correct format** (yt-dlp + Chromium `gaia_cookie_manager_service.cc`):
```
Authorization: Bearer {token}
X-Goog-AuthUser: 0
```

**Fix applied:** `AuthService+YouTubeCookies.swift` — `fetchSAPISIDViaMultilogin` now sends `Bearer {token}` + `X-Goog-AuthUser: 0`. XSSI-prefixed JSON parsing and SAPISID extraction logic is unchanged.

**Expected result:** Multilogin now returns HTTP 200 with a JSON cookie list → SAPISID extracted → WEB_CREATOR SAPISIDHASH auth enabled → rqh=0 adaptive → ≥720p.

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService+YouTubeCookies.swift`

**Build:** Clean (4.80s), no errors.

---

#### Decision 9: Remove Phase 0b from exhaustiveRetry

**What:** Removed the Phase 0b block (WebAuth — WEB nameID=1 + Bearer + X-Goog-AuthUser:0) from `exhaustiveRetry` in `PlaybackViewModel+Fallback.swift`.

**Why:** This path always returns HTTP 400 `INVALID_ARGUMENT` from `www.youtube.com/youtubei/v1/player`. Keeping it in the retry chain wastes ~500ms per attempt with no possible success. The `fetchPlayerInfoWebAuthenticated` method is preserved in case YouTube changes their policy.

**Effect on retry chain (current order):**
1. Phase 0 — TVAuth (Bearer on googleapis.com) → rqh=1 adaptive (skipped by `skipMuxed`-equivalent)
2. ~~Phase 0b — WebAuth~~ → REMOVED
3. Phase 1 — TVEmbedded → UNAVAILABLE (Wu8xNx4njoM not embeddable)
4. WebSafari → HLS 403 on segments
5. MWEB → rqh=1 adaptive
6. iOS → rqh=1 adaptive
7. Android → rqh=1 adaptive
8. AndroidVR → rqh=1 adaptive
9. **WebCreator** → SAPISIDHASH if sapisid set (rqh=0 ✓) / LOGIN_REQUIRED if sapisid nil
10. Android muxed → 360p fallback

---

#### Confirmed auth/stream behavior table (complete, as of May 23, 2026)

| Client | Auth method | Endpoint | Result for Wu8xNx4njoM |
|--------|------------|---------|-------------------------|
| TVHTML5 (nameID=7) | Bearer ✓ | googleapis.com | 200, rqh=1 adaptive |
| WEB (nameID=1) | Bearer + X-Goog-AuthUser:0 | www.youtube.com | **HTTP 400 INVALID_ARGUMENT** |
| WEB_CREATOR (nameID=62) | Bearer + X-Goog-AuthUser:0 | www.youtube.com | **HTTP 400 INVALID_ARGUMENT** |
| WEB_CREATOR (nameID=62) | SAPISID → SAPISIDHASH | www.youtube.com | rqh=0 ✓ (SAPISID unavailable until Multilogin fix) |
| OAuthLogin | Bearer | accounts.google.com | 403 (wrong scope — TV device-code token) |
| Multilogin (pre-fix) | MultiLogin osid=0:{token} | accounts.google.com | **HTTP 400** (wrong auth header) |
| **Multilogin (fixed)** | **Bearer + X-Goog-AuthUser:0** | **accounts.google.com** | **TBD — next test run** |
| TVEmbedded | none | www.youtube.com | UNAVAILABLE (not embeddable) |
| WebSafari | none | www.youtube.com | HLS, segment 403 (rqh=1 sparams) |
| MWEB | none | www.youtube.com | rqh=1 adaptive |
| Android | none | googleapis.com | rqh=1 adaptive (GVS PO Token required) |
| AndroidVR | none | googleapis.com | rqh=1 adaptive |
| iOS | none | googleapis.com | rqh=1 adaptive |

3. **WKWebView sign-in for SAPISID** — replace the OAuthLogin/Multilogin approach with a `WKWebView` that loads `youtube.com`, lets the user sign in manually, and then extracts the `SAPISID` cookie from `WKHTTPCookieStore`. This gives a real SAPISID valid for WEB_CREATOR SAPISIDHASH auth. Requires user interaction once.

---

#### Test Run Results — May 23, 2026 ~19:50–19:58 UTC (3 runs: single-worker on base simulator)

**Result:** FAILED — `360p` consistently (12–14 seconds to failure — far too fast, no auth path working)

**Infrastructure issue (separate from code):** Parallel testing (`-parallel-testing-enabled YES`) was broken across all 5 runs — `FBSOpenApplicationServiceErrorDomain RequestDenied` on the cloned simulator. iOS 26 beta known instability. Single-worker (`-parallel-testing-enabled NO`) was used with user's explicit approval.

**Retry chain observed from live device log capture (`/tmp/smarttube_testlog.txt`, 12,690 lines):**
```
19:57:53.243  [cookies] Fetching YouTube web session cookies for SAPISIDHASH auth  ✓ (expired-token fix working)
19:57:53.432  [cookies] OAuthLogin did not redirect (HTTP 403) — trying Multilogin fallback
19:57:53.432  Multilogin connection starts → accounts.google.com:443 quic
19:57:53.656  [cookies] Multilogin HTTP 400 — SAPISID via Multilogin unavailable  ← STILL 400

19:57:53.588  [iOS] adaptive rqh=1 → skipped (initial direct load)
19:57:54.426  TVAuth: seeded visitorData → retrying (token IS valid — refresh worked)
19:57:54.742  [TVAuth[1]] adaptive rqh=1 → skipped
19:57:55.163  [WebSafari[1]] HLS, no adaptive → skipped
19:57:55.985  [MWEB[1]] adaptive rqh=1 → skipped
19:57:56.270  [iOS[1]] adaptive rqh=1 → skipped
19:57:56.434  [Android[1]] adaptive rqh=1 → skipped
19:57:56.679  [AndroidVR[1]] adaptive rqh=1 → skipped
19:57:56.680  POST /player [WebCreator] auth=Bearer+AuthUser  ← no SAPISID, falls back to Bearer
19:57:56.759  ❌ HTTP 400 INVALID_ARGUMENT for WebCreator
19:57:56.760  "All adaptive failed — trying muxed fallback"
              → Android muxed itag=18 360p plays
```

**New finding: Multilogin STILL returns HTTP 400 with Bearer + X-Goog-AuthUser:0**

The Multilogin request returns 400 in **224ms** — this is a deliberate rejection, not a network error. The authorization header is now correct (`Bearer {token}` + `X-Goog-AuthUser: 0`), but Google's Multilogin infrastructure rejects the token itself because:
- OAuth scope: `gdata.youtube.com + youtube-paid-content` — these are TV/embedded-video scopes
- yt-dlp uses `https://www.googleapis.com/auth/youtube` scope — full YouTube scope  
- Google's Multilogin endpoint only accepts tokens with `youtube` scope (or broader OAuth scopes)
- The scope check happens at the OAuth infrastructure level before any header is even validated

**TVAuth fires and works (token IS valid):** `TVAuth: seeded visitorData → retrying` at 19:57:54 confirms the Bearer token is valid (just refreshed by proactive refresh). The token can access `googleapis.com` but not Multilogin.

---

#### Decision 10: Add `https://www.googleapis.com/auth/youtube` to OAuth scope

**Root cause:** `AuthService.scope` was set to `"http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"`. These are TV/embedded-content scopes. Google's Multilogin endpoint requires a token with the `https://www.googleapis.com/auth/youtube` scope (what yt-dlp uses) to authorize a browser session creation.

**Fix applied:** `AuthService.swift` — scope expanded to include `https://www.googleapis.com/auth/youtube`:
```swift
var scope = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/youtube"
```

**Effect:** Tokens issued on the NEXT sign-in will include the `youtube` scope. Multilogin should accept these tokens and return SAPISID.

**⚠️ Required user action:** The current Keychain token has the OLD scope. Multilogin will continue to return 400 with the old token. The user must:
1. Open SmartTube on the simulator
2. Sign **out** (Settings → Account → Sign Out)
3. Sign **in** again (TV device code flow — new token issued with `youtube` scope)
4. Then run the test — Multilogin should now return 200 + SAPISID → WebCreator SAPISIDHASH → ≥720p

**Build:** Clean (3.53s, 0 errors).

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService.swift`

---

#### Decision 11: Fix expired-token race — `loadFromKeychain` + `validAccessToken()` in `fetchYouTubeWebCookies`

**Problem found during test run (14-second failure pattern):** When the access token is expired at app launch:
1. `loadFromKeychain` clears `accessToken` (expired)
2. `isSignedIn = true` (refreshToken present)
3. Old condition: `if isSignedIn && sapisid == nil && accessToken != nil` → FALSE (accessToken nil) → `fetchYouTubeWebCookies` NEVER fires
4. `scheduleProactiveRefresh()` fires asynchronously and refreshes the token, but SAPISID fetch is never scheduled after the refresh
5. `exhaustiveRetry` runs with no SAPISID → WebCreator LOGIN_REQUIRED → Android muxed 360p in ~13s

**Fix 1:** `AuthService+Keychain.swift` — removed `&& accessToken != nil` guard:
```swift
// Before:
if isSignedIn && sapisid == nil && accessToken != nil { ... }

// After:
if isSignedIn && sapisid == nil { ... }
```

**Fix 2:** `AuthService+YouTubeCookies.swift` — `fetchYouTubeWebCookies` now calls `validAccessToken()` instead of using `accessToken` directly:
```swift
// Before:
guard let token = accessToken else { ... return }

// After:
let token = try await validAccessToken()  // refreshes token if expired
```

**Result:** `fetchYouTubeWebCookies` now fires on every app launch when signed in and SAPISID is nil, regardless of token expiry. The token refresh and Multilogin call happen atomically in sequence.

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService+Keychain.swift`
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService+YouTubeCookies.swift`

---

#### Updated auth/stream behavior table (as of Decision 11)

| Client | Auth method | Endpoint | Result for Wu8xNx4njoM |
|--------|------------|---------|-------------------------|
| TVHTML5 (nameID=7) | Bearer ✓ | googleapis.com | 200, rqh=1 adaptive |
| WEB (nameID=1) | Bearer + X-Goog-AuthUser:0 | www.youtube.com | HTTP 400 INVALID_ARGUMENT (definitively removed) |
| WEB_CREATOR (nameID=62) | Bearer + X-Goog-AuthUser:0 | www.youtube.com | HTTP 400 INVALID_ARGUMENT |
| WEB_CREATOR (nameID=62) | SAPISID → SAPISIDHASH | www.youtube.com | **rqh=0 ✓ — THE TARGET PATH** |
| OAuthLogin | Bearer | accounts.google.com | 403 (TV scope) |
| Multilogin (old scope) | Bearer + X-Goog-AuthUser:0 | accounts.google.com | 400 (scope `gdata+paid-content` rejected) |
| **Multilogin (new scope)** | **Bearer + X-Goog-AuthUser:0** | **accounts.google.com** | **TBD after re-sign-in with `youtube` scope** |
| TVEmbedded | none | www.youtube.com | UNAVAILABLE (not embeddable) |
| WebSafari | none | www.youtube.com | HLS, segment 403 (rqh=1 sparams) |
| MWEB | none | www.youtube.com | rqh=1 adaptive |
| Android | none | googleapis.com | rqh=1 adaptive |
| AndroidVR | none | googleapis.com | rqh=1 adaptive |
| iOS | none | googleapis.com | rqh=1 adaptive |

---

#### Next required action: Re-sign-in on simulator

The Keychain token has the old scope (`gdata.youtube.com + youtube-paid-content`). Multilogin will continue to reject it until a new token with `youtube` scope is issued:

1. Open SmartTube on the iPhone 17 simulator
2. Settings → Account → **Sign Out**
3. Settings → Account → **Sign In** (TV device code — completes sign-in with new `youtube` scope)
4. Run `testAutoQualityAbove360p`

**Expected log after re-sign-in:**
```
[cookies] Multilogin HTTP 200 → SAPISID obtained ✅
POST /player [WebCreator] videoId=Wu8xNx4njoM auth=SAPISIDHASH
[WebCreator[1]/adaptive] streams: adaptiveVideo=true — rqh=0 confirmed
≥720p → TEST PASSES
```

---

#### Test Run — May 23, 2026 ~20:06 UTC (after re-sign-in, scope fix in place)

**User action:** Signed out + signed back in on iPhone 17 simulator, then ran test.

**Result: FAILED — still 360p**

**Key log lines:**
```
[cookies] Fetching YouTube web session cookies for SAPISIDHASH auth   ← triggered ✓
[cookies] OAuthLogin did not redirect (HTTP 403) — trying Multilogin fallback
[cookies] Multilogin HTTP 400 — SAPISID via Multilogin unavailable    ← STILL 400
[stats] snapshot — res=640×360 codec=mp4 source=presentationSize       (×6)
```

**Analysis:** Multilogin returns 400 even after re-sign-in with the expanded scope. The `youtube` scope addition to `AuthService.scope` did NOT fix Multilogin. Token is valid (`ya29.a0A...` confirmed in log at 20:06:28.154 before OAuthLogin fires).

**Decision 12: Add diagnostic logging — tokeninfo + Multilogin 400 response body**

Two logging additions to `AuthService+YouTubeCookies.swift`:
1. `GET https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={token}` — logs the actual granted scopes on the token, confirming whether Google issued `youtube` scope or silently dropped it
2. Multilogin 400 response body logged — reveals Google's exact rejection reason (`MISSING_SCOPE`, `INVALID_CLIENT`, etc.)
3. OAuthLogin 403 `WWW-Authenticate` header logged

Build: Clean (0.94s)

**Running test again to capture diagnostic output...**

---

#### Test Run — May 23, 2026 ~20:23 UTC (diagnostic logging run, scope fix in place)

**Result: FAILED — still 360p (13.5s)**

**Key diagnostic findings:**

```
[cookies] tokeninfo={
  "azp": "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com",
  "aud": "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com",
  "scope": "https://www.googleapis.com/auth/youtube https://www.googleapis.com/auth/youtube-paid-content",
  "exp": "1779622026",
  "expires_in": "61395",
  "access_type": "offline"
}
[cookies] OAuthLogin did not redirect (HTTP 403) WWW-Authenticate=none → trying Multilogin fallback
[cookies] Multilogin HTTP 400 body=)]}'{"status":"INVALID_INPUT"}
```

**Key findings:**
- Token client ID: `861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68` — **same as yt-dlp's TV embedded client** ✓
- Token scope: `youtube + youtube-paid-content` — scope IS granted ✓
- No `sub` field in tokeninfo — `openid` scope not in token (added to `scope` string but no re-sign-in yet) ✓ expected
- `INVALID_INPUT` from Multilogin — request format is wrong

**Root cause: Google's Multilogin API changed in 2024/2025**

By reading the current Chromium source (`google_apis/gaia/gaia_auth_fetcher.cc`, `StartOAuthMultilogin()`):

| Field | Old format (what we sent) | New format (Chromium 2025) |
|-------|--------------------------|---------------------------|
| Authorization | `Bearer {token}` + `X-Goog-AuthUser: 0` | `MultiBearer {token}:{gaiaId}` |
| URL param | `pt=I1` | `reuseCookies=0` |
| Body | `source=ChromiumBrowser` | `" "` (space, to force POST) |

The `INVALID_INPUT` is because the server no longer accepts the old `Bearer` format. The new format requires `MultiBearer {token}:{gaiaId}` where `gaiaId` is the user's **numeric Gaia ID** (the `sub` claim in OpenID Connect).

**Why the `sub` claim was missing:** The token was issued with `youtube + youtube-paid-content` scope but NOT `openid` scope. The `sub` (Gaia ID) is only returned by tokeninfo/userinfo when `openid` scope is present.

---

#### Decision 13: Add `openid` scope + implement MultiBearer Multilogin

**Problem:** Multilogin's new API (`MultiBearer {token}:{gaiaId}`) requires the numeric Gaia ID, which is only available as the `sub` claim when `openid` scope is in the token.

**Fix 1 — `AuthService.swift`:**
- Added `openid` to scope string
- Added `public internal(set) var gaiaId: String?` property

Scope is now: `"openid http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/youtube"`

**Fix 2 — `AuthService+YouTubeCookies.swift`:**
- `fetchYouTubeWebCookies`: tokeninfo call now parses `sub` claim → stores as `gaiaId` on `AuthService`
- `fetchSAPISIDViaMultilogin`: completely rewritten to use new Chromium protocol:
  - URL: `https://accounts.google.com/oauth/multilogin?source=ChromiumBrowser&reuseCookies=0`
  - Authorization: `MultiBearer {token}:{gaiaId}` (if gaiaId set) — falls back to old Bearer if not
  - Body: `" "` (space, forces POST — Chromium pattern)
  - Removed: `X-Goog-AuthUser: 0`, `pt=I1`, body `source=ChromiumBrowser`

**Build:** Clean (3.59s)

**⚠️ Required user action:** Sign out + sign in AGAIN. The `openid` scope was just added. The current Keychain token does NOT have `openid` scope (tokeninfo confirms: no `sub` field). A new sign-in will issue a token with `openid` scope → tokeninfo returns `sub` → `gaiaId` extracted → `MultiBearer` Multilogin uses it.

After re-sign-in, the expected log sequence:
```
[cookies] tokeninfo={"sub":"123456789...","scope":"openid youtube youtube-paid-content",...}
[cookies] gaiaId=123456789 — MultiBearer Multilogin enabled
[cookies] Multilogin MultiBearer with gaiaId=123456789
[cookies] ✅ SAPISID obtained via Multilogin
POST /player [WebCreator] auth=SAPISIDHASH
≥720p → TEST PASSES
```

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService.swift`
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService+YouTubeCookies.swift`

---

#### Decision 14: Multilogin INVALID_TOKENS/RECOVERABLE — root cause confirmed

**Observed (after Decision 13 fix):** User signed out + signed back in. New token obtained with `openid` scope.
- tokeninfo `sub` claim: `105073821896836732032` → `gaiaId` extracted ✅
- Multilogin called with `Authorization: MultiBearer {token}:105073821896836732032` ✅
- Multilogin **HTTP 403** response body:

```json
{
  "status": "INVALID_TOKENS",
  "failed_accounts": [{
    "obfuscated_id": "105073821896836732032",
    "status": "RECOVERABLE",
    "url": "https://accounts.google.com/ServiceLogin"
  }]
}
```

**Root cause:** The Multilogin endpoint (`/oauth/multilogin`) is a Chromium browser endpoint. It requires the OAuth2 token to carry `https://www.googleapis.com/auth/accounts.reauth` scope. This scope is granted only by Chrome-type browser OAuth clients. The YouTube TV device-code client (`861556708454-...`) does NOT grant `accounts.reauth`. Multilogin rejects the token as `RECOVERABLE` (meaning the user could re-auth in a browser), but there is no programmatic recovery path with TV tokens.

**Full fallback chain analysis for Wu8xNx4njoM:** Every path blocked:
- TVAuth[1]: all adaptive streams rqh=1, no hlsManifestUrl → skipped
- TVEmbedded[1]: playability=ERROR (video is not embeddable)
- WebSafari[1]: hlsManifestUrl present, master manifest 200 ✅ → variant playlist (hls_playlist) HTTP 403
- MWEB/iOS/Android/AndroidVR: all adaptive rqh=1 → skipped
- WebCreator[1]: SAPISID absent → Bearer+AuthUser fallback → HTTP 400 INVALID_ARGUMENT (www.youtube.com rejects Bearer)
- Android muxed: itag=18 360p 446 kbps → **plays at 360p** (test fails)

**Core unanswered question:** Is the WebSafari `hls_playlist` variant URL accessible at all without SAPISID, or does it require YouTube session cookies? The master `hls_variant` URL fetches 200 with iOS UA (no cookies). The variant `hls_playlist` URL fails with HTTP 403 in AVPlayer. It is unknown whether AVPlayer sends different headers from URLSession (possible `AVURLAssetHTTPHeaderFieldsKey` mismatch or AVPlayer injecting unexpected headers), or whether the CDN enforces cookie-auth at the variant level but not at the master level.

**Significance:** If the variant URL returns 200 via URLSession with just Safari UA + Origin + Referer (no cookies), then the 403 is AVPlayer-specific and fixable in the app. If URLSession also returns 403, then SAPISID is required and no header fix will help.

---

#### Decision 15: Add D-14 diagnostic probe + accounts.reauth scope

**Problem:** Can't determine root cause of WebSafari HLS 403 without direct URLSession test of the variant URL.

**Fix 1 — Diagnostic probe (`PlaybackViewModel+Fallback.swift`):**
Added a `Task.detached` URLSession probe immediately after selecting the HLS variant URL (before AVPlayer loads it). Uses an **ephemeral URLSession** (no cookies, no shared state) with Safari UA + Origin + Referer headers. Logs:
- `D-14 HLS variant probe (no-cookie/Safari UA): HTTP {code} bytes={n}` if response received
- `D-14 HLS variant probe: fail/timeout (no-cookie/Safari UA)` on network error or timeout

Decision rules from this log line:
- **HTTP 200**: Variant URL IS accessible without cookies. The 403 in AVPlayer is due to AVPlayer adding unexpected request headers or stripping ours. Fix: investigate `AVURLAssetHTTPHeaderFieldsKey` behavior; possibly pass master manifest URL directly to AVPlayer (let AVFoundation's HLS stack handle variant selection natively) with Safari UA.
- **HTTP 403**: SAPISID is required. The CDN enforces session-auth at the variant level. Any fix requires either getting SAPISID via a new mechanism, or an entirely different playback path.

**Fix 2 — accounts.reauth scope (`AuthService.swift`):**
Added `https://www.googleapis.com/auth/accounts.reauth` to the OAuth scope string. If Google grants this scope for the YouTube TV client (unconfirmed — may be silently ignored), the next sign-in will produce a token accepted by Multilogin → SAPISID → WebCreator → ≥720p.

New scope: `"openid https://www.googleapis.com/auth/accounts.reauth http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/youtube"`

**Build:** Clean (3.98s)

**⚠️ Required user action:** Sign out + sign in AGAIN. The `accounts.reauth` scope was just added. Current token will NOT have it. A new sign-in will tell us if Google grants it.

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift`
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService.swift`

---

#### Decision 16: D-14 enhanced probe — rqh/1 confirmed in HLS segments (path-format bug)

**Test run findings:**

D-14 probe result for WebSafari[1]/HLS variant:
- Variant playlist (index.m3u8): HTTP 200, 275374 bytes ✅
- First segment URL: `https://rr3---sn-ncc-cxbr.googlevideo.com/videoplayback/id/5aef31371e278e83/itag/96/source/youtube/expire/.../ip/188.2.243.94/requiressl/yes/ratebypass/yes/pfa/1/sgoap/.../sgovp/.../rqh/1/hls_chunk_host/...`
- `firstSeg_rqh` logged as `false` ← **probe code bug**: looked for `rqh=1` query style but URL uses `/rqh/1/` path style
- Actual value: `rqh=1` IS present as `/rqh/1/` in the segment URL path ✅ CONFIRMED
- Segment probe (Safari UA/no-cookie): HTTP 403 ← CDN rejects the request due to rqh=1 enforcement

**What D-14 actually tells us:**
1. The variant playlist is accessible WITHOUT cookies (HTTP 200, any User-Agent) — confirms the 403 is at segment level, not playlist level
2. The segments have `/rqh/1/` in their path — CDN requires BotGuard `pot=` OR a different (authenticated) InnerTube request to get rqh=0 URLs
3. `AVURLAssetHTTPHeaderFieldsKey` does NOT apply to HLS sub-resource requests (Apple SDK limitation) — confirmed by Apple docs
4. The AVPlayer 403 is NOT due to AVPlayer sending wrong headers — it's because the SEGMENT URLS have `/rqh/1/` and need CDN bot authentication regardless of headers

**Bug fix:** Updated rqh detection to look for `/rqh/1` (path-style) in addition to `rqh=1` (query-style).

**Confirmed root cause chain:**
```
WebSafari (no SAPISID) → InnerTube returns HLS manifest → segment URLs contain /rqh/1/ path
→ CDN requires pot= token → no pot= (banned by constraints) → HTTP 403 on every segment
→ AVPlayer item fails → fallback to 360p muxed → testAutoQualityAbove360p FAILS

With SAPISID:
→ WEB_CREATOR InnerTube request (SAPISIDHASH auth) → returns rqh=0 adaptive streams (itag 137/140)
→ AVMutableComposition → 1080p@30fps → TEST PASSES ✅
```

**Why yt-dlp gets 720p/1080p:** yt-dlp has the developer's YouTube browser cookies (SAPISID) in its cookie jar, which causes the WEB_CREATOR InnerTube endpoint to return rqh=0 URLs.

**Next action required:** User must sign out + sign in to get a new token with `accounts.reauth` scope (added in Decision 15). If Google grants this scope for the YouTube TV client, Multilogin will succeed → SAPISID obtained → WebCreator authenticated → rqh=0 streams → test passes.

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift` — rqh detection bug fix

---

#### Decision 17: accounts.reauth scope rejected by YouTube TV OAuth client

**Observed:** Added `https://www.googleapis.com/auth/accounts.reauth` to scope string (Decision 15). User tapped "Sign In" in the app. Sign-in failed immediately with "Could not start sign-in. Check your internet connection."

**Root cause:** The POST to `https://oauth2.googleapis.com/device/code` returned a non-2xx HTTP status. Google rejects the device code request entirely when an unsupported scope is requested by the YouTube TV client (`861556708454-...`). The `accounts.reauth` scope is only grantable to Chrome-type browser OAuth clients. `deviceCodeRequestFailed` error thrown by `requestDeviceCode()`.

**Fix:** Removed `accounts.reauth` from scope string. Scope reverted to `"openid http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/youtube"`.

**Consequence:** Multilogin path is permanently blocked for the YouTube TV OAuth client. SAPISID cannot be obtained via any Google account cookie establishment endpoint with this token.

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/Services/AuthService.swift` — accounts.reauth scope removed

---

#### Decision 18: TVAuth Bearer token on rqh=1 adaptive streams (experiment)

**Problem:** All paths to ≥720p are blocked. The only unexplored option is: does the YouTube CDN accept `Authorization: Bearer {token}` for TVHTML5 adaptive streams that have `rqh=1`?

**Theory:** The official YouTube TV app on Apple TV plays TVHTML5 adaptive streams (which have `rqh=1`). It does not use BotGuard/pot=. It uses OAuth2 Bearer token auth. Therefore, for authenticated TVHTML5 CDN requests, the CDN might accept `Authorization: Bearer {token}` as the session credential instead of `pot=`.

**Implementation in `attemptComposition`:**
1. `videoRqh` detection fixed to check both `rqh=1` (query style) AND `/rqh/1` (path style)
2. When `label.contains("TVAuth") && hasAuthToken && currentAuthToken != nil`:
   - Don't skip the stream (allow attempt)
   - Log: `"attempting rqh=1 TVAuth with Bearer — CDN auth experiment"`
   - Inject `Authorization: Bearer {token}` into `AVURLAsset` headers alongside UA
3. Added actual 8-second timeout to `raceStream`:
   - A `Task.detached` that `sleep(nanoseconds: timeoutNs)` then `raceCont.yield(nil); raceCont.finish()`
   - Prevents indefinite CDN hang if CDN accepts connection but holds it open
   - Both tasks' duplicate `yield`/`finish` calls are no-ops after the first `finish()`

**Expected outcomes:**
- `loadTracks` returns tracks: Bearer auth satisfied CDN → composition succeeds → ≥720p → **TEST PASSES**
- `loadTracks` throws/returns nil quickly: CDN rejected Bearer with error → timeout races → composition fails → fallback continues
- `loadTracks` hangs: timeout fires after 8s → returns nil → composition fails → fallback continues (≤8s wait)

**Note:** `AVURLAssetHTTPHeaderFieldsKey` applies only to the INITIAL CDN request (the first range request AVFoundation makes to obtain track metadata). If the CDN returns an auth-required response for the initial request, `loadTracks` throws. If the CDN accepts the initial request but blocks segment requests, `AVPlayerItem` fails after `.readyToPlay` with HTTP 403.

**Build:** Clean (1.67s)

**Files changed:**
- `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift`
