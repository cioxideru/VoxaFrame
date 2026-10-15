> Status: current — retained research reference; classification reviewed 2026-10-15.
> External repository details are historical snapshots, not verified-current upstream facts.

# yt-dlp — Knowledge Reference for SmartTubeIOS

> Research snapshot based on yt-dlp `master` branch (circa May 2026).  
> Primary sources: [yt-dlp README](https://github.com/yt-dlp/yt-dlp), [`_base.py`](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py)  
> Purpose: mine yt-dlp's battle-tested YouTube reverse-engineering for approaches we can apply or watch out for in SmartTubeIOS.

---

## 1. InnerTube Client Registry

yt-dlp maintains a `INNERTUBE_CLIENTS` dict in `_base.py` that is the single most valuable reference for what client contexts actually work today. Full roster with the fields that matter to us:

| Client key | `clientName` | `clientVersion` (as of May 2026) | `INNERTUBE_CONTEXT_CLIENT_NAME` (int) | `REQUIRE_JS_PLAYER` | Notes |
|---|---|---|---|---|---|
| `web` | `WEB` | `2.20260114.08.00` | 1 | ✅ | n-sig throttling applies; needs JS deobfuscation |
| `web_safari` | `WEB` | `2.20260114.08.00` | 1 | ✅ | Safari UA variant; default unauthenticated client in yt-dlp |
| `web_embedded` | `WEB_EMBEDDED_PLAYER` | `1.20260115.01.00` | 56 | ✅ | Age-restriction bypass (unreliable) |
| `web_music` | `WEB_REMIX` | `1.20260114.03.00` | — | ✅ | `music.youtube.com` host |
| `web_creator` | — | — | — | ✅ | Studio; requires auth + PO Token |
| `mweb` | `MWEB` | `2.20260115.01.00` | 2 | ✅ | Has "ultralow" formats; PO Token required |
| `android` | `ANDROID` | — | 3 | ❌ | REQUIRE_JS_PLAYER=false; PO Token required for HTTPS/DASH |
| `android_vr` | `ANDROID_VR` | **`1.65.10`** | 28 | ❌ | Oculus Quest 3 identity; **no PO Token required**; yt-dlp default unauthenticated |
| `ios` | `IOS` | `21.02.3` | **5** | ❌ | iPhone16,2, iOS 18.3.2; PO Token required for GVS/HLS URLs |
| `tv` | `TVHTML5` | `7.20260114.12.00` | **7** | ✅ (optional) | Cobalt UA; SUPPORTS_COOKIES |
| `tv_downgraded` | `TVHTML5` | `5.20260114` | **7** | ✅ (optional) | Cobalt UA, older version; **REQUIRE_AUTH=True**; yt-dlp default authenticated |
| `tv_simply` | `TVHTML5_SIMPLY` | `1.0` | 75 | — | PO Token required for HTTPS/DASH |

**Relevance to SmartTubeIOS:**
- Our `postPlayer()` uses `IOS` (client 5) — matches `ios` above. yt-dlp shows this now requires PO Tokens for GVS and HLS URLs. Watch for throttled/403 stream URLs in the future.
- Our `postTV()` uses `TVHTML5` (client 7) with Bearer auth — matches `tv_downgraded` above (yt-dlp uses for free auth accounts). The `tv_downgraded` version string `5.20260114` is older than `tv` (`7.20260114.12.00`); we may want to track which version YouTube prefers.
- **`android_vr` (client 28) is currently the most permissive unauthenticated client** — no JS player required and no PO Token required. Consider it as a fallback for unauthenticated stream extraction.

---

## 2. iOS Client Device Identity (for 60fps)

yt-dlp hard-codes this in `_base.py` and it is the identity that unlocks 60fps formats:

```
clientName:    IOS
clientVersion: 21.02.3
deviceMake:    Apple
deviceModel:   iPhone16,2          ← iPhone 15 Pro Max
osName:        iPhone
osVersion:     18.3.2.22D82
userAgent:     com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)
```

SmartTubeIOS currently sends a static `clientVersion` in `postPlayer()`. Keeping `clientVersion`, `deviceModel`, and `osVersion` in sync with what yt-dlp ships improves format availability. See [TeamNewPipe/NewPipeExtractor#680](https://github.com/TeamNewPipe/NewPipeExtractor/issues/680#issuecomment-1002724558) for the 60fps unlock mechanism.

---

## 3. TV Client / Cobalt User-Agent

yt-dlp's `tv` client uses a Cobalt browser UA:

```
Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)
```

`tv_downgraded` (the authenticated TV client) uses an older Cobalt UA:

```
Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version
```

SmartTubeIOS's `postTV()` should match the Cobalt UA string that `tv_downgraded` uses when sending authenticated requests, as mismatches can cause YouTube to reject or downgrade the token context.

---

## 4. PO Token (Proof of Origin) — Critical 2024–2026 Change

yt-dlp added comprehensive PO Token support. The token is needed to authenticate that stream URLs are being fetched by a legitimate player context.

**What it is:** A short-lived token (`po_token`) that must be appended to GVS (Google Video Server) stream URLs and/or included in the player request body. YouTube enforces it per-client:

| Client | HTTPS streams | DASH streams | HLS streams |
|---|---|---|---|
| `ios` | Required | — | Required (30s into livestream) |
| `android` | Required | Required | Recommended |
| `android_vr` | Not required ✅ | Not required ✅ | Recommended |
| `mweb` | Required | Required | Recommended |
| `tv` / `tv_downgraded` | Not enforced ✅ | Not enforced ✅ | Not enforced ✅ |

**Implication:** Our current iOS client (`postPlayer()`) is increasingly subject to PO Token enforcement. The TV client (`postTV()`) is currently exempt. If stream URLs from `postPlayer()` start throttling/403-ing, the fix is either:
1. Switch to `android_vr` (client 28) for unauthenticated stream extraction.
2. Implement PO Token generation (complex — requires JS execution or a trusted token provider).

**yt-dlp PO Token guide:** https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide

---

## 5. n-sig Based Throttling

yt-dlp documents a major YouTube mitigation: stream URLs contain an `n` parameter that is obfuscated. If not deobfuscated correctly, download speeds are throttled to ~40–80 kbps. yt-dlp solves this by:
1. Fetching the YouTube JS player.
2. Running a JS deobfuscation function to transform the `n` parameter.
3. Replacing `n=<old>` with `n=<transformed>` in each stream URL.

**SmartTubeIOS approach:** We avoid this by using the **iOS client** (REQUIRE_JS_PLAYER=false) and the **TV client** (Bearer-authenticated). Neither requires JS execution because YouTube serves pre-signed URLs to these clients. This is the same strategy the Android SmartTube uses.

**Watch out for:** If you ever add a `web` or `mweb` client path, n-sig throttling will apply and you'll need a Swift JS execution layer or a pre-computed transform.

Reference: [youtube-dl#29326](https://github.com/ytdl-org/youtube-dl/issues/29326)

---

## 6. Player Response Format Object Structure

The InnerTube `/player` endpoint returns `streamingData.adaptiveFormats[]` and `streamingData.formats[]`. Each format object has these fields (from yt-dlp's extraction logic):

```json
{
  "itag": 137,
  "url": "https://rr*.googlevideo.com/videoplayback?...",
  "mimeType": "video/mp4; codecs=\"avc1.640028\"",
  "bitrate": 2500000,
  "width": 1920,
  "height": 1080,
  "lastModified": "1700000000000000",
  "contentLength": "123456789",
  "quality": "hd1080",
  "qualityLabel": "1080p",
  "fps": 30,
  "projectionType": "RECTANGULAR",
  "averageBitrate": 2400000,
  "approxDurationMs": "123456",
  "audioQuality": "AUDIO_QUALITY_MEDIUM",
  "audioSampleRate": "44100",
  "audioChannels": 2,
  "signatureCipher": "..."   // only present if URL is ciphered (web client)
}
```

**Key yt-dlp observations:**
- `url` field is present directly for mobile clients (ios, android, android_vr) — no cipher decoding needed.
- `signatureCipher` / `cipher` is present for `web` client formats — requires JS deobfuscation.
- `qualityLabel` is the human-readable string shown in the quality picker (`"1080p"`, `"720p60"`, etc.).
- `approxDurationMs` is a string, not a number.
- `audioQuality` is `AUDIO_QUALITY_LOW`, `AUDIO_QUALITY_MEDIUM`, or `AUDIO_QUALITY_HIGH`.

---

## 7. Format Quality Sorting Logic

yt-dlp's default sort order for YouTube formats is:

```
lang, quality, res, fps, hdr:12, vcodec, channels, acodec, size, br, asr, proto, ext, hasaud, source, id
```

**Codec priority (video):** `av01` > `vp9.2` > `vp9` > `h265` > `h264` > `vp8`  
**Codec priority (audio):** `flac/alac` > `opus` > `vorbis` > `aac` > `mp4a` > `mp3`  
**Extension priority (video):** `mp4` > `mov` > `webm` > `flv`  
**Extension priority (audio):** `m4a` > `aac` > `mp3` > `opus` > `webm`

Note that **Dolby Vision is not preferred by default** (`hdr:12` caps HDR preference at HDR10+). DV formats are not broadly compatible.

**For SmartTubeIOS quality picker:** AVKit on iOS/macOS natively decodes H.264 and H.265 in hardware. AV1 (`av01`) is software-only on iOS < 16 and hardware on A17+ (iPhone 15 Pro). Prefer `hvc1`/`hev1` (H.265) over AV1 for broadest hardware compatibility.

---

## 8. DASH vs HLS vs HTTPS Stream Protocols

yt-dlp recognises these protocols from the YouTube player response:

| Protocol | Description | SmartTubeIOS notes |
|---|---|---|
| `https` | Progressive MP4/m4a, direct URL | Used today via `postPlayer()` |
| `http_dash_segments` | DASH (MPD) manifest | Available from multiple clients; better adaptive bitrate |
| `m3u8` / `m3u8_native` | HLS manifest | iOS client returns HLS for live streams; AVPlayer handles natively |

**DASH manifests** in the player response: look for `streamingData.dashManifestUrl`. SmartTubeIOS currently uses `adaptiveFormats` directly, which gives the same DASH segments but pre-enumerated.

**HLS for live streams:** The iOS client (`IOS`, client 5) returns `streamingData.hlsManifestUrl` for live content. AVPlayer can consume this `.m3u8` directly — no custom segment downloader needed.

---

## 9. Visitor Data and Session Continuity

yt-dlp extracts `visitorData` from InnerTube responses and includes it as `X-Goog-Visitor-Id` in subsequent requests. This is a Base64-encoded protobuf that represents the session state.

```
X-Goog-Visitor-Id: <visitorData>
```

**SmartTubeIOS:** Our current implementation does not thread `visitorData` across requests. For some content (mixes, recommendations), YouTube may return different results or errors without a consistent visitor context. Consider extracting and threading `responseContext.visitorData` from the first InnerTube response.

---

## 10. SOCS Cookie (Consent)

yt-dlp sets a `SOCS=CAI` cookie on `.youtube.com` for unauthenticated requests. Without this cookie, YouTube may redirect to a GDPR/consent page in some regions, blocking API responses.

```swift
// In URLRequest for InnerTube:
// Set-Cookie: SOCS=CAI; Domain=.youtube.com; Secure
```

This affects SmartTubeIOS for EU users. If home feed or search fails silently, check whether consent cookie injection is needed.

---

## 11. Subtitle / Caption Extraction

yt-dlp extracts captions from `streamingData` → no; from `captions.playerCaptionsTracklistRenderer.captionTracks[]`. Each track has:

```json
{
  "baseUrl": "https://www.youtube.com/api/timedtext?...",
  "name": { "simpleText": "English" },
  "vssId": ".en",
  "languageCode": "en",
  "kind": "asr"   // "asr" = auto-generated
}
```

**Auto-translated subtitles:** Available at `captions.playerCaptionsTracklistRenderer.translationLanguages[]`. Request a translated track by appending `&tlang=<code>` to the `baseUrl`.

**Format:** Default is `srv3` (XML). Append `&fmt=vtt` for WebVTT or `&fmt=json3` for JSON.

---

## 12. Chapter Markers

yt-dlp uses `macroMarkersListItemRenderer` from the `/next` endpoint (same as SmartTubeIOS), confirming our approach is correct. The parser looks for:

```
response → engagementPanels → engagementPanelSectionListRenderer
         → content → macroMarkersListRenderer
         → contents → macroMarkersListItemRenderer[]
```

Each item:
```json
{
  "title": { "simpleText": "Intro" },
  "timeDescriptionText": { "simpleText": "0:00" },
  "thumbnailImage": { ... },
  "onTap": {
    "watchEndpoint": { "startTimeSeconds": 0 }
  }
}
```

Use `onTap.watchEndpoint.startTimeSeconds` (integer) as the canonical chapter start time — more reliable than parsing `timeDescriptionText`.

---

## 13. SponsorBlock (yt-dlp Integration)

yt-dlp has native `--sponsorblock-mark` / `--sponsorblock-remove` options using the [SponsorBlock API](https://sponsor.ajay.app/).

**Categories yt-dlp supports** (same as what SmartTubeIOS implements):
`sponsor`, `intro`, `outro`, `selfpromo`, `preview`, `filler`, `interaction`, `music_offtopic`, `hook`, `poi_highlight`, `chapter`

**Action types:** `skip`, `poi` (point of interest / highlight), `full` (entire video is category), `mute`

The API endpoint SmartTubeIOS uses (`https://sponsor.ajay.app/api/skipSegments`) is the same one yt-dlp queries. No changes needed here — our implementation is aligned.

---

## 14. Known YouTube Client Anti-Abuse Patterns

Patterns yt-dlp works around that SmartTubeIOS should be aware of:

### 14a. `android_vr` SABR Streams
When `android_vr` clientVersion exceeds `1.65`, YouTube returns SABR (Server-Adaptive Bitrate Rate) streams instead of regular HTTPS URLs. SABR is a proprietary streaming protocol that requires a custom downloader. **Stay on `1.65.10` if using `android_vr`.**

### 14b. Rate Limiting (HTTP 429)
yt-dlp retries on 429 responses. For InnerTube, 429 typically means too many requests too fast. SmartTubeIOS should add a small inter-request delay when paginating continuations.

### 14c. `tv` Client `appInstallData` 
yt-dlp has a workaround: when using the `tv` client unauthenticated, it strips `appInstallData` from `INNERTUBE_CONTEXT.client.configInfo` to avoid a known issue. If unauthenticated TV requests fail (403), try omitting `configInfo` entirely from the context.

### 14d. Cookie Rotation Warning
yt-dlp detects when YouTube rotates auth cookies mid-session (login info cleared). SmartTubeIOS uses Bearer tokens (not cookies), so this specific issue doesn't apply — but token expiry/401 handling is the equivalent.

---

## 15. Key Source Files to Study in yt-dlp

| File | Why it's useful |
|---|---|
| [`yt_dlp/extractor/youtube/_base.py`](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py) | All client contexts, API call patterns, header generation |
| [`yt_dlp/extractor/youtube/_tab.py`](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_tab.py) | Browse/feed parsing (shelf, continuation tokens) |
| [`yt_dlp/extractor/youtube/pot/`](https://github.com/yt-dlp/yt-dlp/tree/master/yt_dlp/extractor/youtube/pot) | PO Token providers architecture |
| [`yt_dlp/extractor/youtube/_video.py`](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_video.py) | Full player response parsing, format extraction |

---

## 16. Approaches That Can Help SmartTubeIOS

### Short-term
1. **Track `clientVersion` for iOS client** — update periodically to match yt-dlp's `ios` entry. An outdated version may lose access to new formats or trigger bot detection.
2. **Consider `android_vr` (client 28) as a secondary stream source** — currently the most permissive unauthenticated client; useful when the iOS client starts requiring PO Tokens.
3. **Thread `visitorData`** from the first InnerTube response and echo it back in subsequent requests (`X-Goog-Visitor-Id` header).
4. **Use `startTimeSeconds` from chapter `onTap.watchEndpoint`** instead of parsing `timeDescriptionText` strings.

### Medium-term
5. **Monitor PO Token enforcement for iOS client** — if `adaptiveFormats[].url` starts returning 403 or throttled streams, the iOS client has been restricted. Migration path: `android_vr` → no PO Token needed.
6. **HLS for live streams** — iOS client returns `hlsManifestUrl`; feed directly to AVPlayer. yt-dlp confirms iOS client is the right one for HLS live content.
7. **DASH manifest URL** — `streamingData.dashManifestUrl` (when present) provides the full adaptive manifest. Parsing it gives segment URLs without enumerating `adaptiveFormats`. Useful for future adaptive streaming support.

### Long-term
8. **PO Token infrastructure** — if PO Token enforcement reaches all clients including TV, SmartTubeIOS will need to implement token generation. Study [yt-dlp/wiki/PO-Token-Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide) for the current state. A JS execution layer (WKWebView or JavaScriptCore) would be the iOS-native approach.
9. **n-sig deobfuscation (if ever needed)** — only needed if switching to a `web`-family client. The JS function name is found via regex in the player JS. This is a significant complexity addition — avoid web clients.

---

## References

- **yt-dlp main repo:** https://github.com/yt-dlp/yt-dlp
- **YouTube extractor base:** https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py
- **PO Token Guide:** https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide
- **n-sig throttling issue:** https://github.com/ytdl-org/youtube-dl/issues/29326
- **iOS 60fps device model:** https://github.com/TeamNewPipe/NewPipeExtractor/issues/680#issuecomment-1002724558
- **SponsorBlock categories:** https://wiki.sponsor.ajay.app/w/Segment_Categories
- **InnerTube API host matrix:** `www.youtube.com` (web/mobile), `youtubei.googleapis.com` (TV/authenticated), `music.youtube.com` (music)
