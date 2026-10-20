# PLAN-0030: Resume worktrees and release VoxaFrame 5.18

Status: completed

Resolution: four unfinished feature worktrees integrated, required acceptance passed,
and [VoxaFrame 5.18 (40)](https://github.com/cioxideru/VoxaFrame/releases/tag/v5.18)
published on 2026-10-20. Release commit: `a90174c3`; annotated tag: `v5.18`.

Owner: Codex for Ivan Baranov. Started 2026-10-20.
Git boundary: `mac/release-5.18` in the existing `p29-release` worktree, based on
`master` at `dfc06e62`. Original worktrees stay preserved during acceptance.
Basis: the request to resume unfinished branches, finish their checks, merge into
`master` and publish a new release; the unfinished PLAN-0029 changes and their reviews.

## Scope and acceptance

- Finish offline SponsorBlock, recommendation-only Home, default Shorts/Queue visibility,
  and offline file sizes. Preserve saved settings, account identity and downloaded files.
- Review affected callers, fixtures, migration paths and tests; resolve integration conflicts.
- Run CI, strict SwiftLint, iOS/tvOS UI-test compilation, native macOS build and focused
  simulator UI tests. Record hardware and live-service checks separately.
- Change inherited marketing/build versions through Xcode, verify built bundle versions,
  update the changelog, commit and merge into local `master`.
- Publish a source-only GitHub release in `cioxideru/VoxaFrame`, with tag and notes.
  No personal signing identifiers or signed binaries.

## Inventory and exclusions

The initial inventory found 49 worktrees. Only `p29/offline-sponsorblock` had
a commit outside `master` (`177cc69a`). Seven worktrees had local modifications.
Their patches and untracked files were saved under
`/private/tmp/voxaframe-resume-20261020` before integration.

`p29/shorts-probe` is an explicitly temporary endpoint experiment, not production code.
Its account-specific diagnostic output and project/localization changes are not release content.
The old `integrate/stability-2026-10-15` commits, including Xcode cleanup, already belong
to `master`; stale worktree residue does not require merging the branch again.
Existing broader design and device acceptance remains in the open-question register.

## Checkpoints

| Work | Status and evidence |
| --- | --- |
| Inventory and recovery copies | Done; remote master matches `dfc06e62`, latest release is `v5.17` |
| Offline SponsorBlock | Integrated; unit tests cover storage, failed refreshes, throttling, shared requests, current-video guards and manual skipping |
| Home recommendations | Integrated; bounded pagination, repeated cursors, deduplication, refresh/account generations and empty feeds covered |
| Default visibility | Integrated; existing settings preserved, Queue toggle localized and Shorts test override shared with tvOS |
| Download sizes | Integrated; byte counters, saved/partial files, cancellation and measurement cache covered; UI verifies storage display and deletion |
| Versions and builds | Xcode project updated to 5.18 (40); iOS, native macOS and tvOS Release builds passed, including iOS/tvOS UI-test compilation |
| UI acceptance | All 16 focused iPad tests passed, no failures or skips |
| Publication | `a90174c3` merged into master; remote master and tag verified; GitHub release published, no binary assets |

## Validation

- Xcode 27.0 (27A266a); package targets use Swift 6. Reviewed actor boundaries,
  cancellation and late-result guards. The new macOS notification observer uses a
  view-owned async task.
- `scripts/ci.sh`: 1,347 tests in 181 suites passed; secret-file, documentation,
  Core-import and formatting checks passed.
- Strict SwiftLint: exit 0, no new violations. Its existing configuration warning
  about `unused_private_declaration` remains.
- iOS Debug app and UI-test targets compiled with simulator ad-hoc signing.
  tvOS Release app and UI-test targets compiled. Native macOS and iOS Release builds passed.
  Existing compiler warnings in unchanged playback code remain.
- Built app and embedded extension versions checked on every platform: 5.18 (40).
- iPad Pro 13-inch Simulator, iPadOS 27.0: all eight `DownloadsPlaybackUITests`,
  all four `RecommendedChipUITests`, the Queue default/toggle test, the wide-sidebar test,
  watched-page continuation and automatic SponsorBlock persistence passed (16/16).
  Downloads, media playback and translations used loopback fixtures.
- Two sidebar tests emitted the same SwiftUI state-during-update warning at landscape launch.
  A separate build of unchanged `master` at `dfc06e62` reproduced it in the wide-sidebar test.
  This predates the integrated branches; its unresolved source is recorded in OQ-0019.
- XcodeBuildMCP's request timed out after five minutes while Xcode continued running.
  The completed Xcode log and xcresult independently confirm all 16 tests passed.
- Local evidence: `/private/tmp/voxaframe-resume-20261020` contains CI/lint/build logs,
  bundle versions, UI summaries, screenshots, the baseline comparison and original
  worktree recovery copies. The full UI result bundle is under
  `~/Library/Developer/XcodeBuildMCP/workspaces/SmartTubeIOS-debccfdd8460/result-bundles/`
  (`test_sim_2026-10-20T11-43-29-097Z_pid76424_ccce3352.xcresult`).

Physical-device, authenticated live-service and tvOS UI runs are not part of this
source release acceptance. Existing follow-ups remain in
[OQ-0005](../../OPEN_QUESTIONS.md#oq-0005--playback-device-acceptance),
[OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad)
and [OQ-0019](../../OPEN_QUESTIONS.md#oq-0019--voxaframe-redesign-follow-ups).
No tvOS Simulator runtime is installed. Signing, App Store and TestFlight distribution
remain [OQ-0007](../../OPEN_QUESTIONS.md#oq-0007--release-runbook-and-version-settings).

## Delivery and preserved work

The merge commit retains `177cc69a` as its second parent. It includes the four pending
tasks and the reviewed fixes, with the five post-5.17 player/Home changes already on master.
GitHub independently reports `v5.18` as published (not a draft or prerelease), with no
binary assets. Remote master and the dereferenced tag matched `a90174c3` at publication.

Original worktrees were left intact, including the non-production Shorts probe.
The main checkout's pre-existing Xcode string-catalog extraction was preserved in stash
`c0481d2c` (`Preserve Xcode catalog extraction before v5.18 (PLAN-0030)`), as well as
the recovery copies above. A local signing-filter index refresh was needed before the
fast-forward; no personal signing identifier entered the commit.
