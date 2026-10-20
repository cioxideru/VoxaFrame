# PLAN-0032: Preserve original language for saved-video live translation

Status: blocked
Owner: Codex
Date: 2026-10-20

## Scope and evidence

Investigate the user's screenshot of `iI2NaN_QVTI` ("How UPI Works: Real-Time
Payments in India | Paypal | Zelle") and reported Ukrainian speech under a Russian
translation label. Preserve the original media and retain a recovery copy of the
reported translation before repairing it.

The physical iPad manifest has original audio `en-US` and translation `ru`.
The original MP4 is also tagged `eng`. The saved translation was written on
2026-10-19 at 23:49 local time, before PLAN-0031.
Its SHA-256 exactly matches a fresh `auto→ru` response:
`c8a114d836f40ff9322ca6c60470fe94efd300dd1f9de878def3093dba7a8ba2`.
A fresh `en→ru` response is different:
`681aba111776581e0ca4255d84eec2dd22d42cd69b5549737148c3d3e4ee0692`.
Both requests returned FINISHED. The user was given a short sample of the latter.
Local evidence is in `/private/tmp/voxaframe-yandex-20261020/`; no media or raw logs
will be committed.

PLAN-0031 already selects the original language for new downloads, but local live
playback still starts with `auto` and only recovers after FAILED. A successful
response containing wrong-language speech bypasses that recovery. Read the known
original language from the existing offline library before the first live request.
Do not add a network lookup when local metadata supplies the language.

## Boundaries and acceptance

Use the current `master` checkout at `020b9474` and installed Xcode 27.0. Preserve
unrelated changes in `project.pbxproj` and `Localizable.xcstrings`. No remote push.

- Reproduce the first live request using `auto` despite a known original language.
- Use existing library metadata and shared language normalization; retain cancellation.
- Keep saved translation playback independent of network and source-language lookup.
- Confirm the replacement file's language before replacing the reported saved track.
- Run CI, strict lint, relevant platform builds and the physical-device repeat.
- Commit task changes to local master after checks.

## Checkpoints

| Check | Evidence | Result |
|---|---|---|
| Screenshot and device records | Same video ID, original en-US, translation ru | confirmed |
| File association | Saved file equals fresh auto response, differs from explicit en response | confirmed |
| Spoken language | Local transcription of the first 30 seconds shows Ukrainian vocabulary in the old file and Russian text in the new file; user sample reply pending | content checked |
| Live request regression | New test failed before the fix: initial request auto, stored language unread; passes after the fix | passed |
| Focused tests | 35 tests / 2 suites, including cancellation at either library read and saved playback without language lookup | passed |
| Required checks | CI: 1,352 tests / 181 suites; strict SwiftLint: 0 violations / 492 files | passed |
| Platform builds | Physical iOS Debug and generic tvOS Simulator Debug builds exited 0 | passed |
| Device deployment | Xcode installed/reran the app; paused on main thread for precise re-enqueue | installed |
| Device repair | Old MP3 backed up; no saved files changed yet. Xcode UI became unavailable when the Mac locked | blocked |

## Implementation and review

`OfflineTranslationFinding` now reads the original-audio language from the existing
library only after finding no saved translation for the requested target. Normalization
is shared with download resolution. Dubbed and translated tracks cannot supply the
original language. The view model checks cancellation and playback identity after the
new suspension. A missing/unsupported language retains the existing `auto` fallback.
No new network request, persisted field, dependency or automatic file migration was added.

The local speech diagnostic used an isolated temporary faster-whisper 1.2.1 environment
and the base model; audio was processed locally. Its automatic language classifier called
both samples Russian, so that classifier is not evidence of the old file's language.
The actual transcript contains Ukrainian vocabulary consistent with the user's report;
the new transcript is Russian. Evidence: `language-recognition.jsonl`. These diagnostic
packages/model are outside the repository and are not application dependencies.

Dependencies: connected iPad and an unlocked Mac for Xcode control.
Blocker: the UI tool reported that the Mac is locked and requires manual unlocking.
The app was paused by the debugger. CoreDevice accepted `process resume` for PID 26003,
but debugger state could not be checked while locked; verify/resume it before the next test.
Re-enqueue only `vot-ru` for this video using the existing coordinator; preserve video
and original audio. Verify the resulting file matches the fresh `en→ru` hash above.
