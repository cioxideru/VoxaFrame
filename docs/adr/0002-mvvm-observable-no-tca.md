# 0002 — MVVM with `@Observable`, no TCA

- ID: ADR-0002
- Status: accepted
- Date: 2026-09-10
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

The codebase needs one state-management approach agents and contributors can rely on without
re-deriving it per file. Swift has several viable options as of 2024-2026: `ObservableObject`
+ Combine, `@Observable` (Swift 5.9+), or a third-party unidirectional framework like
The Composable Architecture (TCA).

## Decision

MVVM with `@MainActor @Observable` view models. No `ObservableObject`, `@Published`, or Combine
in new code. No TCA or other state-management framework (`docs/modernization/PLAN.md` §8,
out of scope).

## Consequences

- Good: the `@Observable` migration is already complete — zero `ObservableObject` in the
  codebase (verified: `grep -rc ObservableObject SmartTubeIOS/Sources` is 0 except doc comments
  referencing the old pattern). No new framework dependency or learning curve.
- Good: `@Observable` integrates directly with SwiftUI's diffing without a Combine bridge.
- Bad: MVVM alone doesn't prevent the god-object growth seen in `PlaybackViewModel` (6,024 LOC,
  ~93 stored properties per `docs/modernization/PLAN.md` §3) — WS4/WS5 address that with seams
  and a shared `PlaybackSession`, not a framework swap.

## Alternatives considered

- **TCA**: rejected — a full rewrite of every view model's structure for a codebase this size,
  with a bug-scarred playback subsystem already mid-stabilization (`docs/modernization/AUDIT.md`
  §2.2), is a much larger and riskier change than the modernization program's stated goal
  ("without a rewrite and without breaking shipping behaviour").
- **Keep `ObservableObject`/Combine**: rejected — already fully migrated away from; reverting
  would be pure churn.

## Implementation check — 2026-10-15

View models use `@MainActor` / `@Observable`; the package has no TCA dependency. Historical line counts above are not current measurements.
