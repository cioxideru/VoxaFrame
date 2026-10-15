# 0006 — TOS-compliant WKWebView player is the default player on iOS

- ID: ADR-0006
- Status: superseded
- Superseded-by: [ADR-0010](0010-remove-iframe-player.md)
- Date: 2026-06-11
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

The original iOS playback pipeline resolved raw HLS/DASH streams and fed them to AVPlayer,
inheriting the whole class of failures documented in `docs/modernization/AUDIT.md` §2.2:
CDN/geo blocks, BotGuard/PO-token churn, HLS/DASH manifest-parsing errors. A
TOS-compliant player embeds YouTube's own IFrame player in a WKWebView instead, so YouTube's
own player handles stream resolution and ABR.

## Decision

`TOSPlayerViewModel` (WKWebView-hosted YouTube IFrame player) is the default and only player on
iOS; `useTOSPlayerOnIOS` is hardcoded `true` in `SettingsStore` with no user-facing toggle
(verified current: `SettingsStore.swift:35`, `PlayerRouter.swift:39`). Existing installs were
migrated automatically; the old AVPlayer/HLS-extraction pipeline was removed from the iOS path
(it's still used on tvOS and for iOS Shorts' non-embed cases). `docs/modernization/PLAN.md`
DEC-3 keeps this unchanged and out of scope for the modernization program.

## Consequences

- Good: removed an entire class of playback failures caused by CDN/geo blocks and BotGuard/PO-token
  issues on iOS (CHANGELOG 4.5).
- Good: YouTube's own player owns ABR — no more manual quality-cascade logic needed on this path.
- Bad: video quality/ABR on iOS is now controlled entirely by YouTube's player; the app's manual
  quality picker and "max resolution" setting no longer apply on iOS (CHANGELOG 4.5, "Changed").
- Bad: WKWebView playback has its own limitations — no system Picture-in-Picture without a real
  user tap (see ADR-0007, and `docs/modernization` memory: WKWebView `evaluateJavaScript` has no
  user activation, so Swift-triggered PiP/fullscreen calls never work).

## Alternatives considered

- **Keep the AVPlayer/HLS-extraction pipeline as the iOS default, harden it instead**: this is
  effectively what WS4/WS5 now do, but only for the *remaining* non-TOS uses (tvOS, Shorts) — the
  TOS-as-default decision for the main iOS video player predates the modernization program and
  is not being revisited by it.

## Implementation check — 2026-10-15

The default remains `useTOSPlayerOnIOS = true` in `AppSettings`, but `SettingsStore` now reads the persisted setting (with a test override), `SettingsView.playerEngineSection` exposes a toggle, and `PlayerRouter.open` permits AVPlayer selection and per-video fatal-embed fallback. iOS Shorts use `ShortsEmbedPlayerViewModel`. The accepted text above records the original decision; the exclusive-player statement no longer matches implementation. The replacement decision is [ADR-0010](0010-remove-iframe-player.md) (OQ-0010 closed).

## Superseded — 2026-10-15

The embed player this record governs was removed; see [ADR-0010](0010-remove-iframe-player.md).
