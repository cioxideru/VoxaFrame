# PLAN-0051: Buffered range on the player timeline

Status: active

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
| Implementation | | NOT RUN |
| Simulator check | | NOT RUN |
