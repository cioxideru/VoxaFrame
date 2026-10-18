# 0017 — Local durable stores own mutations; sync transports revisions

- ID: ADR-0017
- Status: proposed
- Date: 2026-10-18
- Deciders: maintainer; acceptance pending, including conflict policy
- Basis: PLAN-0029 AUDIT; [audit A05/A08](../architecture-audit-2026-10.md); [ADR-0004](0004-plain-init-injection.md); [offline library plan](../exec-plans/completed/offline-library.md)
- Supersedes: none
- Superseded-by: none

## Context

Queue, subscriptions, RSS and watch-state actors persist JSON and separately schedule cloud pushes. [CurrentQueueStore:94–96, 147–149](../../SmartTubeIOS/Sources/SmartTubeIOSCore/CurrentQueueStore.swift#L94) clears locally by removing the defaults entry, skipping `persist()` and its cloud-push hook. Player code can clear the latest queue using an old positional cursor ([PlaybackViewModel+Navigation:57–69](../../SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+Navigation.swift#L57)). `replaceAll` permits duplicate video IDs, so video identity alone cannot identify a queue entry. The [visible-queue handoff:37–43](../../SmartTubeIOS/Sources/SmartTubeIOSCore/PlaylistViewModel.swift#L37) calls `replaceAll(with: visible)` and persists only the visible items, permanently dropping hidden Shorts and other filtered entries. Whether filtering should remove stored items is a product decision.

The cloud manager's only startup call is in the unused package app, its changes stream has no production consumer, and [syncEnabled:36–39](../../SmartTubeIOS/Sources/SmartTubeIOSCore/iCloudSyncManager.swift#L36) is an unsafe cross-actor variable. Its [identity-change observer:67–73](../../SmartTubeIOS/Sources/SmartTubeIOSCore/iCloudSyncManager.swift#L67) discards the registration token; [cleanup:122–129](../../SmartTubeIOS/Sources/SmartTubeIOSCore/iCloudSyncManager.swift#L122) removes `self` instead. Restoring just the startup call would not define observer lifetime, merge, deletion, ordering or error behavior. Existing cloud tests mainly check defaults and absence of crashes.

The [offline store:113–147](../../SmartTubeIOS/Sources/SmartTubeIOSCore/OfflineLibrary.swift#L113) already commits an atomic manifest before exposing a new revision. Its background download/receipt workflow is a separate working architecture and must not be replaced as part of this decision. Apple's [iCloud key-value store](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore?v=1.1.1) has a 1 MB total value quota; whole-collection sync is not unlimited storage.

## Decision

Propose one mutation owner for each durable dataset: its local store actor. Views and playback issue commands to that store and consume snapshots; neither a view cache nor the cloud adapter becomes a second durable writer.

As a small interim change, hide or disable the [“Sync to iCloud” toggle:286](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Settings/SettingsView.swift#L286), or clearly label the workflow as unavailable/incomplete until this proposal is implemented. That correction can land before the store/sync work.

- Stores publish versioned snapshots after successful persistence. Keep existing defaults keys and decode existing data; introduce schema migration only for the affected data shape. A local monotonic revision orders local events, not independent devices.
- Give queue entries stable identity separate from video ID. Queue advance/clear operations carry the relevant queue revision/cursor and reject obsolete operations. Clearing the queue does not silently give a still-playing old item authority over a later replacement queue.
- The playback session owns its active cursor; Core owns queue order and the rules for resolving mutations against that cursor. Obtain an explicit product decision on whether visible-queue playback permanently removes hidden items or only skips them, then encode and test that policy in the store/playback boundary. This proposal does not endorse the current destructive handoff by default.
- One process-lifetime sync adapter observes ordered local changes and applies validated remote snapshots through store commands. Incoming application records its origin and does not immediately export an identical echo. Remove scattered fire-and-forget store-to-cloud pushes after the ordered path is in place.
- Configure opt-in through an actor-isolated operation before startup, using saved settings. Start once, retain observer tokens, stop/reconfigure on identity or opt-in changes, and define cancellation ownership. Durable local data remains usable when cloud delivery fails.
- Define conflict and deletion behavior separately for subscriptions, RSS, watch state and queue before enabling incoming mutations. Device-local revisions alone cannot resolve concurrent edits. Specify a comparable version/conflict rule and deletion representation; do not assume that wall-clock “last write wins” is correct for all four collections.
- Check encoded size against the cloud quota, report delivery failures, and preserve local state on rejection or decode failure. Do not silently drop data or switch storage technologies in response to one failed cloud write.

Use initializer-injected local storage, cloud transport and time in tests. Retain UserDefaults/JSON for bounded data, the atomic offline manifest for downloaded assets, and Keychain for tokens. Do not move credentials into settings, sync snapshots or logs. Security and cloud implementation objects move behind platform adapters under [ADR-0016](0016-core-platform-adapters.md).

## Consequences

Queue changes and sync events become testable ordered operations rather than timing assumptions. Restoring sync will require explicit product choices for conflicts and deletions, plus migration of queue identity. That work is larger than adding a listener.

First land a small stale-queue guard and tests, plus the interim sync-control correction. Then prove the chosen hide/play/unhide behavior, saved opt-in at launch, ordered exports, incoming application without echo, local clear/delete propagation, duplicate queue entries, stale player-end events, malformed/oversized data and account changes using a fake transport. Two-device signed acceptance is still required; no such evidence was produced by this audit.

Rollout is reversible by disabling the transport while retaining local writes and backward-compatible decoding. Do not erase existing records or rename store keys to perform the migration. Exact conflict semantics and UI behavior when a playing item is removed remain proposed questions in the [audit roadmap](../architecture-audit-2026-10.md#proposed-open-question-entries), for the [open-question register](../OPEN_QUESTIONS.md).

## Alternatives considered

- Let every store push independently and add a global pull listener: retains ordering, echo, delete and ownership problems.
- Make cloud storage the sole source of truth: breaks local/offline use and makes temporary cloud failures affect ordinary playback state.
- Identify queue entries only by video ID: cannot represent the allowed duplicate video entries.
- Migrate everything to SwiftData/CloudKit: introduces schema and platform work without first defining the missing mutation/conflict contract. Revisit only if measured size/query requirements exceed the current bounded stores.
