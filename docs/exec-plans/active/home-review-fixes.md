# PLAN-0004: Home feed review fixes

Status: active

Owner: coding agent; coordinator owns build and test acceptance.
Git boundary: this worktree, starting at `492342e`; initially clean.
Basis: six independent-review findings supplied on 2026-10-15.
Scope: load and page generations, retained Shorts demand, persistent layout reset,
page deduplication, and controlled continuation UI coverage in the existing test file.
Constraints: no builds or tests in this worktree; no project-file edits or protected paths.
Dependencies: existing API protocol, Swift Testing fakes, existing Home UI-test target.
Next deliverable: six logical fixes with regression coverage and commits.
Acceptance: obsolete requests cannot publish data or flags; demand resumes after busy
requests; refresh resets layout across chips; page IDs are unique; UI tests require
continuation-only cards to become visible. Coordinator must compile and run tests.
Blocker: execution acceptance is delegated to the coordinator.

| Checkpoint | Evidence and review |
|---|---|
| Full-load ownership | Generation checks and cancellation-ignoring fake regressions added; NOT RUN |
| Remaining findings | Implementation in progress |
