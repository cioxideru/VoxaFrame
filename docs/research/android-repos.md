> Status: current — retained research reference; classification reviewed 2026-10-15.
> External repository details are historical snapshots, not verified-current upstream facts.

# Android Repository References

These are the original Android-based repositories that SmartTube was built on.
They are preserved here for reference — useful if any business logic, API handling, or protocol details need to be consulted during iOS development.

## Original SmartTube Android App
- **Repo:** https://github.com/yuliskov/SmartTube
- The main Android TV app. Entry point is `smarttubetv/`. Uses Leanback UI, ExoPlayer, and the libs below.

## MediaServiceCore (Android submodule)
- **Repo:** https://github.com/yuliskov/MediaServiceCore
- Contains the YouTube API client, media service interfaces (`mediaserviceinterfaces/`), and `youtubeapi/` module.
- This is the primary source of truth for YouTube API integration logic, parsing, and playback URLs.

## SharedModules (Android submodule)
- **Repo:** https://github.com/yuliskov/SharedModules
- Shared Gradle/build infrastructure and common utilities used across MediaServiceCore and smarttubetv.

## Notable Android Libraries Bundled
| Directory | Purpose |
|---|---|
| `exoplayer-amzn-2.10.6/` | Amazon-patched ExoPlayer 2.10.6 for DASH/HLS playback |
| `chatkit/` | Live chat UI rendering |
| `common/` | App-level shared code (settings, preferences, UI utils) |
| `leanback-1.0.0/` | Android TV Leanback UI components |
| `leanbackassistant/` | Voice/assistant integration for Leanback |
| `fragment-1.1.0/` | Patched AndroidX Fragment library |
| `filepicker-lib/` | File picker for local media |
| `doubletapplayerview/` | Double-tap seek gesture overlay |
| `slidableactivity/` | Slide-to-dismiss activity gesture |

## To Clone Android Codebase
```bash
git clone https://github.com/yuliskov/SmartTube android-smarttube
cd android-smarttube
git submodule update --init --recursive
```

---

## How SmartTube Android Plays All Video Quality Formats

> Source: `MediaServiceCore/youtubeapi/` — primarily `videoinfo/`, `formatbuilders/`, and `service/data/`.

### 1. Entry Point: Multi-Client Format Fetching (`VideoInfoService.java`)

`VideoInfoService.getVideoInfo(videoId)` drives the entire format pipeline. It uses a **rotating-client fallback list**:

```
AppClient.TV → TV_SIMPLY → ANDROID_SDK_LESS → (others)
```

`firstPlayable()` iterates this list and returns the first non-unplayable `VideoInfo`. On failure or throttle, `switchNextFormat()` either resets the PoToken cache for the current client or advances to the next client type. The last-successful client is persisted to prefs and used as the starting point on next launch.

Special cases:
- **Auth content** — always fetches via `AppClient.TV` (the only client that supports signed-in auth tokens).
- **Extended HLS formats** — if `FORMATS_EXTENDED_HLS` is enabled and the TV client returns broken extended formats, a second request is made via `AppClient.IOS` to get a real HLS manifest URL.
- **Auto-generated subtitles** — if fewer than 100 translation languages are returned, a third request via `AppClient.WEB` tops up the subtitle list.

### 2. Two Classes of Streams

| Class | Description | ExoPlayer path |
|---|---|---|
| **Adaptive (DASH)** | `adaptiveFormats[]` — video-only + audio-only, one quality per entry | Custom in-memory MPD → DASH media source |
| **Regular (muxed)** | `regularFormats[]` — muxed video+audio (mainly itag 18, 360p) | Direct URL list → ProgressiveMediaSource |
| **HLS manifest** | `hlsManifestUrl` — live or extended-format path | HLS media source |
| **DASH manifest URL** | `dashManifestUrl` — pre-built MPD from YouTube CDN | DASH media source (URL) |
| **SABR** | Server-ABR (new YouTube UMP protocol) | Special SABR media source |

`YouTubeMediaItemFormatInfo` wraps these and exposes `containsDashFormats()`, `containsSabrFormats()`, `containsHlsUrl()`, `containsUrlFormats()` so the player can select the right path.

