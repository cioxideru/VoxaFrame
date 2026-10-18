# 0018 — Localize at the owning resource bundle; keep identity stable

- ID: ADR-0018
- Status: proposed
- Date: 2026-10-18
- Deciders: maintainer; acceptance pending
- Basis: PLAN-0029 AUDIT; [audit A09](../architecture-audit-2026-10.md#a09--catalog-coverage-and-resource-lookup-are-separate-problems-p1-m-order-2); [ADR-0012](0012-redesign-availability-and-tokens.md); [localization guide](../how-to/localization.md)
- Supersedes: none
- Superseded-by: none

## Context

The [package manifest:37–41](../../SmartTubeIOS/Package.swift#L37) processes `Localizable.xcstrings` as a resource of `SmartTubeIOS`. Several package views still use implicit bundle lookup, for example [SettingsView:88–90](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Settings/SettingsView.swift#L88). Apple's [localized Text initializer](https://developer.apple.com/documentation/swiftui/text/init%28_%3Atablename%3Abundle%3Acomment%3A%29) uses the main bundle when no bundle is supplied. A package translation cannot be relied upon through that lookup.

Navigation labels have a second problem: [ShellItem:22–25](../../SmartTubeIOS/Sources/SmartTubeIOS/Views/Shell/ShellItem.swift#L22) deliberately renders raw section IDs verbatim. Those values also participate in identity and UI tests. App extensions and App Intents have their own resource and presentation contexts. Raw catalog coverage is therefore neither lookup correctness nor a complete localization audit.

## Decision

Each UI/resource owner resolves its own display text. Do not create a global main-bundle workaround or duplicate the entire package catalog into each app target.

- Within `SmartTubeIOS`, localizable `Text` and `String(localized:)` lookups explicitly use `bundle: .module`. Labels, buttons, menus, alerts, notifications and accessibility descriptions follow the same ownership rule.
- Use the text-producing form of a component when its string convenience initializer cannot specify the required bundle. Prefer direct Foundation/SwiftUI APIs; a helper is justified only for repeated behavior, not to hide resource ownership.
- Dynamic video/channel/user text is display data, not a localization key. Use verbatim text where appropriate. Deliberately untranslated names, numbers and format-only keys must be distinguished from missing translations.
- Core retains stable IDs and domain values. UI maps section/enum values to localized display titles. Never translate or rename `AppSection` raw values, existing accessibility identifier values, persistence keys or route payloads as a localization fix. Keep the Core/UI-test identifier mirror consistent.
- App targets, Share/widget extensions and App Intent metadata use their actual resource bundle. Inventory their strings explicitly. Share pure keys/values when needed, but do not pull the whole UI library into an extension merely to obtain translations. Any future shared resource target requires a separate justified project change through Xcode.
- New user-visible package strings have English and Russian entries in the existing catalog, preserving its 2-space indentation and `" : "` separators. Preserve interpolation placeholders and plural variants; source-English fallback for older keys is not by itself a defect.

Keep this distinct from design token ownership in ADR-0012. Fix resource lookup before treating missing visible translations as missing catalog entries. Updating the localization guide's bundle-less example belongs in the implementation follow-up.

## Consequences

Russian text resolves consistently without changing test IDs or external contracts. Reviewing only `Text` is insufficient: non-view notifications and extension strings need coverage too. The migration is incremental by screen/resource owner and does not require new state-management or localization dependencies.

Acceptance includes changed-key placeholder/plural checks and runtime bundle resolution, then Russian shell, settings, player controls and offline flows on the supported platforms. Verify Share/widget/intent resources in their actual hosts. A grep count can identify candidates but cannot prove the correct overload, bundle, grammar or rendered layout. English and Russian copy review remains a human/product task.

Rollback can revert a screen's presentation mapping without changing stored identity. Missing-key fallback remains the ordinary platform behavior, not a second custom resource search path. Proposed coverage and extension-resource questions are listed in the [audit roadmap](../architecture-audit-2026-10.md#proposed-open-question-entries), for the [open-question register](../OPEN_QUESTIONS.md).

## Alternatives considered

- Copy the package catalog to every main bundle: multiplies translation ownership and still misses extension hosts.
- Translate raw section or accessibility values: changes identity, tests and potentially persistence instead of just presentation.
- Treat every `Text` string as a localization key: incorrectly localizes provider/user content and format-only data.
- Add a third-party localization framework: the existing native APIs already express the required bundle and plural behavior.
