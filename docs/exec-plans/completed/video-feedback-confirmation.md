# PLAN-0038: Video feedback confirmation

Status: completed
Owner: Codex
Date: 2026-10-20

## Scope and boundary

The user requested an additional confirmation for Not Interested and Don't Recommend
Channel in a video's context menu. The same commands occur on normal and Shorts cards;
normal cards also expose them through More, VoiceOver and the tvOS Play/Pause dialog.

Work is isolated in `mac/video-feedback-confirmation`, based on local `master` at
`c0067fc6`. The worktree started clean; master had just received a separate localization
commit. Commit and merge only this task locally after checks; no remote push.

Reuse native alerts, existing localized labels and the existing feedback handlers.
Cancel must perform no request, feed notification or blocked-channel settings change.
Keep feedback token fallback, signed-in visibility and channel-ID guards unchanged.
No API changes, additional dependencies or Xcode project edits are needed.

## Acceptance and dependencies

- Both actions show the video or channel name and an explicit destructive confirmation.
- Cancel keeps the card; confirming runs the existing handler.
- Normal-card context/More and Shorts context paths have offline fixture UI coverage.
- Xcode 27.0, CI, strict SwiftLint and iOS/tvOS builds pass.
- Reuse the subscription fixture transport so tests cannot change a real account.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Trace callers | VideoCardView menu shared by four entry points; ShortsCardView has its own menu | reviewed |
| Implementation | Both cards defer feedback until the destructive alert action; existing handlers unchanged | reviewed |
| CI | `scripts/ci.sh`: 1,370 package tests in 182 suites; secrets, doc links, core imports and formatting | passed |
| SwiftLint | Strict baseline check, no new violations | passed |
| Platform builds | Xcode 27.0 iOS app and UI-test target; tvOS Simulator app; native macOS package compiled by CI | passed |
| UI regression | `VideoFeedbackConfirmationUITests`: 4 passed, 0 failed, 0 skipped on iPad Pro 13-inch (M5), iOS 27.0 Simulator | passed |
| Visual review | Not Interested names the video; Don't Recommend Channel names the channel; both buttons remain readable | passed |

The UI cases cancel, verify the card remains, reopen the same action, confirm, and verify
that the card disappears. The native iOS menu drops SwiftUI identifiers, so tests fall back
to the action label with an explicitly English test locale. Native alert buttons retain
identifiers but expose nested matches; the tests select their first match.

Evidence: `/private/tmp/voxaframe-video-feedback-PLAN-0037/feedback-ui-4.xcresult`,
`ci.log`, `swiftlint-final.log` and `tvos-build.log` in the same directory. The temporary
directory predates reassignment to PLAN-0038 after a parallel task claimed PLAN-0037.

NOT RUN: physical-device interaction, live YouTube feedback, macOS/tvOS UI interaction.
The existing transport and token fallback are unchanged; UI tests use the fixture transport.

One intermediate pre-commit CI run ended with a SIGTRAP in native
MediaToolbox/CoreFoundation (`__CF_IS_OBJC`, `CFDictionaryAddValue`), without a Swift
test assertion. The subsequent complete pre-commit CI, rules and SwiftLint gate passed.
No playback code was changed for this task.
