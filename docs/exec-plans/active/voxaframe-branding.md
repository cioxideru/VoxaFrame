# PLAN-0023 — VoxaFrame identity

Status: active

- Owner: coordinator; Astra prepares existing asset exports and visible strings.
- Git boundary: `mac/offline-integration`; source work prepared in `mac/stream-source-boundary`.
- Initial state: user changes to the primary scheme and localization catalog are preserved separately.
- Scope: user-selected VoxaFrame name and two-voices/Play icon, app and extension display names, existing icon slots, launch screen, visible app references and documentation.
- Constraints: keep license and attribution, bundle IDs, Keychain, app groups, URL schemes, internal modules and existing repository URLs. Project settings are changed only in Xcode 27.0.
- Basis: user's selection, [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html), [GitHub repository rename documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).
- Dependencies: combined iOS/tvOS acceptance with PLAN-0020–0022.
- Next deliverable: reviewed app build and iPad Simulator check, then local master merge.
- Acceptance: VoxaFrame display name and selected icon appear in built products; installed data and deep links retain their technical identity; no upstream App Store listing is presented as the fork's release.
- Blockers: none for local app branding. Repository rename needs a separate explicit decision.

## Artwork

The selected original is [voxaframe-master.png](../../../brand-assets/voxaframe-master.png), created with the built-in image generator. Design brief: two overlapping coral and ivory speech bubbles forming a Play triangle on a dark plum background, no letters, square full-bleed app icon. Platform exports only resize/pad this original. Existing source notices and GPL license remain.

## Checkpoints

| Check | Result |
| --- | --- |
| User selection | VoxaFrame — two voices and Play |
| Asset dimensions and opaque exports | PASS in delegated worktree |
| tvOS display name | Changed through Xcode, Debug and Release |
| iOS/tvOS builds and Simulator | Pending integration acceptance |
| Trademark/name clearance | Not performed; availability is not claimed |
| GitHub repository rename | Not requested as a final action; not performed |
