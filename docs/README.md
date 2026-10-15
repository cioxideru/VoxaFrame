# Docs index

One line per doc. `Status` is `current` (trust it) or `archived` (history only, don't follow it).
This table is the source of truth for what exists — if a doc isn't listed here, treat it as
undiscoverable until it is. Keep this under 100 lines; anything that doesn't fit gets archived.

| Doc | What it is | Status | Last verified |
|---|---|---|---|
| [../AGENTS.md](../AGENTS.md) | Agent entry point: commands, rules, gotchas | current | 2026-09-10 |
| [../CLAUDE.md](../CLAUDE.md) | Claude Code specifics, imports AGENTS.md | current | 2026-09-10 |
| [../CONTEXT.md](../CONTEXT.md) | Domain glossary + architecture vocabulary | current | 2026-09-11 |
| [architecture.md](architecture.md) | C4 container diagram, module map, playback pipeline, deep links | current | 2026-09-10 |
| [design/tos-player.md](design/tos-player.md) | TOS player (macOS) development worklog | current | 2026-06 |
| [design/tos-player-ios-plan.md](design/tos-player-ios-plan.md) | TOS player iOS port plan | current | 2026-06 |
| [adr/README.md](adr/README.md) | Architecture Decision Records index (0001-0009) | current | 2026-09-10 |
| [explanation/swift-style.md](explanation/swift-style.md) | Swift style guide (moved from private repo) | current | 2026-09-11 |
| [explanation/solid.md](explanation/solid.md) | SOLID principles reference (moved from private repo) | current | 2026-09-11 |
| [explanation/home-feed-architecture.md](explanation/home-feed-architecture.md) | Home feed / Shorts detection notes | unverified | 2026-09-11 |
| [explanation/hls-n-descrambler.md](explanation/hls-n-descrambler.md) | HLS n-parameter descrambling notes | unverified | 2026-09-11 |
| [explanation/dash-quality-switch-tests.md](explanation/dash-quality-switch-tests.md) | DASH quality-switch test notes | unverified | 2026-09-11 |
| [explanation/no-botguard.md](explanation/no-botguard.md) | Notes on avoiding BotGuard | unverified | 2026-09-11 |
| [explanation/reviewer-notes.md](explanation/reviewer-notes.md) | Code reviewer notes | unverified | 2026-09-11 |
| [explanation/changelog-unreleased.md](explanation/changelog-unreleased.md) | Unreleased-changes draft notes | unverified | 2026-09-11 |
| [explanation/task-89-short-detection-issue.md](explanation/task-89-short-detection-issue.md) | Shorts-detection issue investigation | unverified | 2026-09-11 |
| [how-to/localization.md](how-to/localization.md) | Localization how-to | current | 2026-09-11 |
| [how-to/run-tests.md](how-to/run-tests.md) | How to run tests, target simulator, one-time setup | current | 2026-09-11 |
| [how-to/device-logs.md](how-to/device-logs.md) | How to capture device/app logs (simulator + physical device) | current | 2026-09-11 |
| [how-to/release.md](how-to/release.md) | How to cut a release | partial | 2026-09-11 |
| [research/playing-methods.md](research/playing-methods.md) | All known video-ID→AVPlayer paths | research reference | 2026-09-11 |
| [research/BotGuard.md](research/BotGuard.md) | BotGuard/PoToken state and migration notes | research reference | 2026-09-11 |
| [research/yt-dlp.md](research/yt-dlp.md) | yt-dlp knowledge reference | research reference | 2026-09-11 |
| [research/freetube-analysis.md](research/freetube-analysis.md) | FreeTube reference analysis | research reference | 2026-09-11 |
| [research/android-repos.md](research/android-repos.md) | Original Android repo references | research reference | 2026-09-11 |
| [research/AetherEngine.md](research/AetherEngine.md) | AetherEngine proposal — considered, not adopted | research reference | 2026-09-11 |
| [archive/2026-05-aether-engine-proposal/AetherEngine.md](archive/2026-05-aether-engine-proposal/AetherEngine.md) | Original AetherEngine proposal (May 2026) | archived | 2026-05 |
| [superpowers/specs/2026-06-11-tos-player-shorts-design.md](superpowers/specs/2026-06-11-tos-player-shorts-design.md) | TOS player for Shorts (iOS) design spec | current | 2026-06-11 |
| `docs/modernization/README.md` (private repo, not linkable from here) | Architecture audit + modernization plan | current | 2026-09-10 — still in the private repo, deliberately deferred (see WS2-T2.6 Outcome) |

## Not yet written

These are named in the modernization plan but don't exist yet — don't link to them until their task lands:
`docs/how-to/add-a-stream-source.md` (WS4-T4.7).

## Deliberately not moved from the private repo (WS2-T2.6)

`docs/modernization/**` (this session's own live execution record — moving it mid-task was too
risky), `docs/RULES.md`, `docs/project.md`, `docs/running-tests.md`, `docs/tasks-log.md`,
`docs/planning.md`, `.github/skills/*` (skill-invocation path risk, and `run-tasks` is now
private-repo-`tasks/`-specific), and ~20 undifferentiated docs (benchmark worklogs, per-feature
plans) that need individual triage, not a bulk mechanical move. See
`docs/modernization/workstreams/WS2-docs-and-tasks.md` T2.6 Outcome for the full list and reasoning.
