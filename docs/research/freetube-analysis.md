> Status: current — retained research reference; classification reviewed 2026-10-15.
> External repository details are historical snapshots, not verified-current upstream facts.

# FreeTube — Reference Analysis

**Repo:** https://github.com/FreeTubeApp/FreeTube
**Branch:** `development`
**Stars:** ~20.8k | **Forks:** ~1.4k | **Contributors:** 481
**License:** GNU AGPLv3

---

## What Is FreeTube?

FreeTube is an open-source, privacy-focused desktop YouTube client built on **Electron + Vue 3**. It runs on Windows, macOS, and Linux. It does **not** use the official YouTube API — it scrapes YouTube directly using a built-in extractor or optionally routes through an Invidious proxy instance. No Google cookies, no tracking, no ads.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Runtime | Electron (Chromium + Node.js) |
| UI Framework | Vue 3 |
| State Management | Vuex store (modularized) |
| Routing | Vue Router |
| Styling | CSS + SCSS partials |
| Local Database | NeDB (embedded NoSQL, file-based) |
| Package Manager | pnpm |
| Languages | Vue 45%, JavaScript 44%, CSS/SCSS 11% |

---

## Source Tree

```
src/
  data/                  # Static app data (e.g. language lists)
  datastores/            # NeDB database handlers
    handlers/            # Per-entity handlers: subscriptions, history,
                         # playlists, profiles, settings, search history
    index.js             # DB initialisation + corruption recovery
  main/                  # Electron main process (window management, IPC)
  preload/               # Electron preload scripts (context bridge)
  renderer/              # Vue 3 SPA
    components/          # Reusable Vue components
    composables/         # Vue 3 composables (shared logic)
    directives/          # Custom Vue directives
    helpers/             # Pure utility functions
    i18n/                # Internationalisation strings
    router/              # Vue Router route definitions
    scss-partials/       # Shared SCSS variables/mixins
    store/               # Vuex modules (one per domain)
    views/               # Page-level components (routes)
    App.vue              # Root component
    main.js              # Renderer entry point
  botGuardScript.js      # YouTube bot-guard bypass (poToken binding)
  constants.js           # App-wide constants
  index.ejs              # Electron HTML template
```

---

## Architecture: Dual Extractor Model

FreeTube supports two data-source modes, switchable in settings:

