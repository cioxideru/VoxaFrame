# PLAN-0039: HIG review fixes

Status: completed
Owner: Claude (coordinator); Opus 5.5 executors; GPT-6.0 Astra reviewers
Date: 2026-10-21

## Scope and boundary

A whole-app Apple HIG review (five reviewers, 14 subsystems, static reading only) produced
5 high, about 30 medium and about 25 low findings. The user accepted these groups:
all low findings; accessibility and appearance; navigation; feedback (one consistent style);
destructive actions without confirmation; SponsorBlock colours for both themes. They added a
compact subscription row in the player's More menu: subscription status, subscribe/unsubscribe
and Go to Channel in one line.

Out of scope by the user's decision (recorded in [OQ-0020](../../OPEN_QUESTIONS.md#oq-0020--hig-review-findings-left-open)):
the remaining high findings (iOS player controls hide under VoiceOver, unnamed tvOS
player controls, Channel cards that do not open on tvOS, tvOS sign-in in Light theme), and
load errors shown as empty states. Also out: replacing the custom tvOS player with the system
player and system search on tvOS (large, separate work).

Work runs in six parallel worktrees based on local `master` at `61afa070`, branches
`plan-0039/<package>`. The coordinator merges them into `master` one at a time.

## Packages

| Package | Content | Review |
|---|---|---|
| sponsorblock-motion | SponsorBlock colours for light/dark, Skip button contrast, timeline marks, Reduce Motion in player transitions, duplicate toast, error announcement | Astra |
| player-menu | Subscription row (status, subscribe/unsubscribe, Go to Channel), tvOS focus in More menu and pickers, macOS Esc/modal, selected traits, sleep timer remaining time | Astra |
| player-chrome | `AppSymbol` consolidation and symbol meanings, glyph weights, Large Content Viewer, `.help`, 2× badge, AirPlay label, captions with Dynamic Type, stats overlay | Astra |
| navigation | Channel opening for the current tab only, one tvOS player presentation, macOS menu bar commands, Settings out of the macOS sidebar, small shell fixes | Astra |
| feedback | Success → toast, toast and error announcements, visible failures, confirmations for Clear History and Sign Out, consistent wording and casing, forms | Astra |
| small-polish | Radii/spacing tokens, decorative images, empty-state actions, tvOS card focus in Light, widget type and contrast | none |

## Acceptance

- Each package: CI, strict SwiftLint, iOS and tvOS builds pass; macOS compiled by package tests.
- Reviewed packages: Astra review has no blocking findings.
- HIG commit gate: high = 0 on the staged files.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Review | Five design-reviewer reports, high findings checked against code | done |
| sponsorblock-motion | Astra: marker contrast over the scrim fixed (Fill/Fit translation finding rejected: English-only); HIG gate high=0 | `52c4f807` |
| player-chrome | Astra: Downloads empty glyph fixed, two call sites moved to stitch; HIG gate high=0 | `70fd2d4b` |
| player-menu | Astra: unsubscribe confirmation bound to its channel and account, regression test; HIG gate high=0 | `355d378d` |
| feedback | Astra, three rounds: real feedback send, Shorts, rating toast on all platforms, app-level toast, Keychain status, UI tests; HIG gate high=0 | `e9456503` |
| navigation | Astra, two rounds: tvOS Queue/RSS covers, tvOS Open Channel from covers, no tvOS URL scheme, search link clears channel; verdict pass; HIG gate high=0 | `d8932309` |
| small-polish | No external review; HIG gate high=0 | `1beabd40` |
| stitch | Cross-package follow-ups, no external review; HIG gate high=0 | `c1f08809` |
| Merged master | `./h check`, SwiftLint strict baseline, iOS and tvOS builds, iOS/tvOS build-for-testing | passed |
| UI tests (iOS Simulator) | VideoFeedbackConfirmation 4/4, clear history confirm and cancel, PlayerMoreMenuOpenChannel | passed |
| Full `verify` | Stopped by the harness doctor (`Package.resolved` missing since the Firebase removal); its stages were run one by one above | NOT RUN |
| macOS app target, rendered checks | Not built by the scripts; nothing rendered | NOT RUN |

Resolution: all accepted groups and the subscription row are delivered. Xcode 27.1 became the local toolchain during
this work. Unfinished items and evidence gaps are in [OQ-0020](../../OPEN_QUESTIONS.md#oq-0020--hig-review-findings-left-open).
