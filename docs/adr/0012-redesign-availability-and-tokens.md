# 0012 — Redesign: availability fallbacks and token ownership

- ID: ADR-0012
- Status: proposed
- Date: 2026-10-17
- Deciders: Ivan Baranov (accent and logic scope, 2026-10-17); availability policy and token ownership proposed
- Basis: [PLAN-0027](../exec-plans/active/voxaframe-redesign.md), [design package](../design/voxaframe-redesign/START-HERE.md)
- Supersedes: none
- Superseded-by: none

## Context

The package targets "Apple 27" with Liquid Glass, a search-role tab, a tab-bar bottom accessory and an adaptive sidebar.
The app still supports iOS/iPadOS 17, macOS 14 and tvOS 17, and the design states that minimum versions do not change.
The code has no `glassEffect` today; "Disable Liquid Glass" only restyles the UIKit tab bar. `AccentColor` is not defined,
so "System" currently means the platform default. The design tokens are a specification, not a runtime store.

## Decision

- Every API newer than the minimum OS (`glassEffect`, `Tab(role: .search)`, `tabViewBottomAccessory`, `.sidebarAdaptable`) is used
  behind `#available` with the nearest standard component as fallback. Glass is not imitated with custom blurs on older systems.
- One view modifier in `Views/DesignSystem/` applies glass. It falls back to an opaque `elevated` surface when Reduce Transparency
  is on or `AppSettings.disableLiquidGlass` is set; views never decide this themselves.
- Tokens are Swift constants in `Views/DesignSystem/` plus light/dark colour sets in package resources. Views use system semantic
  colours where they exist and never hard-code hex. `tokens.json` stays documentation.
- Accent "System" resolves to the coral action colour on iOS, iPadOS and tvOS and to the system accent on macOS, once the prominent
  button style that pairs it with the `onAction` label exists (the system label is white and fails contrast on the dark-mode coral).
- `AppSection` raw values and accessibility identifiers are not renamed with visible text.

## Consequences

Older systems look like a standard system app, not like the mockups; the design is checked on 17 and on 26+. The mini-player
accessory may conflict with the persistent UIKit player layer, so stage 2 starts with a spike and keeps the current overlay
if the layer would be duplicated ([OQ-0019](../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups)).

## Alternatives considered

- Raise the minimum OS to 26: rejected; the design and brief keep 17/14/17.
- Reproduce glass with materials on old systems: rejected; it contradicts the "no imitation" rule of the design system and costs performance.
- Coral accent on macOS too: rejected; macOS HIG expects the user's system accent.
