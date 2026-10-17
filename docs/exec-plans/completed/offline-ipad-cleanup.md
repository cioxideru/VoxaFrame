# PLAN-0028: Physical iPad offline download and cleanup

Status: completed
Resolution: deletion fix and adaptive range transfers delivered with physical foreground, background video completion, offline video and bulk-cleanup evidence. Background throughput, repeated CDN rejection and remaining audio/notification acceptance are tracked in OQ-0018.
Owner: Codex. Branch `mac/offline-ipad-cleanup`, attached offline-integration worktree, initially based on `0e81d8a`; build-37 follow-up integrated master `d74a646` before final checks.
Primary checkout has unrelated localization and design work; preserve it. No remote push.

## Scope and result

Fix the reported failure to delete a legacy HLS package on the connected iPad. Download
`JhjPPRZ6W3I` with explicit video quality, original audio and Yandex translation; play with
Wi-Fi disabled; delete all offline videos and verify the owned media/cache files are gone.
Keep sign-in and other app data. Use Xcode 27.0; edit project settings only in Xcode.

Protected package restoration now resolves the physical app-container home before adding
`/.nofollow`. The previous `/var` symlink caused `NSCocoaErrorDomain 512` / POSIX 62 (ELOOP).
The regression uses real filesystem access and failed with the same error before the fix.
Literal percent characters in the package filename were not the cause.

Direct downloads with a known `clen` use sequential HTTP ranges of at most 10 MiB in the
foreground, within the existing background URLSession. Build 37 switches the remaining bytes
to one range when backgrounded, as described below. Validate the exact Content-Range, total and body
length before appending with a 1 MiB copy buffer. Publish only complete files. Partial receipts,
attempt identities and removal records retain ownership across cancellation and restoration.
Cancellation remains active until the terminal callback so a late range cannot restart a removed job.
HTTP rejection is reported with its status instead of being mislabeled as corrupt media.

## Evidence on physical hardware

Device: iPad Pro 11 M5, iPadOS 27.0.1. The first evidence table is VoxaFrame 5.16 (36); the follow-up below is 5.16 (37).
Evidence files below are local under `/private/tmp/` and are not repository fixtures.

| Check | Result and evidence |
|---|---|
| Legacy package deletion | PASS: 1,927 files / 6,772,844,755 bytes removed. Native asset folder, manifest entries/jobs/pending removals empty. `offline-ipad-legacy-inventory.json`, `offline-ipad-after-legacy-files.json`, `offline-ipad-after-legacy-cleanup.json`. |
| Explicit selection | PASS: one 720p H.264 MP4 (731,790,155 bytes), Russian original AAC (77,578,422 bytes), Yandex English MP3 (76,697,226 bytes). Three files total 886,065,803 bytes; other variants were not queued. `offline-ipad-completed-manifest.json`, `offline-ipad-completed-files.json`. |
| Download throughput | Whole-response video transferred 366,467,922 bytes in 1,281 s before cancellation. With ranges, the full 731,790,155-byte video took about 82 s, around 8.6 MiB/s versus 0.27 MiB/s observed previously. This is one live-device comparison, not a network-independent guarantee. Original audio took about 8 s. |
| Playback without internet | PASS for video: Wi-Fi off, local 720p video visibly played for several minutes. Local translation attachment logged at 21:14:17. `offline-ipad-wifi-off.png`, `offline-ipad-playback-with-translation.png`. The user confirmed audible English translation after explicitly selecting the saved track at 21:30. The detail screen defaults to Without translation on re-entry; the earlier original-only report came from a playback with no local translation attachment. Wi-Fi was switched off again at 21:31 and video continued in PiP until 21:35; the user did not observe that repeat, so offline audibility remains unverified. Lip-sync was not measured. |
| Final bulk deletion | PASS at 21:35: Delete all removed the three selected media files (886,065,803 bytes), receipts and queue entries. The offline directory contains only a 60-byte empty manifest; the native asset folder has no remaining media. Library and Downloads are empty. Unrelated WebKit data and a compiler profile were retained. `offline-ipad-after-bulk-delete-manifest.json`, `offline-ipad-after-bulk-delete-files.json`, `offline-ipad-after-bulk-library.json`, `offline-ipad-after-bulk-tmp.json`. |
| Native CI and lint | PASS: 1,161 tests / 160 suites; strict SwiftLint 0 violations in 439 files. `offline-ipad-final-ci.log`, `offline-ipad-final-lint.log`; repeated after master integration in `offline-ipad-integrated-ci.log`, `offline-ipad-integrated-lint.log`. |
| Platform builds | PASS: physical iOS Debug build; iOS Debug and tvOS Release apps with UI-test targets compiled. Quiet xcodebuild runs exited 0. `offline-ipad-final-device-build.log`, `offline-ipad-final-ios-build.log`, `offline-ipad-final-tvos-build.log`. UI-test execution is not claimed. |

