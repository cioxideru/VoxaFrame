# 0016 — Enforce the Core boundary with explicit platform adapters

- ID: ADR-0016
- Status: proposed
- Date: 2026-10-18
- Deciders: maintainer; acceptance pending
- Basis: PLAN-0029 AUDIT; [audit A01](../architecture-audit-2026-10.md#a01--core-still-contains-platform-adapters-p2-m-order-5); [architecture guide](../architecture.md); [ADR-0004](0004-plain-init-injection.md)
- Supersedes: none
- Superseded-by: none

## Context

`SmartTubeIOSCore` is intended to hold Foundation-level models, APIs, stores and policy. [Package.swift:24–42](../../SmartTubeIOS/Package.swift#L24) makes the UI library depend on Core, never the reverse. Share and widget consumers also use Core.

The [import guard:7–19](../../scripts/check-core-imports.py#L7) allows Foundation-related modules, Observation, logging and CryptoKit, plus five file-scoped platform exceptions. These include Network, JavaScriptCore, image processing and the disabled ActivityKit download type. An import-only check also misses OS coupling behind Foundation: [TokenManager:173–212](../../SmartTubeIOS/Sources/SmartTubeIOSCore/TokenManager.swift#L173) uses Security symbols, and [HomeWidgetStore:69–74](../../SmartTubeIOS/Sources/SmartTubeIOSCore/HomeWidgetSnapshot.swift#L69) discovers an App Group container.

The target is a practical boundary with a small explicit allowlist, not the claim that Core imports only the Foundation module or already builds on every non-Apple system. No new portability claim has been validated.

## Decision

Keep the two existing Swift products initially. Core owns values and behavior that do not need Apple UI/media/cloud runtime objects; platform adapters live in `SmartTubeIOS` or the appropriate app/extension target. Do not add a package per feature or rename any module in this work.

| Concern | Core retains | Platform owner |
|---|---|---|
| Connectivity | Transfer policy and network-change input values | Network monitoring adapter injected into API/cache consumers |
| Stream challenges | `PoTokenProvider` contract and pure payload/decoding logic | JavaScriptCore/WebKit execution, thread confinement and engine lifetime |
| Credentials | Credential values and the narrow storage capability required by consumers | Security Keychain adapter; AuthService composition |
| Cloud sync | Local store mutations, revisions and conflict rules | iCloud KVS observation/transport; see ADR-0017 |
| Home widget | Snapshot values, selection rules and shared identifier contract | Container discovery, image conversion and WidgetKit refresh |
| Gallery Live Activity | Nothing if the inactive Gallery feature is retired | If retained, extension-safe ActivityKit attributes outside Core |

Foundation URLSession adapters and bounded JSON stores may remain in Core when they expose injectable transport/storage seams and have no UI or media-engine dependencies. View-model code using Foundation/Observation is not a violation merely because its name ends in `ViewModel`. UI state containing SwiftUI/AppKit/UIKit/AVFoundation types belongs in `SmartTubeIOS`.

For a shared platform type needed by both app and extension, first use the smallest extension-safe source arrangement supported by the project. If a dedicated shared target is necessary, propose it separately with an import graph and extension-safety check; change Xcode membership through Xcode. Do not make extensions depend on the whole UI library to avoid deciding ownership.

Move one adapter at a time with an injected fake and parity checks, then remove its import exception. Review platform symbol use as well as imports so Keychain/container access cannot hide behind Foundation. Keep the existing guard as a ratchet while migration is incomplete.

## Consequences

Core tests can control network transitions, credentials, cloud events and image-independent widget values without starting OS facilities. Extension dependency scope is clearer. Costs include adapting constructors and splitting files that currently mix value types with runtime services.

Acceptance includes existing parser/policy tests, adapter tests, all platform and extension builds, and removal of each migrated allowlist entry. Check that widget images, account refresh, network-change behavior and background playback still work. A green import scan alone is not acceptance.

No persistence, URL, App Group, bundle or Keychain identifier changes accompany a code move. Each adapter can be moved back behind the same interface if a platform constraint is discovered. Packaging and Gallery questions remain proposed in the [audit roadmap](../architecture-audit-2026-10.md#proposed-open-question-entries) for the [open-question register](../OPEN_QUESTIONS.md).

## Alternatives considered

- Expand the Core allowlist indefinitely: permits new platform ownership to accumulate while the boundary appears green.
- Split every service into a new Swift target immediately: increases project changes before the actual shared interfaces are known.
- Move all I/O and all view models out of Core: conflates portable Foundation behavior with platform runtime coupling and discards useful existing seams.
- Import the UI library from every extension: widens dependencies and may pull APIs unavailable to app extensions into their build graph.
