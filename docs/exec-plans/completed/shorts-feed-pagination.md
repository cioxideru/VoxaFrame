# PLAN-0014: Preserve account feed pagination

Status: completed

- Owner: Codex.
- Git boundary: `mac/shorts-feed-pagination`, based on local `master` `c8a9af9`,
  in the existing managed worktree. Initially clean. Primary-checkout localization
  and local signing changes are outside this task.
- Scope: trace and fix account Shorts mixing on later feed rows; cover Home,
  Recommended and subscription-backed Shorts at their shared response parser.
- Constraints: preserve authenticated sources, no new background requests, no
  changes to YouTube ranking, Xcode-only project edits, local commit/merge, no push.
- Basis: the flat parser overwrites the feed continuation with nested shelf
  continuations and walks every navigation tab. Existing request tests use only
  one continuation and cannot detect a change of feed during pagination.
- Outcome: shared parser correction and regression checks delivered; version
  5.11 (29), local commit and master integration authorized.
- Dependencies: existing InnerTube browse transport and feed view models.
- Blockers: none for deterministic checks; live account relevance is separate
  acceptance in [OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance).

## Acceptance

- The owning feed continuation takes precedence over a nested shelf continuation;
  unrelated navigation tabs do not contribute videos or replace pagination.
- Second and third account pages retain the account browse source and Bearer auth.
- Existing single-shelf, grid, search and continuation response formats still work.
- Required native checks, iPad Simulator feed tests and iOS/tvOS builds pass.
- Update version in Xcode, commit task changes and merge into local master.

## Checkpoints

| Step | Evidence / review | Status |
|---|---|---|
| Reproduce source drift | Three regression tests failed on the old parser (eight failed assertions across flat/row variants) | complete |
| Shared parser fix | Active-tab selection, parent cursor precedence, terminal feeds and three authenticated pages pass | complete |
| Native checks | 1059 tests / 147 suites, formatting, strict SwiftLint and repository rules pass | complete |
| Simulator and platform checks | Four iPad UI tests pass with no skips; iOS/tvOS build-for-testing passes | complete |
| Version and local integration | Xcode project and built iOS/tvOS apps confirm 5.11 (29); local commit/merge authorized | complete |

## Evidence and limits

The shared parser owns navigation selection and continuation scope. Both flat and
row parsers use the same rule. The UI fixture now passes through the parser and
includes an unselected tab plus conflicting nested shelf cursors; it no longer
bypasses this boundary with prebuilt video groups.

The four updated SwiftLint baseline records only lower existing measurements:
row parser length 122 → 117, flat parser length 199 → 169, nested walker length
182 → 152, and walker complexity 46 → 43. No new exceptions were added.

Checks completed on 2026-10-17. The iPad Pro 11-inch (M5), iOS 26.5 Simulator
passed both `HomeShortsEndlessUITests` and the Recommended/Subscriptions spacing
tests from `MixedFeedLayoutUITests`. The result bundle `shorts-feed-ipad.xcresult`
records four passes, zero failures and zero skips. Native checks passed 1059 tests
in 147 suites. Both simulator apps and UI-test targets compiled successfully.

These fixtures prove request/source ownership, not the relevance of YouTube's
server-ranked recommendations for a live account. Physical iPad verification and
live account relevance remain in OQ-0005.
