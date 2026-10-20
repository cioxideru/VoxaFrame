# How to prepare a release

Status: current
Reviewed: 2026-10-20 (source releases)

This guide covers version preparation and source-only GitHub releases. Signing, archiving and upload still need
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
4. Commit the validated change and merge it into local `master`. Check `git remote -v`:
   the maintained checkout uses `fork` for `cioxideru/VoxaFrame`; a fresh clone may use `origin`.
   With an explicit request to publish, push `master` and an annotated `v<version>` tag to that
   repository, then create its GitHub release from the reviewed changelog and validation notes.
   Use a notes file with `gh release create --notes-file`, and attach no personally signed binary.
5. Verify the remote tag resolves to the release commit, the remote `master` includes it, and
   `gh release view` reports the intended version as published. Record the release URL and
   platform test evidence in the execution plan.

Source publication does not establish App Store, TestFlight or physical-device acceptance.
