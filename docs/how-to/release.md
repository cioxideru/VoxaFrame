# How to prepare a release

Status: current
Reviewed: 2026-10-16 (version settings)

This guide covers version and changelog preparation. Signing, archiving and upload still need
a project-specific runbook; [OQ-0007](../OPEN_QUESTIONS.md#oq-0007--release-runbook-and-version-settings)
tracks the remaining release-runbook gap.

1. In Xcode, select the **SmartTubeApp project** (not an individual target) → **Build Settings**
   and update **Marketing Version** and **Current Project Version** for Debug and Release.
   All shipping targets inherit these settings. Avoid target overrides and duplicate values in
   [Base.xcconfig](../../SmartTubeApp/Config/Base.xcconfig), which is not wired as a base configuration.
   Verify the app and embedded extensions' built `CFBundleShortVersionString` / `CFBundleVersion`;
   the Settings screen reads those bundle values. Increment the build for each distributed build,
   and the marketing version for a new release.
2. Run `git-cliff --config cliff.toml --unreleased --prepend CHANGELOG.md` to draft release notes
   from Conventional Commits. Review the generated text and any existing Unreleased entries.
3. Run `scripts/ci.sh` and the SwiftLint command in the [agent guide](../../AGENTS.md) before tagging.
   Follow the [test guide](run-tests.md) for platform acceptance and record checks not run.

No signing, archive, upload, or release validation was run during this documentation review.
