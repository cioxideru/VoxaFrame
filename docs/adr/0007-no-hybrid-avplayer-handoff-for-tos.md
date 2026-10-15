# 0007 — No hybrid AVPlayer handoff for TOS background play / PiP

- ID: ADR-0007
- Status: accepted
- Date: 2026-06
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

The TOS player (ADR-0006) is a WKWebView-hosted IFrame; simple JS-triggered native WebKit PiP
does not work (confirmed across 5 live-device experiments while investigating background
audio / system Picture-in-Picture support). One proposed fix was a "hybrid handoff": swap to a
hidden native AVPlayer (reusing the already-working `AVPictureInPictureController` and
background-audio code from the pre-TOS pipeline) whenever the app backgrounds, then swap back to
WKWebView in the foreground.

## Decision

Do not implement a hybrid/dual-engine handoff between WKWebView and AVPlayer for the TOS player.
Rejected immediately and without a design review when proposed.

## Consequences

- Good: keeps the TOS player on one playback engine with one set of failure modes, at a point
  where the player was still being actively stabilized (Shorts pause/resume races, a
  `rateObserver` crash, and others fixed in the same period).
- Good: avoids a synchronization/handoff layer between two engines, which is a well-known source
  of state-drift bugs (which engine is "the" source of truth for position/rate during the swap
  window?).
- Bad: no system-level Picture-in-Picture or reliable background audio for the TOS player today.
  Scoped, additive options remain open (e.g. proper `MPNowPlayingInfoCenter`/
  `MPRemoteCommandCenter` wiring for foreground/mini-player control) without touching the engine.

## Alternatives considered

- **Hybrid AVPlayer handoff** (described above): rejected without a design review — the
  maintainer's stated reasoning was that a second playback engine plus a handoff layer was too
  risky for a player still being stabilized, even to gain background/PiP support. Do not
  re-propose this without being asked again.

## Implementation check — 2026-10-15

No TOS-to-AVPlayer handoff for background/PiP is implemented. `PlayerRouter` selecting AVPlayer at video open or after a fatal embed error is a different mechanism, not a background handoff. Device behavior was not rerun; see [OQ-0005](../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).
