# PLAN-0023 — VoxaFrame identity

Status: completed

Resolution: scoped implementation accepted with native, platform-build and Simulator checks.
Physical and live-service acceptance remains tracked separately in OQ-0018.

- Owner: coordinator; Astra prepares existing asset exports and visible strings.
- Git boundary: `mac/offline-integration`; source work prepared in `mac/stream-source-boundary`.
- Initial state: user changes to the primary scheme and localization catalog are preserved separately.
- Scope: user-selected VoxaFrame name and two-voices/Play icon, app and extension display names, existing icon slots, launch screen, visible app references and documentation.
- Constraints: keep license and attribution, bundle IDs, Keychain, app groups, URL schemes, internal modules and existing repository URLs. Project settings are changed only in Xcode 27.0.
- Basis: user's selection, [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html), [GitHub repository rename documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).
- Dependencies: combined iOS/tvOS acceptance with PLAN-0020–0022.
- Next deliverable: none for this scoped implementation; deferred checks are recorded in OQ-0018.
- Acceptance: VoxaFrame display name and selected icon appear in built products; installed data and deep links retain their technical identity; no upstream App Store listing is presented as the fork's release.
- Blockers: none for local app branding. Repository rename needs a separate explicit decision.

## Artwork

The selected original is [voxaframe-master.png](../../../brand-assets/voxaframe-master.png), created with the built-in image generator. Design brief: two overlapping coral and ivory speech bubbles forming a Play triangle on a dark plum background, no letters, square full-bleed app icon. Platform exports only resize/pad this original. Existing source notices and GPL license remain.

## Checkpoints

| Check | Result |
| --- | --- |
| User selection | VoxaFrame — two voices and Play |
| Asset dimensions and opaque exports | PASS in delegated worktree |
| tvOS display name | Changed through Xcode, Debug and Release |
| iOS/tvOS builds and Simulator | PASS; combined evidence below |
| Trademark/name clearance | Not performed; availability is not claimed |
| GitHub repository rename | Not requested as a final action; not performed |

## Combined integration checks — 2026-10-17

- Xcode 27.0: Release app and UI-test-target builds PASS for both iOS and tvOS.
  Logs: `/private/tmp/voxaframe-ios-release-build.log` and
  `/private/tmp/voxaframe-tvos-release-build.log`. Build output paths were isolated.
- iPad Pro 11-inch (M5) Simulator: both `DownloadsPlaybackUITests` scenarios PASS,
  zero failures/skips, 170.5 seconds; `/private/tmp/voxaframe-final-ui.xcresult`.
  These exercise real URLSession/AVAssetDownloadURLSession and AVPlayer with synthetic local media:
  additional quality/AAC/VOT, saved HLS resolution, rotation, relaunch and unchanged original-media request counts.
- Independent merge review found no loss of the stream-source boundary, playback-demand reset,
  local-source identity, cancellation guards or offline scheduling ownership.
- Built iOS/tvOS bundles report VoxaFrame 5.15 (33), retaining the existing bundle identifier.
  The chosen icon and VoxaFrame label were visually verified on the Simulator home screen.
- Physical background delivery, real YouTube/Yandex requests and measured playback-priority
  benefit remain in [OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad).

## Final gate

- Combined `scripts/ci.sh`: PASS, 1133 tests in 157 suites; secrets, links, Core imports
  and formatting pass. `/private/tmp/voxaframe-final-ci.log`.
- Strict baseline SwiftLint: PASS, zero violations across 429 files.
  `/private/tmp/voxaframe-final-lint.log`.
- Rotation follow-up: PASS, one scenario, zero skips, 96.2 seconds;
  `/private/tmp/voxaframe-rotation-final.xcresult`. The test waits for the app's landscape
  bounds and advancing playback. `XCUIScreen` capture confirms the final layout;
  the first XCTest window is an empty auxiliary window and must not be used for this assertion.
