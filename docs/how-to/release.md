# How to prepare a release

Status: current
Reviewed: 2026-10-15 (source/configuration inspection)

This guide covers version and changelog preparation. Signing, archiving and upload still need
a project-specific runbook; [OQ-0007](../OPEN_QUESTIONS.md#oq-0007--release-runbook-and-version-settings)
tracks that gap and incomplete version-setting centralization.

1. Review `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   [Base.xcconfig](../../SmartTubeApp/Config/Base.xcconfig). The Xcode project still has hardcoded
   versions and is not wired to that file through base configuration references. Use Xcode to
   reconcile all shipping targets/configurations and verify resolved build settings; editing
   the config alone does not establish the built version.
2. Run `git-cliff --config cliff.toml --unreleased --prepend CHANGELOG.md` to draft release notes
   from Conventional Commits. Review the generated text and any existing Unreleased entries.
3. Run `scripts/ci.sh` and the SwiftLint command in the [agent guide](../../AGENTS.md) before tagging.
   Follow the [test guide](run-tests.md) for platform acceptance and record checks not run.

No signing, archive, upload, or release validation was run during this documentation review.