### 3. Format Deciphering (`VideoInfoServiceBase.java`)

Before formats are usable, three transforms are applied to every URL in both adaptive and regular format lists:

1. **n-parameter deobfuscation** — YouTube throttles streams that carry an un-transformed `n=` param. All `n` values are extracted, batch-passed to a JS deobfuscator (`AppService.bulkSigExtract()`), and written back via `applyNParams()`.
2. **Signature decryption** — cipher-protected streams have `sig=` or `s=` params similarly batch-decrypted and applied via `applySignatures()`.
3. **PO Token injection** — `PoTokenGate.getPoToken(client, videoId)` returns a BotGuard-derived PO token; it is appended to every URL as `&pot=...` via `applySessionPoToken()`.

For **live streams**, an additional DASH segment probe is performed on the smallest audio track to obtain `segmentDurationUs`, `startTimeMs`, and `startSegmentNum`. Three probe strategies are tried in order: HTTP headers → redirect URL → content body.

### 4. ITag Quality Ordering (`ITagUtils.java`)

Every stream entry carries an **itag** integer that encodes codec + resolution + frame-rate. `ITagUtils` defines two ordered lists used for quality comparison and MPD sorting:

**AVC / H.264 itag order (lowest → highest quality):**
| itag | Format |
|---|---|
| `139` | Audio 48k AAC |
| `140` | Audio 128k AAC |
| `160` | Video 144p |
| `133` | Video 240p |
| `134` | Video 360p |
| `135` | Video 480p |
| `136` | Video 720p |
| `298` | Video 720p60 |
| `137` | Video 1080p |
| `299` | Video 1080p60 |
| `264` | Video 1440p |
| `266` | Video 2160p (4K) |
| `272` | Video 2160p HQ (4K) |

**WebM / VP9 + Opus itag order (lowest → highest quality):**
| itag | Format |
|---|---|
| `249` | Audio 68k Opus |
| `250` | Audio 89k Opus |
| `251` | Audio 156k Opus |
| `278` | Video 144p |
| `242` | Video 240p |
| `243` | Video 360p |
| `244` | Video 480p |
| `247` | Video 720p |
| `302` | Video 720p60 HDR |
| `248` | Video 1080p |
| `303` | Video 1080p60 HDR |
| `271` | Video 1440p |
| `308` | Video 1440p60 HDR / 60fps |
| `313` | Video 2160p (4K) |
| `315` | Video 2160p60 HDR (4K) |

`ITagUtils.compare(leftITag, rightITag)` returns the quality delta within the same codec family, enabling sorted insertion into the MPD's `AdaptationSet`.

### 5. MPD Construction (`YouTubeMPDBuilder.java`)

The app never uses YouTube's own DASH manifest directly for adaptive VOD; it builds a custom MPD in-memory:

1. Formats are partitioned into four `TreeSet` buckets sorted by `MediaFormatComparator` (which uses `ITagUtils.compare`):
   - `mMP4Videos` / `mWEBMVideos` — video AdaptationSets
   - `mMP4Audios` / `mWEBMAudios` — audio AdaptationSets keyed by language
2. An `AdaptationSet` XML element is written per bucket, with a `Representation` per format entry carrying: `id`, `codecs`, `bandwidth`, `width`, `height`, `maxPlayoutRate`, `frameRate` (video) or `audioSamplingRate` (audio).
3. Segment addressing strategy is chosen per-format:
   - **`SegmentBase` + `indexRange`/`initRange`**: standard VOD DASH (byte-range init + index)
   - **`SegmentList` + `SegmentURL`**: segmented streams
   - **`SegmentTemplate` + `SegmentTimeline`**: live streams (type=dynamic, `&sq=$Number$` URL template)
   - **OTF `SegmentTemplate`**: on-the-fly streams — segment timeline is built by parsing the OTF init segment via `YouTubeOtfSegmentParser`
4. `limitVideoCodec()` / `limitAudioCodec()` can filter the MPD to a single codec (used for user-selectable codec preference: AVC / VP9 / AV1).

