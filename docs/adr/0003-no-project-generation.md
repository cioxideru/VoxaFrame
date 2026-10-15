# 0003 — No Tuist/XcodeGen — the `.xcodeproj` is the source of truth

- ID: ADR-0003
- Status: accepted
- Date: 2026-09-10
- Deciders: maintainer

<a id="context-and-problem-statement"></a>

## Context

Before this ADR, private-repo docs (`docs/RULES.md`) claimed the project used XcodeGen with a
`project.yml` source of truth and forbade `xcodebuild`, while other private docs
(`copilot-instructions.md`) mandated `xcodebuild`. Neither `project.yml` nor XcodeGen actually
exist in the repo (`docs/modernization/AUDIT.md` §4, finding H5) — the docs described a project
structure that was never real.

## Decision

`SmartTubeApp/SmartTubeApp.xcodeproj` (7 targets: iOS+Catalyst app, tvOS app, Share extension,
Safari extension, Download widget, two UI-test targets) is edited only through Xcode. No
Tuist, XcodeGen, or other project-generation tool. Agents must not hand-edit `project.pbxproj`
(enforced by the `block-pbxproj.sh` PreToolUse hook, WS1-T1.5); building and testing goes
through `xcodebuild`/`swift test`, wrapped by `scripts/` (WS1-T1.1; originally a `justfile`).

## Consequences

- Good: removes a whole class of "which tool actually generates the project" confusion; one
  truthful rule instead of two contradictory ones.
- Good: Xcode 16+ synchronized folders already handle new-file pickup for most targets without
  needing a generator.
- Bad: adding a target or a build-setting change still requires a human in Xcode — not scriptable
  end-to-end. Accepted as the smaller risk versus introducing a generator into a project that has
  never used one.

## Alternatives considered

- **Adopt XcodeGen properly** (write the `project.yml` the old docs assumed existed): rejected —
  a 7-target project with hand-scripted UI-test target membership (`docs/modernization/AUDIT.md`
  §2.3: "30 hand-scripted non-Xcode object IDs") would need careful, target-by-target
  reverse-engineering into `project.yml` with real risk of silently dropping a build setting;
  no maintainer request to take on that risk.
- **Adopt Tuist**: same objection, plus a new dependency and DSL to learn.

## Implementation check — 2026-10-15

The Xcode project remains the source of truth; no project generator configuration is present. Version-setting wiring is still incomplete; see [OQ-0007](../OPEN_QUESTIONS.md#oq-0007--release-runbook-and-version-settings).