Wi-Fi was restored at 21:39 after the offline checks. The app was updated without uninstalling
or replacing its data container. Remaining broader hardware acceptance stays in [OQ-0018](../../OPEN_QUESTIONS.md#oq-0018--offline-library-and-playback-priority-on-physical-ipad).

## Reference mechanisms

The user supplied these repositories. Inspected read-only snapshots; no third-party source
code copied, dependencies added or reference code executed.

| Reference | Useful mechanism | Decision |
|---|---|---|
| [yt-dlp HTTP downloader](https://github.com/yt-dlp/yt-dlp/blob/897341241f2bfb2439fe0367f4c7c9ccd29a3828/yt_dlp/downloader/http.py) and [YouTube extractor](https://github.com/yt-dlp/yt-dlp/blob/897341241f2bfb2439fe0367f4c7c9ccd29a3828/yt_dlp/extractor/youtube/_video.py) | Bounded ranges, range/length validation, final publication only after completion | Adapted to native background sessions; physical speed improvement measured above. No Python process or new downloader dependency. |
| [Seal queue](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/download/DownloaderV2.kt) | Explicit job states, limited concurrency and targeted cancellation | Existing serialized queue and attempt IDs retained; fixed early cancellation acknowledgement. Three concurrent downloads are not adopted for iPad. |
| [Seal format selection](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/DownloadUtil.kt) | Explicit formats and single-video requests | Existing exact selection retained and verified as three files on device. Seal uses yt-dlp for extraction, not an independent extractor. |

An initial HTTP 403 was observed before the stable successful run. Its source was not isolated;
no speculative token changes, arbitrary delays or claim of a permanent 403 fix. No new parallel
workers. Process death between range tasks can restart a transfer; exact-offset crash resume is
not promised. Background notification delivery, offline translation listening/synchronization and
playback priority under competing traffic remain separate checks in OQ-0018.

## Background scheduling check

[Apple background-download guidance](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background) warns that starting another task after each background wake can increase scheduling delays. The measured 82-second result is foreground-only. Background ranges may incur these delays; no background throughput guarantee follows from the foreground result. Hardware acceptance remains in OQ-0018.

A repeat selected 720p/AAC download at 21:40 and video retry at 21:41 returned HTTP 403 before transferring bytes. Both attempts obtained fresh player responses; retry does not reuse the previous signed URL. These attempts provide no evidence about background scheduling. The Mac initially locked before UI cleanup of these two failed test jobs; they were subsequently removed at 22:13. No media bytes were saved for the rejected attempts. Wi-Fi remains on. Earlier bulk deletion of the completed media is independently verified above.

### Follow-up: background continuation (build 37)

Reproduced on the same iPad at 22:07–22:13: the selected 720p video stopped at 19%
(146,800,640 staged bytes) after returning to Home. At 22:09:25, `nsurlsessiond`
reported a 120-second scheduling delay and discretionary classification while the app
was suspended. Returning to the app resumed progress immediately. Evidence:
`offline-ipad-background-mid-manifest.json`, `offline-ipad-background-mid-files.json`,
`offline-ipad-background-stalled-manifest.json`, `offline-ipad-resumed-background-scheduler.log`.

The transport now uses 10 MiB ranges while the app is in the foreground. In the
background, its next request keeps the completed byte offset and downloads the remaining
range in one transfer. This avoids a separate system wake for every 10 MiB. The validator,
serial queue, cancellation identity, partial receipt and 1 MiB file-copy buffer are unchanged.
A background relaunch defaults to the single remaining-range policy; other platforms keep
the existing bounded policy. Swift Testing verifies exact offset, total, progress and completion.

At 22:13, Delete all removed the interrupted video and both failed tasks. The offline folder
contains only the 60-byte empty manifest: `offline-ipad-post-cancel-manifest.json` and
`offline-ipad-post-cancel-files.json`. Wi-Fi remains enabled. Build 37 was installed without
uninstalling or replacing the app container. After the Mac was unlocked, the same selected
720p H.264 / Russian AAC 135 kbps / English Yandex batch started at 22:39. The app went to
Home at about 59%. The system suspended it at 22:39:53; request 43 had already accepted a
206 response for the remaining 291,388,235 bytes. The video completed at 22:56:57 without
opening the app; the next original-audio job resolved and started automatically at 22:56:58.
The remainder took about 1,025 seconds, around 0.27 MiB/s, with no per-10-MiB wake delays.

Large responses on this CDN remain substantially slower than bounded foreground requests:
video was about 0.27 MiB/s and original audio about 32 KB/s. An already running remainder
keeps its request size when the app returns to the foreground. At 22:59 the app was reopened
and the original-audio job was cancelled and retried to avoid waiting for that slow response.
English translation and retried original audio completed in the foreground by 23:00. All
three files totalled 886,065,803 bytes. This verifies background video completion and automatic
start of the next job, not completion of the entire three-file batch in the background or
background notification delivery.

The final build also ignores transient inactive phases when choosing range size: only an
actual background phase switches policy. That final predicate adjustment was compiled and
installed after the background run. At 23:01 Wi-Fi was disabled, both saved audio choices were
explicitly selected, and the final binary played the local video at 23:04. The English track
attachment was logged at 23:04:12. Video advanced until the test stopped at 23:07; audible
English remained unconfirmed because the remote screen has no audio and no listening reply
arrived before cleanup.

Evidence: `offline-ipad-build37-scheduler.log`, `offline-ipad-build37-video-completed.json`,
`offline-ipad-build37-completed.json`, `offline-ipad-build37-completed-files.json`,
`offline-ipad-build37-offline-files.json`, `offline-ipad-build37-validation.log` and
`offline-ipad-build37-progress-00.json` through `offline-ipad-build37-progress-23.json`.

At 23:07, Delete all removed the three media files (886,065,803 bytes) and all queue entries.
The offline directory contained only the 60-byte manifest with empty entries/jobs; the native
asset folder and background URLSession download cache were empty, with no offline receipts
or staged media under tmp. Existing WebKit data and a compiler profile were retained. A fresh
launch at 23:09 still showed an empty library. Wi-Fi was restored and connected at 23:08.
Evidence: `offline-ipad-build37-deleted-manifest.json`, `offline-ipad-build37-deleted-files.json`,
`offline-ipad-build37-deleted-caches.json`, `offline-ipad-build37-deleted-library.json` and
`offline-ipad-build37-deleted-tmp.json`.

Build-37 checks passed: 1,165 package tests in 161 suites, strict SwiftLint with zero violations
in 443 files, physical iOS Debug build, iOS Debug and tvOS Release builds with UI-test targets.
Evidence: `offline-ipad-background-ci.log`, `offline-ipad-background-lint.log`,
`offline-ipad-background-device-build.log`, `offline-ipad-background-ios-build.log` and
`offline-ipad-background-tvos-build.log`. No UI-test execution is claimed. All builds used Xcode
27.0; the physical installed product's `CFBundleVersion` was verified as 37.
