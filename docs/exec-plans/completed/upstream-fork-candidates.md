# PLAN-0049: Candidates from upstream and its forks

Status: completed (2026-11-09)
Resolution: candidates 1–4, 6 and 7 delivered; 5 needed no change. The iPad playback check passed; the Brand Account and
Apple TV checks were not run; they are tracked in [OQ-0023](../../OPEN_QUESTIONS.md#oq-0023--upstream-port-device-checks).

- Owner: coordinator (single session), candidates done one at a time.
- Git boundary: local `master`, after PLAN-0048 (`d90656c9`); one commit per candidate, merged into `master`.
- Scope: fixes and features found in [milika/SmartTubeIOS](https://github.com/milika/SmartTubeIOS) after the
  fork point (`e659ce92`, 2026-10-12), its open pull requests and issues, and its active forks
  (review of 2026-11-09). Upstream patches do not apply cleanly; each candidate is ported by hand.
- Constraints: `SmartTubeIOSCore` stays Foundation-only; no new branches in the legacy fallback cascade
  (ADR-0005, WS4) — removing a dead client is allowed.

## Candidates

1. **Channel Videos tab pagination** (upstream #138, `50af4856`). `fetchChannel` returns the Home tab, whose
   continuation tokens are per shelf and return no videos, so `ChannelViewModel.loadMore` stops after ~50 items.
   Take the first page from the Videos tab and page it; keep Home Shorts in a separate list.
2. **SponsorBlock segment-end tolerance** (ThomasHack/NewTube-iOS `f83f4fa3`). A seek to a segment's end can land a
   fraction of a millisecond before it (timescale 600), which still counts as inside, so the skip repeats.
3. **Watch a skipped segment** (ThomasHack `45ec2444`, `eb196821`). Moving back into a segment that was already
   skipped re-skips it at once. Offer the skip button instead, and hide it after a few seconds.
4. **Brand Account channels** (upstream #172, `93a606a9`, `fb0077da`). Keep the primary account's token and send the
   selected channel's `pageId` as `X-Goog-Pageid` on authenticated InnerTube requests, including the watch-history
   player request (PLAN-0046). Picker in Settings › Account; switching reloads Home.
5. **Full subscriptions list** (upstream issue #177, ThomasHack `3ec9649a`). Check whether `FEsubscriptions`
   pagination returns every channel of a large account; port the `FEchannels` merge only if it does not.
6. **Search sort by upload date / views** (upstream issue #178). YouTube ignores the sort option for our clients;
   sort the loaded results locally.
7. **Remove the AndroidVR client** (upstream PR #175 rationale). Since 2026-08-17 `android_vr` answers 403 for every
   format without a GVS PO token; it still runs as race path C and serial step 6 of the exhaustive retry.

Not ported (decided 2026-11-09): upstream PRs #167 and #180 (iframe player, removed by ADR-0010), #169 (identity
xcconfig already present), the remote-command reset (already present), #184 captions, tvOS progressive 4K, and the
forks' tvOS-only rewrites and rebranding. Candidate 8 of the review (launch screen choice) is not in scope.

## Acceptance

- Unit tests for each candidate at its protocol seam (fake API / fake player), no live network.
- `scripts/ci.sh`, SwiftLint and ast-grep rules before each commit; iOS and tvOS builds at the end.
- Device checks that need an account (4, 5) are recorded as `NOT RUN` until done on the iPad.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Review | upstream log, PRs, issues, 14 forks compared on 2026-11-09 | done |
| 1. Channel pagination | `ChannelVideosPaginationTests` (6); `scripts/ci.sh`, SwiftLint, ast-grep rules | passed |
| 2. Segment-end tolerance | `SponsorBlockDecisionEngineTests` (new landing case); `scripts/ci.sh`, SwiftLint, ast-grep rules | passed |
| 3. Watch a skipped segment | `SponsorBlockSkipManagerTests` (4 new), `SponsorBlockDecisionEngineTests` (handled segments); `scripts/ci.sh`, SwiftLint, ast-grep rules | passed |
| 4. Brand Accounts | `BrandAccountChannelTests` (11: parsing, header on Bearer/none/unauthenticated, switch, fallback, sign-out); `scripts/ci.sh`, SwiftLint, ast-grep rules; iOS and tvOS builds. Keychain persistence of the page ID is not unit-tested (the test process has no Keychain entitlement) | passed |
| 4. Brand Accounts on a device | switch to a Brand Account on the iPad: Home, Subscriptions and watch history belong to it | NOT RUN (needs an account with a Brand Account) |
| 5. Full subscriptions list | not ported: upstream #177 comes from upstream's guide-based list; ours pages `FEsubscriptions` navigation since PLAN-0017, whose iPad acceptance loaded 338 channels repeatedly | no change needed |
| 6. Search sort | live WEB search for `bmw i3 neue klasse` returned the same order with and without `CAI=` (2026-11-09); `SearchLocalOrderTests` (4); `scripts/ci.sh`, SwiftLint, ast-grep rules | passed |
| 7. AndroidVR removal | live check 2026-11-09: ANDROID_VR `/player` for `jAf0hEe13LI` answered OK; adaptive video and audio gave 206 for bytes 0–100000 and 403 from byte 3000000; muxed 360p read fully (other clients already supply muxed). Removed race path C, serial step 6, the muxed-fallback upgrade and prefetch, the audio-only retry, the probe method and the client; tvOS now starts the TVEmbedded prefetch with the race. `scripts/ci.sh` (1451 tests), SwiftLint, ast-grep rules; iOS, tvOS and UI-test builds | passed |
| 7. Playback on the iPad | iPad Pro 11-inch M5, build of `033c798b`, signed in: `v2ZtAi2rDzA` and `Wu8xNx4njoM` played by VisionOS HLS; the age-restricted `eZk6xlCtJIg` ran the whole fallback (race paths A and B, serial WKWebView, three rounds of six clients) and ended with "All 3 retry attempts exhausted" after 85 s, mostly two 40 s WKWebView timeouts; ANDROID_VR also answers LOGIN_REQUIRED for it. Toggling Audio-Only in the player loaded the audio item on the first attempt three times. No `AndroidVR` line in the whole log | passed |
| 7. Playback on Apple TV | same checks on tvOS | NOT RUN (no Apple TV connected) |
| Follow-up: audio-only start (former OQ-0024) | the iPad check found that Audio-Only from settings never swapped on the VisionOS, adaptive and fallback starts. Fixed: the swap now runs after any successful start, and each load clears the stale audio-item flag. `AudioOnlyAfterStartTests` (2); `scripts/ci.sh` (1453 tests), SwiftLint, ast-grep rules; iOS and tvOS builds; iPad: `dQw4w9WgXcQ` and `Wu8xNx4njoM` started on VisionOS HLS, switched to the audio-only item within 0.7 s and kept playing (position 140→170 s in 30 s) | passed |
