# PLAN-0004: Firebase removal review fixes

Status: active

- Owner: branch agent; coordinator owns builds, tests, Xcode cleanup and integration.
- Git boundary: `worktree-agent-a04dc7f6f36259262`, starting at `6a33caf`; initially clean.
- Basis and task IDs: review findings 2–6 supplied on 2026-10-15.
- Scope: safe local error/URL logging and unit tests; Yandex audio-transfer disclosure;
  file-timestamp privacy reason; native macOS naming in OQ-0012; local logging in the Shorts design.
- Constraints: no builds or tests in this worktree; no project-file or excluded-tooling edits.
- Acceptance: each finding has a separate commit; source and document diffs reviewed;
  coordinator runs the added tests and platform builds before integration.
- Dependencies/blockers: finding 1 remains a manual Xcode step tracked by
  [OQ-0012](../../OPEN_QUESTIONS.md#oq-0012--firebase-removal-xcode-project-and-app-store-follow-up);
  finding 7 belongs to the coordinator.
- Next deliverable: commits for findings 2–6 with explicit validation limits.

| Checkpoint | Evidence and review result |
|---|---|
| 2: logging | Shared domain/code/host formatter, safe replacement-logger call sites, privacy regression tests added; builds/tests NOT RUN. |
| 3: Yandex disclosure | Policy now describes the conditional original-audio download/upload; checked against `VoiceOverTranslationController.uploadOriginalAudio`. |
| 4: file timestamps | Pending. |
| 5: native macOS naming | Pending. |
| 6: design logging | Pending. |
