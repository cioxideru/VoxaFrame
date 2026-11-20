# PLAN-0050: Small fixes from upstream issues, its forks and Android SmartTube

Status: active

- Owner: coordinator; one executor for all three items, one commit per item, merged into `master`.
- Git boundary: worktree `wt/upstream-small-0050` from `master` after `a4a5e7bc`.
- Basis: review of 2026-11-20 of [milika/SmartTubeIOS](https://github.com/milika/SmartTubeIOS) issues and pull
  requests after PLAN-0049, its active forks and [yuliskov/SmartTube](https://github.com/yuliskov/SmartTube) 32.69–32.80.
- Constraints: `SmartTubeIOSCore` stays Foundation-only; no new branches in the playback fallback cascade (ADR-0005).

## Items

1. **Home opens the first visible section** (upstream issue #194). `HomeView` starts with
   `BrowseSection.allSections[0]` (Home) even when Settings › Visible Sections puts another section first or hides Home.
   Start with the first visible section; a section opened by a shortcut or notification keeps working.
2. **Remote completion beats an older local position** (Android `348cbe28`). When YouTube reports a video as
   100 % watched, an older position saved on the device must not override it in cards or on resume. Check our
   behaviour first; change it only if the defect is confirmed.
3. **Up to 6 grid columns in landscape** (fork zlwu `4991a675`). `AppSettings.availableGridColumnCounts` is `1...5`;
   allow 6 for wide iPad and Mac windows. Saved values stay valid.

## Acceptance

- A Swift Testing test for each change at its seam (fake API or store), no live network, no `Task.sleep`.
- `scripts/ci.sh`, SwiftLint and the ast-grep rules before each commit; iOS, tvOS and macOS builds at the end.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Review | upstream issues and PRs, forks, Android commits compared on 2026-11-20 | done |
| 1. First visible section | | NOT RUN |
| 2. Remote completion | | NOT RUN |
| 3. Six columns | | NOT RUN |
