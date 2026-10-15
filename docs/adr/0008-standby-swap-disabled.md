# 0008 — Shorts standby-swap "instant swipe" promotion is permanently disabled

- ID: ADR-0008
- Status: superseded
- Superseded-by: [ADR-0010](0010-remove-iframe-player.md)
- Date: 2026-06
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

`ShortsEmbedPlayerViewModel`'s "instant swipe" mechanism pre-warmed the next Short in a hidden
`WKWebView`, then promoted it by moving it from the hidden container into the visible one
(tasks #271-278). This turned out to be unreliable **on physical devices, not just Simulator**:
verified via `ShortsVisualPlaybackUITests.testHomeFirstShortPlaysAcrossThreeSwipes` on a real
iPhone 16 Pro Max — initial load and same-webview reload rendered correctly, but every
standby-swap promotion (reparenting the `WKWebView` between containers) went solid black, despite
JS-side diagnostics confirming decode was correct the whole time. Three independent fixes
targeting the reparent (forced layout + `isHidden` toggle, replacing near-zero opacity with
off-screen positioning, explicitly deactivating stale Auto Layout constraints) all failed.

(Separately and unrelated: the iOS Simulator cannot decode VP9/AV1 at all — Shorts are served
VP9/AV1-only. That's an accepted, permanent Simulator/WebKit limitation, not part of this
decision; see the Gotchas in `AGENTS.md`.)

## Decision

`goTo(_:)`'s standby-swap and previous-swap hot paths are permanently disabled (verified current:
`ShortsPlayerView+Navigation.swift` — the comment block above `prewarmStandby(for:)` documents
this). Every swipe, forward or backward, goes through `loadVideo(at:)`/`swapEmbed` — an
iframe-`src` swap on the one `WKWebView` that stays attached to the visible container and is
never reparented. `prewarmStandby(for:)` is no longer called. The supporting VM infrastructure
(`isStandby`/`activate()`/`loadShortAsStandby`, the hidden `ShortsTOSWebView` hosts for
`standbyVM`/`previousVM`) is left in place but unreachable, for a future revisit if the
reparenting bug is ever root-caused.

## Consequences

- Good: `ShortsVisualPlaybackUITests` passes reliably on both Simulator and device with the
  cold-reload-every-swipe fallback, with no measurable slowdown versus the broken promotion path.
- Bad: swipe transitions are not "instant" (no pre-warmed standby webview) — every swipe pays a
  cold-load cost, deemed acceptable versus a black screen.
- Neutral: dead-but-present standby infrastructure remains in the codebase as a base for a future
  fix, rather than being deleted — a deliberate choice to preserve investigation work.

## Alternatives considered

- **Keep debugging the reparenting bug**: three independent fixes failed (layout/isHidden,
  opacity/positioning, Auto Layout constraints) before disabling the mechanism instead.
- **Delete the standby infrastructure entirely**: rejected — kept unreachable for a future fix.

## Do not re-enable without

Root-causing the WKWebView reparenting bug (#279) first — it reliably reproduces a black screen
on both Simulator and device, independent of the fixes above. Check `git log` on
`ShortsPlayerView+Navigation.swift`/`ShortsTOSWebView.swift` to confirm this path is still
disabled before assuming a new Shorts report is a regression of something else.

## Implementation check — 2026-10-15

`ShortsPlayerView+Navigation.goTo` still calls `loadVideo(at:)` and does not invoke `prewarmStandby(for:)`; standby hosts remain unreachable. Historical passing runs above were not repeated. Re-enabling promotion still requires root-causing issue #279.

## Superseded — 2026-10-15

The embed player this record governs was removed; see [ADR-0010](0010-remove-iframe-player.md).
