# Changelog

All notable changes to Apex Stream Player.

---

## Build 47 (1.2.0) — July 23, 2026

### Crash Fixes

- **SwiftData crash when deleting a playlist (iCloud reconcile)** — TestFlight reports showed `EXC_BREAKPOINT` in `_InvalidFutureBackingData.getValue` during `CloudSyncEngine.saveStores()` → `_propagateDelete`. Playlist → Category and Series → Episode relationships now declare explicit inverses, and `PlaylistDeletion` clears/deletes categories before the playlist so cascade delete never walks half-invalid backing data after a background-context merge.
- **Background kill `0xdead10cc` during iCloud sync** — RunningBoard killed the app when a CloudKit import held the SQLite write lock while the pre-suspension reconcile tried to save. Background/inactive now requests a `beginBackgroundTask` so in-flight commits can finish, and skips starting a competing flush while CloudKit is already syncing.

### Release

- Build number **47** (1.2.0).

---

## Build 46 (1.2.0) — July 20, 2026

### Playback Fixes

- **Next Episode and autoplay reliability** — KSPlayer, VLCKit, and AVPlayer now report a real end-of-playback event to the shared player host. The Next Episode overlay initializes correctly on every platform, and Auto Play Next advances only when enabled.
- **Skip Intro no longer loops the opening** — Pressing Skip Intro or Skip Recap now latches the segment as dismissed, cancels any pending resume seek, and advances the shared playback clock immediately. Drift tolerance applies before the tagged segment only, preventing a completed skip from jumping backward and replaying the first few seconds.
- **macOS Next Episode button remains reachable** — Moving the pointer to the button may reveal the player controls, but the Next Episode action stays visible and moves above the transport bar instead of disappearing.
- **Stalker link timeout hardened** — Stream-link resolution now races the portal request against a 45-second timeout, cancels the losing task, and presents a useful retry message when a portal does not respond.

### Subtitle Fixes

- **macOS duplicate subtitles removed** — Each playback engine reports embedded subtitle availability to the shared player. Once an embedded track is discovered, the downloaded subtitle overlay is removed so only one subtitle layer is rendered.
- **Cross-platform subtitle placement verified** — Bottom subtitles clear safe areas and visible transport controls on iOS, macOS, and tvOS; Center subtitles remain geometrically centered and do not shift with controls.

### Performance and Release Hardening

- **Large Xtream playlists remain responsive on tvOS** — Browse counts use SwiftData `fetchCount` rather than unbounded live queries, avoiding full-catalog observation and repeated view invalidation. Stalker background imports save once per category and yield between categories to preserve Siri Remote responsiveness.
- **Release metadata aligned** — The main app and Top Shelf extension now share build number 46.
- **macOS icon packaging corrected** — The 32 pt Retina app-icon slot now uses a proper 64×64 asset instead of an undersized image.
- **Release documentation refreshed** — The TestFlight checklist now covers large-playlist responsiveness, every playback engine's end-of-episode behavior, subtitle deduplication, pointer interaction, and Skip Intro regression testing.

---

## Build 45 (1.2.0) — July 20, 2026

### Bug Fixes

- **Favorite poster badges visible everywhere** — The filled red heart now receives the live favorite state in every movie/series poster implementation, including category grids, Home rails, Favorites/Recently Watched rows, similar-title strips, and tvOS recommendation rails. The shared top-left badge uses a high-contrast dark plate and stays separate from the top-right TMDB/IMDb rating badge. Live TV continues to show an inline red heart beside favorited channel names.
- **Subtitle placement refined by platform** — Bottom subtitles now respect the video safe area and animate above visible playback controls, returning to the lower resting position when controls hide. iOS/iPadOS uses orientation-aware clearance (120 pt landscape / 150 pt portrait), macOS uses 140 pt, and tvOS uses the larger of 300 pt or 30% of player height. The Center option remains geometrically centered and does not move with the controls. Shared placement applies to external subtitle overlays, KSPlayer embedded subtitles, and the custom macOS AVPlayer subtitle overlay; control visibility is reported by KSPlayer, VLCKit, and AVPlayer.

- **Stalker live TV not playing** — Two root causes fixed:
  - `candidateEndpoints()` now tests PHP middleware endpoints under the user's URL path prefix (e.g. `/c/portal.php`) before falling back to root-level paths. Portals that only serve the API under a subpath were unreachable.
  - `resolveStreamURL()` detects when a channel's `cmd` already contains a pre-tokenized playable URL and returns it directly, instead of re-resolving through `create_link` — which strips the stream parameter on some portals.
