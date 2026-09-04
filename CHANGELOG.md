# Changelog

All notable changes to Apex Stream Player.

---

## Build 55 (1.2.0) — September 4, 2026

### Bug Fixes

- **Adding a second playlist spun forever** — The add sheet saved the new playlist on the main thread. If the first playlist was still catalog-syncing, that save blocked the UI and the connection timeout could not fire. New playlists now persist off the main actor, Cancel stays available while connecting, and a hung provider test times out after 20 seconds.
- **iPhone portrait Guide left a black band above the video** — Opening the in-player mini-guide while holding the phone vertically kept the 16:9 picture centered, so the Guide sat in the bottom letterbox and the top stayed empty. The picture now pins to the top and the Guide uses the space underneath.
- **Previous title kept playing audio after you started something else** — Dismissing a series player and immediately opening a movie could overlap both soundtracks. Only one playback session is allowed; starting or claiming a new player stops the outgoing engine immediately.
- **Apple TV in-player Guide showed only a handful of channels** — The compact overlay is unchanged, but Down now walks the full category. Focus lands on programmes (not a giant white box). Scrolling no longer hitching or jumping from building every row at once.
- **In-player channel surf stopped after ~40 channels** — Live up/down uses the full surf list for the current category or section.
- **Sync Now waited on the full TV Guide XMLTV download** — Playlist catalog refresh is no longer blocked on that inline EPG wait.
- **Posters kept spinning after Stop (tvOS)** — Returning from playback no longer leaves TMDB/`CachedAsyncImage` in a permanent loading state.
- **OpenSubtitles chips on Apple TV used a huge white focus rectangle** — Chips and colour swatches draw their own focus chrome.

### Improvements

- **Hidden channels and categories sync over iCloud** — Hide or un-hide in Content Management on one device and the same profile on your other devices picks it up after iCloud flushes (leave the app so the background sync can run). Player settings, EPG layout, and the parental PIN stay on each device.

### Verification

- Playlist add persistence, exclusive playback session, portrait Guide layout, CloudKit hide merge, and channel-surf list covered by unit tests.
- Manual: Apple TV in-player Guide — compact, full-list scroll, tight focus, smooth motion. iPhone portrait Guide — video on top. Hide a category on one device, background the app, confirm on another.

### Release

- Build number **55** (1.2.0).
- Deploy CloudKit **Development → Production** before upload so `CD_UserContentState.isHidden` (and kind `category`) is in Production. Schema from Build 53 (`SyncedPlaylist.deletedAt`, catalog-sync lease) must already be in Production.

---

## Build 54 (1.2.0) — September 3, 2026

### Bug Fixes

- **New episodes stayed frozen after Sync Now** — Catalog sync only upserted the series row. Episode lists were lazy and only fetched when empty, so a cached show never picked up a new airing (e.g. The Ark S3E5). Opening a series now always refreshes from the provider. Sync Now also refreshes Xtream shows whose `last_modified` changed, plus the last 20 watched (capped).
- **Recently Watched showed titles you never played** — A leftover `lastWatchedDate`, iCloud rematch, or tap-and-back was enough to land in the row. Recently Watched now requires several seconds of real progress (or marked watched).
- **Fast-forward / rewind did nothing on many IPTV files** — Skip clamped to a reported duration of 0. Skip now keeps going when length is unknown. On Apple TV, Siri Remote left/right skip 10 seconds on movies and episodes while controls are hidden.

### Improvements

- **Recently Added is the active playlist** — Movies and Series collection rows query this playlist’s id prefix, so another playlist’s newest titles cannot crowd out this one.
- **Default auto-sync is daily** — New installs (and unset Settings) refresh catalogs every day instead of every 3 days. A stored 3-day or weekly choice is unchanged.
- **Subtitles on by default** — External subtitle fetch (Wyzie) is on unless you turn it off. A missing toggle used to count as off. KSPlayer still auto-selects embedded tracks (Apple TV HD still skips auto-select on heavy MKV remux).
- **Catalog existence vs artwork** — TMDB art/ratings, EPG now/next, and the playback engine do not decide whether a title exists. Missing poster ≠ missing item. After the provider adds something: Sync Now, then Recently Added or Show All / search — not only the 20-poster category row.

### Verification

- Episode refresh planner, daily auto-sync default, subtitle enabled-by-default, skip math, and Recently Watched evidence covered by unit tests.
- Manual: Sync Now → new episode without opening the show; Recently Added is this playlist; Recently Watched is only what you played; skip/rewind on VOD.

### Release

- Build number **54** (1.2.0).
- CloudKit schema from Build 53 (`SyncedPlaylist.deletedAt`, catalog-sync lease fields) must already be in Production before this upload.

---

## Build 53 (1.2.0) — September 1, 2026

### Bug Fixes

