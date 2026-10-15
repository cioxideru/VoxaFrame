> Status: archived — classified from code on 2026-10-15.
> The named ytDlpHLSVariantURL entry point no longer exists (the helper is ytDlpHLSPlaylistURL), fallback code has moved, and the May pass/client-availability claims are historical. Current live acceptance is OQ-0005.
> Current references: [architecture](../architecture.md), [open questions](../OPEN_QUESTIONS.md).

# HLS Quality / testAutoQualityAbove360p

## Passing fix (2026-05-23)
- `testAutoQualityAbove360p` (videoId: `Wu8xNx4njoM`, minimumHeight: 720) — PASSES 3/3
- Fix: in `#if targetEnvironment(simulator)` block inside `attemptURL`, call `YouTubeNDescrambler.ytDlpHLSVariantURL(videoId:)` FIRST to get a pre-descrambled 720p/1080p HLS variant URL from yt-dlp; only fall back to the JS-solver proxy if yt-dlp unavailable.
- Root cause of failure: iOS Simulator URLSession routes CDN segment requests differently (likely IPv6 vs IPv4) from how yt-dlp/Python makes requests. `ip/x.x.x.x/` baked into segment URLs embeds the InnerTube API caller's IP; segment requests from the simulator may arrive from a different IP → CDN 403. yt-dlp's API call + segment requests share the same Mac IP → 200.
- Key files: `YouTubeNDescrambler.swift` (added `static ytDlpHLSVariantURL`), `PlaybackViewModel+Fallback.swift` (try yt-dlp before `descrambledVariantURL` in simulator)

# DASH Quality Switch Tests — FIXED (May 2026)

Both `testQualityCycleOnDASHVideo` and `testQualityCycleOnDASHVideo_GZzsJMSQKAs` now pass.

**Root fix:** `PlayerInfo.asMuxedOnly` (InnerTubeModels.swift) + used in `tryAllStreams` muxed path (PlaybackViewModel+Fallback.swift). Prevents adaptive-format leakage into quality picker when muxed is the actual playback stream.

**Adaptive stream status (as of May 2026):** All clients fail adaptive — rqh=1 CDN 403 (iOS, Android), AVFoundation -11828 (TV auth), bot-detect (Android VR), login-required (WebCreator), unsupported (TV Embedded).

**Test behavior when adaptive unavailable:** picker shows only 360p muxed → test skips 720p-144p, selects 360p, resolution assertion instant pass.
