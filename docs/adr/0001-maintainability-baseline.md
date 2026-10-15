# 0001 — Maintainability baseline

- Status: accepted
- Date: 2026-09-10

## Context

WS1 (modernization program, see `docs/modernization/`) introduces SwiftLint with a frozen
`.swiftlint.baseline` so SwiftLint (`--baseline .swiftlint.baseline`) fails only on *new* violations, not the ~1,162 pre-existing
ones. That baseline needs a recorded starting point so future work can show the ratchet moving
down instead of just silently accumulating exceptions.

## Decision

Record the metrics below as the baseline. Every future PR that touches a metric here should move
it toward the WS0-stated program-wide targets (`docs/modernization/PLAN.md` §3), never away from
them. `scripts/metrics.sh` reproduces the metrics that have a recipe; the rest are ad hoc greps recorded
here for now until `scripts/metrics.sh` covers them.

## Baseline (2026-09-10, commit range WS0–WS1-T1.3)

**SwiftLint** (`swiftlint lint --config .swiftlint.yml --reporter summary`): **1,162 violations
across 192 files**, all captured in `.swiftlint.baseline`. Largest contributors: `identifier_name`
(307), `force_unwrapping` (224), `raw_accessibility_identifier` (159), `implicit_optional_initialization`
(97), `async_without_await` (47), `function_body_length` (47).

**Largest Swift files:**

| Lines | File |
|---|---|
| 2,935 | `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Fallback.swift` |
| 1,486 | `SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Loading.swift` |
| 1,303 | `SmartTubeIOS/Sources/SmartTubeIOSCore/BotGuardClient.swift` |
| 1,233 | `SmartTubeIOS/Sources/SmartTubeIOSCore/InnerTubeAPI+VideoRenderers.swift` |
| 1,001 | `SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/TOSPlayerViewModel.swift` |

**Other metrics:**

| Metric | Value |
|---|---|
| Raw `accessibilityIdentifier("` literals in Sources | 157 |
| `sleep(` in UI tests | 373 |
| `XCTSkip` in UI tests | 119 |
| `.shared` reads in `Views/` | 91 |
| Files matching `mirror` under `Tests/` | 20 |
| `AGENTS.md` | not yet created — WS1-T1.5 |

These match `docs/modernization/AUDIT.md`'s figures (157 / 373 / 119) recorded on the same day, so
the two documents agree on the starting line.

## Consequences

- SwiftLint is green today; it stays green only by not introducing new violations of any kind
  the baseline already tracks, including in files the baseline covers.
- Deleting a violation from a file removes its baseline entry the next time `swiftlint lint --write-baseline .swiftlint.baseline --config .swiftlint.yml`
  is regenerated (not automatic) — regenerate deliberately, not to hide new violations.
- The metrics above are a snapshot, not a target. Targets are in `docs/modernization/PLAN.md` §3.
