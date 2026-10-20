# PLAN-0034: Language and bitrate defaults in the offline download dialog

Status: active
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
- Reuse original-track and auto-generated-caption language evidence in the
  catalog. Preserve explicit dubbed-track languages and HLS selection names.
- Collapse direct variants with the same saved-track ID (normal/DRC duplicates).
- Record the changed defaults and acceptance evidence.

## Acceptance and checkpoints

| Check | Evidence | Result |
|---|---|---|
| Callers and data flow | One shared sheet used by video cards and player; current audio preference selects original, translation starts off | inspected |
| Language and bitrate defaults | 17 focused tests covered by full CI: settings/system language, regional tags, lowest known rate, original fallback, compatible HLS choice, bitrate propagation, legacy decoding and unlabeled audio | passed |
| Manual choice | Simulator UI test covers Russian/English settings, enabled translation, manual target and toggle retained across quality changes | passed |
| Physical iPad | Fresh manifest proves completed AAC 50,704 bps plus Yandex `ru`; the original-language/deduplication build is now installed and running | label confirmation pending |
| Missing language | Initial investigation found no `audioTrack` or HLS `LANGUAGE`; the caption metadata follow-up below found original-speech `ru`. Generic labels alone did not satisfy the request | superseded |
| Required checks | Current CI: 1,360 tests / 181 suites; strict SwiftLint: zero violations / 492 files | passed |
| Platform acceptance | Earlier defaults UI run: 2 passed / 0 failed; current tvOS Debug simulator build exit 0; Xcode rebuilt and reports Running SmartTube on iPad (Ivan) | passed |
| Library-label follow-up | Regression failed before the fix; CI now passes 1,357 tests / 181 suites, strict lint has zero violations; iPad rebuilt and launched | code verified |
| Original-language follow-up | Regression covers ASR versus manual captions, direct duplicates, muxed/video-only formats, ambiguous/multilingual audio and stable HLS selection identities; included in full CI | code verified |

## Evidence and limits

The user's 18:56 screenshot shows a new-download dialog for a Vert Dider
Sapolsky lecture, with two identical AAC 53 kbps choices and two AAC 134 kbps
choices. The user clarified that the issue affects Vert Dider videos generally;
already-downloaded videos cannot reopen that dialog. This corrects the earlier
assumption that the remaining screenshot problem was in the saved library.

A new sanitized VisionOS metadata probe of `X-v5XyT1XwU` found a Russian
auto-generated caption track (`languageCode=ru`, `kind=asr`, `vssId=a.ru`).
The first investigation omitted this source of language evidence. Direct audio
has no `audioTrack` and HLS audio is named `Default` without `LANGUAGE`; repeated
AAC entries are normal/DRC versions sharing an itag. The translator already used
original/ASR language evidence. The catalog now shares that policy: direct audio
without per-track identities and original HLS renditions can use the source
language. Manual captions and explicitly dubbed tracks cannot relabel audio.
Direct saved-track identities stay unchanged and duplicate choices collapse.
HLS display names can show the resolved language while `hlsAudioName` retains the
exact manifest selection name. Saved files and their old metadata are not rewritten.
Evidence: `source-language-metadata.log`, `source-language-focused.log`,
`source-language-ci.log`, `source-language-lint.log` and `source-language-tvos.log`
in the diagnostics folder. Full CI passes 1,360 tests in 181 suites; strict lint
reports zero violations in 492 files; the tvOS simulator build exits 0. Xcode
rebuilt the physical device binary at 19:10 and reported Running SmartTube on
iPad (Ivan). The user has been asked to check the language and duplicate choices
on an undownloaded Vert Dider video; that result remains pending. No new UI-test
run is claimed for this metadata correction.

Follow-up after `2aab6fe2`: the user reported "labels or selection are still
incorrect". LLDB
read the running iPad module UUID as `821747FE-C405-32F8-915D-C5104CCF964A`, exactly
matching the rebuilt local `SmartTube.debug.dylib`. The app was resumed and Xcode
confirmed Running. `OfflineCoordinator.catalog` calls the resolver directly,
so the new-download dialog does not reuse a stored catalog. A fresh, read-only
copy of the iPad manifest confirms this video's completed video, AAC 50,704 bps
track labelled `Audio · AAC 50 kbps`, and Yandex `ru` translation. Selection and
downloads were correct. The library rebuilds audio labels independently from
the nil language, producing "Unknown language" again. A new regression test
reproduced six failed assertions for legacy, current and empty-language tracks.
The library now uses generic Audio with the encoding detail when no language is
provided; known-language labels are unchanged. This does not rewrite saved files.
Follow-up evidence: `library-label-before.log`, `library-label-ci.log`,
`library-label-lint.log`, and `followup-manifest.json` in the diagnostics folder.
Xcode rebuilt the physical app at 18:45 and reported Running. The two simulator
UI tests and tvOS build below belong to the first commit; they were not repeated
for this label-only correction. Physical library-label confirmation is pending.

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

No Kazakh service fix, local speech recognition or saved-file migration is
included. When YouTube supplies neither a usable track language nor original
speech-caption metadata, the catalog retains a generic label. HLS uses its
published peak bitrate; if the source supplies no bitrate, that option follows
known positive rates.