- **Stalker movies not playing** — `resolvedURL(from:)` no longer accepts strings without `http(s)://` as valid URLs. Previously `URL(string:)` accepted base64 JSON and other non-URL strings, causing the pre-built URL fast path to skip `create_link`. Base64-encoded VOD commands now correctly fall through to a working `create_link` call.
- **Stalker series: no episodes** — Three fixes:
  - `streamId(for:)` now splits on `:` and parses just the numeric prefix, so series IDs like `"50782:50782"` are stored correctly instead of being hashed.
  - `fetchStalkerEpisodes()` generates per-episode `cmd` values with `stream_id = series_id:season:episode` and `target_container: ["mp4"]` (matching the portal's movie format), so `create_link` returns a proper playable URL.
  - `performStalkerSync()` now syncs the first page of all movie and series categories during sync (1 page/category, ~1 min total) instead of only preloading the top 15 categories in the background. All categories show poster cards immediately.
- **Channel switching crossed playlists** — `LiveChannelNavigator.adjacentMedia()` now filters by the active stream's owning playlist UUID prefix for `.all`, `.favorites`, and `.recentlyWatched` scopes. Previously channel surfing could jump into channels from a different playlist.
- **VLC/AVPlayer missing channel switching buttons** — iOS/macOS player transport controls for VLCKit and AVPlayer engines now include previous/next channel chevron buttons for live TV, matching the KSPlayer engine. `FullScreenPlayerView` wires `switchLiveChannelAction` to all three engines.

### New Features

- **Start from Beginning** — Movies with saved progress offer a secondary button on the detail screen; episodes with saved progress offer the same action in their context menu. Starting over ignores the saved resume offset for that playback launch without changing the normal Resume action. Available on iOS, macOS, and tvOS.
- **Favorite heart badges** — Favorited movie and series posters show a filled red heart at top-left; favorited Live TV channels show an inline heart beside the channel name. Rating badges remain at top-right with no overlap.
- **Content counts** — Browse tabs show playlist-scoped totals at the top: Movies, Series, and Live TV channels. Hidden or restricted content is excluded where applicable.
- **Subtitle appearance customization** — Settings → Subtitles → Appearance: choose Bottom or Center placement and control font size (14–48 pt), text color, background opacity (0–100%), and bottom offset (0–120 pt). Settings apply to all custom subtitle overlays (KSPlayer embedded, external SRT, AVPlayer macOS). Platform-aware defaults (tvOS starts at 28 pt / 60 pt offset). macOS includes a live preview. tvOS uses pill-style pickers for focus-friendly navigation.
- **Stream resolution timeout** — Stalker `create_link` resolution is wrapped in a 45-second timeout. Unresponsive portals show an error instead of an infinite spinner.

### Improvements

- **One-tap iOS category reorder** — The up/down sort button on the Live TV category bar opens the category picker directly in reorder mode, while the category title still opens normal selection.
- **Stalker background catalog loading** — Sync imports page 1 of every VOD and series category so posters appear immediately, then a detached utility task fills pages 2–20 for all categories without keeping the sync sheet open. Background failures are best-effort and do not block browsing.
- **Stalker resolution logging** — `StalkerClient` and `StalkerStreamResolver` now log at each stage (handshake candidates, `create_link` request/response, resolved URL) with `Logger.network` / `Logger.player` for easier debugging.
- **Channel switching scoped to playlist** — `LiveChannelNavigator` now isolates channel surfing to the active playlist across all browsing scopes.

---

## Build 41 (1.2.0) — July 15, 2026

### Live TV / EPG (iOS)

- **Guide sticky scrolling** — Programme cells no longer attach `onLongPressGesture` on iOS/macOS (that delayed pan recognition). Details open via context menu instead; tvOS keeps press-and-hold Select for the detail sheet.
- **Guide blank until resync** — On-demand EPG persist is no longer skipped on iOS while `EPGSyncGate` is active (bundled sync already preserves the store since Build 25). `EPGBrowseLoader` also merges warm live-memory hits so `forceGuideRefresh` paints programmes even if the store round-trip is still settling.

### Playlists / iCloud (tvOS + all platforms)

- **Xtream preferred after reinstall** — Empty/orphaned `apex.selectedPlaylistID` now resolves to preferred catalog type (Xtream → M3U → Stalker → Stremio), not unsorted `playlists.first`. Progressive CloudKit import that pinned Stremio first is promoted to Xtream when a never-synced catalog playlist arrives.
- **Auto-sync queue** — Catalog playlists enqueue ahead of Stremio. On tvOS, **first-time** syncs (`lastSyncDate == nil`) always present the sync cover (routine refreshes still defer off Settings); tab changes re-promote the queue.

### tvOS Add Playlist

- **In-app Copy / Paste** — Long-press Select on `TVSettingsField` (Xtream URL, Stremio manifest, M3U, Stalker, credentials) opens Copy / Paste / Clear via session `ApexTextClipboard`. Apple TV has no system pasteboard; this is Apex↔Apex only. Hint shown on Add Playlist.

### Home

- **Recently Watched includes** — Settings → Layout → Home: toggles for Movies, Series, and Live Channels (all on by default). Available on iOS, iPadOS, macOS, and tvOS. Per-device (`@AppStorage`); does not sync via iCloud.

### Tests

- `PlaylistSelectionTests` — preferred default + auto-sync ordering
- EPG / CloudSync / SyncFrequency suites still green

---

## Build 39 (1.2.0) — July 14, 2026

### Subtitles — Wyzie Subs (replaces OpenSubtitles)

- **New provider: Wyzie Subs** — Simpler, faster, and more reliable. Just an API key (free at store.wyzie.io/redeem, 1,000 requests/day). No username/password/login required.
- **Series subtitles fixed** — Episodes now resolve IMDB IDs via TMDB automatically at playback time. Previously required opening the series detail screen first.
- **SRT parser rewrite** — Fixed Windows line endings (`\r\n`), BOM characters, and non-UTF-8 encodings (Latin-1, Windows-1252). A 35K character file was only parsing 1 cue; now parses 500+.
- **Rendering reliability** — Added poll timer fallback (0.25s) alongside `@Observable` change detection for consistent subtitle display across all engines.
- **Settings simplified** — Settings → Subtitles now shows: Enable toggle, API key, Language picker. No more username/password fields.

### Bug Fixes

- **Streams not recovering after provider outages** — Previously required removing and re-adding the playlist. Root cause: iOS cached error responses (401/403) from the provider. Fix: URL caching disabled on all provider HTTP sessions. Streams now recover instantly when the provider comes back.
- **Live TV favorites not syncing to tvOS** — Favorites and recently watched channels now sync across all devices via iCloud. Previously only the favorite flag synced; watch history was device-local.
- **Hidden live channels in Recently Watched** — Channels hidden via Content Management no longer appear in the Home → Recently Watched row.
- **Hidden content in Recently Added** — Movies and series from hidden categories no longer appear in the Recently Added rows on Movies/Series tabs.
- **macOS: categories not selectable in Guide mode** — The Live TV sidebar couldn't be clicked when the EPG grid was showing. Root cause: macOS NSOutlineView (used by SwiftUI List) lost first-responder focus to the EPG ScrollView. Fix: rebuilt sidebar with ScrollView + onTapGesture which always responds regardless of focus state.
- **macOS: traffic light buttons covering sidebar** — Added top padding so "All Channels" and other items at the top aren't hidden behind the window close/minimize/maximize buttons.
- **tvOS: Trending Movies/Series missing from Home** — Phase 2 (TMDB trending fetch) was in an unstructured Task that got orphaned when tabs unmount. Now runs as structured await with deferred start so it survives tab lifecycle.
- **tvOS: All Channels showing no channels** — Query fetched 200 channels from any playlist without scoping, then in-memory prefix filter eliminated them. Now filters by playlist ID in the query predicate.
- **tvOS: iPhone Remote keyboard still jittery** — Search debounce increased 600ms → 1000ms.
- **Home launch slowdown** — TMDB trending fetch (structured for tvOS fix) was blocking first paint. Now defers 500ms when library heroes are already visible, letting the UI render immediately.

### What's NOT Changed

- EPG, playback engines, themes, Skip Intro all unchanged
- Embedded subtitle track picker (CC button) still shows for streams with built-in tracks
- Existing Wyzie API key syncs via iCloud to all devices automatically

---

## Build 38 (1.2.0) — July 12, 2026

### Bug Fixes

- **Hidden content on Home screen (final fix)** — All Home rows (Trending, Recently Watched, Favorites, Trakt Watchlist, For You) now filter out content from hidden categories. The previous fix only covered some rows.
- **Verbose login errors** — When adding a playlist fails, the error message now shows exactly what went wrong (timed out, can't connect, 403, invalid JSON, etc.) with the context URL. Users can screenshot and send for support — no Xcode needed.

### New Features

- **Clear Guide Data** — Settings → TV Guide → "Clear Guide Data" (red button). Wipes all cached EPG data so a fresh sync pulls clean data from the provider. No reinstall needed.
- **All Channels section** — Live TV now has an "All Channels" option at the top of the category list, showing every channel across all categories in one combined view.
- **OpenSubtitles iCloud sync** — API key, language, and enabled state sync via iCloud. Enter once on iPhone → available on Apple TV automatically.
- **Playlist tester tool** — `Tools/playlist-tester.html` — open in a browser to test user credentials (server reachability, auth, content counts, EPG) before troubleshooting.

### Improvements

- **tvOS search debounce** — Increased to 600ms (from 300ms) to reduce jank when typing with the iPhone Remote keyboard.

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
