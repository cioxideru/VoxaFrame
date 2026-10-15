# Execution plans

Multi-step implementation work lives here. Design descriptions belong in [design](../design/),
decisions in [ADRs](../adr/README.md), and historical investigations in [archive](../archive/).
The [document index](../README.md) lists every document; [open questions](../OPEN_QUESTIONS.md)
tracks unfinished work, debt, missing verification, and decisions.

## Lifecycle

- Give a plan a permanent `PLAN-NNNN` ID; preserve existing issue/task IDs.
- Put it in `active/` with a plain `Status: active` or `Status: blocked` line (a list prefix is allowed).
- Record owner, Git boundary and working-tree state, scope, constraints, basis, next deliverable,
  acceptance criteria, dependencies, blockers, and a checkpoint table with evidence and review results.
- Keep execution evidence distinct from the original design. `NOT RUN` describes a check, not success.
- Move to `completed/` and set `Status: completed` when accepted work is delivered. For a historical,
  cancelled, superseded, or partial delivery, add `Resolution:` explaining the outcome, evidence,
  replacement, and any remaining items in the open-question register. Moving a file alone proves nothing.
- Directory `README.md` files are indexes, not plans. Do not reuse IDs or invent commit/review evidence.

## Active

- [PLAN-0004: Home feed review fixes](active/home-review-fixes.md) — implementation and coordinator acceptance.

- [PLAN-0003: BotGuard / PoToken](active/BotGuard.md) — implemented foundations; live acceptance and token lifetime remain open.

## Completed

- [PLAN-0001: TOS player iOS port](completed/tos-player-ios-plan.md) — delivered; later settings behavior is recorded separately.
- [PLAN-0002 / #89: Shorts duration guard](completed/task-89-short-detection-issue.md) — fix and regression tests present.

Reviewed against the working tree on 2026-10-15. Historical closure is not a fresh test result.
