# Changelog

All notable changes to Apex Stream Player.

---

## Build 37 (1.2.0) — July 12, 2026

### Bug Fixes

- **Hidden content on Home screen** — Movies, series, and channels from hidden categories no longer appear in Recently Watched or Favorites rows on the Home screen.
- **Favorites channel switching** — When playing from Favorites and switching to next/previous channel, the player now stays within your favorites list instead of jumping to the full category list.
- **Phone sync doesn't interrupt tvOS** — Adding a playlist on iPhone no longer pops up the sync screen on Apple TV while you're watching. The sync runs on next app launch or when you open Settings.

### New Features

- **Reorder Live TV sections** — On iOS, tap the category picker → `...` menu → "Reorder". Drag categories up/down to rearrange without going to Content Management. Much faster when you have 100+ categories.
- **OpenSubtitles.com integration** — External subtitle support for content without embedded tracks:
  - Settings → Subtitles: enable, enter API key, choose language
  - Auto-fetches subtitles by IMDB ID when playing movies/episodes
  - SRT overlay renders synced to playback time on ALL engines
  - Works on iOS, tvOS, and macOS
  - Get a free API key at opensubtitles.com/consumers

### Notes

- TV Guide settings IS available on tvOS (Settings → TV Guide, between Top Shelf and Search)
- EPG sync during playlist refresh and Settings → TV Guide → Sync Now both use the provider-first strategy

---

## Build 35 tvOS / Build 36 iOS (1.2.0) — July 12, 2026

### Reseller Panel Series Playback — Fixed

- **Stream server detection** — Reseller panels (where the API panel and stream server are different hosts) are now automatically detected by comparing movie `stream_url` hosts against the panel URL.
- **Credential extraction** — Stream URLs use different credentials than the panel login. Now extracted from the movie's `stream_url` path (e.g. `http://server/movie/user/pass/id.ext`).
- **HLS forced for reseller panels** — Episode URLs use `.m3u8` (HLS) instead of the source format `.mkv`. Panels return 403 for raw file extensions but serve HLS fine.
- **Duplicate series fallback** — When a series entry has 0 episodes (common with reseller panels that list the same show in multiple categories), the app searches for an alternate entry with the same name that has episodes.
- **VOD `stream_url` parsed** — The `stream_url` field from the Xtream VOD API is now stored as `movie.directURL` so movies play via the correct stream server.

### Stremio Series — Fixed

- **Episodes load on first tap** — IMDB/TMDB ID stored at catalog import time so the episode fetch doesn't need to wait for background enrichment.
- **No more "no episodes → retry" flow** — Was caused by missing ID on first detail screen open.

### What's NOT Changed (no regressions)

- Standard single-server Xtream providers unaffected (reseller detection returns nil)
- EPG, Live TV, Movies playback all unchanged
- All previous fixes retained (EPG speed, large playlist memory, Top Shelf, Stremio catalog)

---

## Build 34 (1.2.0) — July 12, 2026

### Stremio — Fully Working

- **Auto-catalog for stream-only addons** — When you add a stream addon (AIOStreams, Torrentio), the app automatically fetches the Cinemeta catalog so you have movies/series to browse. Just paste your URL → sync → content appears in Movies/Series tabs.
- **Categories created properly** — Stremio content now shows in Movies/Series tabs (was invisible due to missing category assignment).
- **ModelContext crash fixed** — Category creation no longer crashes with "illegal attempt to insert model in different context."
- **Catalog capped to 100 items** — Sync finishes in ~10-15 seconds instead of minutes (was pulling 2000+ items per catalog).
- **Sync progress bar** — Shows step-by-step progress (manifest fetch → per-catalog import with name + fraction).
- **Addon browser removed** — For App Store safety. URL input still works (same model as VLC/Infuse).

### Auto-Sync Fix

- **Playlist auto-sync triggers reliably** — Adding any playlist (Xtream after Stremio, or any order) now always shows the sync refresh screen. Was keyed on `playlists.count`; now keyed on `playlists.map(\.id)`.

### Content Management

- **Hide All / Show All buttons** — Bulk toggle category visibility for Live TV, Movies, or Series. iOS shows a `...` toolbar menu; tvOS shows header buttons.

### tvOS

- **Top Shelf data writes on launch + setting change** — No longer requires a new sync for content to appear. Existing watch history/favorites populate immediately.
- **TestFlight upload fix** — Added `UIRequiredDeviceCapabilities` arm64 to the Top Shelf extension.

---

## Build 33 (1.2.0) — July 11, 2026

### Stremio — Full Addon Support

- **Sync hang fixed** — Stream-only addons (Torrentio, AIOStreams) no longer stall the sync. Added pagination guards (20-page cap, duplicate detection) and empty-catalog detection.
- **Multi-addon stream resolution** — When playing content, ALL configured Stremio addons that support streams are queried concurrently. Browse from Cinemeta, stream from AIOStreams — just like the Stremio desktop app.
- **Stream picker UI** — Shows all available streams ranked by quality (resolution, codec, HDR, file size) with source addon name. Pick manually or tap "Play Best Quality" for instant playback.
- **Addon catalog browser** — Settings → Playlists → "Stremio Addons". Browse the official Stremio community addon collection, searchable and filterable (All / Catalogs / Streams). One-tap install adds any addon as a playlist.
- **Auto-stream quality selection** — Scores streams by 4K/1080p/720p, HEVC/H.264, HDR, file size. Best stream selected automatically when only one is available or via the "Play Best" button.

