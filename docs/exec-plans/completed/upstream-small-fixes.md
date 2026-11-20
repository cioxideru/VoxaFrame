# PLAN-0050: Small fixes from upstream issues, its forks and Android SmartTube

Status: completed (2026-11-20)
Resolution: items 1–3 delivered; Codex review (three rounds) and Fable audit accepted. Resume still restores an older
local position when YouTube reports a full watch; tracked in [OQ-0025](../../OPEN_QUESTIONS.md#oq-0025--resume-ignores-youtubes-full-completion).
On-screen checks (Home start, VoiceOver, six columns on a real iPad or Mac width) are NOT RUN.

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
| 1. First visible section | `HomeStartSectionTests`: reordered Home, hidden Home and hidden Shorts first failed before the change (Home was returned), all six pass after; a list that the Shorts filter empties keeps Home | done |
| 2. Remote completion | `RemoteCompletionProgressTests`: a fake TV response with `percentDurationWatched` 100 and a saved 30 s of 100 s showed 30 % before the change, 100 % after; partial YouTube progress still yields to the saved position. `OfflineRowWatchProgressTests`: the Offline row had no VoiceOver value (its cover is hidden) and now reads the card's "N% watched" text from the same value. Resume still restores the saved 30 s (a probe confirmed it); left for a follow-up | done (cards, Offline rows); resume open |
| 3. Six columns | `AppSettingsAppearanceTests`: landscape 6 decoded, encoded and offered on Mac failed before (clamped to 5), pass after; saved 1–5 in both fields and the 2/3 defaults are unchanged; a Mac window too narrow for six cards drops columns, on Home and, through the width-aware `videoGridColumns`, on Playlist and Channel (1300 pt gives 5, where it gave 6 before) | done |
| Review | Codex: round 1 three findings (Offline VoiceOver, Playlist/Channel width, README), round 2 two minors (locale-safe test, README scope), round 3 clean | passed |
| Audit | Fable high: accepted, four nits (0.95–0.99 boundary test, row modifier test, column literals, answer field in the question queue) | passed |
