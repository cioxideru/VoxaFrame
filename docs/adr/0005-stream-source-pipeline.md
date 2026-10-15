# 0005 — `StreamSource` + `ResolutionPipeline` replace the `exhaustiveRetry` cascade

- ID: ADR-0005
- Status: proposed
- Date: 2026-09-10
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

`exhaustiveRetry` (`PlaybackViewModel+Fallback.swift:88-528`) is a 440-line hand-written cascade
of ~20 ordered branches trying 13 named stream methods plus 6 unnamed ones, with a 7-InnerTube-
client list duplicated in two different shapes that must be kept in sync by hand
(`docs/modernization/AUDIT.md` §2.2). Every guard in this file exists because of a real,
previously-hit bug (`docs/modernization/PLAN.md` §7 risk table) — this is not dead complexity,
it's load-bearing, undocumented policy.

## Decision

Replace the cascade with an ordered list of `StreamSource` adapters driven by one small
`ResolutionPipeline`, introduced via strangler fig: each `StreamSource` ports its existing
branch verbatim first (proving parity against characterization tests), then cleans up second.
The legacy path stays reachable until parity is proven. This is WS4's central piece
(`docs/modernization/workstreams/WS4-playback-seams-and-pipeline.md`).

## Consequences

- Good: turns an imperative, hard-to-extend cascade into data (an ordered list) plus one driver —
  adding a client means adding one `StreamSource`, not editing a `TaskGroup` and a serial loop
  in two places.
- Good: strangler fig means shipping behaviour is never at risk of a big-bang regression; each
  `StreamSource` is verified against the real branch it replaces before the old code is deleted.
- Bad: this is the single largest, riskiest piece of the whole program (4-6 week estimate,
  `docs/modernization/PLAN.md` §2) — playback regressions here are directly user-visible and the
  existing guards are scar tissue from real incidents, not guesses.

## Alternatives considered

- **Leave `exhaustiveRetry` as-is, just add tests around it**: rejected as insufficient — testing
  a 440-line undocumented cascade doesn't make it maintainable, and the audit's "every task ends
  green" principle still requires being able to change one client's behavior without touching
  unrelated branches.
- **Rewrite from scratch**: rejected — violates the program's "behaviour-preserving by default"
  principle; the existing cascade's ordering encodes real-world lessons that a rewrite could
  silently drop.

## Status note

Kept `proposed` until WS4-T4.6 actually lands the pipeline and proves parity — this ADR records
the decision to attempt it, not a completed migration.

## Implementation check — 2026-10-15

Status remains `proposed`. The current tree splits the cascade into `PlaybackViewModel+ExhaustiveRetry.swift`, `+FallbackRace.swift`, and stream helpers, but defines neither `StreamSource` nor `ResolutionPipeline`. File decomposition is not pipeline parity. See [OQ-0002](../OPEN_QUESTIONS.md#oq-0002--stream-pipeline-and-contributor-guide).
