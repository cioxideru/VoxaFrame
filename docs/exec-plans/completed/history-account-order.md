# PLAN-0053: History follows the account order

Status: completed (2026-11-20)

- Owner: coordinator (single session).
- Git boundary: branch `fix/history-account-order`, merged into local `master`.
- Scope: a video watched in the official YouTube app appears at the top of VoxaFrame's History after returning to it.

## Problem

A video watched for a minute in the official YouTube app did not appear in VoxaFrame's History.

## Basis (code, 2026-11-20)

- `fetchHistorySection` put the whole on-device history (up to `LocalWatchHistoryStore.maxEntries` = 300) above the
  account history. A video watched in another app therefore sat below every video ever played in VoxaFrame. That order
  dates from #150, when YouTube did not credit VoxaFrame watches to the account; PLAN-0046 fixed the crediting.
- `select(section:)` ignores the section already shown, and `refreshIfStale` waits 15 minutes, so returning to the
  History tab or to the app within that time showed the old list.
- The account fetch was `try?`: a failure silently left only the on-device history, with no log line.
- The iPad check below confirmed that the TV `FEhistory` request returns a video just watched in the official app.

## Changes

1. `WatchHistoryMerge`: the account order leads. An on-device entry the account does not list yet is placed by the
   on-device entries it does list: at the top when watched within the last hour, right before the first listed entry
   when older, right after the newer listed entry between two of them, and after the account page otherwise.
2. `refreshHistory`: selecting the shown History again and returning to the foreground reload it without clearing
   the list; the new first page replaces the top and the pages already loaded stay below with their token.
3. A failed account fetch is logged.

## Acceptance

- Unit tests: the merge rules; the account order in the History load; the refresh on reselect and foreground keeps
  loaded pages and their token.
- `scripts/ci.sh`, SwiftLint, iOS and tvOS builds.
- iPad (signed in): a video watched in the official app appears at the top of History after returning to VoxaFrame.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Root cause | code above | confirmed |
| Implementation | changes 1–3 | done |
| Focused tests | `swift test --filter "WatchHistoryMerge\|BrowseViewModel"` (41 tests) | passed |
| Checks | `scripts/ci.sh` (1471 tests), SwiftLint, ast-grep rules; `scripts/verify.sh` with iOS and tvOS builds (Smoke stage skipped, OQ-0003) | passed |
| iPad check | master `32039441` on the signed-in iPad: a video watched for a minute in the official app appeared at the top of History after returning to VoxaFrame | passed |
