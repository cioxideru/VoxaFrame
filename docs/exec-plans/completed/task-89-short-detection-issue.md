# Task #89: Fix video wrongly detected as short

- ID: PLAN-0002
- Status: completed
- Owner: maintainer; no new executor assigned by this documentation review
- Reviewed: 2026-10-15
- Git boundary: `master`, HEAD `23284b15d990607bbfcab0f7db1cf6d978229149`; working tree has existing uncommitted source changes. Evidence below refers to that tree, not a new commit or release.
- Scope: the original objective and tasks below; documentation reconciliation only on this date.
- Constraints: preserve existing playback behavior and platform boundaries; no source changes in this review.
- Blockers: none for historical implementation closure; current verification gaps are tracked separately.
- Basis: [architecture](../../architecture.md), [decisions](../../adr/README.md), [open questions](../../OPEN_QUESTIONS.md).

Resolution: task #89's duration guard, regression tests, and duration logging are implemented.
The obsolete open-bug wording is retired in [Unreleased](../../../CHANGELOG.md#unreleased).
Next slice: none for #89; a new regression needs new evidence, not reopening the historical diagnosis.

## Acceptance and evidence

The checkpoint outcomes below define the reconciled scope. Expected new implementation commit:
none assigned in this review. The Git boundary above is the inspection baseline; it is not an
acceptance commit for the original work. Independent review of these documentation changes is
pending coordinator review. An active checkpoint closes only after its relevant checks and review.

## Reconciliation checkpoints

| Checkpoint | Scope / observable result | Evidence | Status |
|---|---|---|---|
| #89 / PLAN-0002.CP1 | Reject long videoRenderer SHORTS overlays | `InnerTubeAPI+VideoRenderers.parseVideoRenderer`: duration ≤ 180 guard | implemented |
| #89 / PLAN-0002.CP2 | Long-video and exact-180-second regression cases | `SmartTubeIOSTests.swift`: tests for `vkUokV3Xwp8` scenario and 180-second boundary | present; not rerun |
| #89 / PLAN-0002.CP3 | Duration included in detection diagnostics | `parseVideoRenderer` logs signal and duration | implemented |

Implementation order and dependencies are retained in the original record below.
No new implementation commit or independent runtime acceptance is claimed. Historical results
belong to their original revisions. Current builds, unit tests, UI tests, and device checks:
`NOT RUN` in this documentation-only review. Next steps and remaining conditions are in
[open questions](../../OPEN_QUESTIONS.md).

## Original record

The following is the original analysis and task sequence, retained for history. Its future
tense, line numbers, and example code are not instructions to undo the current implementation.

## Issue
Video `vkUokV3Xwp8` (regular YouTube video) is incorrectly classified as a Short.

## Root Cause Analysis

### Short Detection Logic by Renderer Type

**parseVideoRenderer (WEB API)** — Lines 628-640 in InnerTubeAPI+VideoRenderers.swift
- Primary signal: `reelWatchEndpoint` in `navigationEndpoint` → isShort = true
- Secondary signal: `thumbnailOverlayTimeStatusRenderer.style == "SHORTS"` → isShort = true
- **Problem**: The "SHORTS" overlay style is checked WITHOUT duration validation

**parseTileRenderer (TVHTML5)** — Lines 365-411 in InnerTubeAPI+VideoRenderers.swift
- TILE_STYLE_YTLR_SHORTS style
- reelWatchEndpoint in onSelectCommand or navigationEndpoint
- SHORTS overlay style
- ustreamerConfig == "GgIIBQ==" WITH duration guard: `duration.map { $0 <= 180 } ?? true`
- Portrait thumbnail (height > width)

### The Vulnerability

In parseVideoRenderer, duration is calculated BEFORE isShort (line 616), but:
```swift
let duration = lengthText.flatMap { parseDuration($0) }

let isShort: Bool = {
    if let nav = r["navigationEndpoint"] as? [String: Any], nav["reelWatchEndpoint"] != nil {
        return true
    }
    // NO DURATION CHECK HERE — overlayStyle signal is trusted unconditionally
    return (r["thumbnailOverlays"] as? [[String: Any]])?.contains {
        ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
    } ?? false
}()
```

A regular video appearing in subscriptions feed or other contexts with `thumbnailOverlayTimeStatusRenderer.style == "SHORTS"` will be misclassified, even if its duration is > 180s.

## Concrete Fix Plan

### 1. Add Duration Guard to parseVideoRenderer (line 628-640)
Validate the overlay style signal with a max-duration check, matching the tileRenderer logic:

```swift
let isShort: Bool = {
    if let nav = r["navigationEndpoint"] as? [String: Any], nav["reelWatchEndpoint"] != nil {
        return true
    }
    // Secondary: SHORTS overlay style guarded by max-duration (180s)
    // Videos longer than Shorts max-length must not be tagged as shorts.
    let hasShortOverlay = (r["thumbnailOverlays"] as? [[String: Any]])?.contains {
        ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "SHORTS"
    } ?? false
    // Guard: if duration is known and > 180s, it cannot be a short
    if hasShortOverlay && duration.map { $0 <= 180 } ?? true {
        return true
    }
    return false
}()
```

### 2. Add Regression Tests
Create a test case in SmartTubeIOSTests.swift that:
- Builds a videoRenderer with overlay style == "SHORTS" but duration > 180s
- Confirms it's tagged isShort = false
- Tests the boundary case: exactly 180s should be isShort = true

### 3. Add Logging
Update the debug logging (line 641) to include duration:
```swift
if isShort {
    let signal = ((r["navigationEndpoint"] as? [String: Any])?["reelWatchEndpoint"] != nil) ? "reelWatchEndpoint" : "overlayStyle"
    tubeLog.debug("videoRenderer isShort=true id=\(videoId, privacy: .public) signal=\(signal) duration=\(Int(duration ?? -1))")
}
```

## Files to Modify
1. [InnerTubeAPI+VideoRenderers.swift](../../../SmartTubeIOS/Sources/SmartTubeIOSCore/InnerTubeAPI+VideoRenderers.swift) — parseVideoRenderer function
2. [SmartTubeIOSTests.swift](../../../SmartTubeIOS/Tests/SmartTubeIOSTests/SmartTubeIOSTests.swift) — add regression test case

## Why This Works
- Shorts have a hard max-length of 180s (YouTube's official limit)
- Overlay style is a weak signal that can leak to regular videos in certain feeds
- Duration validation acts as a firewall against false positives
- Matches existing pattern in parseTileRenderer for ustreamerConfig signal
