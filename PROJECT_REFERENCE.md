# Project Reference

> **What is this?** Your cheat sheet for this project. Read this every time you come back so you know exactly where things stand.

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
| 40 | TestFlight build **17** (1.2.0) — iOS + tvOS upload | 🔄 In progress |
| 41 | TestFlight — external tester groups (Beta App Review) | 🔄 In progress |
| 42 | tvOS TestFlight + large-library hardening (lazy tabs, deferred indexing) | ✅ Done (build 17) |

---

## Key Decisions Made

| Decision | Value |
|----------|-------|
| App name | **Apex** by StreamInfinity |
| Bundle ID | `com.streaminfinity.apex` |
| URL scheme | `apex://` |
| CloudKit container | `iCloud.com.streaminfinity.apex` |
| StoreKit IAP prefix | `com.streaminfinity.apex.premium.*` |
| Monetization | Keep StoreKit 2 (monthly + lifetime) |
| Theme system | 5 themes: System, Frosted Glass, Midnight, Sunset, Ocean |
| Features | 93 kept, 3 reworked, 0 stripped |

## Key Decisions Pending

1. ~~**GitHub repo**~~ — ✅ Live at [github.com/2gchqkkt25-blip/Apex](https://github.com/2gchqkkt25-blip/Apex)
2. ~~**Website / support email**~~ — ✅ support@streaminfinitytv.com, GitHub as homepage
3. ~~**Apple Developer setup**~~ — ✅ Team `VS7D6GB238`, bundle ID registered, IAP products created, iOS TestFlight builds uploaded (July 2, 2026)
4. ~~**CloudKit Development schema**~~ — ✅ Bootstrapped; **Production deployed** — playlist + user data sync verified on TestFlight (July 2, 2026)
5. **TestFlight build 17** — Archive + upload iOS and tvOS (Discord, subtitles, tvOS perf, CloudKit)
6. **iOS TestFlight external testers** — Invites sent; waiting on Apple **Beta App Review** (~1–2 days) for new build
7. ~~**tvOS large-library hardening**~~ — ✅ Lazy tab mount, deferred indexing/EPG (tvOS-only); in build 17
8. **macOS signing** — Requires Apple Developer certificates on this machine
9. **App Store submission** — After TestFlight validation

---

## Placeholder Values

| What | Current | Needs |
|------|---------|-------|
| Website | `github.com/2gchqkkt25-blip/Apex` | Done (GitHub as homepage) |
| Support email | `support@streaminfinitytv.com` | ✅ Done |
| GitHub repo | `github.com/2gchqkkt25-blip/Apex` | ✅ Done |
| Privacy policy | `github.com/2gchqkkt25-blip/Apex/blob/main/PRIVACY.md` | ✅ Done |

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

**Restored Lume parity:**
- **`MainTabView.swift`** — all tabs mount; sync is a cover only (no tab unmount).
- **`SyncProgressView.swift`** — post-sync: `ContentIndexingService.kick(after: .seconds(3))` + `EPGSyncService.syncNow()`.
- **`ApexApp.swift`** — launch indexer `kick()` without long device-only delay.

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

---

## Notes

- The original Lume uses a "Premium" system — this may need to be redone or removed
- AGPL-3.0 means every change you make MUST be published on GitHub
- You CAN sell this on the App Store even though the code is public
- The app ships with NO content — users provide their own credentials/playlists
- CloudKit container configured — Development + **Production** schema live; sync verified on TestFlight (see `CLOUDKIT_SETUP.md`)
- A full feature inventory is at `FEATURE_INVENTORY.md`
- **API keys** — TMDB + OMDb strongly recommended; `INTRO_DB_API_KEY` optional (Skip Intro works unauthenticated). Keys inject at **build time** via `Scripts/inject-env.sh` — **rebuild after editing `.env`**
- **Skip Intro** — Settings toggle only (not Premium); needs IntroDB coverage per episode (some episodes have no skippable intro)
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
| ✅ | iOS builds archived + uploaded to TestFlight (builds 7–16; **17** uploading) |
| ✅ | App working on iPhone 16 Pro Max (physical device, ~28K playlist) |
| ✅ | CloudKit Development + **Production** schema; sync verified |
| ✅ | `.env` — TMDB + OMDb keys confirmed for Release archives |
| 🔄 | TestFlight build **17** — iOS + tvOS archive/upload in progress |
| 🔄 | External TestFlight testers — Beta App Review (per build) |
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
| **Post-sync** | Indexer kick @ 3s + EPG `syncNow()` |
| **CloudKit UI** | Settings → iCloud Sync; foreground reconcile gated on actual imports |

---

## Resolved — iOS Device Issues (July 2, 2026)

See **What's Been Built → iOS Device — Large Library Fix** above for full detail.

**Summary:** Simulator ≠ device was not a platform limitation — it was full-catalog Home fetches and SSL. Fixed with bounded hero/trending, `ProviderURLSession`, and Lume-aligned sync/post-sync flow. **Status: resolved on user's iPhone.**

---

## Next Steps

1. ~~**Deploy CloudKit schema** Development → Production~~ — ✅ Done; sync verified
2. **Archive + upload build 17** — iOS and tvOS to TestFlight (Release, `.env` keys inject at build)
3. **Smoke-test build 17** — sync, hero, subtitles (CC), Discord link, tvOS home responsiveness
4. **Wait for Beta App Review** — external testers (~1–2 days after upload)
5. **macOS signing** — Apple Developer certs on build machine
6. **App Store submission** — after TestFlight validation

---

*Last updated: July 2, 2026 (build 17, CloudKit Production sync verified, Discord + subtitle fixes)*
