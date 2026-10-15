# Docs index

One row per public document. This is the source of truth for document discovery; every row is
reachable from [AGENTS.md](../AGENTS.md). Update this index and incoming links in the same change
as a move. Keep this index under 100 lines.

`current` means a maintained guide, decision, published artifact, or explicitly dated reference;
`archived` means historical material that must not be followed as current instructions. Review
date records the documentation classification/source check, not a fresh test run, upstream
research refresh, legal approval, or validation of historical pass counts. Plan lifecycle status
is separate and appears in each plan. [Open questions](OPEN_QUESTIONS.md) owns outstanding work;
closed outcomes go to [CHANGELOG](../CHANGELOG.md) or an [ADR](adr/README.md).

| Doc | What it is | Status | Last reviewed |
|---|---|---|---|
| [../AGENTS.md](../AGENTS.md) | Agent map: commands, rules, gotchas and document entry points | current | 2026-10-15 |
| [../CLAUDE.md](../CLAUDE.md) | Shared agent workflow and plan location | current | 2026-10-15 |
| [../README.md](../README.md) | Published product overview | current | 2026-10-15 |
| [../CHANGELOG.md](../CHANGELOG.md) | Release history and closed documentation findings | current | 2026-10-15 |
| [../CONTEXT.md](../CONTEXT.md) | Domain and architecture vocabulary | current | 2026-10-15 |
| [../PRIVACY_POLICY.md](../PRIVACY_POLICY.md) | Published policy; lists the services the app contacts (no analytics or crash reporting) | current | 2026-10-15 |
| [../SmartTubeIOS/README.md](../SmartTubeIOS/README.md) | Package entry point and links to canonical guides | current | 2026-10-15 |
| [README.md](README.md) | Canonical document inventory and review meaning | current | 2026-10-15 |
| [architecture.md](architecture.md) | Containers, package boundaries, current playback and navigation | current | 2026-10-15 |
| [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) | Unfinished work, debt, verification gaps and decisions (OQ-0001–0011) | current | 2026-10-15 |
| [exec-plans/README.md](exec-plans/README.md) | Plan lifecycle, metadata and indexes | current | 2026-10-15 |
| [exec-plans/active/BotGuard.md](exec-plans/active/BotGuard.md) | PLAN-0003: active; implemented token paths, remaining live acceptance | current | 2026-10-15 |
| [exec-plans/completed/tos-player-ios-plan.md](exec-plans/completed/tos-player-ios-plan.md) | PLAN-0001: completed port; original tasks and closure evidence | current | 2026-10-15 |
| [exec-plans/completed/task-89-short-detection-issue.md](exec-plans/completed/task-89-short-detection-issue.md) | PLAN-0002 / #89: completed duration guard; tests present, not rerun | current | 2026-10-15 |
| [design/2026-06-11-tos-player-shorts-design.md](design/2026-06-11-tos-player-shorts-design.md) | Shorts embed design, implementation reconciliation and historical baseline | current | 2026-10-15 |
| [adr/README.md](adr/README.md) | ADR index, statuses and preservation rules | current | 2026-10-15 |
| [adr/template.md](adr/template.md) | ADR form: stable ID, Status, Date, Context, Decision, Consequences | current | 2026-10-15 |
| [explanation/swift-style.md](explanation/swift-style.md) | Swift conventions | current | 2026-10-15 |
| [explanation/solid.md](explanation/solid.md) | SOLID principles reference | current | 2026-10-15 |
| [explanation/hls-n-descrambler.md](explanation/hls-n-descrambler.md) | Current Simulator descrambler scope and limits; no current live result | current | 2026-10-15 |
| [how-to/device-logs.md](how-to/device-logs.md) | Simulator/device log capture | current | 2026-10-15 |
| [how-to/localization.md](how-to/localization.md) | Localization workflow | current | 2026-10-15 |
| [how-to/release.md](how-to/release.md) | Version/changelog preparation; remaining release steps in OQ-0007 | current | 2026-10-15 |
| [how-to/run-tests.md](how-to/run-tests.md) | Test commands, platform limits, missing test plans and acceptance | current | 2026-10-15 |
| [research/AetherEngine.md](research/AetherEngine.md) | Non-adoption summary and link to original archived proposal | current | 2026-10-15 |
| [research/android-repos.md](research/android-repos.md) | Android reference repositories; dated external background | current | 2026-10-15 |
| [research/freetube-analysis.md](research/freetube-analysis.md) | Historical FreeTube analysis; external facts not refreshed | current | 2026-10-15 |
| [research/yt-dlp.md](research/yt-dlp.md) | May 2026 yt-dlp research snapshot; external facts not refreshed | current | 2026-10-15 |
| [archive/2026-05-aether-engine-proposal/AetherEngine.md](archive/2026-05-aether-engine-proposal/AetherEngine.md) | Unadopted proposal and historical investigation; not current tasks | archived | 2026-10-15 |
| [archive/tos-player.md](archive/tos-player.md) | June TOS development worklog, including zero-test false-positive investigation | archived | 2026-10-15 |
| [archive/home-feed-architecture.md](archive/home-feed-architecture.md) | Superseded two-shelf/no-Shorts-separation architecture | archived | 2026-10-15 |
| [archive/dash-quality-switch-tests.md](archive/dash-quality-switch-tests.md) | May quality-test results and old helper names; not fresh acceptance | archived | 2026-10-15 |
| [archive/no-botguard.md](archive/no-botguard.md) | Obsolete prohibition superseded by implemented token paths | archived | 2026-10-15 |
| [archive/reviewer-notes.md](archive/reviewer-notes.md) | Obsolete submission copy; do not reuse (OQ-0012) | archived | 2026-10-15 |
| [archive/playing-methods.md](archive/playing-methods.md) | June stream-order snapshot, predating VISIONOS-first and file decomposition | archived | 2026-10-15 |
| [adr/0001-maintainability-baseline.md](adr/0001-maintainability-baseline.md) | 0001 — Maintainability baseline; accepted | current | 2026-10-15 |
| [adr/0002-mvvm-observable-no-tca.md](adr/0002-mvvm-observable-no-tca.md) | 0002 — MVVM with `@Observable`, no TCA; accepted | current | 2026-10-15 |
| [adr/0003-no-project-generation.md](adr/0003-no-project-generation.md) | 0003 — No Tuist/XcodeGen — the `.xcodeproj` is the source of truth; accepted | current | 2026-10-15 |
| [adr/0004-plain-init-injection.md](adr/0004-plain-init-injection.md) | 0004 — Plain protocol + initializer injection, no DI framework; accepted | current | 2026-10-15 |
| [adr/0005-stream-source-pipeline.md](adr/0005-stream-source-pipeline.md) | 0005 — `StreamSource` + `ResolutionPipeline` replace the `exhaustiveRetry` cascade; proposed | current | 2026-10-15 |
| [adr/0006-tos-player-default-on-ios.md](adr/0006-tos-player-default-on-ios.md) | 0006 — TOS-compliant WKWebView player is the default player on iOS; accepted | current | 2026-10-15 |
| [adr/0007-no-hybrid-avplayer-handoff-for-tos.md](adr/0007-no-hybrid-avplayer-handoff-for-tos.md) | 0007 — No hybrid AVPlayer handoff for TOS background play / PiP; accepted | current | 2026-10-15 |
| [adr/0008-standby-swap-disabled.md](adr/0008-standby-swap-disabled.md) | 0008 — Shorts standby-swap "instant swipe" promotion is permanently disabled; accepted | current | 2026-10-15 |
| [adr/0009-docs-live-with-code.md](adr/0009-docs-live-with-code.md) | 0009 — Non-secret docs live in the public repo, with code; accepted | current | 2026-10-15 |
| [../.github/copilot-instructions.md](../.github/copilot-instructions.md) | Assistant entry point delegating to AGENTS.md | current | 2026-10-15 |
| [../.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) | Pull-request acceptance checklist | current | 2026-10-15 |
