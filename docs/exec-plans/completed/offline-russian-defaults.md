# PLAN-0034: Language and bitrate defaults in the offline download dialog

Status: completed
Owner: Codex
Date: 2026-10-20

## Scope and boundaries

The user requests Russian (`ru`) defaults in the offline download dialog and
prefers a lower bitrate. Start from local `master` at `06498088`, using Xcode 27.0.
Preserve unrelated `project.pbxproj` and `Localizable.xcstrings` changes.
Commit accepted task changes to local master; no remote push.
Kazakh translation is explicitly out of scope and is not a priority.

The user clarified: choose an audio track in Default Audio Language and always
enable Yandex translation to the same language, even when a matching track exists.
Prefer the lowest known positive bitrate within that language; fall back to the
original audio when absent. Auto follows the system language. Original Track Only
and languages unsupported by Yandex cannot start a matching translation.
Initial defaults must not overwrite later user choices. Keep existing video-quality
selection and download validation.

## Implementation scope

- `OfflineSelection` owns initial audio preference; the sheet consumes it.
- Carry direct-stream bitrate through the existing optional track metadata; use
  existing HLS bitrate metadata for HLS choices.
- Update selection tests and affected UI fixture expectations.
- Omit the misleading "Unknown language" prefix when YouTube provides no audio
  language; retain codec/bitrate and leave the language metadata unset.
- Record the changed defaults and acceptance evidence.

## Acceptance and checkpoints

| Check | Evidence | Result |
|---|---|---|
| Callers and data flow | One shared sheet used by video cards and player; current audio preference selects original, translation starts off | inspected |
| Language and bitrate defaults | 17 focused tests covered by full CI: settings/system language, regional tags, lowest known rate, original fallback, compatible HLS choice, bitrate propagation, legacy decoding and unlabeled audio | passed |
| Manual choice | Simulator UI test covers Russian/English settings, enabled translation, manual target and toggle retained across quality changes | passed |
| Physical iPad | User confirmed initial choices; reported unknown language labels for `X-v5XyT1XwU` | defaults confirmed |
| Missing language | Live VisionOS response for the reported video has no `audioTrack`, `LANGUAGE` or video language metadata; AAC options are 50,704 and 131,413 bps. Regression preserves nil language and labels them by codec/rate | fixed |
| Required checks | Final CI: 1,356 tests / 181 suites; strict SwiftLint: zero violations / 492 files | passed |
| Platform acceptance | Final iOS UI run: 2 passed / 0 failed; tvOS Debug simulator build exit 0; Xcode rebuilt and reports Running SmartTube on iPad (Ivan) | passed |

## Evidence and limits

Local diagnostics: `/private/tmp/voxaframe-offline-defaults-20261020`.
`ci-final.log`, `lint-final.log` and the sanitized `reported-audio-metadata.log`
record the checks above. The latter is a read-only metadata request, not a download
or a translation request.

Final iOS result bundle:
`~/Library/Developer/XcodeBuildMCP/workspaces/SmartTubeIOS-debccfdd8460/result-bundles/test_sim_2026-10-20T14-35-50-658Z_pid52182_112e2856.xcresult`.
The tests cover settings-based defaults and manual choices, plus downloading only
selected streams and deleting their task/library files. `tvos-build-final.log`
records the tvOS build. The physical app binary was rebuilt at 17:37 on 2026-10-20;
the user confirmed initial defaults before the final label-only correction.

The additional existing download/add-audio/playback test reached local video and
translation playback without an error (`rate=1`, `voiceRate=1`) but failed its
landscape-window assertion: the simulator app frame remained 683×909. Its
post-rotation/relaunch steps therefore remain unverified in this run. No rotation
code was changed. Result bundle:
`~/Library/Developer/XcodeBuildMCP/workspaces/SmartTubeIOS-debccfdd8460/result-bundles/test_sim_2026-10-20T14-30-34-875Z_pid52182_6dff34c6.xcresult`.

The first defaults UI run exposed an empty audio-picker accessibility value;
explicit audio/translation values fixed it, and the same UI test passed.
An earlier CLI run was terminated after hanging during diagnostic collection;
it is not counted as a passing test.

No Kazakh service fix, new automatic language detection or saved-file migration
is included. HLS uses its published peak bitrate; if the source supplies no
bitrate, that option follows known positive rates.