The resulting MPD `InputStream` is fed directly to ExoPlayer's `DashMediaSource`.

### 6. MIME Type / Codec Detection (`MediaFormatUtils.java`)

Codec family is inferred from the `codecs=` string in the format's MIME type:
- `vorbis` / `opus` → `audio/webm`
- `vp9` / `vp09` / `av01` → `video/webm`
- `avc1` / `mp4a` → `video/mp4` / `audio/mp4`

`isDash()` checks for the `itag` field presence and whether the value appears in the known DASH itag set.

### 7. Codec and Codec-Group Routing (iOS Relevance)

Android selects codec by merging both MP4 and WebM groups into the same MPD and letting ExoPlayer's `DefaultTrackSelector` pick the best rendition. The user can also explicitly pin a codec family via `limitVideoCodec("avc1")` / `limitVideoCodec("vp9")`.

**iOS implication:** AVFoundation cannot decode VP9/WebM or AV1 in older OS versions. The iOS port must either:
- Skip the WebM `AdaptationSet` entirely when building the manifest, or
- Apply `limitVideoCodec("avc1")` for all iOS/tvOS targets, or
- Use the HLS manifest path (iOS `AppClient`) which only returns H.264-compatible streams.

### 8. SABR (Server-Side ABR — New Path)

`containsSabrFormats()` returns true when the first adaptive format has `FORMAT_TYPE_SABR`. This signals the player to use YouTube's new UMP/SABR streaming protocol (`serverAbrStreamingUrl`) instead of a client-assembled MPD. The SABR path bypasses client-side ABR entirely — the server decides quality based on reported bandwidth. Android SmartTube has preliminary SABR support; iOS should monitor this as it may eventually replace DASH for all clients.

---

## Cross-Platform / Desktop Reference Projects

### FreeTube (Desktop — Electron + Vue 3)
- **Repo:** https://github.com/FreeTubeApp/FreeTube
- **Analysis:** [docs/freetube-analysis.md](freetube-analysis.md)
- Privacy-focused open-source YouTube desktop client (~20.8k stars).
- Uses `youtubei.js` (InnerTube local extractor) or Invidious API — no official YouTube API.
- Key areas of interest: **BotGuard/poToken handling**, SponsorBlock integration, dual API fallback pattern, local-first data model (NeDB), and subscription profiles.

### BgUtils — BotGuard / PO Token Reference (TypeScript)
- **Repo:** https://github.com/LuanRT/BgUtils
- **npm:** `bgutils-js` · ~270 stars · MIT · last release v3.2.0 (Mar 2025)
- Gold-standard open-source implementation of Google's BotGuard attestation + PO token pipeline.
- **Why we care:** YouTube CDN returns `rqh=1` on adaptive streams for many videos. Without a valid `pot=` PO token appended to stream URLs, `AVAssetResourceLoader` / `loadTracks` times out after 8 s — leaving only muxed itag=18 (360p) playable.
- **Pipeline (all 5 steps):**
  1. POST `[requestKey]` → `jnn-pa.googleapis.com/$rpc/google.internal.waa.v1.Waa/Create` → interpreter JS URL + program + globalName
  2. Load interpreter JS via `JSContext.evaluateScript` (JavaScriptCore); call `vm.a(program, vmFunctionsCallback, true, …)`
  3. Call `asyncSnapshotFn(callback, [undefined, undefined, webPoSignalOutput, undefined])` → `botguardResponse` (string)
  4. POST `[requestKey, botguardResponse]` → `.../GenerateIT` → `integrityTokenB64`
  5. Call `webPoSignalOutput[0](integrityTokenBytes)` → `getMinter` → `mintCallback(videoIdBytes)` → base64 PO token (~110–128 bytes)
- **WAA API key (public):** `AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw`
- **YouTube requestKey (stable):** `O43z0dpjhgX20SCx4KAo`
- **iOS port:** `BotGuardClient.swift` in `SmartTubeIOSCore` — implements `PoTokenProvider` via JavaScriptCore, synchronous JS execution + semaphore-bridged URLSession calls on `jsQueue`.
