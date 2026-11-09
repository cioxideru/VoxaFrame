# PLAN-0045: Card feedback from TV feed menus

Status: completed

Resolution: delivered on local `master`; package checks, fixture UI tests and a signed-in physical iPad check passed.
Cards from WEB responses are open in
[OQ-0022](../../OPEN_QUESTIONS.md#oq-0022--card-feedback-on-web-cards).

- Owner: coordinator (single session).
- Git boundary: local `master`, one commit; the pre-existing `Localizable.xcstrings` change is not part of it.
- Scope: Not Interested, Don't Like This Video and Don't Recommend Channel in video and Shorts card menus
  for a signed-in account.

## Problem

Every card feedback action shows "Couldn't send feedback. Try again." for a signed-in user.

## Basis

- Signed-in Home, Subscriptions and History come from the TVHTML5 client as `tileRenderer`s.
  `parseTileRenderer` read no feedback tokens, so every card fell back to `sendFeedbackForVideo`.
- That fallback posts an anonymous WEB `/next`. A live anonymous WEB `/next` (2026-11-09,
  `dQw4w9WgXcQ`) held no `feedbackEndpoint` at all: only `FLAG` and `REMOVE` icons. The fallback
  therefore always threw `tokenUnavailable`. Had a signed-in response carried tokens, the walk would have
  taken the first one in the document, which belongs to a related video, not the card.
- Android SmartTube (MediaServiceCore `8b4a884b`, 2026-09-20, "Restore Not interested and Don't recommend
  channel context menu items"): TV tiles now carry `onLongPressCommand.showEngagementPanelEndpoint`
  (`identifier.tag` = panel ID, `globalConfiguration.params`). The menu, with its tokens, comes from
  `POST /youtubei/v1/get_panel` (TV client, `panelId` + `params`). Older tiles keep the menu inline in
  `onLongPressCommand.showMenuCommand.menu.menuRenderer.items`. Neither form has icon types.
- In both forms "Not interested" (and "Hide" in Subscriptions) carries its `feedbackEndpoint` directly;
  "Don't recommend channel" nests it in the confirmation of an `openPopupAction`.
- The TV menu has no "Don't like this video" item.

## Changes

1. Core: parse tile feedback — inline tokens (direct = video, behind a popup = channel) and the panel
   endpoint — into `Video`.
2. Core: `fetchFeedbackTokens(panelId:params:)` posts `get_panel` and classifies the tokens the same way.
3. Core: `sendFeedback(for:action:)` resolves the token in order: card token, panel, nothing. The anonymous
   WEB `/next` walk is removed; no token throws `tokenUnavailable` and sends nothing.
4. Don't Like This Video sends the card's `DISLIKE` feedback token when a WEB feed provided one. The first commit
   fell back to a `like/dislike` rating; on 2026-11-09 the owner chose instead to show the item only where YouTube
   offers it, so TV cards have no Don't Like.
5. "No token" gets its own message instead of "Try again".
6. UI-test fixture `/next` tokens are replaced by a `get_panel` answer.

## Acceptance

- Unit tests: tile parsing (both forms), panel classification, resolution order, Don't Like fallback,
  no request when nothing is available.
- `scripts/ci.sh`, SwiftLint, iOS and tvOS builds.
- Live: a signed-in Not Interested hides a Home card without the error.

## Checkpoints

| Step | Evidence | Result |
|---|---|---|
| Root cause | live anonymous WEB `/next`, Android commit and fixtures | confirmed |
| Implementation | `VideoFeedback.swift`, tile parser, `sendFeedback(_:for:)`, `get_panel`, card menu, fixtures | done |
| Unit tests | `./h check` 2026-11-09: 1407 tests in 189 suites passed; 12 new in `VideoFeedbackTokenTests` | passed |
| Lint and rules | SwiftLint (baseline) and ast-grep rules: no new findings | passed |
| Builds | `scripts/verify.sh` 2026-11-09: ci, SwiftLint, iOS and tvOS simulator builds | passed |
| Fixture UI tests | `VideoFeedbackConfirmationUITests` 2026-11-09: 7 of 7 passed; app log shows 4 inline-token `feedback` posts and 2 `like/dislike`, no `get_panel` (fixture Home cards carry inline tokens; the panel path is covered by unit tests only) | passed |
| Live acceptance | iPad Pro 11-inch (M5), signed-in account, Profile build of `10000b70`, 2026-11-09: user ran the card actions; app log shows 6 `get_panel` (youtubei.googleapis.com, TV client, HTTP 200, both tokens found), 6 `feedback` accepted with `feedbackResponses`, 1 `like/dislike` HTTP 200, no API errors | passed |
| Don't Like follow-up | owner decision 2026-11-09; `./h check`: 1407 tests passed; `VideoFeedbackConfirmationUITests`: 7 of 7 passed (fixture cards carry a `DISLIKE` token) | passed |