### 1. Local API (default)
Uses [`youtubei.js`](https://github.com/LuanRT/YouTube.js) — an unofficial YouTube InnerTube API client written in TypeScript. This is what handles:
- Video metadata & stream URLs
- Search results
- Channel pages
- Trending
- Signature/cipher decoding
- **poToken / BotGuard** (`botGuardScript.js`) — handles YouTube's bot-detection challenges

### 2. Invidious API
Routes all requests through a user-configured Invidious instance (self-hosted YouTube frontend/proxy). Falls back gracefully when the instance is unavailable.

> **Relevance:** The local extractor uses the same `youtubei.js` library used in other open-source YouTube clients. The BotGuard/poToken handling is directly applicable to our playback URL resolution challenges.

---

## Data Persistence: NeDB (Local-First)

All user data is stored **entirely on-device** using NeDB — a lightweight embedded document store. No server, no account required.

Stored locally:
- **Subscriptions** — channel subscriptions (no YT account)
- **History** — watch history
- **Playlists** — user-created playlists
- **Profiles** — subscription groupings (feeds filtered by profile)
- **Settings** — all user preferences
- **Search History** — past queries (importable/exportable)

Export/import supported for all of the above.

> **Relevance:** This is a strong reference for our offline-first data model and local subscription/history management.

---

## Key Features Worth Studying

| Feature | Notes |
|---|---|
| **SponsorBlock** | Skips sponsored segments, intros, outros, etc. Community-sourced timestamps. |
| **DeArrow** | Community-sourced video titles and thumbnails (less clickbait). |
| **Subscription Profiles** | Group channels into profiles; each profile has its own filtered feed. |
| **Mini Player (PiP)** | Picture-in-Picture support. |
| **Chapter Support** | YouTube chapter markers shown in scrubber. |
| **Multiple Windows** | Electron multi-window support. |
| **Keyboard Shortcuts** | Full keyboard navigation. |
| **Screenshot** | Take screenshot of a video frame. |
| **External Player** | Open video in VLC or another external player. |
| **Distraction-Free Mode** | Hide UI elements (comments, related videos, etc.). |
| **Tor/Proxy Support** | Route traffic through an external proxy. |

---

## BotGuard / poToken — Most Relevant Technical Detail

File: [`src/botGuardScript.js`](https://github.com/FreeTubeApp/FreeTube/blob/development/src/botGuardScript.js)

YouTube has been rolling out bot-detection that requires a **proof-of-origin token (poToken)** bound to each video ID. FreeTube solves this by:
1. Running a sandboxed script in a hidden Electron renderer frame (`sigFrameScript.js`)
2. Generating the poToken client-side using the BotGuard challenge
3. Binding the token to a specific video ID before requesting stream URLs

This is a solved problem in FreeTube and is directly applicable to our playback URL resolution layer.

---

## SponsorBlock Integration

FreeTube integrates the [SponsorBlock API](https://sponsor.ajay.app/) to fetch crowd-sourced segment data:
- Categories: sponsor, intro, outro, interaction, self-promo, music_offtopic, preview
- Configurable per-category auto-skip or highlight behavior
- Handled in the store and player component layers

---

## Relevant Vuex Store Modules

Located in `src/renderer/store/`:
- `utils` — general helpers and shared actions
- `settings` — all settings state
- `subscriptions-cache` — caches subscription feed data
- `history` — watch history CRUD
- `playlists` — local playlist management
- `profiles` — profile management

Each module communicates with the NeDB datastores through IPC (main process) or direct datastore calls.

---

## How Subscriptions Work Without Login

This is the most immediately useful mechanism to understand. The whole system is essentially a local RSS reader — no YouTube account, no OAuth, no cookies.

### Step 1 — Storing a Subscription (the "Subscribe" button)

`FtSubscribeButton.vue` handles the subscribe action. When clicked it dispatches:

```js
store.dispatch('addChannelToProfiles', {
  channel: {
    id: props.channelId,          // e.g. "UCBcRF18a7Qf58cCRy5xuWwQ"
    name: props.channelName,      // e.g. "Linus Tech Tips"
    thumbnail: props.channelThumbnail
  },
  profileIds   // which local profiles to add the channel to
})
```

Only three fields are stored: `{ id, name, thumbnail }`. No auth token, no account, no server call.

The Vuex action writes to NeDB via:
```js
db.profiles.updateAsync(
  { _id: profileId },
  { $push: { subscriptions: channel } }
)
```

Subscriptions are stored as an array of `{ id, name, thumbnail }` objects inside a **Profile document** in the local NeDB database (a flat JSON file on disk). That's it — a channel subscription is just a row in a local file.

### Step 2 — Building the Feed

`SubscriptionsVideos.vue` loads videos for all subscribed channels. It has four code paths, with automatic fallback:

```
Primary backend = Local API?
├── RSS mode ON  →  getChannelVideosLocalRSS()
│     └─ fail → getChannelVideosLocalScraper()
│         └─ fail → getChannelVideosInvidiousScraper() (if fallback enabled)
└── RSS mode OFF →  getChannelVideosLocalScraper()
      └─ fail → getChannelVideosLocalRSS()
          └─ fail → getChannelVideosInvidiousScraper() (if fallback enabled)

Primary backend = Invidious?
├── RSS mode ON  →  getChannelVideosInvidiousRSS()
│     └─ fail → getChannelVideosInvidiousScraper()
│         └─ fail → getChannelVideosLocalScraper() (if fallback enabled)
└── RSS mode OFF →  getChannelVideosInvidiousScraper()
      └─ fail → getChannelVideosInvidiousRSS()
          └─ fail → getChannelVideosLocalScraper() (if fallback enabled)
```

If a profile has 125+ subscriptions, it automatically forces RSS to avoid rate limiting.

### Path A — YouTube RSS (public, no auth)

```js
const playlistId = getChannelPlaylistId(channel.id, 'videos', 'newest')
// converts "UCxxxxxx" → "UUxxxxxx" (uploads playlist format)

const feedUrl = `https://www.youtube.com/feeds/videos.xml?playlist_id=${playlistId}`
const response = await fetch(feedUrl)
return await parseYouTubeRSSFeed(await response.text(), channel.id)
```

**Key insight:** YouTube exposes a public Atom/RSS XML feed for every channel at:
```
https://www.youtube.com/feeds/videos.xml?playlist_id=UU{channelId_without_UC}
```
No cookies. No auth. Returns the last 15 videos. This is the same endpoint RSS readers use.

Fallback URL if the playlist feed 404s:
```
https://www.youtube.com/feeds/videos.xml?channel_id={channelId}
```

`parseYouTubeRSSFeed()` parses the Atom XML using `DOMParser`, extracting:
- `yt:videoId` — video ID
- `title` — video title
- `published` — ISO date → `Date.parse()` timestamp
- `media:statistics views` — view count
- `author > name` — channel name (used to keep stored name up to date)

### Path B — Local API Scraper (youtubei.js, no auth)

```js
const result = await getLocalChannelVideos(channel.id)
```

This hits YouTube's InnerTube API directly via `youtubei.js`, without any authentication. Equivalent to what a browser does loading a YouTube channel page — just without cookies/login. Returns richer metadata than RSS (thumbnails, duration, live status, shorts detection, etc.) but is more prone to rate limiting and bot detection.

### Path C — Invidious Scraper / RSS

Routes all requests through a self-hosted Invidious instance as a privacy proxy. The RSS variant uses:
```
{invidiousInstanceUrl}/feed/playlist/{playlistId}
```

### Step 3 — Cache

After fetching, results are stored per-channel in NeDB `subscriptionCache` table:
```js
// keyed by channelId
{ _id: channelId, videos: [...], videosTimestamp: Date, liveStreams: [...], shorts: [...] }
```

On next visit, cached data renders immediately (with a "last refreshed X ago" label). Refresh happens in the background or on manual refresh.

### Step 4 — Profile System

There is always one "All Channels" profile (constant `MAIN_PROFILE_ID`). When you subscribe:
- The channel is **always** added to the main profile
- Optionally also added to additional user-created profiles

`getSubscribedChannelIdSet` returns a `Set` of all channel IDs from the main profile for O(1) "is subscribed?" checks.

### Summary: Why No Login is Needed

| Concern | How FreeTube solves it |
|---|---|
| Storing subscriptions | Local NeDB file — just a list of `{ channelId, name, thumbnail }` |
| Getting new videos | YouTube's public RSS feeds (no auth) or InnerTube API (no cookies) |
| Knowing if subscribed | Set lookup in local profile document |
| Syncing across devices | Not supported — all data is local-only |
| Channel metadata freshness | Updated in-place when RSS/API returns a newer name or thumbnail |

---

## What We Can Learn / Adapt

1. **BotGuard/poToken handling** — Their approach to generating tokens per video ID is the current best practice for unauthed playback. Study `botGuardScript.js` and `sigFrameScript.js`.

2. **Dual API fallback pattern** — Local extractor primary, Invidious as fallback. We could mirror this with a local `youtubei.js`-based extractor vs our existing backend.

3. **SponsorBlock integration** — Clean reference implementation for fetching and applying segment skip data in a native player.

4. **Local-first persistence model** — NeDB approach maps well to our iOS CoreData/SwiftData local-first model for subscriptions and history.

5. **Subscription profiles** — The concept of grouping subscriptions into profiles with independent feeds is a UX pattern worth evaluating for SmartTubeIOS.

6. **`youtubei.js` library** — Same library drives the local extractor. Worth monitoring for iOS-compatible TypeScript usage or adapting its protocol logic.

---

## Links

- **GitHub:** https://github.com/FreeTubeApp/FreeTube
- **Website:** https://freetubeapp.io
- **Docs:** https://docs.freetubeapp.io
- **`youtubei.js` (underlying extractor):** https://github.com/LuanRT/YouTube.js
- **Invidious (alternative API):** https://github.com/iv-org/invidious
- **SponsorBlock:** https://sponsor.ajay.app
