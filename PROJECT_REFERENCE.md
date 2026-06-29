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
| `INTRO_DB_API_KEY` | [introdb.app](https://introdb.app) | Skip intro/recap (optional) |

Without these keys, the app works but metadata is limited to what the IPTV provider supplies.

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
| 12 | Set up your own GitHub repo | ⬜ Not started |
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

1. **GitHub repo** — Where to publish the source (AGPL requirement)
2. **Website / support email** — Currently using placeholders (`TBD`)
3. **Apple Developer setup** — CloudKit container, IAP products, App Store Connect listing
4. **TMDB enrichment in Simulator** — Content indexer was blocked indefinitely by embedding model sandbox error (`NLNaturalLanguageErrorDomain Code 7`). Fixed by adding max retry (4 attempts) to `prepareEmbedder` and allowing TMDB enrichment to proceed without semantic-search embeddings when the model is unavailable.

---

## Placeholder Values

| What | Current | Needs |
|------|---------|-------|
| Website | `TBD-website.example.com` | Real domain |
| Support email | `support@TBD.example.com` | Real email |
| GitHub repo | `github.com/TBD/apex` | Your GitHub org + repo |
| Privacy policy | `github.com/TBD/apex/blob/main/PRIVACY.md` | Real URL |

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

---

## Notes

- The original Lume uses a "Premium" system — this may need to be redone or removed
- AGPL-3.0 means every change you make MUST be published on GitHub
- You CAN sell this on the App Store even though the code is public
- The app ships with NO content — users provide their own credentials/playlists
- CloudKit container + IAP product IDs are renamed but won't work until set up in Apple Developer Portal
- A full feature inventory is at `FEATURE_INVENTORY.md`
- **API keys are required** for TMDB/OMDb metadata — see `.env` setup section above
- **macOS builds** require an Apple Developer account signed into Xcode (no signing identities on this machine)
- **tvOS Search tab** — first tab (magnifying glass); empty state shows poster-grid category browse for Movies and Series; text search when typing

---

*Last updated: June 29, 2026 (VOD poster rating badges + tvOS Search category browse with poster tiles)*
