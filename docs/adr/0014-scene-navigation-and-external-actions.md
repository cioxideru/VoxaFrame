# 0014 — Scene-owned navigation and typed external actions

- ID: ADR-0014
- Status: proposed
- Date: 2026-10-18
- Deciders: maintainer; acceptance pending
- Basis: PLAN-0029 AUDIT; [audit A03–A04](../architecture-audit-2026-10.md#navigation-external-actions-and-playback-state); [PLAN-0027](../exec-plans/active/voxaframe-redesign.md); [functional brief](../design/voxaframe-redesign/docs/VoxaFrame-Functionality.ru.md)
- Supersedes: none
- Superseded-by: none

## Context

Core already defines a typed external URL contract, [SmartTubeRoute](../../SmartTubeIOS/Sources/SmartTubeIOSCore/SmartTubeURLScheme.swift#L43). There is no single owner of delivery into a scene. [AppEntry:386–397](../../SmartTubeApp/Sources/AppEntry.swift#L386) converts routes to NotificationCenter dictionaries; six screens subscribe to the channel event. The Mac shell has no consumer for the search-query event. While iOS is covered by the player, AppEntry bypasses the normal browse-state mailbox ([AppEntry:422–435](../../SmartTubeApp/Sources/AppEntry.swift#L422)).

The shared `HomeWidgetStore.appGroup` constant and every App Group entitlement agree on `group.com.ibaranov.smarttube`. Only the app's pending-inbox reader at [AppEntry:45](../../SmartTubeApp/Sources/AppEntry.swift#L45) retains `group.com.void.smarttube`, omitted by regression commit `7f1e270` (2026-10-14). Share actions “Add to Watch Later”, “Add to Queue” and “Add to RSS” are always silently lost to the app while the extension reports success; “Open in VoxaFrame” through its video URL and the widget are unaffected by this regression. Four pending key names are duplicated. These effects follow from the source and commit history; multi-window and signed-extension behavior has not been executed by this audit.

The product intentionally has an iOS overlay/mini-player, a native Mac content-stack player and TV focus navigation. This proposal does not standardize their appearance. The agreed 18/15/18 OS floor is handled separately by reserved ADR-0013.

## Decision

Propose one `@MainActor @Observable` navigation owner per app scene in `SmartTubeIOS`. It owns selected section, navigation path and modal/presentation state. Views submit typed actions to that owner; they do not broadcast app navigation through NotificationCenter or put pending navigation into a browse model.

- Reuse `SmartTubeRoute` for external URLs. Core owns serializable intent values and URL validation; it does not own SwiftUI paths, scenes or player objects.
- Platform entry adapters decode Share, URL, widget, Spotlight and App Intent requests and deliver them to one selected scene. The scene owner invokes the appropriate player presenter. Preserve the iOS persistent layer/PiP path, Mac stack/inspector and TV Back/focus behavior.
- Define the existing App Group and pending keys once as Foundation values shared by the app and extensions. Keep actual defaults/container access in platform adapters. Do not make Share import the entire UI package for these constants.
- Hold an action until the destination is ready. Consume/acknowledge it when accepted by its owner, not when a view happens to observe a property. A URL and inbox representing the same pending action must not be delivered twice; deduplication is by pending-action identity, not permanent suppression of a video ID.
- Keep local delivery acknowledgement distinct from success of an asynchronous remote mutation. A failed Watch Later request must have an explicit retry/error outcome; this is not a claim of exactly-once delivery to YouTube.
- Retain NotificationCenter for real OS events. Remove migrated route notifications and the `deepLinkedVideo` mailbox once their callers use the new owner. Do not retain two authoritative paths for the same action.

Keep one navigation stack per root/tab or independent modal. A pushed destination does not create another stack. Existing section raw values, accessibility values and URL schemes remain unchanged. Separate localized display titles from identity.

The first change is the small App Group contract repair; it does not wait for the router. Complete the single App Group constant before the decided later bundle-ID rename to `com.ibaranov.voxaframe.*`, so that rename updates one authoritative identifier with matching entitlements. Migrate routing by destination with characterization checks. No router framework or new Swift target is required. The interface can be revised per platform without changing the external URL contract; an implementation rollback restores the previous presenter, not two active route owners.

## Consequences

Navigation can be tested as state transitions without constructing every screen, and retained screens cannot all respond to one channel broadcast. The cost is moving paths and sheet state out of several views and making readiness explicit.

Acceptance requires cold/warm video, search, section and channel links; a link while the player is open; Share inbox replay/deduplication; back navigation; iPad width changes; and two independent Mac windows. Test the real shared container on a signed app as well as an injected-suite round trip. Use existing UI-test files for new scenarios.

Which Mac window receives an external action must be decided before implementation: prefer the active eligible window, with a defined fallback when none exists. Unsupported platform actions need an explicit outcome. These proposed questions are listed in the [audit roadmap](../architecture-audit-2026-10.md#proposed-open-question-entries) for later reconciliation with the [open-question register](../OPEN_QUESTIONS.md).

## Alternatives considered

- Keep NotificationCenter and add more guards: each new screen/window must repeat delivery policy; untyped payloads and readiness remain implicit.
- One process-global navigation model: makes independent Mac windows share destinations and back stacks.
- Replace all presenters with one full-screen player: changes established platform behavior and threatens iOS layer/PiP ownership.
- Introduce a new URL route enum: duplicates the already tested `SmartTubeRoute` contract. Extend existing values only when a new external action actually requires it.
