# Architecture Decision Records

Before proposing an architecture change, read this folder; a rejected idea is re-proposed only
with new evidence. Use the [template](template.md), with a permanent `ADR-NNNN` ID and the existing numbered
filename. Status is one of `proposed`, `accepted`, `rejected`, or `superseded`; use a separate
`Superseded-by` link for a replacement. Preserve accepted Context, Decision, and Consequences:
new decisions get new numbers. Metadata and dated implementation notes may identify drift
without silently rewriting the original decision. Keep records concise; do not omit evidence
to meet an arbitrary line limit.

Code reconciliation: 2026-10-15. `accepted` records a decision, not a passing runtime test.
ADR 0005 remains proposed: the cascade is split across files but no `StreamSource` or
`ResolutionPipeline` exists. ADRs 0006–0008 are superseded by ADR 0010, which removed the embed players.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-maintainability-baseline.md) | Maintainability baseline | accepted |
| [0002](0002-mvvm-observable-no-tca.md) | MVVM with `@Observable`, no TCA | accepted |
| [0003](0003-no-project-generation.md) | No Tuist/XcodeGen — the `.xcodeproj` is the source of truth | accepted |
| [0004](0004-plain-init-injection.md) | Plain protocol + initializer injection, no DI framework | accepted |
| [0005](0005-stream-source-pipeline.md) | `StreamSource` + `ResolutionPipeline` replace the `exhaustiveRetry` cascade | proposed |
| [0006](0006-tos-player-default-on-ios.md) | TOS-compliant WKWebView player is the default player on iOS | superseded |
| [0007](0007-no-hybrid-avplayer-handoff-for-tos.md) | No hybrid AVPlayer handoff for TOS background play / PiP | superseded |
| [0008](0008-standby-swap-disabled.md) | Shorts standby-swap "instant swipe" promotion is permanently disabled | superseded |
| [0009](0009-docs-live-with-code.md) | Non-secret docs live in the public repo, with code | accepted |
| [0010](0010-remove-iframe-player.md) | Remove the IFrame (TOS) and Shorts embed players; AVPlayer is the only engine | accepted |
| [0011](0011-bounded-native-shorts-preloading.md) | Session-owned native Shorts preloading and bounded retention | accepted |
| [0012](0012-redesign-availability-and-tokens.md) | Redesign: availability fallbacks and token ownership | proposed |
