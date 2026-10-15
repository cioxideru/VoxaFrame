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
- Next deliverable: coordinator build/test acceptance of the five review-fix commits.

| Checkpoint | Evidence and review result |
|---|---|
| 2: logging | Shared domain/code/host formatter, safe replacement-logger call sites, privacy regression tests added; builds/tests NOT RUN. |
| 3: Yandex disclosure | Policy now describes the conditional original-audio download/upload; checked against `VoiceOverTranslationController.uploadOriginalAudio`. |
| 4: file timestamps | Added `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1` for app-container cache metadata; checked against [Apple's required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). |
| 5: native macOS naming | OQ-0012 now names the target and exception setting as native macOS; project settings inspected read-only (`SUPPORTS_MACCATALYST = NO`, macOS plist selection). |
| 6: design logging | Replaced the Crashlytics instruction with local `os.Logger` guidance and domain/code/host-only error details. |

Implementation for findings 2–6 is delivered. The plan remains active until coordinator acceptance.
Five logging privacy tests were added but NOT RUN; builds, unit tests and UI tests are NOT RUN.
Static checks: changed Swift files pass strict swift-format lint; SwiftLint passes with the existing
baseline (the installed version warns that `unused_private_declaration` is not a valid rule).
The privacy manifest passes `plutil -lint`; `git diff --check` passes. Commit hooks were disabled
for these commits to honor the no-build/no-test instruction.
