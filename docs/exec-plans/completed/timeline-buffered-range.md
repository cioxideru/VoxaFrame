# PLAN-0051: Buffered range on the player timeline

Status: completed (2026-11-20)
Resolution: delivered; Codex review (two rounds) and Fable audit accepted. Visual checks other than the iOS
simulator in the dark theme are tracked in [OQ-0019](../../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).

- Owner: coordinator; one executor.
- Git boundary: worktree `wt/timeline-buffer-0051` from `master` after `a4a5e7bc`.
- Basis: fork [axrbarsic/AxrTube](https://github.com/axrbarsic/AxrTube) `18a13727`, `63da8bc9` (cached and
  buffered parts on the progress bar), review of 2026-11-20. Their caching HLS proxy is not in scope.
- Constraints: no new branches in the playback fallback cascade (ADR-0005); the stall watchdog and seek behaviour
  stay as they are; the timeline stays readable with Liquid Glass and its opaque fallback.

## Scope

Show how far ahead the current item is buffered on the player timeline (iOS, iPadOS, macOS and tvOS), from the
`AVPlayerItem.loadedTimeRanges` range that contains the playhead. The buffered layer sits between the track and the
played part, updates while playing, paused and after a seek, and resets when the item changes. A fully downloaded
offline video shows the whole timeline as buffered. Live streams without a fixed duration show nothing.

## Acceptance

- The range calculation is a pure function with Swift Testing tests: playhead inside, before and after the ranges,
  several ranges, zero or indefinite duration, clamping to the duration.
- No extra view-model updates per frame: the value is published only when it changes noticeably.
- `scripts/ci.sh`, SwiftLint and the ast-grep rules; iOS, tvOS and macOS builds; a simulator screenshot of the
  timeline with a buffered range.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Review | AxrTube commits read on 2026-11-20 | done |
| Implementation | `PlayerTimeline.bufferedSpan` and `bufferedSpanChanged` with `PlayerTimelineTests`; `PlaybackBufferedRangeTests` (measurement, local item, publish threshold; KVO delivery while paused of more loaded ranges, a length that turns finite and item swaps, without manual refresh; a replaced item is released); `ShortsPreloadingTests` covers player adoption; package tests, SwiftLint, iOS, tvOS and macOS builds passed on 2026-11-20 | done |
| Simulator check | iPhone 17 simulator, dark theme, guest, H.264 video: the buffered band runs from the playhead at 0:21 to about 43 % of the bar, between the played part and the track (2026-11-20). Not observed: light theme, bright frames, Reduce Transparency, `disableLiquidGlass`, tvOS, offline items | done (iOS dark only) |
| Review | Codex: round 1 two findings (late length while paused, tests bypassing KVO), round 2 clean | passed |
| Audit | Fable high: accepted, four nits (comments, seek-refresh test, test helper notes, design README owner) | passed |
