# PLAN-0005: Home feed review fixes

Status: active

Owner: coding agent; coordinator owns build and test acceptance.
Git boundary: this worktree, starting at `492342e`; initially clean.
Basis: six independent-review findings supplied on 2026-10-15.
Scope: load and page generations, retained Shorts demand, persistent layout reset,
page deduplication, and controlled continuation UI coverage in the existing test file.
Constraints: no builds or tests in this worktree; no project-file edits or protected paths.
Dependencies: existing API protocol, Swift Testing fakes, existing Home UI-test target.
Next deliverable: coordinator compilation, unit/UI execution, and independent acceptance.
Acceptance: obsolete requests cannot publish data or flags; demand resumes after busy
requests; refresh resets layout across chips; page IDs are unique; UI tests require
continuation-only cards to become visible. Coordinator must compile and run tests.
Blocker: execution acceptance is delegated to the coordinator.

| Checkpoint | Evidence and review |
|---|---|
| Full-load ownership | Generation checks and cancellation-ignoring fake regressions added; NOT RUN |
| Page ownership | Generation guards protect data, tokens, and flags; delayed page fakes added; NOT RUN |
| Retained demand | Largest target survives active paging; subscriptions completion resumes demand; fake regressions added; NOT RUN |
| Layout lifetime | Generation observer moved to persistent HomeView; chip-switch UI acceptance NOT RUN |
| Duplicate page IDs | Growing sets applied to both Shorts sources; regression includes duplicates within and across shelves; NOT RUN |
| Continuation UI coverage | Existing UI-test file uses debug-only API fixture: ten initial Shorts, two distinct pages, no regular continuations; asserts hittable cards inside row/window; NOT RUN |
| Static review | Changed Swift formatted and whitespace diff checked; no builds, tests, or commit hooks executed |

All six source fixes are delivered. Execution acceptance remains open in
[OQ-0015](../../OPEN_QUESTIONS.md#oq-0015--home-feed-review-acceptance).
