# PLAN-0048: Live streams in watch history

Status: completed (2026-11-09)

- Owner: coordinator (single session).
- Git boundary: local `master`, after PLAN-0047.
- Scope: a live stream watched in VoxaFrame by a signed-in account appears in YouTube's watch history.

## Basis (iPad log, 2026-11-09)

- Four live streams were watched (`VoapoQmDzVQ`, `QuPSFtsKJW8`, `DxgDeW-gIcU`, `ythTqjjTqXo`), two of them for over 40 s.
  The account player response returned `playbackTracking` for each, but no checkpoint, flush or stats ping was sent.
- A live HLS item reports an indefinite duration, so the player's `duration` stays 0. `WatchtimeTracker.checkpoint`,
  `checkpointIfDue` and the transition flush return early without a length, and the player's time observer, `stop()`,
  `suspend()` and `load()` only call the tracker when `duration > 0`.

## Changes

1. `WatchtimeTracker` tracks a live stream once the player marks it: pings carry `len=0` and the player position, no
   final ping, and no resume position is saved. A transition resets the mark and flushes the old stream as live.
2. The player marks the stream live when its item is ready to play and its duration is still indefinite, and calls
   the tracker for it in the time observer, `stop()`, `suspend()` and `load()` through one condition.
3. Found on the iPad: every item reports an indefinite duration until it is ready to play, so the first build marked
   the 880 s video `hBqvRjM4dhk` live 1 s before readyToPlay (its pings carried `len=0`). The readyToPlay condition
   in change 2 fixes it.

## Acceptance

- Unit tests: live checkpoints send playback and watchtime pings with `len=0`, never `final=1`, and save no position;
  the transition flush of a live stream sends both pings; an item that is not ready is never a live stream.
- `scripts/ci.sh`, SwiftLint, iOS and tvOS builds.
- iPad: the log shows stats pings for a live stream; the stream appears in the official app's history.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Root cause | iPad log and code above | confirmed |
| Implementation | changes 1–2 | done |
| Checks | `scripts/ci.sh` (1425 tests), SwiftLint, ast-grep rules; `scripts/verify.sh` with iOS and tvOS builds (Smoke stage skipped, OQ-0003) | passed |
| iPad, first build | live `ythTqjjTqXo`: playback and watchtime pings with `len=0.000`, st=894 et=924, then 924→936, all `ok`; the video `hBqvRjM4dhk` was wrongly marked live (change 3) | partly passed |
| Fix and checks | change 3; `scripts/ci.sh` (1427 tests), SwiftLint, ast-grep rules | passed |
| iPad, second build | video `EJ2XRN2yVVY` pinged with `len=1005.160` and never marked live; live `uPcmBYiX0tE` marked after readyToPlay, pings with `len=0.000` (st=894 et=924, then 924→930), all `ok` | passed |
| History | the user found the live stream `ythTqjjTqXo` in the official app's history | passed |