- **tvOS Home reloads on every tab switch** — Leaving Home (Movies, Series, Live TV, …) unmounted the whole screen, so hero artwork, trending rails, and `@State` were thrown away and rebuilt from TMDB on return. Home now stays mounted on Apple TV the same way it already did on iOS and Mac. Other browse tabs still unmount so Apple TV HD does not hold Home + Media + EPG at once.
- **tvOS Home and trending stall on first launch** — 4K Apple TV waited for the whole playlist catalog sync before fetching TMDB trending (HD already skipped that wait). Trending now starts immediately, paints from TMDB page 1, then widens the match pool. Finishing a catalog sync no longer wipes rails that are already on screen.
- **tvOS trending showed fewer titles than iOS/Mac** — Constrained Apple TV (including Apple TV HD) capped Trending Movies/Series at 6. Those rails now show the same 20 titles as iOS and Mac. Recently Watched / Favorites / Trakt still cap at 6 on HD.
- **tvOS Movies and Series tabs did not open or play titles** — `NavigationStack(path:)` was bound to `DeepLinkRouter`, which does not participate in the tvOS focus engine. Movies and Series keep a local path on Apple TV and consume deep links on appear.
- **tvOS Settings → Media Servers jumped focus and painted blank** — A `List` nested in Settings’ outer `ScrollView` broke the focus engine. Media Servers now uses a tvOS in-pane layout and drills into a server from Settings instead of pushing a nested list.
- **IPTV Play disabled / “No episodes available”** — Xtream/M3U catalog ids (`{playlistUUID}-movie-…`) were treated as Plex/Jellyfin/Emby items. Media-server detection now requires `{serverUUID}-library-…` (or a `mediaserver://` URL), so IPTV movies and series play again.
- **Deleted playlists came back via iCloud** — Local `PlaylistDeletion` never wrote a CloudKit tombstone. A missing mirror was treated as a slow import and re-published. `SyncedPlaylist.deletedAt` now marks an explicit delete; siblings remove the playlist and its catalog. Deletes made on Build 52 or earlier need to be deleted once more on this build.
- **Sync Now on iPhone popped the blocking sync cover on Apple TV** — iCloud created the playlist on tvOS with `lastSyncDate == nil`, so first-time auto-sync presented the full-screen cover. A per-install `CatalogSyncLease` (30-minute quiet period on `SyncedPlaylist`) lets the device that started Sync Now keep the cover; siblings skip it. Fresh Apple TV first launch still auto-syncs.
- **Manual Sync Now left a stale catalog** — Per-category fetches that looked incomplete still pruned against a partial id set. Full sync now falls back to an unfiltered provider list, and prune only runs when the fetch looks complete.

### Improvements

- **Media-server iCloud deletions** — Connect sheet and media sync completion kick reconcile so a tombstoned Plex/Jellyfin/Emby connection does not briefly reappear.

### Verification

- tvOS Home stays populated after Movies → Home (confirmed on device).
- Playlist iCloud tombstone, catalog-sync lease, and media-server identity covered by unit tests (`CloudSyncTests`, `SyncFrequencyTests`, `MediaServerIdentityTests`).

### Release

- Build number **53** (1.2.0).
- Deploy CloudKit **Development → Production** before upload (`SyncedPlaylist.deletedAt`, `catalogSyncDeviceID`, `catalogSyncHeartbeatAt`).

---

## Build 52 (1.2.0) — August 31, 2026

### Features

- **Media tab for Plex, Jellyfin, and Emby** — Dedicated **Media** tab, kept separate from IPTV playlists. Connect via Plex PIN or Jellyfin/Emby credentials, sync movies/series/episodes into the local catalog, and play with AVPlayer-first direct play → remux → HLS transcode. Watch progress reports back to the server. Connections sync through iCloud; each device keeps its own library index.
- **Media libraries survive tab changes and relaunches** — The Media tab mounts its server-backed catalog from launch, restores the selected server, and exposes the server selector, Manage Servers, and Sync controls on iOS.

### Bug Fixes

- **Plex playback on tvOS and iOS** — Plex universal-transcode decision and HLS start requests now use the same client/session contract. Constrained devices such as Apple TV HD force a real 1080p/12 Mbps transcode instead of an uncapped remux, use Plex's supported subtitle-disable parameter, and keep the HLS session alive during playback. Failed Plex transcodes can retry through the safe direct-play fallback when the source permits it.
- **Jellyfin and Emby playback share the hardened resolver** — Media-server playback selects Apple-compatible HLS transcodes ahead of unsafe containers when needed, carries authentication through manifest and segment requests, and reports progress/watched state back to the connected server.
- **Deleted servers stay deleted** — Removing a Plex, Jellyfin, or Emby connection now deletes both its local catalog rows and its iCloud mirror in one coordinated operation. A CloudKit tombstone baseline prevents an exporting deletion from briefly restoring the old connection.
- **Duplicate detail back buttons removed** — Media detail screens no longer sit inside UIKit's automatic More navigation controller and their own nested navigation history at the same time.
- **Live TV no longer opens blank from More** — iPhone now has five direct tabs: Home, Movies, Series, Live TV, and Media. Search moved to the magnifying-glass button on Home, eliminating the automatic More tab and its cached blank placeholder/navigation wrapper.
- **Physical-device builds no longer require Apple's Multicast Networking approval** — The restricted `com.apple.developer.networking.multicast` entitlement was removed from development and release entitlements. Manual/PIN server connection and the non-multicast discovery fallback remain available.

