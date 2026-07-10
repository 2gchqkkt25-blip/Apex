# Project Reference

> **What is this?** Your cheat sheet for this project. Read this every time you come back so you know exactly where things stand.
>
> **Before changing EPG, Live TV, indexer, or Home:** see § **Do Not Regress — Pre-Change Checklists** and `.cursor/rules/apex-*.mdc`.

---

## At a Glance

| | |
|---|---|
| **App** | **Apex** — IPTV player by StreamInfinity |
| **Forked from** | [Lume](https://github.com/bilipp/Lume) |
| **License** | AGPL-3.0 (source must stay public) |
| **Location** | `/Users/christopherbird/IPTV app/IPTV player/` |
| **Cloned** | June 28, 2026 |

---

## What This App Does

- Browse & stream **Live TV**, **Movies**, and **Series**
- Content from **Xtream Codes**, **M3U/M3U8 playlists**, **Stalker portals**, or **Stremio addons**
- **EPG guide** with full time-grid view
- **TMDB/OMDb metadata** — posters, ratings, cast, descriptions
- **3 playback engines** — KSPlayer (default), VLCKit, AVPlayer (auto-fallback)
- **5 theme system** — System, Frosted Glass, Midnight, Sunset, Ocean
- **User profiles**, **parental controls**, **cloud sync**, **downloads**
- Runs on **iPhone, iPad, Mac, Apple TV, Vision Pro**

---

## How to Build & Run

```bash
open "/Users/christopherbird/IPTV app/IPTV player/Apex.xcodeproj"
```

- Requires Xcode 16+ (Swift 6)
- Select a scheme (iOS, tvOS, macOS) and build
- SPM dependencies resolve automatically

### API Keys (.env file)

Metadata and ratings need free API keys. Copy the template and fill it in:

```bash
cp .env.example .env
```

| Key | Get it here | What it powers |
|-----|-------------|----------------|
| `TMDB_ACCESS_TOKEN` | [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api) | Backdrops, cast, genres, trailers, collections |
| `OMDB_API_KEY` | [omdbapi.com/apikey.aspx](https://www.omdbapi.com/apikey.aspx) | IMDb, Rotten Tomatoes, Metacritic scores |
| `TRAKT_CLIENT_ID` | [trakt.tv/oauth/applications](https://trakt.tv/oauth/applications) | Watch scrobbling (optional) |
| `INTRO_DB_API_KEY` | [introdb.app](https://introdb.app) | Skip intro/recap (optional — reads work unauthenticated; key helps rate limits) |

Without these keys, the app works but metadata is limited to what the IPTV provider supplies. **Rebuild after editing `.env`** — secrets inject at build time, not at runtime.

---

## Customization Progress

| # | Task | Status |
|---|------|--------|
| 1 | App named — **Apex** (by StreamInfinity) | ✅ Done |
| 2 | Rename all files + code from "Lume" to "Apex" | ✅ Done |
| 3 | Replace app icon (iOS, macOS, tvOS) | ✅ Done |
| 4 | Change bundle ID to `com.streaminfinity.apex` | ✅ Done |
| 5 | Change URL scheme to `apex://` | ✅ Done |
| 6 | Feature review — keep/strip/rework | ✅ Done (93 keep, 3 rework) |
| 7 | Theme system — 5 themes + settings UI | ✅ Done |
| 8 | EPG performance fixes | ✅ Done |
| 9 | Series detail → Movie parity | ✅ Done |
| 10 | Movie VOD metadata improvements | ✅ Done |
| 11 | Stremio addon support | ✅ Done |
| 12 | Set up your own GitHub repo | ✅ Done |
| 13 | API keys — TMDB + OMDb (`.env`) | ✅ Done |
| 14 | Icon URL fix — relative → absolute URLs | ✅ Done |
| 15 | Content indexer — TMDB enrichment unblocked | ✅ Done |
| 16 | Live TV channel icons not displaying | ✅ Done |
| 17 | tvOS build — compile errors (scrollContentBackground, serverURLFieldTitle) | ✅ Done |
| 18 | tvOS — Appearance/Theme picker not rendering | ✅ Done |
| 19 | tvOS — Theme accent colours resolving to white | ✅ Done |
| 20 | tvOS — TMDB/IMDb metadata not loading | ✅ Done |
| 21 | tvOS — Sync/refresh option not discoverable | ✅ Done |
| 22 | tvOS — "Show All" links rendering as coloured blocks | ✅ Done |
| 23 | tvOS — App icon missing from asset catalog | ✅ Done |
| 24 | tvOS — TMDB/IMDb metadata reactivity gap | ✅ Done |
| 25 | tvOS — `_UIReplicantView` warnings (Material fallback) | ✅ Done |
| 26 | tvOS — TMDB/IMDb metadata main-context enrichment | ✅ Done |
| 27 | VOD poster rating badges (star + score on covers) | ✅ Done |
| 28 | tvOS — All Categories moved to Search with poster tiles | ✅ Done |
| 29 | iPadOS — System theme contrast fixes (selection text, settings icon, Add Playlist) | ✅ Done |
| 30 | Skip Intro — TMDB IMDb ID resolution on playback (was nil for direct category plays) | ✅ Done |
| 31 | Skip Intro — full playback fix (series link, overlay, IntroDB, settings gate) | ✅ Done |
| 32 | Home hero backdrop — iPad + tvOS horizontal TMDB carousel parity with iPhone | ✅ Done |
| 33 | For You — genre/TMDB fallback ranker when embeddings unavailable (tvOS parity) | ✅ Done |
| 34 | Home hero — title matching + library artwork fallback when trending overlap is thin | ✅ Done |
| 35 | iOS device — large-library crash/freeze fix (~28K Xtream playlist) | ✅ Done |
| 36 | CloudKit re-enabled + Development schema bootstrapped | ✅ Done |
| 37 | CloudKit Production schema deploy + iCloud sync verified | ✅ Done |
| 38 | Discord link — `discord.gg/fKhGp6xpB` (app + README + GitHub) | ✅ Done |
| 39 | Subtitles — KSPlayer overlay + tvOS track menus + macOS AVPlayer legible output | ✅ Done |
| 40 | TestFlight build **17** (1.2.0) — iOS + tvOS upload | 🔄 Superseded — use **18+** |
| 41 | TestFlight — external tester groups (Beta App Review) | 🔄 In progress |
| 42 | tvOS TestFlight + large-library hardening (lazy tabs, deferred indexing) | ✅ Done (build 17) |
| 43 | GitHub README — Apex Stream Player logo (replaced Lume banner) | ✅ Done |
| 44 | App Store metadata drafted (iOS + tvOS descriptions, age rating, privacy) | ✅ Done — paste in Connect |
| 45 | Full App Store release (screenshots, public listing) | ⏳ After TestFlight |
| 46 | TestFlight Pro unlock for beta testers | ✅ Done (`BetaBuildDetection` + `PremiumManager`) |
| 47 | Home screen freeze fix (~28K playlist) | ✅ Mostly done — lazy tabs, deferred indexer/trending |
| 48 | **EPG guide loading** (Xtream ~1.6K live channels) | ✅ **Done** — per-channel API + align, perf, progress %; see `EPG.md` |
| 49 | **EPG bulk sync speed + device freeze** | ✅ **Done** — single-path per-channel sync, single save; see `EPG.md` |
| 50 | **EPG: slow sync + guide/stream mismatch** | ✅ **Done (Jul 4)** for fresh-xmltv providers — bulk `xmltv.php`, offset-honest parse, no shifting. See `EPG.md`. |
| 51 | **EPG: StreamInfinity test panel** | ✅ **Working (Jul 7 late)** — external EPG (epgshare01) primary, unified playlist sync with %, instant channel cards, persists across restarts. Local-affiliate West/Pacific still partial. See `EPG.md`. |
| 52 | **EPG: expanded external sources + West/Pacific +3h insert + normalizer tightening** | ✅ **Done (Jul 7 pm)** — 3 → 14 epgshare01 feeds, structural `epgChannelId` check for West/Pacific pairing, live-API gap-fill cap 12 → 24, empty-TTL 10 → 3 min. See `EPG.md`. |
| 53 | **EPG: cross-device parity** | ✅ **Done (Jul 7 pm, updated late)** — per-device sync triggers (playlist inline guide, Live TV tab `syncIfDue`), tvOS in-player refresh after Sync Now, sync timeout 1 h for 14 feeds. EPG is local-only (not iCloud). See `EPG.md` § Cross-device. |
| 54 | **EPG: external parse speed + incremental UI** | ✅ **Done (Jul 7 late)** — single-pass `importExternalEPG`, US-first feed order, skip `US_LOCALS1` at coverage threshold, mid-sync `refreshGeneration`, `.userInitiated` parse priority. See `EPG.md` § Parse speed. |
| 55 | **Playlist sync: branded UI + unified EPG** | ✅ **Done (Jul 7 late)** — Apex logo-gradient sync screen; content + TV guide in one flow; bundled EPG mode (US feeds, ~88% early stop); **% progress** on TV Guide step. See `EPG.md` § Playlist sync. |
| 56 | **EPG: instant channel cards after sync** | ✅ **Done (Jul 7 late)** — `EPGBrowseLoader` skips live API when store already has rows (was adding 3+ min delay). `forceGuideRefresh()` on guide step complete. |
| 57 | **Home tab first-launch performance** | ✅ **Done (Jul 7 late)** — library-first heroes, playlist-only sync wait, deferred indexer (20s iOS) + EPG (90s iOS). See § Home Launch Performance below. |
| 58 | **Stremio manifest URL parsing** | ✅ **Done (Jul 7 late)** — decode object-style `resources` (Torrentio), optional catalog `name`, URL normalizer, MAC-address validation bug fixed on login form. |
| 59 | **Build 19 — tvOS EPG stability & performance** | ✅ **Done (Jul 8)** — crashes fixed, guide-load speed matched list view, category caching persists, inline quick EPG sync. See § Build 19 below. |
| 60 | **Sync screen — remove playlist/server name** | ✅ **Done (Jul 8)** — `playlist.name` removed from branded sync header on iOS + tvOS. Shows "Apex" + status only. |
| 61 | **Default Live TV view setting** | ✅ **Done (Jul 8)** — Settings → TV Guide → Default View picker (List / Guide). Uses existing `@AppStorage` so it takes effect immediately. |
| 62 | **Theme syncs via iCloud** | ✅ **Done (Jul 8)** — `NSUbiquitousKeyValueStore` in `ThemeManager`; writes on select, reads on launch (prefers cloud), observes remote changes. Added `ubiquity-kvstore-identifier` entitlement. |
| 63 | **Build 20/21 — TestFlight performance regression** | ✅ **Done (Jul 8 pm)** — freeze on launch/foreground/tab-switch fixed. CloudKit reconcile deferred, image cache stabilized, indexer de-aggressified. See § Build 21 below. |
| 64 | **Genre/Category browse → Search tab (all platforms)** | ✅ **Done (Jul 8 pm)** — "Browse by Genre" and "All Categories" moved from Movies/Series to the Search empty state on iOS/iPad/Mac. tvOS poster tiles unchanged. |
| 65 | **NetworkMonitor — WiFi-off crash fix** | ✅ **Done (Jul 8)** — `NetworkMonitor` class (EPG + indexer pause on connectivity loss); missing `import Combine` fixed. |
| 66 | **Build 24 — EPG UI regression restore + performance hardening** | 🔄 **Testing (Jul 9)** — Shared `LiveTVSectionEPGCache`, list+guide `ZStack`, merge-only loads. Regression checklists + `.cursor/rules/apex-*.mdc`. See § Build 24 and § Do Not Regress. |

---

## Build 19 — tvOS EPG Stability & Performance (Jul 8, 2026)

> **Context:** TestFlight build 18 shipped the big EPG overhaul but regressed hard — slow/buggy navigation and crashes on playback and playlist sync, worst on Apple TV. Build 19 is a fix-forward effort: keep every EPG feature, make it stable and fast. **iOS and tvOS are both stable and performant.** Verified on both platforms Jul 8.

### ✅ Fixed — Crashes (carried from earlier in Build 19)

1. **Playlist-sync crash / cancellation storm.**
   - `EPGSyncService.kick()` now **coalesces** triggers (an in-flight sync is never cancel-restarted) and clears its task handle on finish. Removed the redundant `syncIfDue()` trigger on Live TV tab selection. Background parse restored to `.utility` priority.
2. **tvOS out-of-memory (jetsam) on large feeds.**
   - Replaced `XMLParser(contentsOf:)` with an **`InputStream`-backed streaming parser** (5 call sites + disk cache); gzip decompress is file-to-file in 256 KB chunks. Flat memory instead of loading a multi-hundred-MB XML blob.
   - **Decoded-image cache capped at 64 MB on tvOS** (was 256 MB).
   - **Skip the heaviest feeds on tvOS:** `US_LOCALS1` (~500 MB) always, and `US2` (73 MB, national) — both drove memory warnings. Other US feeds + on-demand per-channel API still populate the guide.
3. **Fatal SwiftData crash — `PersistentIdentifier ... remapped ... fatal logic error in DefaultStore`.**
   - Root cause: on-demand guide writes (`EPGAPISync.persist`/`.sync`) inserted `EPGListing` rows with a `@Attribute(.unique) id` **without checking for existing rows**, and browse-triggered persists raced each other on separate contexts → SwiftData's unique-constraint upsert remapped identifiers and crashed.
   - Fix: all on-demand writes now funnel through a single **serial `EPGListingWriter` actor** that reads existing ids first and **inserts only genuinely new rows**. On-demand writes are skipped while the external XMLTV sync owns the store (`EPGSyncGate`) — except on tvOS where persists are always allowed (bundled sync preserves rows).
4. **tvOS content-sync memory peak.**
   - The full guide import no longer runs inside the content-sync sheet on tvOS. A lightweight **inline quick sync** (3 smallest feeds, ~30 MB total) runs during the sheet; remaining feeds run deferred ~10 s after the sheet closes.
5. **Guide going blank during background sync (tvOS).**
   - The external guide sync **no longer clears the whole `EPGListing` store** on tvOS bundled passes — it preserves existing rows and inserts only new ids (deduped against a snapshot taken at sync start).
   - Background/deferred/scheduled syncs **no longer wipe `EPGLiveLoader`'s in-memory browse cache** (`invalidateAll()`); only an explicit **Settings → Sync Now** does.

### ✅ Fixed — tvOS Performance & UX (Jul 8)

6. **EPG data now persists across category switches.**
   - On tvOS, on-demand persist is no longer gated off during the deferred guide sync (`EPGSyncGate` skipped on tvOS). Data browsed is immediately written to the store and survives category switches.
   - Removed eager `programsByChannel = [:]` / `epgByChannel = [:]` clears on `sectionToken` change — views reload from store naturally via `.task(id:)`.
   - Removed `.id()` modifiers from `TVLiveTVScreen` content views — views no longer destroyed/recreated on category switch or list↔guide toggle.

7. **All channels in a category now load (not just first 24).**
   - `synchronousFetchCap` raised to 50 on tvOS (matches page size) — full first page loads in the initial pass.
   - After the initial urgent batch, a **background task** fetches ALL remaining channels and signals `refreshGeneration` when done. Views reload from the now-populated store.

8. **Per-channel live API dramatically faster on tvOS.**
   - Concurrency raised: 2 → **6** on tvOS (the 502 issue was at 6+ during sustained full sync of 1600 channels; short browse bursts of 50 are safe).
   - **Cumulative stagger eliminated** on tvOS (was adding 7+ seconds of pure idle delay for 50 channels). The concurrency limit alone prevents panel overload.
   - **Single API call per channel** on tvOS — skips the expanded second fetch (`limit=8`) when the first call (`limit=4`) returns any data. Halves per-channel time.
   - Net result: 50 channels via API takes ~8–16 s (was ~33 s+).

9. **Guide view matches list view speed.**
   - Guide now uses the same `EPGBrowseLoader.load` path as the list — identical data fetch, identical speed.
   - **Skeleton rows render immediately** (channel names + gap cells) before the first `await` — grid structure appears without waiting for data, same as list view showing channel names instantly.
   - Eliminated double-rendering: no more `.onAppear` empty-row build + redundant row rebuild on pagination.

10. **Focus no longer blocked while data loads.**
    - State updates batched: compute merged dictionaries and new rows first, then assign in rapid sequence (SwiftUI coalesces into one render pass).
    - Logo prefetch moved to detached `Task` (doesn't block grid paint).
    - Category rail already owns its own `.focusSection()` — no changes needed there.

11. **Initial guide shows data within seconds of playlist sync (was ~3 min).**
    - **Inline quick EPG sync** on tvOS during playlist sync: downloads only the 3 lightest/fastest feeds (~30 MB total: US National 1, US Sports, US Movies). Populates the store for 60–80% of channels before the user opens Live TV.
    - Deferred background pass (remaining bundled feeds) starts 10 s after the sync sheet closes, filling gaps without blocking the UI.
    - `EPGSyncMode.tvOSQuick` added: 3-feed fast path with 120 s timeout.

### Files touched in build 19

- `Apex/Services/Sync/EPGSyncService.swift` — coalescing, task cleanup, `bundledSyncTimeout`, exclusive-sync guard, `mode`/`invalidateLiveCache` params, tvOS bundled scheduling, `tvOSQuick` timeout.
- `Apex/Services/Sync/EPGSyncManager.swift` — streaming parse, tvOS skip `US2`/`US_LOCALS1`, tvOS store-preserve + per-feed dedup, `EPGSyncMode.tvOSQuick` case.
- `Apex/Services/Sync/EPGAPISync.swift` — `EPGListingWriter` serial actor; `persist` async; tvOS skips `EPGSyncGate`; `sync` commit routed through writer.
- `Apex/Services/Sync/EPGLiveLoader.swift` — tvOS 6-concurrent / 0-stagger / cap 50; background fetch for remaining channels; skip expanded fetch on tvOS.
- `Apex/Services/Sync/ExternalEPGSources.swift` — `urlsForTVOSQuickSync()` (3 lightest feeds); `urlsForPlaylist` accepts `EPGSyncMode`.
- `Apex/Services/Images/ImageCache.swift` — 64 MB tvOS cost limit.
- `Apex/Services/Network/XtreamClient.swift`, `Apex/Services/Sync/XMLTVChannelDiskCache.swift` — streaming `XMLParser(stream:)`.
- `Apex/Views/Sync/SyncProgressView.swift` — tvOS inline quick EPG sync; deferred background pass 10 s; `runEPGStep(mode:)`.
- `Apex/Views/LiveTV/LiveTVTVComponents.swift` — removed `.id()` from content views; batched state updates; `programsByChannel` gate for pagination.
- `Apex/Views/LiveTV/EPG/EPGGuideView.swift` — skeleton-first rendering; single `EPGBrowseLoader.load` path; eliminated double-rendering.
- `Apex/Views/MainTabView.swift` — removed Live TV tab `syncIfDue` trigger.

### Verified (Jul 8)

- ✅ tvOS: playlist sync completes with inline EPG, guide loads fast, category switching retains data, list and guide views match in speed, focus responsive during loads.
- ✅ iOS: playlist sync + inline EPG unchanged, guide loads and persists, no regressions.
- ✅ All 56 EPG tests pass on both platforms.

---

## Build 21 — TestFlight Performance Fix + Genre/Category UX (Jul 8, 2026 pm)

> **Context:** Build 20 (first TestFlight after the Build 19 EPG fixes) regressed hard on performance — app froze on launch, on foreground return, and showed loading spinners on all poster covers. Worked fine when pushed via Xcode. Root cause: production CloudKit (TestFlight entitlements) delivers push notifications that development (Xcode) suppresses, plus the content indexer was purging the image cache every 2 seconds.

### ✅ Fixed — Performance (TestFlight-specific freezes)

1. **CloudKit reconcile no longer blocks launch.**
   - `await cloudSync.start()` → `Task { await cloudSync.start() }` — launch `.task` proceeds immediately; UI paints from cached local store without waiting for CloudKit account check (up to 10s) + reconcile.
   - Launch reconcile deferred 2s inside `start()` so first frame renders before any `@Query`-disrupting saves.

2. **Foreground return no longer freezes.**
   - `handleScenePhaseChange(.active)` reconcile deferred 1.5s — cached UI renders before CloudKit merge fires.
   - On TestFlight, `cloudImportPending` was always `true` on foreground return (production pushes arrive during background), triggering immediate reconcile that froze all `@Query` views.

3. **Image cache no longer purged every 2 seconds.**
   - **Removed `ImageMemoryCache.shared.purge("index chunk")`** from `ContentIndexer` run loop. This was the #1 cause of spinner flash — every 20-item chunk (every ~2s) wiped ALL decoded poster images, forcing every visible cover to reload from disk.
   - `NSCache` handles memory pressure eviction on its own.

4. **Image cache not purged on brief background.**
   - Replaced immediate purge with `scheduleDeferredPurge()` — 8-second delay, cancelled if user returns sooner. Brief app switches (checking a notification) no longer wipe the cache.

5. **CachedAsyncImage no longer flashes spinners on re-evaluation.**
   - When `.task(id:)` re-fires (e.g. `@Query` re-evaluation), if the view already has a `.success` phase, it keeps showing the image while reloading from cache. Previously set `phase = .empty` → spinner flash.

6. **CloudKit reconcile debounce increased 600ms → 2s.**
   - Production CloudKit sends notifications in bursts; 600ms wasn't collapsing them enough.

7. **Content indexer chunk size 20 → 50, inter-chunk pause 100ms → 500ms.**
   - Fewer saves = fewer main-context merges = fewer `@Query` re-evaluations during browse. Net indexing throughput similar.

8. **TraktService.restore() — 5-second timeout added.**
   - Was unbounded; a slow/dead Trakt server could stall the entire launch pipeline indefinitely.

9. **TMDBLanguageWatcher — background context.**
   - Language-change invalidation (rare) now runs on a background `ModelContext` instead of the main context. Prevents a heavy save (thousands of rows) from freezing launch.

### ✅ Fixed — UX: Genre & Category Browse → Search Tab

- **iOS / iPad / macOS:** "Browse by Genre" (Movie + Series) and "All Categories" (Movie + Series) moved from Movies/Series tabs into the **Search tab's empty state** (when no query is entered).
- **tvOS:** Unchanged — existing `CategoryPosterGridSection` (poster tiles) remains.
- **Movies/Series tabs:** Now show only Recently Watched, Favorites, Recently Added, and the first 4 category preview rows. Cleaner for browsing; discovery lives in Search.
- Navigation destinations for `GenreSelection` added to SearchView (navigates to `MovieGenreView` / `SeriesGenreView`).

### ✅ Fixed — Build Error (terminal crash recovery)

- **`EPGSyncService.swift`** — missing `import Combine` for the `NetworkMonitor` class (added for a tester's WiFi-off crash report). Last line before the previous terminal session crashed.

### Files touched in build 21

- `Apex/ApexApp.swift` — fire-and-forget CloudKit start; deferred image purge
- `Apex/Services/Sync/CloudSync/CloudSyncCoordinator.swift` — 2s launch reconcile delay; 1.5s foreground reconcile delay; debounce 600ms → 2s
- `Apex/Services/Indexing/ContentIndexer.swift` — removed per-chunk image purge; chunk size 20 → 50; inter-chunk pause 500ms
- `Apex/Services/Images/ImageCache.swift` — `scheduleDeferredPurge()` / `cancelDeferredPurge()` API
- `Apex/Views/Components/CachedAsyncImage.swift` — preserve `.success` phase on re-evaluation
- `Apex/Services/Sync/EPGSyncService.swift` — `import Combine` for `NetworkMonitor`
- `Apex/Services/Network/Trakt/TraktService.swift` — 5s timeout on `restore()`
- `Apex/Services/Network/TMDBLanguageWatcher.swift` — background context for invalidation
- `Apex/Views/SearchView.swift` — genre/category browse on all platforms (empty state)
- `Apex/Views/Movies/MoviesView.swift` — removed GenreGridSection + CategoryGridSection
- `Apex/Views/Series/SeriesView.swift` — removed GenreGridSection + CategoryGridSection
- `Apex/Views/LiveTV/LiveTVView.swift` — documented @Query limitation

### Testing (Jul 8–9)

- ❌ **Build 21** — EPG not loading (`playlist(for:)` returning nil); watchdog crash on launch (main-thread SQL)
- ❌ **Build 22** — EPG still not loading; performance improved but EPG regression remained
- ⚠️ **Build 23** — Partial. Playlist passed to `ChannelsList`/`TVChannelsList` (EPG loads again); watchlist off main thread; category-switch wipe removed on tvOS list. User-reported regressions after performance pass: EPG slow / data not persisting on category switch, TMDB details not loading on tap, home freeze on launch/reopen. Cellular stability confirmed (no crash off Wi‑Fi).
- 🔄 **Build 24** — **Testing now (Jul 9).** Restores Build 19 EPG UI guarantees (no destructive `.id()`, no eager cache wipe, `playlist` on guide); TMDB title-search fallback on iOS/macOS detail screens; home paints library heroes before TMDB trending; all Build 21–23 performance fixes retained. EPG sync/parse layer **not modified**. iOS + tvOS compile green; EPG unit tests pass.

---

## Build 24 — EPG UI Restore + Performance Hardening (Jul 9, 2026)

> **Context:** After the Build 21–23 performance work, TestFlight testing reported EPG regressions (slow guide/list load, data not persisting across category switches or app reopen), TMDB metadata not loading immediately on movie/show tap, and a multi-second home-screen freeze on cold launch/reopen. Build 24 is a **fix-forward** pass: restore every Build 19 EPG UI behavior documented above, keep all performance wins, and **do not touch** the EPG sync/parse services layer (`EPGSyncService`, `EPGSyncManager`, `EPGAPISync`, `EPGLiveLoader`, `ExternalEPGSources`).

### ✅ Fixed — EPG UI (Build 19 regression restore + shared cache)

1. **Category / layout switches no longer destroy EPG views.**
   - Removed `.id("\(section)-\(sort)-\(layout)")` from `LiveTVView.detail(for:)` — this was recreating `ChannelsList` / `EPGGuideView` on every category change, wiping in-memory EPG cache (the exact anti-pattern Build 19 item #6 removed).
   - Sort-only `.id(contentSort.rawValue)` retained so `@Query` descriptors refresh when sort changes.
   - **List and guide both stay mounted** in a `ZStack` (opacity + `allowsHitTesting`) — toggling List ↔ Guide no longer destroys either view (Build 19).

2. **Shared `LiveTVSectionEPGCache`** — list and guide read the same programme data keyed by `LiveTVSection.id`. Category switches restore cached data instantly; loads **merge** missing channels only (no `replace: true` wipe).

3. **EPG cache no longer cleared eagerly on category switch.**
   - `onChange(sectionToken)` — only resets `visibleCount`; does **not** clear programme dictionaries.

4. **Playlist passed directly to guide** — `EPGGuideView` accepts `playlist: Playlist?` (same as list). Guide uses the **same** `EPGBrowseLoader.load` call as the list (no custom `windowStart`/`windowEnd`).

5. **Build 19 sync layer verified intact.**
   - `EPGListingWriter`, `EPGSyncGate`, streaming parse, tvOS quick sync, store-preserve, `invalidateAll()` only on Sync Now — all unchanged.
   - EPG unit tests (`EPGSyncTests`, `EPGSourceTests`, `XMLTVDateTests`) pass on iOS Simulator.

### ✅ Fixed — TMDB detail on tap

- Background indexer sets **TMDB id only** (no full detail fetch in background — correct for large libraries).
- **iOS/macOS `MovieDetailView` / `SeriesDetailView`** now mirror tvOS: `resolveTMDBIdIfNeeded()` searches by title when provider omitted id; loading state shown whenever TMDB is configured and enrichment is needed (not only when `tmdbId` already exists).

### ✅ Fixed — Home launch / reopen freeze

- `loadTrending()` paints **library heroes first** and marks Home `.loaded` immediately (phase 1).
- TMDB trending upgrade (phase 2) runs in a **background task** when heroes are already visible — does not block first paint.
- `waitUntilPlaylistSyncIdle()` only blocks when phase 1 produced no heroes.
- Hero logo enrichment gated on `NetworkMonitor.shouldProceedWithHeavyNetworkWork()` (Wi‑Fi only).

### ✅ Retained — Performance stack (Builds 21–23 + Jul 9 session)

| Area | Change |
|------|--------|
| **Indexer** | Chunk 50 + 500 ms pause; no per-chunk image purge; TMDB background = id-only; pauses on EPG sync gate, browse, cloud sync; tvOS skips `TextEmbedder` |
| **Tabs** | Lazy tab mount shows content immediately; `pauseForBrowse()` on tab switch |
| **Cellular** | `NetworkMonitor` defers heavy indexer + background EPG sync; resumes on Wi‑Fi return |
| **Home** | No `ContentIndexingService` observation; trending reload only on playlist sync end |
| **Collections** | Favorites/Recently Watched `@Query` capped; Show All grids paginated (100/page) |
| **Search** | Genre derivation deferred until search field empty |
| **Images** | Build 21 `CachedAsyncImage` + deferred purge retained |
| **CloudKit** | Build 21 deferred reconcile retained |

### Files touched in build 24

**EPG UI only (sync layer not touched):**
- `Apex/Views/LiveTV/LiveTVSectionEPGCache.swift` — shared section-keyed cache for list + guide
- `Apex/Views/LiveTV/LiveTVView.swift` — `ZStack` mounts list + guide; shared cache; sort-only `.id`
- `Apex/Views/LiveTV/EPG/EPGGuideView.swift` — reads shared cache; merge-only loads; same `EPGBrowseLoader` as list
- `Apex/Views/LiveTV/LiveTVTVComponents.swift` — same patterns on tvOS (`TVLiveTVScreen` `ZStack`)

**TMDB detail:**
- `Apex/Views/Movies/MovieDetailView.swift` — `resolveTMDBIdIfNeeded()`; loading state when id missing
- `Apex/Views/Series/SeriesDetailView.swift` — same

**Home:**
- `Apex/Views/Home/HomeView+Trending.swift` — phase-1 unblock; background phase 2; Wi‑Fi gate on logo enrichment

**Performance (earlier Jul 9 session, retained in this build):**
- `Apex/Services/Indexing/ContentIndexer.swift`, `ContentIndexingService.swift`
- `Apex/Views/MainTabView.swift`, `HomeView.swift`, `LiveTVView.swift` (query caps)
- `Apex/Views/Library/LibraryCollectionRows.swift`, `SearchView.swift`
- `Apex/Services/Sync/EPGSyncService.swift` (`NetworkMonitor` only — no sync logic changes)

### TestFlight checklist (Build 24)

**EPG (priority — validates Build 19 investment):**
- [ ] Sync playlist → open Live TV within 10 s → guide and list show data quickly
- [ ] Switch categories rapidly → no empty flash; returning to a category is fast
- [ ] Toggle List ↔ Guide → matching EPG on both
- [ ] Force-quit and reopen → Live TV loads from store (not blank)
- [ ] tvOS: focus stays responsive while guide loads

**Performance:**
- [ ] Cold launch Home — paints within 1–2 s (library hero; TMDB may upgrade shortly after)
- [ ] Tab switch Movies → Series → Live TV — responsive
- [ ] Tap movie/show without TMDB id — loading state then full details
- [ ] Wi‑Fi off — no crash (cellular deferral working)

### Verified before archive (Jul 9)

- ✅ iOS + tvOS `xcodebuild` compile green
- ✅ EPG unit tests pass (`EPGSyncTests`, `EPGSourceTests`, `XMLTVDateTests`)
- 🔄 TestFlight device testing in progress (Christopher)

---

## Do Not Regress — Pre-Change Checklists

> **Why this section exists:** Build 19 fixed EPG stability and speed. Builds 21–23 performance work re-broke Live TV UI by reintroducing patterns Build 19 explicitly removed (destructive `.id()`, list/guide `if/else`, guide-only store window, cache wipe on category switch). **Run the relevant checklist before merging any change that touches the listed files.** Cursor rules in `.cursor/rules/apex-*.mdc` mirror this section.

### When to run

| You are changing… | Run checklist |
|-------------------|---------------|
| `LiveTVView`, `EPGGuideView`, `ChannelsList`, `LiveTVTVComponents`, `LiveTVSectionEPGCache` | **EPG UI** (below) |
| `EPGSyncService`, `EPGSyncManager`, `EPGAPISync`, `EPGLiveLoader`, `ExternalEPGSources` | **EPG sync** + `EPG.md` stability rules |
| `ContentIndexer`, `HomeView`, `MainTabView`, `ApexApp`, `CloudSyncCoordinator`, `CachedAsyncImage` | **Performance** (below) |
| `MovieDetailView`, `SeriesDetailView` | **TMDB detail** (below) |
| Anything above + preparing TestFlight | **All** + manual TestFlight checklist (§ Build 24) |

### EPG UI checklist (Build 19 + 24 — mandatory for Live TV view edits)

- [ ] List and guide both mounted (`ZStack` + opacity) — **not** `if layoutMode == .guide { … } else { … }`
- [ ] No `.id()` keyed on section, category, or layout — **sort-only** `.id(contentSort.rawValue)` is allowed
- [ ] No eager `programsByChannel = [:]` / `epgByChannel = [:]` on `sectionToken` change — only reset `visibleCount`
- [ ] List and guide share `LiveTVSectionEPGCache` keyed by `LiveTVSection.id`
- [ ] Loads **merge** via `epgCache.merge` / `channelsNeedingLoad` — no full-dict `replace: true` wipe
- [ ] `playlist: Playlist?` passed into list **and** guide — not `playlist(for:)` fetch
- [ ] Guide calls `EPGBrowseLoader.load` with **same parameters as list** (no custom `windowStart`/`windowEnd`)
- [ ] `.task(id: sectionToken)` for first page; pagination via unstructured `Task` + merge
- [ ] EPG sync files **not** modified unless fixing a logged sync bug

**Automated (run before archive):**
```bash
cd "IPTV player"
xcodebuild test -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ApexTests/EPGSyncTests \
  -only-testing:ApexTests/EPGSourceTests \
  -only-testing:ApexTests/XMLTVDateTests
```

**Manual (2 min):** List shows EPG → Guide instant → category switch → back → List ↔ Guide toggle — data never blank.

### EPG sync checklist (mandatory for `Apex/Services/Sync/EPG*` edits)

Full rules: `EPG.md` § **Stability rules (do not regress)**. Highlights:

- [ ] Never clear entire `EPGListing` store at sync start (except documented external full-replace path)
- [ ] All on-demand writes through `EPGListingWriter` actor
- [ ] `programsFromStore` scoped by channel id predicate, off main thread
- [ ] `EPGBrowseLoader`: store first; live API only when store empty for channel
- [ ] No timestamp shifting / realign on read or write
- [ ] Bulk sync = `xmltv.php`; per-channel API for visible channels only
- [ ] Run EPG unit tests (command above)

### Performance checklist (mandatory for indexer / launch / tab edits)

- [ ] `ContentIndexer`: chunk 50, 500 ms pause; **no** per-chunk image purge
- [ ] Background indexer: TMDB **id-only** (`details: nil`); full detail on detail-screen open
- [ ] tvOS: `TextEmbedder` skipped in indexer
- [ ] `ContentIndexingService.pauseForBrowse()` still called on tab switch
- [ ] `NetworkMonitor` still gates background indexer + EPG `syncIfDue` on cellular
- [ ] `HomeView` does **not** observe `ContentIndexingService`
- [ ] `loadTrending()`: library heroes first; TMDB phase 2 non-blocking when heroes exist
- [ ] `ApexApp`: CloudKit `Task { await cloudSync.start() }` — not blocking launch
- [ ] `CachedAsyncImage`: preserve `.success` phase on re-evaluation
- [ ] Lazy tab mount: content shows when `selection == tab`
- [ ] Live TV performance edits did **not** violate EPG UI checklist above

### TMDB detail checklist

- [ ] Background indexer does not fetch full `movieDetails` / `tvDetails`
- [ ] `MovieDetailView` / `SeriesDetailView` (iOS/macOS): `resolveTMDBIdIfNeeded()` + loading state when TMDB configured
- [ ] tvOS detail views unchanged unless intentionally aligned

### Regression history (learn from)

| Build | What broke | Cause |
|-------|------------|-------|
| 20–21 | Launch freeze, image spinners | CloudKit blocked launch; per-chunk image purge |
| 21–23 | EPG not loading | `playlist(for:)` nil; guide/list diverged |
| 23–24 | EPG slow / data vanishes | Destructive `.id()`, list/guide `if/else`, guide-only store window, cache wipe |

**Rule:** Performance passes must not edit Live TV EPG UI without running the EPG UI checklist. EPG fixes must not edit sync layer without running EPG sync checklist.

---

## Key Decisions Made

| Decision | Value |
|----------|-------|
| App name | **Apex** by StreamInfinity |
| Bundle ID | `com.streaminfinity.apex` |
| URL scheme | `apex://` |
| CloudKit container | `iCloud.com.streaminfinity.apex` |
| StoreKit IAP prefix | `com.streaminfinity.apex.premium.*` |
| Monetization | StoreKit 2 — **Apex Pro** monthly + lifetime; free tier = 1 playlist + core playback; sideload builds fully unlocked (AGPL) |
| App Store age rating | **17+** (user-supplied streams may include unfiltered third-party media) |
| Theme system | 5 themes: System, Frosted Glass, Midnight, Sunset, Ocean |
| Features | 93 kept, 3 reworked, 0 stripped |

## Key Decisions Pending

1. ~~**GitHub repo**~~ — ✅ Live at [github.com/2gchqkkt25-blip/Apex](https://github.com/2gchqkkt25-blip/Apex)
2. ~~**Website / support email**~~ — ✅ support@streaminfinitytv.com, GitHub as homepage
3. ~~**Apple Developer setup**~~ — ✅ Team `VS7D6GB238`, bundle ID registered, IAP products created, iOS TestFlight builds uploaded (July 2, 2026)
4. ~~**CloudKit Development schema**~~ — ✅ Bootstrapped; **Production deployed** — playlist + user data sync verified on TestFlight (July 2, 2026)
5. **TestFlight build 24** — 🔄 Testing now (Jul 9). Bump build number, archive, run EPG + performance checklist in § Build 24. Build 19 EPG sync layer intact; UI regressions restored.
6. **External TestFlight** — Age rating + privacy URL + App Privacy + What to Test → Beta App Review (~1–2 days)
7. ~~**tvOS large-library hardening**~~ — ✅ Lazy tab mount, deferred indexing/EPG (tvOS-only); in build 17
8. ~~**EPG guide**~~ — ✅ Working (`xmltv.php` bulk download, offset-honest parse; slow-sync + mismatch fixed); notes in `EPG.md`
9. **App Store listing** — Screenshots + description/subtitle (not required for external TestFlight)
10. **macOS signing** — Requires Apple Developer certificates on this machine
11. **App Store public release** — After TestFlight validation

---

## Placeholder Values

| What | Current | Needs |
|------|---------|-------|
| Website | `github.com/2gchqkkt25-blip/Apex` | Done (GitHub as homepage) |
| Support email | `support@streaminfinitytv.com` | ✅ Done |
| GitHub repo | `github.com/2gchqkkt25-blip/Apex` | ✅ Done |
| Privacy policy | `github.com/2gchqkkt25-blip/Apex/blob/main/PRIVACY.md` | ✅ Done (iOS + tvOS same URL) |
| Discord | `discord.gg/fKhGp6xpB` | ✅ Done |
| App Store Connect | [Apex Stream Player](https://apps.apple.com/app/id6779551584) — ID `6779551584` | ✅ Done |

---

## Themes

| Theme | Accent | Background | Style |
|-------|--------|------------|-------|
| System | System blue | Platform default | Light/Dark adaptive |
| Frosted Glass | `#6B7AFF` | Glass/transparent | Translucent |
| Midnight | `#5B5EA6` | `#0D0D1A` | Dark indigo |
| Sunset | `#FF8C42` | `#1A1410` | Warm amber |
| Ocean | `#00B4D8` | `#0A1628` | Deep teal |

Settings → Appearance (between Premium and Profiles)

---

## What's Been Built

### Live TV Channel Icons (June 29, 2026)
- **Symptom:** Icons showed in List view and Recently Watched, but not in EPG Guide (grid) — left channel column was blank.
- **Root cause:** Provider logos are small grayscale PNGs. The poster pipeline (`CachedAsyncImage` → ImageIO downsampling) broke many of them. In Guide mode, the frozen channel column used `LazyVStack` + `.offset` scroll sync, so off-screen cells were never realized and SwiftUI `Image(uiImage:)` drew blank in that layout on iOS.
- **Fix:**
  - `ChannelLogoLoader` + `ChannelLogoView` — plain `UIImage(data:)` decode, disk/memory cache, batch prefetch
  - `PlatformImageView` (`UIImageView`) instead of SwiftUI `Image` for reliable rendering in scroll layouts
  - iOS List mode for channel lists (instead of `LazyVStack` in `ScrollView`)
  - EPG frozen column → windowed row renderer + logo prefetch refresh (tvOS keeps scroll-synced `LazyVStack`)
  - `LiveStream.iconURL` handles protocol-relative URLs (`//host/...`)
- **Verified:** Guide view channel logos display correctly on iOS Simulator.

### API Keys & Secrets (June 29, 2026)
- `.env` file created with TMDB v4 access token + OMDb API key
- `Scripts/inject-env.sh` injects secrets into `Info.plist` at build time
- TMDB/OMDb clients confirmed configured and working (`[TMDBDebug] Configured`)

### Icon URL Fix (June 29, 2026)
- Added `absoluteIconURL(from:serverURL:)` in `ContentSyncManager+Helpers.swift`
- Applied to Xtream, M3U, and Stalker sync pipelines for Live TV, Movies, and Series
- Icon URLs are now resolved to absolute URLs when providers return relative paths

### Content Indexer Fix (June 29, 2026)
- `prepareEmbedder` in `ContentIndexer.swift` now limits retries to 4 attempts
- `indexNextChunk` and `write` accept optional `TextEmbedder` — nil when model unavailable
- TMDB enrichment proceeds without semantic-search embeddings on affected devices (e.g. iOS Simulator)

### Rename (19 filesystem items, 160+ Swift files)
- All source files, tests, project config, localization, docs
- Bundle ID, URL scheme, CloudKit container, Keychain services, IAP IDs

### App Icon
- iOS/macOS: 1024x1024 + macOS sizes
- tvOS: Layered home screen + App Store icons + top shelf

### EPG Performance (6 fixes)
- Window reduced 25h → 6h (~75% fewer listings in memory)
- `buildRows()` deferred to `.task` (first frame instant)
- Frozen column → windowed cells on iOS/macOS; scroll-synced `LazyVStack` on tvOS
- `CachedAsyncImage` skips nil URL tasks
- `GeometryReader` replaced with explicit width

### Series → Movie Parity
- Watch Trailer button + `youtubeTrailer` field on Series model
- Mark Season Watched/Unwatched bulk toggle
- TMDB YouTube trailer extraction during enrichment

### Movie VOD Metadata
- Enhanced title cleaning for TMDB matching (WEB-DL, BluRay, BRRip, AMZN, NF, DSNP, ATVP, etc.)
- Provider badge in Information section

### Stremio Addon Support
- Full source type: client, DTOs, sync pipeline, stream resolver
- Login UI (iOS + tvOS), PlaylistDetail fields
- Playback integration via `stremio://` placeholder resolution
- **Manifest parsing (Jul 7 late):** `StremioResource` enum accepts string **or** object `resources` entries (Torrentio-style). Catalog `name` defaults to `id` when omitted. `StremioURL.normalize()` handles `…/manifest.json`, configured paths (`qualityfilter=…`), and `stremio+https://` install links. Stored playlist base URL is normalized so sync doesn't double-append `manifest.json`. Login form no longer required a Stalker MAC address when Stremio was selected. Tests: `ApexTests/Services/StremioTests.swift`.

### Theme System
- 5 themes with semantic color tokens (accent, background, surface, text)
- `ThemeManager` singleton with `@Observable` + `UserDefaults` persistence
- Global `.tint()` + `.preferredColorScheme(.dark)` for dark themes
- `.themeBackground()` and `.scrollContentBackground(.hidden)` on all surfaces
- Adaptive placeholders via `.fill.quaternary` (visible on all themes)
- Appearance picker in Settings on iOS, macOS, and tvOS

### tvOS Platform Fixes (June 29, 2026)

**Build fixes — 5 compile errors resolved:**
- `.scrollContentBackground(.hidden)` — explicitly marked unavailable on tvOS. Wrapped in `#if !os(tvOS)` in 4 files (LiveTVView, MoviesView, SeriesView, SearchView).
- `serverURLFieldTitle` — defined inside `#if !os(tvOS)` block but referenced from tvOS code. Moved to shared scope in PlaylistDetailView.

**Appearance/Theme picker not rendering:**
- `AppearanceSettingsView` used `Form` which collapses inside tvOS's `ScrollView` detail pane. Split into a tvOS path using `VStack` + `TVSettingsSectionLabel` and `TVSettingsRowButtonStyle` for focusable rows.

**Theme accent colours resolving to white:**
- `Color.accentColor` → always white on tvOS (Apple hardcodes it). Created `Color.platformAccent` — returns `Color.blue` on tvOS, `.accentColor` elsewhere.
- ~15 views used `Color.accentColor` directly instead of theme colors. Replaced with `themeManager.colors.accent` in: EPGGuideView (`Now` button), LiveTVView (`CategorySidebar` selection), ContentManagementView, ChannelManagementView, EpisodeCard, EPGProgramDetailView, SyncProgressView.
- Nested iOS-only views (`ChannelManageRow`, `CategoryManageRow`, `StepRowView`) kept `Color.accentColor` (works fine on iOS).

**TMDB/IMDb metadata not loading:**
- `TextEmbedder()` init threw uncaught `EmbedderError.modelUnavailable` — `NLContextualEmbedding(script: .latin)` unavailable on tvOS. Error propagated to `ContentIndexingService.kick()` which permanently set `state = .unavailable`, blocking ALL future indexing (TMDB enrichment, OMDb ratings, posters, cast, descriptions).
- Fix: wrapped `TextEmbedder()` creation inside do/catch so TMDB enrichment proceeds without semantic-search embeddings. Indexer no longer permanently disabled when model missing.

**Sync/refresh option:**
- iOS has toolbar sync button on every content view. tvOS `libraryToolbar` was a no-op. Added prominent "Sync Now" button at top of tvOS PlaylistDetailView (below playlist name) with last-sync timestamp. Sync still accessible from Settings → Playlists → [playlist] → Sync Now.

**EPG guide theme support:**
- `EPGColors.live` changed from hardcoded `Color.blue` to `ThemeManager.shared.colors.accent` — live programme border and fill now follow the active theme (indigo for Midnight, amber for Sunset, teal for Ocean).
- Live program cell fill changed from white to theme-accent tint at 12% opacity.

**"Show All" links:**
- Global `.tint()` caused tvOS NavigationLinks to render as solid coloured blocks (orange for Sunset, indigo for Midnight, etc.). Overridden with `.tint(.primary)` (white) on tvOS for "Show All" links in `CategoryPreviewRow` and `LibraryCollectionRow`.

**tvOS App Icon (June 29, 2026):**
- **Symptom:** tvOS Home Screen showed no app icon (blank/placeholder).
- **Root cause 1:** `AppIcon.appiconset/Contents.json` had entries for iOS and macOS but zero tvOS slots. Added 128x128 @1x and @2x tvOS entries using the existing ApexIcon-1024.png.
- **Root cause 2:** The brand assets folder was named `Apex.brandassets` but tvOS expects `<APPICON_NAME>.brandassets` — the build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` means it looks for `AppIcon.brandassets`. Renamed folder to match.
- **Root cause 3:** The brand asset images still contained the original Lume artwork (400x240 landscape ratio). Regenerated all 6 tvOS icon images (`front_400.png`, `front_800.png`, `back_400.png`, `back_800.png`, and App Store 1280x768 versions) from the Apex 1024x1024 logo.

**macOS build:** Fails due to missing code-signing identity. Requires Apple Developer account sign-in in Xcode (no certificates on this machine: `0 valid identities found`).

### tvOS TMDB/IMDb Reactivity Fix (June 29, 2026)
- **Symptom:** Movie/Series detail screens on tvOS showed no TMDB backdrops, cast, ratings, or OMDb scores — even after the ContentIndexer had finished background indexing.
- **Root cause:** The tvOS detail views (`TVMovieDetailView`, `TVSeriesDetailView`) checked `tmdbId` in their `.task` handler, but the ContentIndexer runs on a 3-second delay after sync — creating a window where the view appears before `tmdbId` is assigned. Once the view was displayed, there was no mechanism to react when `tmdbId` became available later (no `.onChange(of: tmdbId)` handler).
- **Fix:**
  - Added `.onChange(of: movie.tmdbId)` to `TVMovieDetailView` — silently triggers TMDB enrichment + OMDb ratings when the background indexer assigns a TMDB ID after the view is already visible
  - Added `.onChange(of: series.tmdbId)` to `TVSeriesDetailView` — same reactive enrichment
  - Reduced `SyncProgressView` indexer kick delay from 3 s → 0 s on tvOS (the delay exists to let the embedding model download, but `NLContextualEmbedding` is unavailable on tvOS so the delay was pure waste)
- **Note:** This addressed the timing gap but metadata still did not appear on screen — see the main-context enrichment fix below.

### tvOS TMDB/IMDb Main-Context Enrichment Fix (June 29, 2026)
- **Symptom:** TMDB backdrops, cast, plot, and OMDb ratings (IMDb / Rotten Tomatoes / Metacritic) still missing on tvOS detail screens even after the indexer and reactivity fixes above. iOS showed metadata correctly for the same playlist.
- **Root cause:** `TVMovieDetailView` and `TVSeriesDetailView` called `ContentSyncManager.enrichMovie()` / `enrichSeries()` and `enrichMovieRatings()` / `enrichSeriesRatings()`, which fetch and persist on a **background `ModelContext`** and rely on SwiftData auto-merge into the view. On tvOS the detail screen often never re-rendered with the merged data — the same class of bug already documented for episode loading (`insertEpisodes` on the view context vs background writes). iOS detail views (`MovieDetailView`, `SeriesDetailView`) already used the correct pattern: fetch off-thread, `applyMovieDetails` / `applySeriesDetails` on the **view's main context**, then `modelContext.save()`.
- **Fix:**
  - `TVMovieDetailView` / `TVSeriesDetailView` — `enrichIfNeeded()` now matches iOS: `fetchTMDBMovieDetails` / `fetchTMDBTVDetails` off-thread → `applyMovieDetails` / `applySeriesDetails` on the view's `modelContext` → save
  - Added `resolveTMDBIdIfNeeded()` — searches TMDB by cleaned title when the provider supplies no `tmdbId` (same `ContentIndexText.searchQuery` logic as the content indexer)
  - `@Bindable` on `movie` / `series` in tvOS detail views for reliable SwiftUI observation
  - Loading spinner now shows whenever TMDB is configured and enrichment is stale, even when `tmdbId` is initially nil (search-by-title path)
  - `enrichMovieRatingsIfNeeded` / `enrichSeriesRatingsIfNeeded` — fetch OMDb off-thread, apply `externalRatings` on the view's main context (was background persist everywhere; tvOS missed the merge)
  - `ContentIndexingService.kick()` — no longer permanently blocked by stale `.unavailable` state from older embedding-model errors; `TextEmbedder.EmbedderError` now sets `.interrupted` (retry) instead of `.unavailable` (dead)
- **Verified:** TMDB backdrops, cast, plot, and OMDb rating chips display correctly on tvOS Simulator.

### tvOS `_UIReplicantView` Warnings (June 29, 2026)
- **Symptom:** Console flooded with `Adding '_UIReplicantView' as a subview of UIHostingController.view is not supported` on tvOS < 26. Could cause broken view hierarchies with Material/blur backgrounds.
- **Root cause:** SwiftUI's `.regularMaterial` / `.ultraThinMaterial` / `.thinMaterial` create a private `_UIReplicantView` (Apple's blur renderer) inside the UIKit host view. On tvOS < 26, where `glassEffect()` isn't available, these Material fallbacks were used throughout player controls, home screen, detail views, and settings — all hitting the warning.
- **Fix:**
  - Created `GlassFallback` enum in `GlassEffectCompat.swift` — `GlassFallback.thin` (`white.opacity(0.06)`) and `GlassFallback.regular` (`white.opacity(0.08)`) on tvOS, the real `Material` styles elsewhere. On tvOS's always-dark canvas these solid fills read identically to the materials they replace.
  - Updated `glassEffectCompat()` to use `GlassFallback.regular` for its `< tvOS 26` path (the `tvOS 26+` `glassEffect()` path is untouched).
  - Replaced direct `Material` usages in 11 files: `TVHomeScreen`, `TVDetailButtons`, `TVSeriesDetailView`, `TVPlayerPanels`, `AppearanceSettingsView`, `HeroPageIndicator`, `ExternalRatingsView`, `PlaylistSwitchProgress`, `FullScreenPlayerView`, `MediaDetailComponents`, `CategoryContentGrid`.

### VOD Poster Rating Badges (June 29, 2026)
- **What:** A compact star + score pill (e.g. `★ 8.4`) overlaid on the top-right corner of movie/series poster cards across browse surfaces.
- **Score priority:** IMDb (when OMDb enrichment has run) → provider/TMDB `rating` or `rating_5based` (normalised to /10 display). No badge when no score is available.
- **Where:** `MovieCardView`, `SeriesCardView`, Home rows (`HomePosterCard`), detail "You May Also Like" rails (`DetailPosterCard`, `TVPosterCard`).
- **Files:** `PosterRatingBadge.swift` (`PosterRatingDisplay`, `PosterRatingBadge`, `.posterRatingOverlay()`), `HomeMediaItem.posterRating`, OMDb ratings now applied on the view's main context in `enrichMovieRatingsIfNeeded` / `enrichSeriesRatingsIfNeeded` (helps badges update after detail enrichment).

### tvOS Search — Category Browse with Poster Tiles (June 29, 2026)
- **What changed:** On tvOS, the text-based **"All Categories"** grid at the bottom of Movies and Series was removed. Category browsing now lives in the **Search** tab (magnifying-glass icon, first tab).
- **Empty search state:** When the search field is empty, Search shows two poster grids — **Movie Categories** and **Series Categories** — listing every category for the active playlist (respects category sort order and parental restrictions).
- **Poster tiles:** Each category tile shows artwork from a title in that category (first available movie poster or series cover), with the category name over a bottom gradient. Focus ring + lift matches other browse cards. Tapping navigates to the full category grid (`MovieCategoryView` / `SeriesCategoryView`).
- **Search unchanged:** Typing in the search field switches to normal text search results (movies, series, live TV).
- **iOS / macOS unchanged:** "All Categories" text tiles remain on Movies and Series tabs.
- **Files:** `CategoryPosterTile`, `CategoryPosterGridSection`, `CategoryArtwork` in `CategoryContentGrid.swift`; `SearchView.swift` (tvOS category browse + `navigationDestination(for: Category.self)`); `#if !os(tvOS)` guard on `CategoryGridSection` in `MoviesView.swift` / `SeriesView.swift`.

### iPadOS System Theme Contrast Fixes (June 30, 2026)
- **Symptom:** On iPadOS with the System theme, three contrast failures: (1) tab bar selection capsule showed invisible white text, (2) the settings gear icon in the toolbar was obscured, (3) the "Add Playlist" button at first launch was nearly invisible.
- **Root cause:** A custom `AccentColor` asset catalog entry set to `#4248FF` — a very dark blue-purple (perceived luminance ~0.09). iPadOS system controls (tab bar capsules, segmented controls, list row highlights) read the asset catalog accent **directly**, bypassing the view hierarchy's `.tint()` override. When the dark accent was used as a fill behind primary/dark text in light mode, contrast collapsed. The branded themes (Midnight, Sunset, Ocean, Frosted Glass) were never affected — they all force `.dark` color scheme and render white text on their fills.
- **Fix:**
  - **Deleted** `Assets.xcassets/AccentColor.colorset/` — removes the global `#4248FF` override so system controls use the standard iOS blue they're designed for
  - Changed `Color.platformAccent` from `Color.accentColor` → `Color.blue` on all platforms (standard system blue, luminance ~0.22, works correctly in all control states)
  - **LoginView:** "Add Playlist" button → `.borderedProminent` (solid accent fill, always visible); segmented picker gets explicit `.tint()`; validation-on-tap instead of silent disable with low-opacity text
  - **LibraryToolbar:** Split grouped `HStack` into separate `ToolbarItem`s — iPadOS was rendering the HStack as a tint-filled grouped control that obscured the icons
  - **MainTabView:** Added explicit `.tint()` on the `TabView` to guarantee the accent reaches the tab bar capsule
- **Files:** `Theme.swift` (`platformAccent`), `AccentColor.colorset/` (deleted), `LoginView.swift`, `LibraryToolbar.swift`, `MainTabView.swift`, `EPGComponents.swift` (comment update)

### Skip Intro — TMDB IMDb ID Resolution (June 30, 2026)
- **Symptom:** The "Skip Intro" button never appeared during playback on any platform, even when IntroDB had segment data for the episode and the setting was enabled.
- **Root cause:** `Series.imdbId` was only populated during TMDB enrichment — which only runs when the user opens the Series detail screen. When playing an episode directly from a category (the common IPTV flow), the series had a `tmdbId` (set by the content indexer) but `imdbId` was `nil`. `IntroSkipResolver.lookup()` returned `nil` when `imdbId` was missing → segments never fetched → button never shown. The `try?` in the calling code silently swallowed all errors, making the failure invisible.
- **Fix:**
  - Added `TMDBClient.tvExternalIMDbID(_:)` — a lightweight call to `/tv/{id}/external_ids` (single field, no heavy `append_to_response`) that returns just the IMDb ID string
  - Rewrote `IntroSkipResolver.lookup(for:in:)` as `async` — when the series has a `tmdbId` but no cached `imdbId`, it fetches the IMDb ID from TMDB on the spot and persists it so subsequent episodes from the same series hit the fast path
  - Updated `FullScreenPlayerView` to `await` the now-async lookup
  - Replaced silent `try?` with `do`/`catch` + `Logger.player` diagnostics at every guard in the skip-intro chain so the exact failure point can be identified in Console.app
  - Added `onAppear` logging to `PlayerSkipIntroOverlay` to confirm when segments are mounted
- **Files:** `IntroSkipResolver.swift` (async rewrite + TMDB fallback), `TMDBClient.swift` (`tvExternalIMDbID`), `FullScreenPlayerView.swift` (`await` lookup + diagnostics), `PlayerSkipIntroOverlay.swift` (mount logging)

### Skip Intro — Full Playback Fix (June 30, 2026)
- **Symptom:** After the IMDb ID fix, Skip Intro still failed on many episodes (including direct category plays on Xtream/Stalker). On iOS the button could appear briefly then vanish; Breaking Bad S1E1 had no skippable intro in IntroDB (outro-only).
- **Root causes (multiple):**
  - Xtream/Stalker episodes inserted without `episode.series` set → series lookup failed
  - Skip overlay lived inside per-engine views and was gated on `controlsVisible` — KSPlayer kept controls visible on iOS, hiding the button
  - TMDB title search / episode-number fallback missing when `tmdbId` absent
  - Premium gate blocked the feature even when the Settings toggle looked on
  - `@Observable` playback clock did not reliably drive overlay updates
  - IntroDB returns outro-only for some episodes; legacy `/intro` endpoint needed as fallback
- **Fix:**
  - **`EpisodeSeriesResolver.swift`** — recover parent series from episode ID when the SwiftData link is missing
  - **`ContentSyncManager`** — set `episode.series = self` on episode insert
  - **`IntroSkipResolver`** — series resolver, TMDB title search, episode-number fallback, IMDb ID normalization
  - **`FullScreenPlayerView`** — host-level skip overlay; **`PlayerSeekBridge`** on **`PlaybackClock`** for seek-after-skip on all engines
  - **`PlayerSkipIntroOverlay`** — `@Bindable` clock, timer poll, no controls gate, ±20s timing slack, `startTime` support
  - **`IntroDBClient`** — `hasSkippableOpener`, legacy `/intro` fallback, `skippableSegments()`
  - **`PlayerSettings`** — `canUseSkipIntro` follows the setting only (no Premium gate); autoplay / next episode remain Premium
  - Engine views (`KSPlayer`, `AVPlayer`, `VLC`) — `seekBridge` wiring; removed per-engine skip overlay
  - Settings UI — skip intro toggle no longer Premium-gated
  - Tests: `EpisodeSeriesResolverTests`, `IntroDBClientTests`
- **Verified:** Skip Intro works on iOS, iPadOS, and tvOS after rebuild (e.g. Breaking Bad S1E2+ has intro ~5:14+; S1E1 has no intro in IntroDB)

### Home Hero Backdrop — iPad + tvOS Parity (June 30, 2026)
- **Symptom:** iPhone Home showed TMDB trending artwork scrolling/auto-advancing in the hero; iPad and tvOS did not match (iPad lacked the immersive full-screen effect; tvOS used crossfade-only backdrop).
- **Fix:**
  - Extracted shared carousel logic into **`HomeHeroController`** + **`HomeHeroArtworkPager`** (horizontal paging, 6s auto-advance, infinite loop via boundary clones)
  - **iPad:** new **`HomeImmersiveHomeScreen`** — fixed full-screen TMDB backdrop behind scroll content, hero copy + page dots in the top slot (`HomeView` branches on `UIDevice.current.userInterfaceIdiom == .pad`)
  - **tvOS:** **`TVHomeScreen`** backdrop switched from opacity crossfade to the same horizontal pager (remote left/right still pages; fold-snapping and frost/dim below the fold unchanged)
  - **iPhone / macOS:** unchanged inline **`HomeHeroCarousel`** at top of scroll (refactored to use shared controller/pager)
- **Files:** `HomeHeroController.swift`, `HomeHeroArtworkPager.swift`, `HomeImmersiveHomeScreen.swift`, `HomeHeroCarousel.swift`, `HomeView.swift`, `TVHomeScreen.swift`

### For You — tvOS / Metadata Fallback (June 30, 2026)
- **Symptom:** "For You" row stayed empty on tvOS (and anywhere embeddings weren't built yet), even with Premium, watch history, and `.env` configured.
- **Root cause:** `RecommendationEngine` only ranked titles with `embeddingData` from the on-device `NLContextualEmbedding` model. tvOS cannot run that model, so the indexer enriches TMDB but never writes vectors — taste signals and candidates both filtered out.
- **Fix:**
  - Added **`RecommendationMetadataRanker`** — genre-overlap + TMDB "similar titles" + rating fallback when embeddings are absent
  - **`RecommendationEngine`** tries embedding-based ranking first; falls back to metadata ranking when no vectors exist or embedding rank returns empty
  - Works on tvOS-only setups after the user watches or favorites something (same taste-signal requirement as before)
- **Files:** `RecommendationMetadataRanker.swift`, `RecommendationEngine.swift`, `RecommendationMetadataRankerTests.swift`

### Home Hero — Robust Matching + Library Fallback (June 30, 2026)
- **Symptom:** Hero carousel empty on some devices despite TMDB key in `.env` — trending titles didn't match library until TMDB ids were assigned by the background indexer.
- **Fix:**
  - Added **`HomeHeroBuilder`** — match trending → library by **TMDB id**, then by **cleaned title** (`ContentIndexText.searchQuery` handles provider prefixes like `DE | Title (2024) 4K`)
  - **`supplementFromLibrary`** fills the carousel from the user's own highest-rated titles with backdrop/poster artwork when trending overlap is thin (< 3 heroes)
  - Trending Movies/Series rows use the same resolution path
- **Note:** TMDB key is injected at **build time** — rebuild after editing `.env`. Hero still requires a synced playlist with VOD content.
- **Files:** `HomeHeroBuilder.swift`, `HomeView+Trending.swift`, `HomeView.swift`

### iOS Device — Large Library Fix (July 2, 2026)

**Device:** iPhone 16 Pro Max, iOS 26.5.1  
**Provider:** Xtream, `app.streaminfinitytv.com` (~28K items: ~20.7K movies, ~7.5K series, ~1.6K live streams)

**Symptom:** App worked in Simulator but crashed or froze on physical iPhone after syncing — sync cover Done/Cancel unresponsive, UI dead, memory jetsam. Original Lume reportedly worked on the same device.

**Root causes:**
1. **TLS** — Provider cert didn't match `app.streaminfinitytv.com`; device rejected connections (Simulator was lenient).
2. **Home hero OOM** — `HomeHeroBuilder` / trending path scanned the **entire catalog** to match TMDB titles; ~28K rows into memory after sync.
3. **Sync memory spike** (earlier) — single JSON fetch for all VOD before batching (fixed with category-scoped sync).

**Fixes applied (kept):**
- **`ProviderURLSession.swift`** — shared permissive TLS for all provider HTTP (Xtream, M3U, Stalker, image/icon loaders).
- **Category-scoped Xtream sync** — movies/series/live fetched per category; `batchSize = 2000`.
- **`HomeView+Trending.swift`** — batched TMDB ID lookups (Lume pattern); no full-catalog scan.
- **`HomeHeroBuilder.swift`** — title fallback + library supplement with **bounded** fetches (80 library / 100 title search).
- **CloudKit split stores** — catalog local-only; user data in `CloudUserData` (unchanged architecture).

**Fixes reverted (device-only workarounds — caused parity issues):**
- Tab deferral / `browseTabsMounted` / `CatalogLoadingPlaceholder` during sync
- `LargeCatalogGuard`, `CatalogSyncState`, `waitForBrowseReady`
- 120s indexer delay on device; reduced Movies/Series category preview limits
- Stripped post-sync indexer + EPG kick (restored to Lume behavior)

**Restored Lume parity (superseded Jul 7 late for EPG):**
- **`MainTabView.swift`** — all tabs mount; sync is a cover only (no tab unmount).
- **`SyncProgressView.swift`** — post-sync: `ContentIndexingService.kick(after: .seconds(3))` only; **EPG runs inline** during playlist sync (Jul 7 late).
- **`ApexApp.swift`** — launch indexer deferred 20 s (iOS); EPG `syncIfDue()` deferred 90 s (iOS).

**Verified:** iOS app working on physical iPhone with full hero carousel, browse, and sync (user confirmed July 2, 2026).

**Key files:** `ProviderURLSession.swift`, `ContentSyncManager.swift`, `HomeView+Trending.swift`, `HomeHeroBuilder.swift`, `MainTabView.swift`, `SyncProgressView.swift`, `ApexApp.swift`

### CloudKit Re-enable + Schema (July 2, 2026)

**Was disabled:** `if true { return false }` in `ApexApp.isCloudKitEnvironment` (temporary crash isolation during device debugging).

**Re-enabled:** CloudKit on all signed builds (Debug, Release, Sideload). Still off for SwiftUI previews and automated tests only.

**Development schema bootstrapped** in [CloudKit Console](https://icloud.developer.apple.com) for `iCloud.com.streaminfinity.apex`:
- `CD_SyncedPlaylist` (16 fields)
- `CD_UserContentState` (16 fields)
- `CD_UserProfile` (15 fields)
- `CD_SyncedEPGSource` — appears when a manual EPG source is added

**Settings → iCloud Sync** shows **On** on device after container provisioning + fresh install.

**Production schema deployed** (July 2, 2026) — playlist + favorites/progress sync verified on TestFlight. See `CLOUDKIT_SETUP.md`.

**Diagnostics added:** account status timeout (10s), Settings refresh on appear, launch log `CloudKit sync enabled: true/false`.

### Discord + Subtitles (July 2, 2026)

**Discord:** `SupportInfo.swift` → Settings → Support (iOS/iPad/Mac) and About QR (tvOS). Invite: `https://discord.gg/fKhGp6xpB`. Also updated in `README.md` and `.github/ISSUE_TEMPLATE/config.yml`.

**Subtitles:** All three engines expose a CC menu in player controls. **KSPlayer** (default) now mounts `KSPlayerSubtitleOverlay` so selected tracks actually render (previously menu-only). **VLCKit** / **AVPlayer** unchanged for rendering; tvOS track menus refresh when tracks load mid-stream; **macOS AVPlayer** uses `AVPlayerItemLegibleOutput` overlay.

**Key files:** `SupportInfo.swift`, `KSPlayerSubtitleOverlay.swift`, `KSPlayerEngineView.swift`, `KSTVPlaybackEngine.swift`, `VLCPlayerCoordinator.swift`, `AVPlayerCoordinator.swift`

### TestFlight (July 2, 2026)

| Item | Status |
|------|--------|
| App Store Connect app | ✅ "Apex Stream Player" |
| IAP products | ✅ `premium.monthly` + `premium.lifetime` |
| Version / build | **1.2.0 (17)** — current target for upload |
| iOS archive + upload | 🔄 Build 17 (includes Discord, subtitles, CloudKit, device/tvOS fixes) |
| Internal testing (self) | ✅ ~30–60 min after processing |
| External tester invites | 🔄 **Beta App Review** (~1–2 days per build) |
| CloudKit Production schema | ✅ Deployed; playlist + user data sync verified |
| tvOS TestFlight | 🔄 Upload build 17 (lazy tabs + deferred background work included) |
| `.env` secrets | ✅ TMDB + OMDb set; IntroDB/Trakt optional (empty) |

### tvOS — Hero + Large Library Audit (July 2, 2026)

**Hero on Apple TV:** Already implemented via **`TVHomeScreen`** (full-screen TMDB backdrop, fold scroll). Same `loadTrending()` + `HomeHeroBuilder` as iOS.

**Bug fixed:** `HomeView.isEmpty` ignored `heroItems` — hero-only homes showed "Nothing Here Yet" instead of the immersive hero (iOS + tvOS).

**Large-library hardening (tvOS, build 17):** Lazy-mount browse tabs (`MainTabView.activatedTabs`), 30s launch indexer delay, 60s launch EPG delay, post-sync background work deferred, trending gated on sync idle, hero logo enrichment deferred. User-reported multi-minute home freeze addressed — retest on Apple TV with build 17.

**Optional (not in build 17):** Paginate Live TV `@Query` channel lists (UI paginates display but query still loads full category).

**Files:** `TVHomeScreen.swift`, `HomeView.swift`, `MainTabView.swift`, `ApexApp.swift`, `SyncProgressView.swift`, `HomeView+Trending.swift`, `GenreBrowse.swift`

### GitHub README Branding (July 2, 2026)

- Replaced Lume banner with **Apex Stream Player** artwork in `.github/assets/apex-banner.png`
- Added `.github/assets/apex-logo.png` (512px icon); removed Lume `apex-logo.svg`
- Pushed to [github.com/2gchqkkt25-blip/Apex](https://github.com/2gchqkkt25-blip/Apex) (commit `c179fb5`)

### TestFlight Pro Unlock (July 2, 2026)

- **`BetaBuildDetection.swift`** — detects TestFlight via `beta-reports-active` in embedded provisioning profile (+ sandbox receipt fallback)
- **`PremiumManager.swift`** — Release builds: `testFlightGrantsPremium` cached at launch; `isPremium` true for TestFlight
- **Critical fix:** uncached TestFlight detection was reading `embedded.mobileprovision` on every `isPremium` check → app-wide slowness after Pro unlock. Now cached once at launch.

### Home Screen Performance (July 2, 2026 — evening)

**Symptom:** Home tab froze for minutes on ~28K-item Xtream playlist after sync; returning to Home was sluggish.

**Fixes applied:**
- **`HomeHeroBuilder.matchTrending`** — moved off main thread
- **`MainTabView`** — lazy tab mounting on iOS/macOS (was tvOS-only)
- **`HomeView`** — trending cache via `lastTrendingPlaylistStamp`; deferred hero logo enrichment; batched For You fetches; removed EPG sync from `isSyncBusy` gate
- **`ApexApp`** — indexer deferred 20s (iOS) / 30s (tvOS); watchlist deferred 3s; For You deferred 8s on Home
- **`HomeHeroArtworkPager`** — backdrop downsampling

**Status:** User confirmed startup much better and returning to Home is smooth (July 2 evening). Do not re-introduce heavy work at launch.

### EPG Guide — Broadened External Sources + Safe West/Pacific Offset (July 7, 2026 — evening)

**Context:** After the July 7 morning session, the app was pulling EPG from **three** epgshare01 feeds (US2, UK1, CA2) and had a `westMappings` mechanism that *collected* East → West pairings but never wrote shifted listings. Regional variants were blank; niche/international channels were blank; and a handful of unrelated local affiliates were being paired as if they were network west feeds.

**Changes:**
- **`ExternalEPGSources.swift`** — feed list expanded 3 → 14: `US1`, `US2`, `US_LOCALS1–4`, `US_SPORTS1`, `US_MOVIES1`, `UK1`, `UK2`, `CA1`, `CA2`, `IE1`, `AU1`. Missing URLs log a warning and skip — safe to include speculatively.
- **`EPGSyncManager.syncExternalEPG`** — West/Pacific `+3h` insert pass **actually implemented**. For each programme resolved to a matched East primary, we now insert an additional `EPGListing` under each mapped West primary with `start/end += 3 h`. Previously the mappings were computed and logged but never persisted.
- **`EPGLiveLoader`** — `synchronousFetchCap` 12 → 24 and `emptyTTL` 10 min → 3 min so unmatched channels get gap-filled in one scroll page and recover from transient panel misses sooner. Safe at `maxConcurrent = 2` + 200 ms stagger.
- **`EPGNameNormalizer.normalize`** — expanded country-code / TLD strip list to `au|nz|ie|de|fr|es|it|nl|pt|br|mx|ar|in|ph|tr|pl|ro|se|no|dk|fi` (plus original `us|usa|uk|gb|ca`). Country codes at the end of a name double as XMLTV TLD suffixes (`\b` matches after the `.`).
- **`EPGChannelCatalog.fromExternalEPG`** — West/Pacific detection **tightened** to use the provider-issued `epgChannelId` for structural matching, not the display name. New rule: the west stream's `epgChannelId` (minus TLD, minus `west`/`pacific`) must equal a matched east stream's `epgChannelId` (minus TLD). This correctly accepts `hbowest.us ↔ hbo.us` and `tbswest.us ↔ tbs.us` and correctly rejects `mtv2west.us ↔ mtv.us` (`mtv2` ≠ `mtv`) and any pairing whose IDs don't share the `<base>west` structure.
- **`EPGNameNormalizer.normalize`** (second pass, same session) — reverted the `east|eastern|atlantic|central|mountain|feed` strip added earlier that day. It was collapsing distinct local affiliates ("ABC WSB Atlanta" vs "ABC KTRK Houston" both to `abc`) into a single normalized key, which is how the wrong West/Pacific pairings emerged in the console. The East-feed matching case that motivated the strip is instead handled by (a) epgshare01 usually publishing both "HBO" and "HBO East" as separate `<display-name>` entries on the same channel row, and (b) the fuzzy `namesMatch` substring fallback.

**Why the structural check matters — evidence from live console:**
```
EPG WEST MAP: mtv.us → mtv2west.us               ← MTV and MTV2 are different networks
EPG WEST MAP: cbswupaatlantaga.us → cbskovrstocktonsacramentoca.us   ← WUPA Atlanta ≠ KOVR Stockton
EPG WEST MAP: abcwsbatlantaga.us → abcktrkhoustontx.us               ← WSB Atlanta ≠ KTRK Houston
EPG WEST MAP: fyi.us → fyiwest.us                ← legit
EPG WEST MAP: tbs.us → tbswest.us                ← legit
```
Only the last two are actual network west feeds. The others were name-based collisions after the over-aggressive normalizer strip. Structural ID matching eliminates all three false positives.

**Rule going forward:** For any East → West / East → Pacific pairing, the provider-issued `epgChannelId` must literally contain a `west`/`pacific` token and, after stripping that token + TLD, must exactly equal a matched East `epgChannelId` (minus TLD). Name-based matching for this purpose is banned — network prefixes collapse too many unrelated affiliates.

**Files:** `ExternalEPGSources.swift`, `EPGSyncManager.swift`, `EPGLiveLoader.swift`, `Models/LiveStream+EPG.swift` (both `EPGNameNormalizer` and `EPGChannelCatalog.fromExternalEPG`).

**Status:** Build + `XMLTVDateTests` + `EPGSyncTests` + `EPGSourceTests` all green (iOS Simulator, Debug). Next Sync Now clears the store and re-populates, so previous bad shifted rows are wiped.

### EPG Guide — Cross-Device Parity (July 7, 2026 — evening, part 2)

**Key fact:** EPG listings are **local-only** — they do not sync via iCloud. Each iPhone, iPad, Apple TV, and Mac must run its own guide download.

**Gaps closed:**
- **`SyncProgressView`** — playlist refresh now runs **content + TV guide in one flow** (`epgGuide` step, `syncAwaiting(mode: .withPlaylist)`). Post-sync only kicks the content indexer — not a separate deferred EPG pass.
- **`MainTabView`** — selecting the Live TV tab kicks `syncIfDue()` on all platforms (catches tvOS's 60 s launch deferral if the user opens Live TV first).
- **`TVChannelBrowserOverlay`** + **`TVPlayerControlsOverlay`** — now watch `refreshGeneration` so tvOS in-player guide and now/next caption update after Sync Now without leaving playback.
- **`EPGSyncService`** — sync timeout raised 1 200 → 3 600 s; 14 external feeds can exceed 20 min on slow networks.

**Shared pipeline (all platforms):** `EPGSyncManager` → `ExternalEPGSources` → `EPGChannelCatalog.fromExternalEPG` → SwiftData → `EPGBrowseLoader` → UI. No platform forks in the sync/parse layer.

**Verify:** see `EPG.md` § Cross-device verification checklist — run on each physical device / TestFlight build.

### EPG Guide — Parse Speed + Playlist Sync Integration (July 7, 2026 — late evening)

**Symptoms addressed:** External EPG took ~5 min during playlist refresh with little/no % feedback; channel cards stayed blank for several minutes after sync finished.

**Parse / sync speed (`EPGSyncMode`):**
- **`XMLTVParser.importExternalEPG`** — single SAX pass (channel table + programmes); eliminates the old two-pass `parseChannels` + `parseProgrammes` per feed (~50% less XML work).
- **`ExternalEPGSources`** — US feeds first; `US_LOCALS1` last; **`urlsForBundledSync()`** (US-only, 8 feeds) used during playlist refresh vs full 14 on Settings → Sync Now.
- **Early stop (bundled):** stops external fetch when **≥88%** of channels matched; skips **`US_LOCALS1`** at **≥75%** coverage (550 MB, low incremental yield).
- **Live progress:** per-feed + mid-parse callbacks update `EPGSyncService.syncProgress` / label (`67% · US National 2 (2/8)`).
- **`EPGSyncService.signalGuideRefreshDuringSync()`** — throttled `refreshGeneration` every 5 s during active sync so grid/cards fill incrementally.

**Unified playlist + guide refresh (`SyncProgressView`):**
- Branded full-screen sync UI: **`ApexSyncBrandView.swift`**, **`ApexBrandColors.swift`** — electric blue → purple gradient matching the Apex Stream Player logo (not theme accent).
- Final sync step **`epgGuide`** ("TV guide") runs **`EPGSyncService.syncAwaiting(mode: .withPlaylist)`** inline — no separate Settings trip.
- TV Guide row shows **bold %** + feed/channel detail + gradient progress bar.
- Settings → Sync Now still uses **`EPGSyncMode.full`** (all 14 feeds).

**Instant channel cards after sync:**
- **`EPGBrowseLoader`** — live `get_short_epg` gap-fill only when the store has **zero** rows for a channel (was re-fetching even when bulk import already populated SwiftData → 2 concurrent × 24 channels = multi-minute delay).
- **`forceGuideRefresh()`** when the guide step completes so Live TV picks up store data immediately.

**EPG persistence (user expectation):** `EPGListing` rows live in the local SwiftData catalog store and **survive app restarts**. Opening Live TV reads from disk — no manual re-sync required. Background refresh runs on the EPG frequency setting (default: daily) via `syncIfDue()` on launch (deferred 90 s iOS / 60 s tvOS). Playlist refresh re-downloads the guide in the bundled fast path.

**Key files:** `ApexSyncBrandView.swift`, `ApexBrandColors.swift`, `SyncProgressView.swift`, `SyncProgress.swift`, `EPGSyncManager.swift`, `EPGSyncService.swift`, `ExternalEPGSources.swift`, `XtreamClient.swift` (`importExternalEPG`), `EPGLiveLoader.swift` (`EPGBrowseLoader`), `StremioDTOs.swift`, `StremioClient.swift`, `LoginView.swift`.

### Home Tab — First-Launch Performance (July 7, 2026 — late evening)

**Symptom:** ~10 s freeze on first Home open after sync; hero unusable until TMDB network returned.

**Fixes:**
- **`HomeHeroBuilder.libraryHeroMatch()`** — instant heroes from local catalog (no TMDB wait).
- **`HomeView+Trending.swift`** — two-phase load (library heroes first, TMDB enrichment second); **`waitUntilPlaylistSyncIdle()`** (playlist sync only — not full CloudKit reconcile).
- **`ApexApp.swift`** — content indexer deferred **20 s** (iOS) / **30 s** (tvOS); EPG **`syncIfDue()`** deferred **90 s** (iOS) / **60 s** (tvOS) so Home paints first.
- **`SyncProgressView`** — post-sync indexer kick only (EPG now inline in playlist sync, not a deferred `syncIfDue()`).

**Key files:** `HomeHeroBuilder.swift`, `HomeView+Trending.swift`, `HomeView.swift`, `ApexApp.swift`, `SyncProgressView.swift`.

---

### EPG Guide — StreamInfinity panel blocked (July 6, 2026)

**Status: 🔄 Blocked on maintainer test panel** — not working for correct "now" data.
Generic architecture (July 4) is sound for providers with fresh `xmltv.php`.

**Confirmed from device logs:** `xmltv.php` AND `get_short_epg` both lag ~6–9 days
(`startDeltaMin ≈ -9926`). The July 6 assumption that per-channel API was live
was **wrong for this panel**. Shifting stale schedules onto "now" was tried and
**reverted** — titles did not match the live stream.

**What works:** fast sync path (`apiOnDemand`), no 502 storms, honest empty state
when feed is stale, `limit=4` fetch like other apps.

**What doesn't:** correct current programme from provider EPG alone.

**When resuming:** see **`EPG.md` § StreamInfinity panel — blocked** — raw JSON
probe, compare TiviMate EPG source setting, external XMLTV URL, fix parse misses.

---

### EPG Guide — Fast + Correct (July 4, 2026)

**Both problems fixed: slow 25-min sync (and app slow to open VOD during it) + guide/stream mismatch.** This is a published app for arbitrary providers, and the maintainer confirmed **every other IPTV player shows correct current EPG for the same providers** in seconds. Apex now does what they do: **download `xmltv.php` once** and show the provider's real timestamps.

**Speed fix — bulk source is `xmltv.php`, not per-channel API.** The earlier "single-path per-channel" sync made ~1,600 sequential `get_short_epg` calls: many minutes to finish **and** it saturated the provider's shared connection pool, which is why movies/shows were slow to open mid-sync. `EPGSyncManager.syncXtreamAPI` now downloads `xmltv.php` once (one request → seconds); per-channel API is only a fallback (empty xmltv) + on-demand gap-fill of visible channels.

**Correctness fix — honour the timestamp's own UTC offset; no shifting.** Removed all fabrication: `alignIfStale`/`bestTimes` (per-channel), `alignLatestToNow` (XMLTV global shift), and `refreshNowPlaying` (the ~4,800-request freeze storm). The real reason XMLTV *looked* wrong before was a parser bug: `XMLTVDate.parseEPG` dropped the explicit `+ZZZZ` offset and timezone-guessed "closest to now." It now parses the stated offset as an absolute instant (`parseWithExplicitOffset`); only offset-less dumps use the server zone. Deleted the full-file `detectTimezone` pre-pass (the XMLTV double-parse).

**Also:** one-time wipe of the `EPGListing` cache on upgrade (`epg.store.reset.noAlignV1`); `EPGAPISync.sync` (fallback/on-demand path) logs an `EPG raw sample … startDeltaMinutes=N` probe to tell (from Console) whether a provider's feed is live (≈0) or genuinely lagging.

**Residual:** if a *specific* provider's feed really is days behind (visible via the probe), no client can invent current data — the remedy is an external EPG source, not shifting.

**Files:** `EPGSyncManager.swift` (`syncXtreamAPI` → `xmltv.php` primary, per-channel fallback), `XMLTVDate.swift` (honour explicit offsets, drop closest-to-now heuristic, delete `detectTimezone`), `EPGInserter.swift` (single parse, no tz-detection pass, no `alignLatestToNow` shift), `EPGAPISync.swift`/`EPGLiveLoader.swift` (real unix timestamps, no align), `EPGSyncService.swift` (poisoned-store reset), `XMLTVDateTests.swift` (offset tests). Build + `XMLTVDateTests` pass (iOS Simulator, Debug).

---

### EPG Guide — Fixed (July 3, 2026)

**Status: ⚠️ Superseded for StreamInfinity panel** — see July 6 blocked section.
July 3 per-channel align path was reverted July 4; July 6 confirmed provider
feed itself is days stale on test account.

**Root cause (blank guide) — ⚠️ superseded by the July 4 no-shift rewrite above.** The July 3 conclusion was that the provider's `get_short_epg` timestamps were "days behind" and the fix was `EPGAPISync.alignIfStale` (shift the block onto now). That diagnosis was wrong — other players show correct current EPG for the same providers — and the shifting was the actual mismatch bug. `alignIfStale` was removed July 4.

**Follow-on fixes (same day):**
| Issue | Fix |
|-------|-----|
| App janky / partial data while scrolling | Scoped SwiftData fetch (no unscoped `EPGListing` scan); store read off main thread; drop duplicate reload triggers |
| Sync Now slow vs other apps | `thorough: false` on bulk sync (skip fallback cascade); **do not** raise concurrency above 6 — that broke Live TV playback |
| “Now Playing” wrong after sitting on list | Keep raw programmes; recompute now/next every 60s client-side (no network) |
| No visibility into Sync Now | Percent + “N / M channels” in Settings (`EPGSyncService.syncProgress`) |

**Architecture (all platforms):**
| Path | Behaviour |
|------|-----------|
| Live TV / Guide / tvOS player browser | `EPGBrowseLoader` — SwiftData first, per-channel API for gaps, persist |
| Sync Now (Xtream) | `EPGSyncManager` — one `xmltv.php` download → offset-honest parse → SwiftData; per-channel API fallback |
| Per-channel API | Fallback when `xmltv.php` is empty; on-demand gap-fill of visible channels |

**Stability rules (summary — full list in `EPG.md`):** never clear the whole store at sync start; never block browse during Xtream API sync; cache empty API results only briefly (2 min); never unscoped `EPGListing` fetch on main thread; never raise EPG concurrency without confirming provider connection limits; never freeze a “current programme” label without recomputing as time passes; paint logos before EPG network work.

**Testing (in progress):** Live TV during Sync Now; progress %; now-label advances after programme boundary; titles match airings (provider lag still possible).

---

## App Store Connect & TestFlight

Quick reference for [App Store Connect](https://appstoreconnect.apple.com) → **Apex Stream Player**.

### Version / build

| Field | Value |
|-------|-------|
| Marketing version | **1.2.0** |
| Build | **18+** (`CURRENT_PROJECT_VERSION` — bump before next upload) |
| Bundle ID | `com.streaminfinity.apex` |
| Team ID | `VS7D6GB238` |

**Bump build before each upload:** General → Apex target → **Build** → increment (e.g. 17 → 18). Archive with **Release**; `.env` keys inject at build time.

### URLs (App Information — shared iOS + tvOS)

| Field | URL |
|-------|-----|
| **Privacy Policy URL** | `https://github.com/2gchqkkt25-blip/Apex/blob/main/PRIVACY.md` |
| **Support URL** | `https://github.com/2gchqkkt25-blip/Apex` |
| **Marketing URL** (optional) | Same GitHub repo |
| Support email (in-app / review notes) | `support@streaminfinitytv.com` |

Apple TV uses the **same Privacy Policy URL** as iPhone — no separate tvOS policy needed.

### Age rating

**Use 17+.** Apex plays user-supplied IPTV/VOD streams with no content-rating filter. Optional parental controls (child profiles, category hiding) do not lower the store rating. **Not** “Made for Kids.”

Set under **App Information → Age Rating → Edit** (questionnaire: unrestricted web/stream access, mature content possible from user playlists).

### App Privacy questionnaire

Complete **App Privacy** once; must align with `PRIVACY.md`:

- No analytics / ads / first-party accounts
- **Yes** — iCloud/CloudKit sync (progress, favorites, profiles, playlists)
- Optional third-party: TMDB, OMDb, Trakt (user-initiated), IPTV providers (user credentials)
- IAP processed by Apple (StoreKit)

### Monetization (Apex Pro)

| Tier | What |
|------|------|
| **Free** | One playlist, core Live TV / Movies / Series playback |
| **Apex Pro** | Unlimited playlists, downloads, profiles, Trakt, smart playback, For You |

Products: `com.streaminfinity.apex.premium.monthly`, `com.streaminfinity.apex.premium.lifetime`. Charging for **app features** (not content) is allowed under AGPL with source on GitHub. Sideload builds unlock everything (`SIDE_LOAD`).

### External TestFlight — what you **need**

| Required | Notes |
|----------|--------|
| Build uploaded + processed | Archive → Distribute → App Store Connect |
| Export compliance | Usually **No** (standard HTTPS only) |
| Age rating completed | **17+** |
| Privacy Policy URL | GitHub `PRIVACY.md` |
| App Privacy questionnaire | Match policy |
| Test Information | **What to Test** + beta contact email |
| Submit for **Beta App Review** | External group only; ~1–2 days |

### External TestFlight — what you **do NOT** need yet

| Not required for external TestFlight |
|-------------------------------------|
| App Store **screenshots** |
| **Description / subtitle / keywords** |
| **Promotional text** / **What’s New** (store version) |
| Full **App Store review** submission |

Internal TestFlight (team only): upload build, no Beta App Review.

**What to Test** (paste in TestFlight → External Testing):

```
Apex is an IPTV player—users add their own Xtream or M3U playlist. No content is bundled.

Add a playlist, wait for sync, browse Live TV / Movies / Series, and play a stream. Test iCloud sync in Settings if signed into iCloud. Premium IAP unlocks optional features only.

Contact: support@streaminfinitytv.com
```

Add **test playlist credentials** in review notes if you have a legal test source — helps IPTV Beta App Review.

### Full App Store release — additional requirements

When ready for public listing (after TestFlight):

| Item | Where in Connect |
|------|------------------|
| Screenshots | iOS App / Apple TV App → version → **App Store** tab |
| Description, subtitle, keywords (iOS) | Same **App Store** tab |
| tvOS description | **Apple TV App** → version → **App Store** tab (no keywords on tvOS) |
| What’s New | Per version |
| IAP localization | **Subscriptions** / **In-App Purchases** |

**Screenshot tips:** Xcode Simulator → run Apex → sync playlist → **Cmd+S** to save. Capture Home, EPG, Live TV, detail, player. Simulators: iPhone 17 Pro Max (6.9"), Apple TV 4K. Avoid empty states and “free channels” marketing.

**Draft copy** (iOS + tvOS subtitles, descriptions, IAP text) was prepared in project chat July 2, 2026 — paste into Connect when submitting for **public** release.

### Review positioning (IPTV apps)

- Apex is a **player only** — no bundled channels or playlists
- Users supply **authorized** credentials
- Premium unlocks **features**, not content
- Age rating **17+**; anti-piracy policy: [`ANTI_PIRACY.md`](ANTI_PIRACY.md)

---

## Notes

- **Apex Pro** — StoreKit gates convenience features on App Store builds; sideload/source builds stay fully unlocked (see `PremiumManager.swift`)
- AGPL-3.0 means every change you make MUST be published on GitHub
- You CAN sell Apex Pro on the App Store even though the code is public
- The app ships with NO content — users provide their own credentials/playlists
- CloudKit container configured — Development + **Production** schema live; sync verified on TestFlight (see `CLOUDKIT_SETUP.md`)
- A full feature inventory is at `FEATURE_INVENTORY.md`
- **API keys** — TMDB + OMDb strongly recommended; `INTRO_DB_API_KEY` optional (Skip Intro works unauthenticated). Keys inject at **build time** via `Scripts/inject-env.sh` — **rebuild after editing `.env`**
- **Skip Intro** — Settings toggle only (not Premium); needs IntroDB coverage per episode (some episodes have no skippable intro)
- **EPG** — 🔄 **Working on StreamInfinity panel** with 14 external epgshare01 feeds + structural West/Pacific `+3h` insert + broadened live-API gap-fill. Title accuracy correct for major networks; local-affiliate West variants and niche channels fall through to per-channel API. See **`EPG.md`**
- **TestFlight Pro** — beta testers get full Pro without IAP (`BetaBuildDetection`)
- **For You** — Premium + at least one watch/favorite/vote signal; tvOS uses metadata fallback when embeddings unavailable
- **Home hero** — TMDB key + synced playlist; title matching + library fallback when trending overlap is thin
- **macOS builds** require an Apple Developer account signed into Xcode (no signing identities on this machine)
- **tvOS Search tab** — first tab (magnifying glass); empty state shows poster-grid category browse for Movies and Series; text search when typing

---

## Apple Developer Setup (July 2, 2026)

| Done | What |
|------|------|
| ✅ | Team ID `VS7D6GB238` wired up project-wide |
| ✅ | Release entitlements — APNs `production`, CloudKit container, increased memory limit |
| ✅ | App Store Connect app created — "Apex Stream Player" |
| ✅ | IAP products — `premium.monthly` + `premium.lifetime` |
| ✅ | App icon regenerated at all sizes + tvOS brand assets |
| ✅ | iOS builds archived + uploaded to TestFlight (builds 7–16); **17** in progress |
| ✅ | App working on iPhone 16 Pro Max (physical device, ~28K playlist) |
| ✅ | CloudKit Development + **Production** schema; sync verified |
| ✅ | `.env` — TMDB + OMDb keys confirmed for Release archives |
| ✅ | GitHub repo public — latest includes build 17 fixes + README logo (`1a62cee`, `c179fb5`) |
| 🔄 | TestFlight build **17** — iOS + tvOS archive/upload |
| 🔄 | External TestFlight — Beta App Review (see **App Store Connect & TestFlight** above) |
| ⏳ | App Store screenshots + public listing |
| ⏳ | macOS TestFlight / App Store (signing) |

---

## Current Architecture — Large Library + Sync

| Layer | Behavior |
|-------|----------|
| **Catalog** | Local `default.store` only — never CloudKit-synced |
| **User data** | `CloudUserData.store` → CloudKit (`SyncedPlaylist`, `UserContentState`, `UserProfile`, `SyncedEPGSource`) |
| **Xtream sync** | Per-category API fetch → batch writes (2000) |
| **Provider HTTP** | `ProviderURLSession` — TLS bypass for mismatched provider certs |
| **Home hero** | Batched TMDB ID query + bounded title/library fallback (`HomeHeroBuilder`) |
| **Post-sync** | Indexer kick @ 3s (20s tvOS). **EPG runs inline** during playlist sync (`epgGuide` step); tvOS uses quick mode (3 feeds); launch `syncIfDue()` deferred 90s iOS / 60s tvOS — EPG is local-only, not iCloud |
| **EPG sync** | **Playlist refresh (iOS):** bundled mode (8 US feeds, 88% early stop, single-pass parse, **%** progress). **Playlist refresh (tvOS):** quick mode (3 lightest feeds inline, remaining bundled 10s deferred). **Settings → Sync Now:** full 14 epgshare01 feeds. Provider `xmltv.php` fallback → per-channel `get_short_epg` only when store empty for channel. West/Pacific `+3h` insert via structural `epgChannelId`. See `EPG.md`. |
| **EPG browse (tvOS)** | 6 concurrent, 0 stagger, cap 50 channels/page. Single API call per channel. Background fetch for remaining channels with `refreshGeneration` signal. Store read instant after sync. |
| **EPG status** | ✅ Both platforms verified (Jul 8): external EPG primary, branded unified sync, instant post-sync channel cards, persists across restarts and category switches. Guide view matches list view speed. See `EPG.md`. |
| **CloudKit UI** | Settings → iCloud Sync; foreground reconcile gated on actual imports |

---

## Resolved — iOS Device Issues (July 2, 2026)

See **What's Been Built → iOS Device — Large Library Fix** above for full detail.

**Summary:** Simulator ≠ device was not a platform limitation — it was full-catalog Home fetches and SSL. Fixed with bounded hero/trending, `ProviderURLSession`, and Lume-aligned sync/post-sync flow. **Status: resolved on user's iPhone.**

---

## Next Steps

### Priority 1 — Ship

1. ~~**EPG guide**~~ — ✅ Done (`EPG.md`); speed + smoothness fixed
2. ~~**Deploy CloudKit schema** Development → Production~~ — ✅ Done; sync verified
3. ~~**Archive + upload build 19**~~ — ✅ Done.
4. ~~**EPG on device**~~ — ✅ **Working (Jul 8)** on both iOS and tvOS.
5. **TestFlight build 23** — 🔄 **Testing now** — EPG loading fixed (playlist passed directly); watchdog crash fixed (watchlist off main thread); performance fixes retained.
6. **External TestFlight** — Age rating 17+, privacy URL, App Privacy, What to Test → Beta App Review
7. **Smoke-test** — sync (branded UI + TV Guide **%**), hero, subtitles, Discord, tvOS home, **EPG** (cards populate immediately after sync, grid + in-player browser, persistence after force-quit)
8. **Screenshots + store copy** — when ready for **public** App Store
9. **macOS signing** — Apple Developer certs on build machine
10. **App Store public release** — after TestFlight validation

### AGPL
9. **Publish fork changes** to GitHub when ready to ship (license requirement)

---

*Last updated: July 8, 2026 (Build 23 testing — EPG + watchdog crash fixed; performance fixes retained. Genre/category in Search tab.)*
