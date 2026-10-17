# 0011 — Bounded native Shorts preloading

- ID: ADR-0011
- Status: accepted
- Date: 2026-10-17
- Deciders: maintainer request, Codex implementation
- Basis: [PLAN-0015](../exec-plans/completed/shorts-preloading.md), [native playback](0010-remove-iframe-player.md)
- Supersedes: none
- Superseded-by: none

## Context

Full-screen Shorts previously warmed metadata with unowned tasks but recreated media on every
swipe. The view's feed, consumed cursors and regular-player history could grow throughout a
session. The user requested native preloading with bounded tasks, memory and storage.

## Decision

`PlaybackViewModel` owns one `ShortsPreloader` only in Shorts mode. This session-scoped coordinator
owns one cancellable preparation task and one prepared `AVPlayer`. `ShortsStreamPreparing`,
injected through its initializer, isolates asynchronous native-stream preparation for tests.
It uses the existing VISIONOS HLS policy and manifest parser. Networking uses async URLSession
and AVFoundation performs buffering; there is no application-owned worker thread or process.

Preparation begins after the current video plays. A muted player prerolls the next item with a
three-second forward-buffer hint and at most a 720p quality hint. These are AVFoundation hints,
not hard byte limits. On swipe the view model adopts the entire prepared player and transfers
quality, audio, SponsorBlock and observers together. The existing video surface stays attached;
its player binding changes. Transferring a live `AVPlayerItem` alone is invalid in AVFoundation.
The user's actual quality cap is restored on promotion. A miss uses normal foreground playback.

Only the current video and one speculative item are owned. A 30-second deadline, five-minute
expiry, memory pressure, settings/video changes, backgrounding and dismissal cancel stale work.
Generation, preference and current-item checks reject late completion. Native I/O may finish
cancelling asynchronously. Preparation starts no translation, tracking, related-feed requests or
persistent media writes; its URLSession has an ephemeral configuration and no URLCache.

Core's `ShortsFeedWindow` owns retention policy: at most 120 feed entries, 12 previous entries and
64 consumed continuation tokens. The view supplies navigation and lifecycle intent. Shorts
does not populate the regular player's navigation history. The shared metadata disk cache keeps
its existing 20 MiB limit and reconciles existing files on the first write after reopening.

## Consequences

Prepared swipes avoid stream resolution and initial buffering. Preparation failures remain
invisible and fall back to ordinary playback. One extra native player consumes bounded session
resources and speculative network traffic. The backward window intentionally retains only the
latest 12 videos; oversized incoming batches are trimmed to the window's capacity.

Local H.264 iPad Simulator tests measure load-to-ready, playback progress and sustained switching;
they do not establish live YouTube latency, physical-device memory or VP9/AV1 decoding. Verification
and remaining device acceptance are recorded in the plan and [OQ-0013](../OPEN_QUESTIONS.md#oq-0013--ios-hls-prewarm-on-card-appearance).

## Alternatives considered

- Metadata-only lookahead does not prepare media and leaves the swipe's buffering cost intact.
- AVQueuePlayer defers buffering its next item behind the current item on the tested Simulator,
  so early swipes did not reliably reuse a prepared stream.
- Moving AVPlayerItem between players raised an AVFoundation attachment exception. Adopting
  the prepared player preserves its item and buffer without attempting that transfer.
- Multiple playback view models would duplicate session ownership, translation and observers.
  The removed WKWebView promotion mechanism in superseded ADR-0008 is not restored.