### tvOS — Icon Fix + Top Shelf

- **Icon black bars fixed** — tvOS icon layers regenerated from the 1024×1024 source with proper landscape cropping (5:3 aspect). The logo now fills the frame edge-to-edge.
- **Top Shelf support** — When Apex is on the top row of the Apple TV home screen, poster content appears in the Top Shelf area. Configurable in Settings → Top Shelf:
  - Recently Watched (default)
  - Favorites
  - Trending
  - Continue Watching
- Tapping a Top Shelf item deep-links into the app.
- Data refreshes automatically after each playlist sync.

---

## Build 32 (1.2.0) — July 11, 2026

### EPG — Lightning-Fast Guide Loading

- **Provider-first strategy** — EPG now uses the provider's own data directly (like Chilli, SwipTV, TiviMate) instead of downloading 7 separate external feeds. Sync time: ~10-20 seconds vs 1-2 minutes.
- **Instant display** — EPG data appears immediately when opening a Live TV category. Previously waited 1+ minute because store data was held hostage by slow API calls.
- **Single-pass parse** — Provider XMLTV file parsed in one pass instead of two, cutting parse time in half for large providers (1600+ channels).
- **No more 60-second UI delay** — Removed aggressive throttle that prevented the guide from updating for up to a minute after data was ready.
- **Parallel downloads (fallback path)** — When external feeds are needed, all feeds download concurrently (4 on iOS, 2 on tvOS) instead of one at a time.
- **6 concurrent API calls** — Live API gap-fill (for channels not in provider XMLTV) now runs at 6 concurrent on all platforms with no stagger.

### Performance — Large Playlists (17K+ channels)

- **Tab memory management** — Inactive tabs now release their data from memory. Only the current tab and Home stay loaded. This is why other IPTV apps handle large playlists without crashing — they only keep one screen's data in memory.
- **Channel query limits** — Categories capped at 200 channels per query (view paginates at 50). Prevents SwiftData from loading thousands of channels at once.
- **Image cache reduced** — 256MB → 128MB on iOS to leave headroom for the data layer on large libraries.
- **Channel management limit** — Content Management capped at 300 channels per category to prevent crashes on mega-categories.

### EPG Guide UX

- **Smooth scrolling** — Removed the auto-snap-to-now logic that was causing the guide to jump around unpredictably.
- **Now button** — Still available in the top-left corner for manual jump to current time.
- **Initial position** — Guide still opens focused on the current time.

### EPG Data Accuracy

- **Correct programme matching** — Guide now shows the same data as other IPTV apps (Chilli, SwipTV) for the same provider. Previously was rejecting valid provider data as "stale" due to timezone misinterpretation.
- **No stale rejection** — Provider data is accepted and displayed without freshness checks (matching other apps' behavior).

### What's NOT Changed (no regressions)

- EPG data persists across app restarts and category switches
- List and Guide views share the same cache (toggle keeps data)
- iCloud sync still works
- Playback from list and guide unchanged
- Theme system, subtitles, skip intro all unchanged

---

## Build 30 (1.2.0) — July 11, 2026

### EPG Speed

- External EPG feeds download in parallel (4 concurrent iOS, 2 tvOS) instead of sequential.
- Download phase = time of slowest feed instead of sum of all feeds.

### Guide UX

- Guide snaps to current time on vertical scroll (later removed in Build 31 — was causing jumping).

### Memory

- Channel category fetchLimit = 500 (later reduced to 200 in Build 31).

---

## Build 26 (1.2.0) — July 10, 2026

### EPG Stability

- Fixed cross-feed duplicate-id SwiftData crash during external EPG sync.
- Per-channel EPG row cap now survives across syncs (self-healing trim for bloated devices).
- Background `syncIfDue()` no longer runs the full 14-feed pass (was causing OOM kill with ~541MB US_LOCALS1 feed).
- iOS/macOS bundled sync preserves existing EPG store (no longer wipes on every refresh).

---

## Build 24 (1.2.0) — July 9, 2026

### EPG UI Restore

- Shared `LiveTVSectionEPGCache` for list and guide views.
- List and guide mounted in ZStack (toggle doesn't destroy either view).
- Category switches merge data (no wipe).
- TMDB detail on tap (iOS/macOS).
- Home launch freeze fixed (library heroes first, TMDB non-blocking).

---

## Build 21 (1.2.0) — July 8, 2026

### Performance (TestFlight Freeze Fix)

- CloudKit reconcile no longer blocks launch.
- Image cache no longer purged every 2 seconds by indexer.
- Foreground return no longer freezes.
- Genre/Category browse moved to Search tab.

---

## Build 19 (1.2.0) — July 8, 2026

### tvOS EPG Stability

- Playlist-sync crash fixed (coalescing).
- Out-of-memory on large feeds fixed (streaming parser).
- SwiftData unique-constraint crash fixed (EPGListingWriter actor).
- Guide matches list view speed.
- Inline quick EPG sync on tvOS during playlist refresh.
- Category switching retains EPG data.
