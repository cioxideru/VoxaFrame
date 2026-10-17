# PLAN-0026: Delete all offline videos and cache

Status: completed

Owner: Codex. Branch: `mac/offline-delete-all`, reused managed `offline-integration` worktree,
based on local master `761c9f3`. Worktree was clean; primary user scheme, localization and design changes are outside scope.

## Scope and acceptance

- Add a visible Delete all action to Offline videos, available from Library and Downloads, with destructive confirmation.
- Cancel queued, resolving and active offline transfers; delete every saved video, audio, translation,
  protected HLS package and owned unfinished transfer cache. Keep unrelated app data.
- Reuse PLAN-0025's durable deletion journal. Interrupted cleanup resumes after relaunch; late callbacks cannot restore media.
- Check multi-video cleanup and cancellation with fake seams; exercise confirmation, cancellation and relaunch on iPad Simulator.
- Use Xcode 27.0; no project-file hand edits. Commit checked work and merge into local master, without pushing.

## Checkpoints

| Step | Evidence |
| --- | --- |
| Inspection | Existing per-entry cleanup already owns cache paths and durable invalidation. Extend its scope to all entries. |
| Implementation | Shared durable removal supports the whole library, cancels known/orphaned native transfers and cleans owned orphan receipts/files. Build 5.16 (35) set through Xcode 27.0. |
| Native checks | PASS: 21 focused cleanup/coordinator tests; full CI 1154 tests / 159 suites; strict SwiftLint has no violations. Final gate logs: `/private/tmp/offline-delete-all-ci-final.log`, `/private/tmp/offline-delete-all-lint-delivery.log`. |
| iPad Simulator | PASS: `testDeleteAllConfirmsAndClearsBothPagesAfterRelaunch`, `/private/tmp/offline-delete-all-ui-final2.xcresult`. Includes native iPad popover dismissal, confirmed removal from Downloads and both tabs empty after relaunch. |
| Physical file cleanup | PASS: 90 media files including 10 HLS packages observed before deletion in the final test container; all gone, no pending jobs or cached files left. `/private/tmp/offline-delete-all-disk-proof.json`. |
| Platform builds | PASS: iOS Debug app/UI tests and tvOS Release app/UI tests; `/private/tmp/offline-delete-all-ios-final2-build.log`, `/private/tmp/offline-delete-all-tvos-build.log`. App and all embedded iOS extensions report 5.16 (35). |
| Delivery | Commit checked changes and integrate into local master under the standing policy; no remote push. |

No new dependencies or changes to online playback. Physical iPad acceptance is not part of this follow-up.
