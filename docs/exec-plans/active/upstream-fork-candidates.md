# PLAN-0049: Candidates from upstream and its forks

Status: active

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
