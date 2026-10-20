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
| [../AGENTS.md](../AGENTS.md) | Agent map: commands, rules, gotchas and document entry points | current | 2026-10-18 |
| [../CLAUDE.md](../CLAUDE.md) | Shared agent workflow and plan location | current | 2026-10-15 |
| [../README.md](../README.md) | Published product overview | current | 2026-10-18 |
| [../CHANGELOG.md](../CHANGELOG.md) | Release history and closed documentation findings | current | 2026-10-15 |
| [../CONTEXT.md](../CONTEXT.md) | Domain and architecture vocabulary | current | 2026-10-15 |
| [../PRIVACY_POLICY.md](../PRIVACY_POLICY.md) | Published policy; lists the services the app contacts (no analytics or crash reporting) | current | 2026-10-15 |
| [../SmartTubeIOS/README.md](../SmartTubeIOS/README.md) | Package entry point and links to canonical guides | current | 2026-10-15 |
| [README.md](README.md) | Canonical document inventory and review meaning | current | 2026-10-18 |
| [architecture.md](architecture.md) | Containers, package boundaries, current playback and navigation | current | 2026-10-18 |
| [architecture-audit-2026-10.md](architecture-audit-2026-10.md) | PLAN-0029 AUDIT: source findings, framework assessment, ownership proposals and prioritised roadmap; no runtime acceptance | current | 2026-10-18 |
| [design/VoxaFrame-Functionality.ru.md](design/VoxaFrame-Functionality.ru.md) | DESIGN-0002: standalone Russian functional brief for redesigning VoxaFrame on four Apple platforms | current | 2026-10-17 |
| [design/voxaframe-redesign/START-HERE.md](design/voxaframe-redesign/START-HERE.md) | DESIGN-0003: VoxaFrame redesign handoff — screen map, tokens, component contracts, mockups | current | 2026-10-17 |
| [design/voxaframe-redesign/docs/VoxaFrame-Functionality.ru.md](design/voxaframe-redesign/docs/VoxaFrame-Functionality.ru.md) | Functional brief snapshot included in the design export; maintained source is design/VoxaFrame-Functionality.ru.md | current | 2026-10-17 |
| [new-design-v1/README.md](new-design-v1/README.md) | Original design board and app screenshots used as redesign references | current | 2026-10-17 |
| [design/claude-design/README.md](design/claude-design/README.md) | DESIGN-0001: VoxaFrame Claude Design import bundle and visual references | current | 2026-10-17 |
| [design/claude-design/HANDOFF.ru.md](design/claude-design/HANDOFF.ru.md) | Colleague handoff: import files, save the system and check the four platforms | current | 2026-10-17 |
| [design/claude-design/CLAUDE_IMPORT.md](design/claude-design/CLAUDE_IMPORT.md) | Apple 27 design-system specification, platform rules, components and provenance | current | 2026-10-17 |
| [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) | Unfinished work, debt, verification gaps and decisions (OQ-0001–0019) | current | 2026-10-17 |
| [exec-plans/completed/offline-ipad-cleanup.md](exec-plans/completed/offline-ipad-cleanup.md) | PLAN-0028: physical iPad offline download and cleanup | current | 2026-10-17 |
| [exec-plans/README.md](exec-plans/README.md) | Plan lifecycle, metadata and indexes | current | 2026-10-15 |
| [exec-plans/completed/sourcekit-lsp-scan.md](exec-plans/completed/sourcekit-lsp-scan.md) | PLAN-0037: SourceKit-LSP scan and platform compilation fixes | current | 2026-10-20 |
| [exec-plans/completed/ipad-reading-offline-layout.md](exec-plans/completed/ipad-reading-offline-layout.md) | PLAN-0036: iPad reading panels and offline library hierarchy | implemented | 2026-10-20 |
| [exec-plans/completed/audio-translation-grouping.md](exec-plans/completed/audio-translation-grouping.md) | PLAN-0035: provider groups in player and offline download dialog, accepted on iPad | completed | 2026-10-20 |
| [exec-plans/completed/offline-russian-defaults.md](exec-plans/completed/offline-russian-defaults.md) | PLAN-0034: language/bitrate defaults, download and player labels, audio playback confirmed on iPad | completed | 2026-10-20 |
| [exec-plans/completed/offline-translation-language.md](exec-plans/completed/offline-translation-language.md) | PLAN-0032: explicit original language and wrong-language saved track repair verified on iPad | completed | 2026-10-20 |
| [exec-plans/completed/offline-yandex-translation.md](exec-plans/completed/offline-yandex-translation.md) | PLAN-0031: verified Russian translation fix; Kazakh service refusal remains open | current | 2026-10-20 |
| [exec-plans/completed/worktree-release-5-18.md](exec-plans/completed/worktree-release-5-18.md) | PLAN-0030: worktree integration and source release 5.18 | completed | 2026-10-20 |
| [exec-plans/completed/ipad-sidebar-state-warning.md](exec-plans/completed/ipad-sidebar-state-warning.md) | PLAN-0033: sidebar warning and Queue identity fix; Split View acceptance remains open | completed | 2026-10-20 |
| [exec-plans/active/voxaframe-redesign.md](exec-plans/active/voxaframe-redesign.md) | PLAN-0027: VoxaFrame redesign in SwiftUI, staged | current | 2026-10-17 |
| [exec-plans/completed/offline-delete-all.md](exec-plans/completed/offline-delete-all.md) | PLAN-0026: delete all offline videos, tasks and cache | current | 2026-10-17 |
| [exec-plans/completed/offline-selection-cleanup.md](exec-plans/completed/offline-selection-cleanup.md) | PLAN-0025: explicit offline streams, audio and file deletion | current | 2026-10-17 |
| [exec-plans/completed/player-level-gestures.md](exec-plans/completed/player-level-gestures.md) | PLAN-0024: full-screen brightness/volume gestures | accepted | 2026-10-17 |
| [exec-plans/completed/voxaframe-branding.md](exec-plans/completed/voxaframe-branding.md) | PLAN-0023: chosen app name, icon and preserved technical identity | current | 2026-10-17 |
| [exec-plans/completed/playback-priority.md](exec-plans/completed/playback-priority.md) | PLAN-0020: shared playback demand and bounded optional transfers | current | 2026-10-17 |
| [exec-plans/completed/stream-source-boundary.md](exec-plans/completed/stream-source-boundary.md) | PLAN-0022: isolate initial metadata acquisition without changing fallback order | current | 2026-10-17 |
| [exec-plans/completed/offline-library.md](exec-plans/completed/offline-library.md) | PLAN-0021: background media downloads and saved audio translations | current | 2026-10-17 |
| [exec-plans/completed/shorts-playback-speed.md](exec-plans/completed/shorts-playback-speed.md) | PLAN-0019: independent Shorts playback speed and translation sync | current | 2026-10-17 |
| [exec-plans/completed/subscriptions.md](exec-plans/completed/subscriptions.md) | PLAN-0017: subscriptions and channel management | current | 2026-10-17 |
| [exec-plans/completed/ipad-menu-overlap.md](exec-plans/completed/ipad-menu-overlap.md) | PLAN-0016: iPad navigation menu overlap | current | 2026-10-17 |
| [exec-plans/completed/hide-watched-settings.md](exec-plans/completed/hide-watched-settings.md) | PLAN-0018: watched-video filtering, threshold and fork link | current | 2026-10-17 |
| [exec-plans/completed/shorts-preloading.md](exec-plans/completed/shorts-preloading.md) | PLAN-0015: bounded native Shorts preloading and Simulator evidence | current | 2026-10-17 |
| [exec-plans/completed/shorts-feed-pagination.md](exec-plans/completed/shorts-feed-pagination.md) | PLAN-0014: preserve account feed pagination | current | 2026-10-17 |
| [exec-plans/completed/shorts-translation-settings.md](exec-plans/completed/shorts-translation-settings.md) | PLAN-0013: independent Shorts translation settings | current | 2026-10-17 |
| [exec-plans/completed/shorts-account-controls.md](exec-plans/completed/shorts-account-controls.md) | PLAN-0012: account Shorts and shared playback controls | current | 2026-10-16 |
| [exec-plans/completed/resource-quality.md](exec-plans/completed/resource-quality.md) | PLAN-0011: resource ownership fixes and iPad Simulator acceptance | current | 2026-10-16 |
| [exec-plans/completed/ipad-performance.md](exec-plans/completed/ipad-performance.md) | PLAN-0010: physical iPad measurements and redundant feed-load fixes | current | 2026-10-16 |
| [exec-plans/completed/player-shorts-stability.md](exec-plans/completed/player-shorts-stability.md) | PLAN-0009: Shorts controls, loading and player presentation stability | current | 2026-10-16 |
| [exec-plans/completed/remember-playback-quality.md](exec-plans/completed/remember-playback-quality.md) | PLAN-0008: saved playback quality and adaptive selection | current | 2026-10-16 |
| [exec-plans/completed/player-video-scale.md](exec-plans/completed/player-video-scale.md) | PLAN-0007: player Fit / Fill control and simulator acceptance | current | 2026-10-16 |
| [exec-plans/completed/feed-version-shorts.md](exec-plans/completed/feed-version-shorts.md) | PLAN-0006: mixed feed spacing, app version and AVPlayer Shorts | current | 2026-10-16 |
| [exec-plans/active/firebase-review-fixes.md](exec-plans/active/firebase-review-fixes.md) | PLAN-0004: review findings 2–6; coordinator owns build/test acceptance | current | 2026-10-15 |
| [exec-plans/active/BotGuard.md](exec-plans/active/BotGuard.md) | PLAN-0003: active; implemented token paths, remaining live acceptance | current | 2026-10-15 |
| [exec-plans/completed/tos-player-ios-plan.md](exec-plans/completed/tos-player-ios-plan.md) | PLAN-0001: historical port and closure evidence; superseded by ADR-0010 | archived | 2026-10-15 |
| [exec-plans/completed/task-89-short-detection-issue.md](exec-plans/completed/task-89-short-detection-issue.md) | PLAN-0002 / #89: completed duration guard; tests present, not rerun | current | 2026-10-15 |
| [design/2026-06-11-tos-player-shorts-design.md](design/2026-06-11-tos-player-shorts-design.md) | Historical Shorts embed design and reconciliation; superseded by ADR-0010 | archived | 2026-10-15 |
| [adr/README.md](adr/README.md) | ADR index, statuses and preservation rules | current | 2026-10-18 |
| [adr/0011-bounded-native-shorts-preloading.md](adr/0011-bounded-native-shorts-preloading.md) | 0011 — native Shorts preparation and resource ownership | current | 2026-10-17 |
| [adr/0012-redesign-availability-and-tokens.md](adr/0012-redesign-availability-and-tokens.md) | 0012 — availability fallbacks and token ownership for the redesign (proposed) | current | 2026-10-17 |
| [adr/0013-minimum-os-18.md](adr/0013-minimum-os-18.md) | 0013 — accepted 18/15/18 minimum; supersedes ADR-0012's OS baseline | current | 2026-10-18 |
| [adr/0014-scene-navigation-and-external-actions.md](adr/0014-scene-navigation-and-external-actions.md) | 0014 — scene-owned navigation and typed external actions (proposed) | current | 2026-10-18 |
| [adr/0015-composition-and-playback-lifetimes.md](adr/0015-composition-and-playback-lifetimes.md) | 0015 — explicit process, scene and playback lifetimes (proposed) | current | 2026-10-18 |
| [adr/0016-core-platform-adapters.md](adr/0016-core-platform-adapters.md) | 0016 — Core boundary and explicit platform adapters (proposed) | current | 2026-10-18 |
| [adr/0017-durable-store-and-sync-ownership.md](adr/0017-durable-store-and-sync-ownership.md) | 0017 — local durable stores own mutations; sync transports revisions (proposed) | current | 2026-10-18 |
| [adr/0018-localization-resource-ownership.md](adr/0018-localization-resource-ownership.md) | 0018 — owning resource bundle and stable localized UI identity (proposed) | current | 2026-10-18 |
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
| [archive/tos-player.md](archive/tos-player.md) | Historical TOS development worklog and test evidence; superseded by ADR-0010 | archived | 2026-10-15 |
| [archive/home-feed-architecture.md](archive/home-feed-architecture.md) | Superseded two-shelf/no-Shorts-separation architecture | archived | 2026-10-15 |
| [archive/dash-quality-switch-tests.md](archive/dash-quality-switch-tests.md) | May quality-test results and old helper names; not fresh acceptance | archived | 2026-10-15 |
| [archive/no-botguard.md](archive/no-botguard.md) | Obsolete prohibition superseded by implemented token paths | archived | 2026-10-15 |
| [archive/reviewer-notes.md](archive/reviewer-notes.md) | Obsolete submission copy; do not reuse (OQ-0014) | archived | 2026-10-15 |
| [archive/playing-methods.md](archive/playing-methods.md) | June stream-order snapshot, predating VISIONOS-first and file decomposition | archived | 2026-10-15 |
| [adr/0001-maintainability-baseline.md](adr/0001-maintainability-baseline.md) | 0001 — Maintainability baseline; accepted | current | 2026-10-15 |
| [adr/0002-mvvm-observable-no-tca.md](adr/0002-mvvm-observable-no-tca.md) | 0002 — MVVM with `@Observable`, no TCA; accepted | current | 2026-10-15 |
| [adr/0003-no-project-generation.md](adr/0003-no-project-generation.md) | 0003 — No Tuist/XcodeGen — the `.xcodeproj` is the source of truth; accepted | current | 2026-10-15 |
| [adr/0004-plain-init-injection.md](adr/0004-plain-init-injection.md) | 0004 — Plain protocol + initializer injection, no DI framework; accepted | current | 2026-10-15 |
| [adr/0005-stream-source-pipeline.md](adr/0005-stream-source-pipeline.md) | 0005 — `StreamSource` + `ResolutionPipeline` replace the `exhaustiveRetry` cascade; proposed | current | 2026-10-15 |
| [adr/0006-tos-player-default-on-ios.md](adr/0006-tos-player-default-on-ios.md) | 0006 — TOS-compliant WKWebView player is the default player on iOS; superseded | current | 2026-10-15 |
| [adr/0007-no-hybrid-avplayer-handoff-for-tos.md](adr/0007-no-hybrid-avplayer-handoff-for-tos.md) | 0007 — No hybrid AVPlayer handoff for TOS background play / PiP; superseded | current | 2026-10-15 |
| [adr/0008-standby-swap-disabled.md](adr/0008-standby-swap-disabled.md) | 0008 — Shorts standby-swap "instant swipe" promotion is permanently disabled; superseded | current | 2026-10-15 |
| [adr/0009-docs-live-with-code.md](adr/0009-docs-live-with-code.md) | 0009 — Non-secret docs live in the public repo, with code; accepted | current | 2026-10-15 |
| [adr/0010-remove-iframe-player.md](adr/0010-remove-iframe-player.md) | 0010 — Remove the IFrame (TOS) and Shorts embed players; accepted | current | 2026-10-15 |
| [../.github/copilot-instructions.md](../.github/copilot-instructions.md) | Assistant entry point delegating to AGENTS.md | current | 2026-10-15 |
| [../.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) | Pull-request acceptance checklist | current | 2026-10-15 |
| [exec-plans/active/home-review-fixes.md](exec-plans/active/home-review-fixes.md) | PLAN-0005: Home review fixes; coordinator acceptance pending | current | 2026-10-15 |