### Verification

- Plex playback verified on tvOS and iOS; Jellyfin playback verified on tvOS, iOS, and macOS.

### Release

- Build number **52** (1.2.0).

---

## Build 51 (1.2.0) — August 8, 2026

### Bug Fixes

- **Home crash while scrolling (`_InvalidFutureBackingData`)** — Resume bars no longer walk `series.episodes` during SwiftUI prefetch. TestFlight 1.2.0 (50) trapped on `Episode.watchProgress` when a pruned/faulted episode was still in the relationship. Progress is fetched from the store by episode id instead.
- **Live TV mini preview VLC abort on HLS refresh** — Preview stays on VLCKit (must not share KSPlayer’s FFmpeg TLS). Xtream preview tries MPEG-TS `.ts` first and falls back to the original `.m3u8` if `.ts` never starts, so HLS-only panels keep working. VLC is fully stopped before KSPlayer fullscreen starts.
- **Crash expanding mini preview to fullscreen (all platforms)** — Teardown cleared `mediaPlayer.media` right after the asynchronous `stop()`, racing VLC’s player thread and tripping the `libvlc_media_retain` assert (SIGABRT). `stop()` alone closes the input; the media clear was removed.
- **Content drawn under the macOS titlebar (search filters, browse grids)** — `themeBackground()` applied `ignoresSafeArea()` to the whole tab view instead of just the background fill, stripping the safe area from every page. The search All / Movies / Series / Live TV filters (and other top-of-page content) now sit below the toolbar in windowed and fullscreen modes, and the Live TV sidebar no longer needs its 52 pt margin workaround. Filter taps also resign the search field so the click lands on the filter.
- **macOS Quit does nothing** — A hidden player `WindowGroup` plus fullscreen / VLC teardown left terminate hanging. Quit and closing the last window now exit the app.

### Improvements

- **App icon** — New Apex “A” artwork across iOS, macOS, and tvOS. tvOS Home Screen / App Store icons are full-bleed 5:3 layered stacks (not a letterboxed square — that caused the black side bars last time). The square 128×128 tvOS fallback was removed so it cannot be selected again.

---

## Build 49 (1.2.0) — July 28, 2026

### Features

- **In-player Live TV Guide** — While watching a live channel, open Guide from the player controls to browse the EPG timeline over the video and switch channels without leaving playback.
  - **tvOS:** Guide tab on the controls pill; **Up** from play focuses Guide (channel surfing only while controls are hidden).
  - **iOS / macOS:** Guide button in the track pill expands a panel over the video. Tap a channel or programme to switch.
- **Live TV mini preview** — On Wi‑Fi, selecting a channel in Live TV browse opens a live preview so you can keep browsing. Tap / Select the preview (or the same channel again on tvOS) for fullscreen; pick another channel to retarget it. Cellular, Stalker/Stremio, and external-player setups still open fullscreen directly.
  - Preview sits in a top row above the guide/list (doesn’t cover programme cells), with channel name, now/next programme, and synopsis beside the video.
  - Works on **tvOS, iOS, and macOS**. Preview is sized for each platform; Mac and iPad get a larger PiP than iPhone.
  - Settings → TV Guide → **Channel Preview** (all platforms). On by default; turn off to open channels fullscreen immediately.

### Bug Fixes

- **Crash expanding Live TV mini preview** — Expanding the preview to fullscreen no longer crashes on IPTV streams.
- **macOS Live TV toolbar vanishes when mini preview plays** — Sync / Settings / List·Guide stay visible while the preview is open.
- **macOS window stuck letterboxed after mini preview** — Leaving fullscreen restores a normal window size again.
- **macOS channel logos look soft / unclear** — Channel icons in Live TV list, preview, and the EPG guide are sharper and larger on Mac.

### Improvements

- **Faster playlist sync sheet** — Removed artificial pauses between movie/series/live sync phases. Inline TV guide during playlist sync loads faster on all platforms; the rest of the guide fills in after the sheet dismisses.

### Release

- Build number **49** (1.2.0).

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

- **Auto-catalog for stream-only addons** — When you add a stream-only addon, the app automatically fetches the Cinemeta catalog so you have movies/series to browse. Just paste your URL → sync → content appears in Movies/Series tabs.
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

- **Sync hang fixed** — Stream-only addons no longer stall the sync. Added pagination guards (20-page cap, duplicate detection) and empty-catalog detection.
- **Multi-addon stream resolution** — When playing content, ALL configured Stremio addons that support streams are queried concurrently. Browse from Cinemeta, stream from any configured stream addon — just like the Stremio desktop app.
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
