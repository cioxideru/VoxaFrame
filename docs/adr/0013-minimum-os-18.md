# 0013 — Minimum OS: iOS/iPadOS 18, native macOS 15 and tvOS 18

- ID: ADR-0013
- Status: accepted
- Date: 2026-10-18
- Deciders: Ivan Baranov (user decision, 2026-10-18)
- Basis: PLAN-0029 work package OSBUMP; [ADR-0012](0012-redesign-availability-and-tokens.md); [redesign package](../design/voxaframe-redesign/START-HERE.md)
- Supersedes: [ADR-0012](0012-redesign-availability-and-tokens.md), only its iOS/iPadOS 17, macOS 14 and tvOS 17 baseline
- Superseded-by: none

## Context

The redesign kept a 17/14/17 minimum and separate paths for APIs introduced in iOS/iPadOS 18,
macOS 15 and tvOS 18. The user raised the minimum versions on 2026-10-18 as part of PLAN-0029.
The Mac app uses native macOS; the earlier Catalyst descriptions in the agent guide and overview were stale.

## Decision

- Require iOS/iPadOS 18.0, native macOS 15.0 and tvOS 18.0 in the Swift package, shared build settings
  and every applicable app, extension, widget and UI-test target.
- Use the existing 18/15/18 code paths unconditionally: native tabs, Home's gesture recognizer,
  search focus and toolbar presentation, scroll visibility and scroll geometry. Remove their older
  fallbacks and the UI-test skip for pre-iPadOS 18. Use native `Tab` panes in macOS Settings.
- Keep OS 26+ checks and fallbacks: supported systems below 26 still need them. Keep platform guards,
  accessibility identifiers, design tokens and the other policies described in ADR-0012 unchanged.
- Preserve ADR-0012's text as the earlier record. Reverting this decision would require restoring both
  the earlier deployment targets and the compatibility paths.

## Consequences

New builds cannot be installed on iOS/iPadOS 17, macOS 14 or tvOS 17. Supported systems retain their
existing behavior with fewer compatibility branches. No persisted data or localized strings change.

Builds, package tests and simulator acceptance remain open in
[OQ-0019](../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).

## Alternatives considered

- Keep 17/14/17: rejected by the user's minimum-version decision; it retains the compatibility branches.
- Require OS 26 everywhere: rejected; 18/15/18 through 25 remain supported with the existing fallbacks.
