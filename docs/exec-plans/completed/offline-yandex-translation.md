# PLAN-0031: Diagnose offline Yandex translation on iPad

Status: completed
Resolution: original-language and error-reporting fixes accepted for Russian translation on the physical iPad. The subsequent Kazakh translation is still refused by Yandex; that outcome remains open in OQ-0018.
Owner: Codex
Date: 2026-10-20

## Scope and boundaries

Diagnose the user's intermittent translation download on the connected physical iPad,
fix the first proven failure in the shared download/translation path, and verify the
same scenario after the change. Preserve existing offline files, account credentials,
and the running reproduction until the evidence is captured.

Git boundary: the existing `master` checkout, opened by Xcode. Initial unrelated changes
were reported in `project.pbxproj` and `Localizable.xcstrings`; do not include them in
this task. Commit only task changes after required checks; no remote push.

Use installed Xcode 27.0. Do not edit `project.pbxproj` by hand. Tokens, signed media
URLs and raw device logs stay out of the repository.

## Diagnosis and delivered change

Xcode UI confirms the project in this checkout, scheme `SmartTube`, and a running
debug session on `iPad (Ivan)`. The saved scheme uses Debug and LLDB with
`-FIRDebugEnabled`; it has no test-fixture launch arguments.

`idevicesyslog` receives current app/media events. Capture and filtered events are
stored locally in `/private/tmp/voxaframe-yandex-20261020/`. The first sandboxed
`devicectl list devices` timed out; CoreDevice access succeeded with sandbox escalation.

The failed job is for `iwRaNYa8yTw`; its video and original English audio were already saved.
At 15:27:37, 15:28:07 and 15:28:38 local time Yandex returned WAITING, then FAILED at
15:29:08. Manual retry failed at 15:33:19. LLDB at `OfflineSourceResolver.swift:146`
confirmed the message: "Возникла ошибка при переводе, попробуйте позже".
The diagnostic breakpoint was removed and execution resumed.

A translation-only probe compiled with the unchanged production `YandexVOTClient`
compared source languages for this same video/duration/target. At 15:36:59–15:37:00,
alternating `auto`, `en`, `auto`, `en` returned FAILED, FINISHED, FAILED, FINISHED.
Each English request returned an audio URL; auto returned the same refusal seen on iPad.
Evidence: `language-comparison.jsonl` in the local capture folder. No OAuth token was used.

Cause: offline source resolution discards original-language metadata and always requests
`auto`; this video's auto-detection fails although the English translation is available.
The error path then replaces the Yandex explanation with a generic unavailable-variant error.
The saved-video live translation path also starts with `auto`.

Fix: derive source language from original audio metadata or auto-generated captions;
reuse the same metadata for duration/upload in download resolution. Live translation of
a local video resolves the original language only after an auto-language refusal, retries
once with that language and preserves cancellation checks. Other failures remain terminal.
Preserve the server's explanation in the offline job; diagnostic messages remain private.

## Acceptance

- Preserve a timestamped reproduction and explain the first unintended behavior.
- Add focused regression coverage at the existing protocol boundary for a code fix.
- Run package CI, SwiftLint and platform compilation appropriate to changed code.
- Rebuild/run on the connected iPad and repeat the affected action with live logs.
- Keep unverified outcomes explicit; close only after acceptance evidence exists.

## Checkpoints

| Checkpoint | Evidence | Result |
|---|---|---|
| Project and toolchain | Xcode UI and `xcodebuild -version`: 27.0 / 27A266a | confirmed |
| Capture | Device app/media logs arrive; translation/download filter is running | ready |
| Reproduction | WAITING → FAILED in device logs; failed job and LLDB reason read | confirmed |
| Cause | Alternating auto/en requests returned 0/1/0/1 with otherwise identical inputs | confirmed |
| Regression before fix | Three new tests failed with eight issues, including wrong language and lost reason | reproduced |
| Cause, fix, regression | Four new tests cover original-language evidence, both duration paths, preserved refusal and bounded live fallback | passed |
| Required checks | `scripts/ci.sh`: 1,351 tests / 181 suites, repeated after localization; strict SwiftLint: 0 violations / 492 files | passed |
| Device build | Xcode 27.0 physical iOS Debug build exited 0; Xcode installed and launched the app at 15:48 | passed |
| Device repeat | At 15:51:02 `en→ru` returned FINISHED; the same job completed and saved a 10,208,279-byte MP3. User confirmed download, audible Russian, pause and seeking | passed |
| tvOS compilation | Xcode 27.0 generic tvOS Simulator Debug build exited 0 | passed |

Review: source-language selection is shared by download resolution and local live recovery.
Known duration no longer bypasses language evidence. The live fallback is restricted to a
local video's explicit `FAILED` response while using `auto`; saved audio attachment still
makes no network request. A second refusal with the known language is terminal.
The device's `manifest-after.json` and `offline-files-after.json` confirm the translation
asset and size. The original audio/video filenames are unchanged. Voice attachments are
logged at 15:51:22 and 15:51:31. Raw logs and manifests remain in the private local capture
folder; no credentials, signed media URLs or user library inventory are committed.

Airplane-mode playback and long-duration synchronization were not checked in this session.
The live auto-to-original fallback is covered by protocol-fake tests; the device repeat
exercised download and saved playback.

## Kazakh follow-up: unresolved service refusal

The user then requested the same video's Kazakh translation. The device sent `en→kk`
at 15:51:38 and received WAITING with 633 seconds remaining. At 15:52:08 Yandex returned
FAILED with "Аударма кезінде қате пайда болды, кейінірек байқап көріңіз" (an error occurred
during translation; try again later). The job preserved that explanation; no audio URL
or Kazakh file was returned.

Independent translation-only requests on the Mac at 15:53–15:55 reproduced the same
refusal with both `en` and `auto`; interleaved `en→ru` still returned the finished audio.
The request fields match the defaults in the inspected
[upstream encoder](https://github.com/FOSWLY/vot.js/blob/main/packages/core/src/protobuf.ts).
Diagnostic-only requests with `forceSourceLang` and `bypassCache` also returned FAILED.
These options were not added to production code. Response field 12 was 7; its internal
meaning is undocumented and is not treated as an instruction to retry or upload audio.
Evidence: `manifest-kazakh.json`, `target-comparison.jsonl`, `target-recheck.jsonl`,
`target-fields.jsonl`, `target-force.jsonl`, `target-bypass.jsonl`.

[Yandex's supported-language documentation](https://yandex.ru/support/browser/ru/search-and-browse/translators-settings)
includes English-to-Kazakh but states that translation is unavailable for some videos.
The observed boundary is a service refusal before media download; the service's internal
cause and a working Kazakh result are not established. See
[OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad).

Dependencies: connected unlocked iPad and the user's reproduction were available.
Remaining blocker: Yandex must return audio for this video's Kazakh translation before
that target can pass end-to-end acceptance.
