# 0004 — Plain protocol + initializer injection, no DI framework

- ID: ADR-0004
- Status: accepted
- Date: 2026-09-10
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

`docs/modernization/PLAN.md` DEC-7 asks whether to adopt a DI helper library (e.g. Factory) or
keep plain `init` injection as seams get added across WS4/WS6/WS7. Today, dependency injection
is inconsistent: `AppEntry.swift` does manual constructor injection reasonably well, but it's
duplicated in `Smart_TubeApp.swift` and again in a dead, drifted `SmartTubeIOS/SmartTubeApp.swift`
(`docs/modernization/AUDIT.md` §2.3), and most services (`AuthService`, `SettingsStore`,
`CrashlyticsLogger`) reach directly for `.shared`/static singletons instead of being injected.

## Decision

Protocol + initializer injection, with one composition root per app target. No DI framework.
Revisit only if a single composition root exceeds ~150 lines (the PLAN's own trigger for
reconsidering, at WS8).

## Consequences

- Good: zero new dependency, zero magic — anyone reading a type's `init` sees its whole
  dependency graph.
- Good: matches the one already-working example (`AppEntry.swift`'s manual injection) instead
  of introducing a second pattern alongside it.
- Bad: as more seams appear (WS4 `StreamSource`s, WS6 cache/store seams, WS7 `AppEnvironment`),
  a hand-written composition root could get large — explicitly tracked as the revisit trigger
  above, not ignored.

## Alternatives considered

- **Factory (or similar DI library)**: rejected for now — adds a dependency and an indirection
  layer before there's evidence plain injection can't scale to this codebase's needs. The
  duplicated-composition-root problem is about discipline (one root, not three copies), which a
  DI framework doesn't inherently fix.

## Implementation check — 2026-10-15

The app entry points still construct dependencies directly and the package has no DI framework. Consolidating composition roots is unfinished; see [OQ-0009](../OPEN_QUESTIONS.md#oq-0009--architecture-debt).
