# PLAN-0025: Offline selection and deletion

Status: completed

Owner: Codex. Branch: `mac/offline-selection-cleanup`; managed `offline-integration` worktree,
based on local master `c0a6ff7`. Primary checkout has user-owned Xcode scheme/catalog edits.

## Scope and acceptance

- Offline watch asks for one video resolution/codec, one compatible audio track, and optional Yandex language.
- Explicit selection never queues an unbounded adaptive master or an extra default audio track.
- Downloads can delete a task with its owned files; Library can delete a video with every saved stream/audio.
- Cancellation, late callbacks, relaunch and failed disk writes cannot resurrect deleted tasks or delete other media.
- Use existing actor store, background transport and local player. Preserve old manifests and protected HLS paths.
- Public metadata for reported video `JhjPPRZ6W3I` identifies the 79:53 TSMC video.
  Following the existing visitor-ID flow returned a master with 17 video variants and external
  Russian-original/English-dubbed audio groups. The highest peak bandwidth is not an average:
  the provider reports approximately 732 MB for 720p H.264, 1.42 GB for 1080p H.264, and
  6.69 GB for 2160p VP9. The exact 49 GB display is not reproduced. Signed URLs are not committed.

## Checkpoints

| Step | Evidence |
| --- | --- |
| Diagnosis | Adaptive master selected first; explicit video-only request can enqueue first catalog audio. No deletion actions. |
| Implementation | Explicit form, native HLS rendition/audio selection, durable deletion and partial-package receipts; version 5.16 (34) set in Xcode 27.0. |
| Native tests / CI / lint | PASS: 1152 tests / 159 suites and strict SwiftLint; `/private/tmp/offline-selection-ci-delivery.log` and `/private/tmp/offline-selection-lint-delivery.log`. |
| iPad Simulator HLS | Two tests passed in `/private/tmp/offline-selection-final8-hls.xcresult`: muxed HLS + VOT, separate Russian audio + 720p, relaunch, no replay requests or unselected segment downloads. |
| iPad Simulator selection/deletion and MP4 | Two tests passed in `/private/tmp/offline-selection-final8-ui.xcresult`: chosen files only, task/library deletion, separate audio + VOT, rotation and relaunch. |
| Protected HLS cache deletion | Extended test passed in `/private/tmp/offline-selection-final9-delete.xcresult`; host-side before/after inspection confirms both saved files, entry and jobs removed (`/private/tmp/offline-hls-deletion-proof.json`). |
| iOS/tvOS build-for-testing | PASS: iOS Debug app/test products (`offline-selection-final9-build.log`) and tvOS Release app/test targets (`offline-selection-tvos-final2.log`), both under `/private/tmp`. |
| Local delivery | Commit and integrate the checked task branch under the local-master policy; no remote push. |

## Implementation boundaries

- The existing resolver supplies explicit HLS and MP4 alternatives. Original audio metadata is
  kept independently of the device language. Only the chosen video/audio/translation is queued.
- The native downloader uses a unique bitrate qualifier and verifies the actual selected variant
  against the requested URL, dimensions, codec and frame rate before accepting it. Ambiguous
  metadata or an automatic system fallback fails visibly. The explicit-variant qualifier returned
  CoreMedia -12640 on iOS Simulator 26.5; the verified predicate path avoids that failure.
- Offline playback selects cached HLS audio and does not reapply online audio preferences.
  The regression test exposed unwanted English/360p network requests before this fix.
- Removal intent is committed before cancellation. Saved files, protected HLS packages and
  partial transfer receipts are cleaned before removing manifest entries; failed cleanup can retry.
  Attempt ownership prevents an old task's deletion from removing a newer replacement.

Acceptance uses Xcode 27.0 (27A266a) and iPad Pro 11-inch (M5), iOS Simulator 26.5.
No live iPad, live-provider media download, airplane-mode or background-wakeup acceptance is
claimed. Public metadata inspection and synthetic background downloads are separate evidence.
