# HLS n-parameter descrambling

Status: current
Reviewed: 2026-10-15 (source inspection)

[YouTubeNDescrambler.swift](../../SmartTubeIOS/Sources/SmartTubeIOS/Services/YouTubeNDescrambler.swift)
is compiled for Simulator and exposes `descrambleURL` and `ytDlpHLSPlaylistURL`. It downloads
and caches player JavaScript, solves the n parameter, and replaces `/n/SCRAMBLED/` in stream URLs.
The playlist helper also supports a seeded playlist and cookie-seeding fallback. These are
Simulator diagnostics; they do not establish physical-device playback support.

Implementation constraints retained from the original investigation:

- iOS SDK code uses `posix_spawn` and pipe/file actions instead of `Process` or `popen`;
  the tvOS branch returns without spawning.
- Encode a standalone JavaScript string with `JSONEncoder`; serializing it as a top-level
  JSON object can raise an Objective-C exception.
- A usable manifest alone does not prove its media segments can be fetched or decoded.

The old `testAutoQualityAbove360p` 1080p/16-second result belongs to a historical run and is
not current acceptance. No live test was rerun here; [OQ-0005](../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance)
tracks current playback verification.

## Historical observation (not rerun)

The original note recorded `testAutoQualityAbove360p` passing in 16 seconds for
`Wu8xNx4njoM` with minimum height 720 and observed playback at 1080p. It used the WebSafari
client (WEB name ID 1, macOS Safari user agent), a six-variant HLS manifest and n descrambling.
The investigation observed HTTP 403 for scrambled segment URLs and 200 after descrambling;
this is historical evidence, not a general guarantee for current sessions or clients.
