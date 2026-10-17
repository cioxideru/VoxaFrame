# PLAN-0027: VoxaFrame redesign in SwiftUI

Status: active

Owner: Claude Code for Ivan Baranov. Git boundary: local `master` at `0e81d8a`. Working tree has
unrelated changes that stay outside this plan: modified `Localizable.xcstrings`, untracked
`docs/design/claude-design/voxaframe-redesign.zip` and `docs/new-design-v1/`.
Basis: [design package](../../design/voxaframe-redesign/START-HERE.md) (DESIGN-0003) and the
[functional brief](../../design/VoxaFrame-Functionality.ru.md) (DESIGN-0002), which wins over a mockup on any disagreement.
Decisions: [ADR-0012](../../adr/0012-redesign-availability-and-tokens.md); accent and logic scope below.

## Scope and acceptance

- Re-skin the shell, Home and cards, player and panels, Shorts, Offline, Settings, Search, Library and RSS
  for iPhone, iPad, native macOS and Apple TV. Behaviour, queue, audio, subscriptions and files do not change.
- Accent "System" is coral (`#B83829` light, `#FF9988` dark) on iOS, iPadOS and tvOS; on macOS it stays the system accent.
- Logic changes in scope: B1 (confirm clearing device history), B2 (confirm Reset All Settings), B3 (confirm Clear Queue),
  A1 (permanent Queue entry), A2 (Play Next after the current item), A4 (guest local history in Library), A5 (search error screen).
  Everything else marked as logic in the mockups (A3, A6–A12, B4–B8, C1) stays a label and is not implemented.
- Each stage is accepted when: CI and strict SwiftLint pass, iOS/tvOS/macOS builds pass, the stage's screens are checked in
  light and dark, with Reduce Transparency, Increase Contrast, Reduce Motion and Dynamic Type up to AX5 where the stage has text.

## Constraints

- Minimum OS stays iOS/iPadOS 17, macOS 14, tvOS 17. Liquid Glass and iOS 18+/26+ navigation APIs sit behind `#available`.
- Do not rename `AppSection` raw values or any accessibility identifier; do not touch `PlaybackViewModel*`.
- One source for symbols (`AppSymbol`), identifiers (`AccessibilityID`, mirrored in `UITestHelpers.swift`), timeouts (`PlaybackTuning`) and settings.
- No hand edits of `project.pbxproj`; new UI-test files are added in Xcode.

## Checkpoints

| Stage | Content | Status / evidence |
| --- | --- | --- |
| 0 | This plan, ADR-0012, OQ-0019, document index | in progress |
| 1 | `Views/DesignSystem/`: tokens, glass modifier, accent per platform | NOT RUN |
| 2 | Shell: tabs / sidebar / split view / top tabs; mini-player accessory spike; macOS inspector and menu | NOT RUN |
| 3 | Home, cards, A2 | NOT RUN |
| 4 | Player and option panels | NOT RUN |
| 5 | Shorts | NOT RUN |
| 6 | Offline | NOT RUN |
| 7 | Settings, B1, B2 | NOT RUN |
| 8 | Search, Library, RSS, channels, sign-in, A1, A4, A5, B3 | NOT RUN |

Stages 0–2 run in order; stages 3–8 touch separate folders and may run in parallel once stage 2 is merged.
