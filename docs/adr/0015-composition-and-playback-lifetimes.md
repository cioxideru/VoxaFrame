# 0015 — Explicit process, scene and playback lifetimes

- ID: ADR-0015
- Status: proposed
- Date: 2026-10-18
- Deciders: maintainer; acceptance pending
- Basis: PLAN-0029 AUDIT; [audit A02/A06](../architecture-audit-2026-10.md); [ADR-0002](0002-mvvm-observable-no-tca.md); [ADR-0004](0004-plain-init-injection.md); [ADR-0011](0011-bounded-native-shorts-preloading.md)
- Supersedes: none
- Superseded-by: none

## Context

Two real app entry points repeat dependency construction; a third package `SmartTubeApp` is compiled but is neither `@main` nor instantiated. [AppEntry:18–25, 128–177](../../SmartTubeApp/Sources/AppEntry.swift#L18) creates browsing state at App scope and injects it into each Mac window. All three shells create search models with an unauthenticated default `InnerTubeAPI()` ([audit A02](../architecture-audit-2026-10.md#a02--composition-and-lifetime-differ-by-entry-point-and-window-p1-m-order-3)); the [API environment default](../../SmartTubeIOS/Sources/SmartTubeIOS/InnerTubeAPIKey.swift#L6) constructs another API. Accepted ADR-0004 already requires plain injection and one root per app target; the proposal specifies lifetimes, rather than replacing that decision.

iOS regular playback, Shorts and pushed Mac/TV players have different lifetimes. [ShortsPlayerView.init:56–60](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/ShortsPlayerView.swift#L56) and tvOS/macOS [PlayerView.init:123–126](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Player/PlayerView.swift#L123) eagerly construct `PlaybackViewModel` through `State(initialValue:)`. Parent re-evaluation that reconstructs these views creates throwaway models even when SwiftUI keeps their existing state. On UIKit platforms, [model init:513–521](../../SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel.swift#L513) registers remote commands; both [setup](../../SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+NowPlaying.swift#L95) and [deinit](../../SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel.swift#L545) remove every target. A discarded or older model can therefore remove the active model's registrations during ordinary view updates, not just player handoff. The frequency and timing need runtime confirmation.

Now Playing and remote commands are [guarded by `canImport(UIKit)`](../../SmartTubeIOS/Sources/SmartTubeIOS/ViewModels/PlaybackViewModel+NowPlaying.swift#L5). Native macOS has the eager-construction cost but no media-key or Control Center Now Playing integration. The proposed platform service must cover that missing adapter as well as fixing ownership on iOS/tvOS.

The existing [PlaybackAudioSession](../../SmartTubeIOS/Sources/SmartTubeIOS/Services/PlaybackAudioSession.swift#L6) demonstrates a process owner with revocable intent, and ADR-0011 protects bounded session-owned Shorts preparation. Both should be retained.

## Decision

Use plain initializers and small dependency values; no DI framework or universal service locator. The app targets remain the composition roots. Shared construction may live in `SmartTubeIOS` so each target declares capabilities without copying the whole graph.

| Lifetime | Owns | Must not own |
|---|---|---|
| Process/account services | Auth/token access, configured API clients, durable store instances, offline scheduler, cloud transport, shared transfer demand, system playback bridge | Selected tab, per-window path, sheet visibility |
| Scene | Navigation owner, screen models, visible player presentation and scene tasks | Another window's back stack or process-wide durable state |
| Playback session | Current item, cancellation generation, queue cursor, history/Now Playing participation, observers and bounded preloader | An unqualified right to clear global command targets |

Share process services deliberately. A singleton is acceptable when its lifetime really is process-wide; consumers still receive an injectable dependency. Production composition must provide configured APIs to screen models. Default constructors may remain convenience fixtures where they cannot silently bypass production configuration.

Move remote-command registration and global metadata publication to one platform service, with native Mac support rather than a UIKit-only guard. Playback sessions acquire an active-owner token and release only their own participation. Global registration must not occur as a side effect of model init/deinit; construct models at the scene/session lifetime boundary so view re-evaluation does not install transient owners. Late cleanup from a stopped session cannot remove the active session's handlers or metadata. Preserve native delegate/callback adapters where the OS requires them.

Keep the iOS `PlayerStateStore`'s single persistent layer/PiP ownership and native Mac/TV presentation. Regular playback and Shorts use explicit activation/deactivation rather than competing registrations. Do not add background or mini-player behavior on platforms where the product does not define it. Global arbitration across Mac windows is a product decision; independent scene state does not imply simultaneous audio playback.

Transfer required hooks out of the unused package app, then delete it. Centralize session bookkeeping incrementally at existing seams. This proposal does not implement or supersede the separately proposed [ADR-0005 stream pipeline](0005-stream-source-pipeline.md); extraction must preserve its current fallback order.

## Consequences

Dependencies and cleanup become reviewable from construction and lifetime boundaries. Tests can supply isolated queues, history, clocks and system-command drivers. The cost is adapting view initializers, environment injection and existing concrete playback dependencies.

Start with a targeted remote-command ownership fix. Prove that parent re-evaluation and creating/disposing regular and Shorts players in either order cannot clear another owner's commands, and that a cancelled start cannot resume a replaced video. Then verify native Mac media keys/Control Center, two-window browsing, account transitions, offline startup, iOS mini/fullscreen/PiP and TV focus. Existing audio-session and preloader tests are retained; they are not substitutes for device acceptance.

All steps are reversible at the composition boundary without changing persisted identifiers or adding a second service graph. Proposed lifetime/window questions are in the [audit roadmap](../architecture-audit-2026-10.md#proposed-open-question-entries), for the [open-question register](../OPEN_QUESTIONS.md).

## Alternatives considered

- Make every store and model a singleton: hides dependencies and shares view state between windows.
- Create every dependency per view: duplicates caches, background work and system playback ownership.
- Adopt a DI/state framework: does not decide lifetimes or fix blanket handler cleanup; conflicts with accepted ADR-0002/0004 without new supporting evidence.
- Rewrite playback as part of composition cleanup: unnecessarily couples a bounded ownership repair to the larger stream-pipeline migration.
