# PLAN-0032: Preserve original language for saved-video live translation

Status: completed
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

Started from local `master` at `020b9474` using installed Xcode 27.0. Preserve
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
| Spoken language | Local transcription of the first 30 seconds shows Ukrainian vocabulary in the old file and Russian text in the new file; the user confirms the original is accented English and both voice settings played Ukrainian | content checked |
| Live request regression | New test failed before the fix: initial request auto, stored language unread; passes after the fix | passed |
| Focused tests | 35 tests / 2 suites, including cancellation at either library read and saved playback without language lookup | passed |
| Required checks | CI: 1,352 tests / 181 suites; strict SwiftLint: 0 violations / 492 files; both repeated after device repair | passed |
| Platform builds | Physical iOS Debug and generic tvOS Simulator Debug builds exited 0 | passed |
| Device deployment | Xcode installed/reran the current app after the Mac was unlocked; debugger confirms Running on the iPad | installed |
| Device repair | Old MP3 backed up again and hash checked; replaced only that MP3 while the app was stopped; copied it back from the iPad and confirmed the explicit `en→ru` hash and 9,243,629-byte size | passed |
| Preserved media | The selected entry is identical before/after repair, including 720p video, both original English audio tracks and translation identity | passed |
| Physical playback | At 16:57 the iPad attached the local translation and reached readyToPlay in 560 ms; the user confirmed Russian speech, working pause and seeking | passed |

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

Implementation commit: `5243b681`, on local `master`. No remote push.

After unlocking, Xcode showed that the old debug session had ended. A fresh run
installed the current checkout, including the unrelated PLAN-0033 commit.
LLDB found the coordinator's binary symbol, but its Swift expression context could
not resolve the type; no queue mutation occurred. The one-time legacy-file repair
therefore used CoreDevice file transfer while the app was stopped. It did not
exercise a new in-app download or edit the library manifest.

Recovery copy: `upi-pre-repair-backup.mp3` in the private diagnostic directory.
The round-trip copy `upi-device-repaired.mp3` matches the explicit-English response
above and probes as a 577.641-second MP3. All four saved asset records are unchanged;
only normal startup bookkeeping (`revision` and `notifiedBatches`) differs in the
whole manifest. Xcode then launched the app again and confirmed it was running.
Saved-file playback takes precedence over the lively-voice setting, explaining why
both settings replayed the same old wrong-language file.

The user then accepted playback: "Да, русский; пауза и перемотка работают".
Device evidence is in `upi-playback-events.log`; both task-owned live captures were
stopped after the check. The app remains running in Xcode. The first live-request
source selection is covered by the regression test; this physical check verifies
the repaired saved file, not a fresh in-app translation download. The internal
reason Yandex returned Ukrainian content for `auto→ru` is not observable.
Kazakh service refusal and long-duration/offline listening acceptance remain in
[OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad).
