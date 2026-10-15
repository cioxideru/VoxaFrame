# 0010 — Remove the IFrame (TOS) and Shorts embed players; AVPlayer is the only engine

- ID: ADR-0010
- Status: accepted
- Date: 2026-10-15
- Deciders: maintainer
- Basis: ADR-0006, ADR-0007, ADR-0008, OQ-0010 (closed by this record)
- Supersedes: [ADR-0006](0006-tos-player-default-on-ios.md), [ADR-0007](0007-no-hybrid-avplayer-handoff-for-tos.md), [ADR-0008](0008-standby-swap-disabled.md)
- Superseded-by: none

## Context

iOS and macOS carried two WKWebView players built on YouTube's IFrame embed: the TOS player
(`TOSPlayerViewModel`, default on iOS per ADR-0006, opt-in on macOS) and the iOS Shorts embed
player (`ShortsEmbedPlayerViewModel`). tvOS and every fallback already used the AVPlayer pipeline
(`PlaybackViewModel`). Three players meant SponsorBlock, watch history and Now Playing were wired
three times, and the embed paths carried their own failure modes (error 153 / bot check, no
Swift-triggered PiP, WKWebView reparenting black frames — ADR-0007, ADR-0008). ADR-0006's
"only player" wording had already drifted (OQ-0010).

## Decision

Delete both embed players and everything that selects them: `useTOSPlayerOnIOS`/`useTOSPlayerOnMac`
settings and toggles, `TOSPlayerStateStore` and the TOS mini player, `ShortsEmbedURL`, the
src-swap spike, their tests and accessibility IDs. `PlayerRouter.open` always presents the
AVPlayer pipeline. `ShortsPlayerView` uses `PlaybackViewModel` on every platform (the path tvOS
already used). Reversal means restoring the deleted files from git history.

## Consequences

- Good: one playback engine; quality picker, captions, PiP and Yandex voice-over are always available.
- Good: about 15k lines and two WKWebView player stacks removed.
- Bad: iOS is again exposed to the stream-resolution failures ADR-0006 avoided (CDN/geo blocks,
  BotGuard/PO-token churn); the AVPlayer fallback cascade (ADR-0005) carries that load.
- "Play Incognito" (#94), previously honored only by the embed player, is wired into
  `PlaybackViewModel` (`load(video:incognito:)`).
- Device playback of iOS Shorts through AVPlayer has not been re-verified.

## Alternatives considered

- **Keep the TOS player behind the setting**: keeps three player stacks for a minority path.
- **Rebuild Shorts on a dedicated AVPlayer view model**: not needed; `ShortsPlayerView` already
  had a `PlaybackViewModel` branch for tvOS.
