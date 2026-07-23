# Apex — Feature Inventory

> **Purpose:** Track what stays, what goes, and what changes during the Lume → Apex rebrand.
>
> **Last updated:** July 20, 2026 (Build 46)

---

## Decision Key

- `✅ Keep` — Leave as-is (rename/retheme already done)
- `❌ Strip` — Remove entirely
- `🔧 Rework` — Keep the idea but rebuild differently
- `💰 Gate` — Put behind a paywall or setting

---

## 1. Content Sources

### 1.1 Xtream Codes API Integration
Connects to Xtream Codes IPTV panel API. Authenticates, fetches live/VOD/series categories and content, handles retry/backoff.
- **Files:** `XtreamClient.swift`, `XtreamDTOs.swift`, `APIClient.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 1.2 M3U / M3U8 Playlist Import
Fetches remote or local `.m3u`/`.m3u8` files, stream-parses entries, classifies as live/movie/episode, builds categories from group tags.
- **Files:** `M3UClient.swift`, `M3UParser.swift`, `ContentSyncManager+M3U.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 1.3 Stalker (Ministra) Portal API Integration
Authenticates by MAC address against Stalker/Ministra portals. Fetches channels, VOD, series with pagination. Sync imports page 1 of every VOD/series category for immediate browsing, then fills pages 2–20 for all categories in a detached utility task. Resolves short-lived stream URLs at playback time.
- **Files:** `StalkerClient.swift`, `StalkerDTOs.swift`, `StalkerSupport.swift`, `ContentSyncManager+Stalker.swift`, `StalkerStreamResolver.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 1.4 Playlist Management (CRUD)
Create, edit, delete playlists. Stores server URL, credentials, MAC address, EPG URL, sync settings, account info. On **tvOS**, long-press Select on text fields opens in-app Copy / Paste / Clear (`ApexTextClipboard` — no system pasteboard).
- **Files:** `Playlist.swift`, `LoginView.swift`, `PlaylistDetailView.swift`, `PlaylistDeletion.swift`, `TVSettingsComponents.swift`, `ApexTextClipboard.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 1.5 Playlist Switching
Switch between multiple playlists with progress overlay. Each switch re-scopes all content tabs. Limited to 1 playlist on free tier. Empty selection prefers **Xtream → M3U → Stalker → Stremio** so a CloudKit restore does not leave Stremio as the default when a catalog playlist exists (Build 41).
- **Files:** `PlaylistSwitcher.swift`, `PlaylistSwitchProgress.swift`, `MainTabView.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 2. Live TV

### 2.1 Live TV Channel Browsing
Category sidebar/rail + channel list with lazy loading. EPG now/next info on each channel card. Category search on iOS. The browse header shows the active playlist's visible channel count.
- **Files:** `LiveTVView.swift`, `LiveTVSection.swift`, `LiveTVTVComponents.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 2.2 Channel Surfing (Next/Previous)
Navigate to adjacent channels within the current category from the player. Used by tvOS Siri Remote up/down.
- **Files:** `LiveChannelNavigator.swift`, `KSPlayerEngineView+TVChannels.swift`, `TVChannelBrowserOverlay.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 2.3 Live Channel Recall (Last Channel)
Track current and previous live channel — "recall" button to jump back. Recent channels rail (up to 12). Profile-isolated.
- **Files:** `LiveChannelHistory.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 2.4 Catch-up / Timeshift
Play past programmes on live channels that support it (Xtream-only). Modelled as VOD (seekable, no live controls).
- **Files:** `PlayableMedia.swift` (catchup method), `XtreamClient.swift` (buildCatchupURL)
- **Status:** Core — **Decision:** ✅ Keep

### 2.5 Favorite Channels
Toggle channels as favorites from the player or channel list. Favorited channel rows show a filled red heart inline beside the channel name. Independent Favorites ordering.
- **Files:** `LiveStream.swift`, `PlayerFavorites.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 2.6 Channel Management (Hide/Reorder)
Hide channels from browsing, reorder channels within categories, reorder Favorites list. Survives re-syncs.
- **Files:** `ChannelManagementView.swift`, `FavoriteChannelManagementView.swift`, `ContentOrganizing.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 2.7 Recent Channels List
Recently Watched section in the Live TV rail.
- **Files:** Built into `LiveTVView.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 3. Movies

### 3.1 Movie Browsing
Browse movies by category with preview rows, "Show All" per category, compact grid tiles for remaining categories, and an active-playlist movie count at the top. Smart collections (Recently Watched, Favorites, Recently Added). Favorited posters show a top-left heart without overlapping the top-right rating badge.
- **Files:** `MoviesView.swift`, `LibraryCollectionRows.swift`, `CategoryContentGrid.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 3.2 Movie Detail Screen
Full-bleed backdrop hero, metadata line, Play/Resume and Start from Beginning buttons, expandable synopsis, cast row with photos, "You May Also Like", TMDB collection, "Other Sources", external ratings chips, trailer/video rows. Start from Beginning appears when resume progress exists.
- **Files:** `MovieDetailView.swift`, `TVMovieDetailView.swift`, `TVDetailComponents.swift`, `TVDetailButtons.swift`, `MediaDetailComponents.swift`, `ExternalRatingsView.swift`, `ExpandableText.swift`, `VideoComponents.swift`
- **Status:** Core — **Decision:** 🔧 Rework — Add IMDb + TMDB collection data and show metadata for VODs

### 3.3 Movie Favorites
Mark movies as favorites with watchlist date. Drives the Favorites home row and the shared top-left poster badge across category grids, Home rails, collection rows, similar-title strips, and tvOS recommendation rails.
- **Files:** `Movie.swift`, `PlayerFavorites.swift`, `MovieCardView.swift`, `HomeRows.swift`, `PosterRatingBadge.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 3.4 Watched / Unwatched Toggle for Movies
Toggle watched state from detail screen toolbar. Auto-deletes downloads when marked watched.
- **Files:** `MovieDetailView.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 3.5 Movie Genre Browsing
Derive genres from TMDB/provider data and browse by genre.
- **Files:** `GenreBrowse.swift`, `Genre.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 4. Series

### 4.1 Series Browsing
Browse series by category with preview rows, Recently Watched/Favorites/Recently Added collections, genre grid, and an active-playlist series count at the top. Favorited posters use the same top-left heart as movies.
- **Files:** `SeriesView.swift`, `LibraryCollectionRows.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 4.2 Series Detail Screen
Backdrop hero, season/episode list, metadata, cast, trailers, "You May Also Like", similar titles.
- **Files:** `SeriesDetailView.swift`, `SeriesDetailViewPreviews.swift`, `TVSeriesDetailView.swift`
- **Status:** Core — **Decision:** 🔧 Rework — Add IMDb + TMDB metadata, matching the richness of the Movie detail screen

### 4.3 Episode Management
Mark episodes watched/unwatched individually or in batch (mark all earlier/later). Episode context menus include Play from Beginning when saved progress exists, on iOS, macOS, and tvOS.
- **Files:** `Episode.swift`, `EpisodeCard.swift`, `EpisodeWatchedMenu.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 4.4 Series Favorites
Favorite series via detail screen or player controls. Favorite state drives the shared top-left badge across all series poster variants.
- **Files:** `Series.swift`, `PlayerFavorites.swift`, `SeriesCardView.swift`, `HomeRows.swift`, `PosterRatingBadge.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 4.5 Series Genre Browsing
Browse series by genre from TMDB enrichment and provider data.
- **Files:** `GenreBrowse.swift`, `Genre.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 4.6 Episode Fetching (Lazy)
Episode lists fetched on demand when the detail screen opens, not during initial sync.
- **Files:** `ContentSyncManager.swift` (fetchEpisodes), `ContentSyncManager+Stalker.swift` (fetchStalkerEpisodes)
- **Status:** Core — **Decision:** ✅ Keep

---

## 5. Playback

### 5.1 Three Interchangeable Playback Engines
KSPlayer (default), VLCKit (fallback), AVPlayer (tertiary). User-configurable priority. Auto-fallback if one fails.
- **Files:** `PlayerSettings.swift`, `PlayerEngineOptions.swift`, `KSPlayerEngineView.swift` (+6 extensions), `VLCPlayerEngineView.swift`, `VLCPlayerCoordinator.swift` (+1 extension), `AVPlayerEngineView.swift`, `AVPlayerCoordinator.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 5.2 Player Controls Overlays
Three platform-appropriate control overlays with close, transport, scrubber, favorite toggle, live indicator. tvOS immersive overlay with channel surf, EPG, season rail, recent channels.
- **Files:** `KSPlayerControlsOverlay.swift`, `VLCPlayerControlsOverlay.swift`, `AVPlayerControlsOverlay.swift`, `TVPlayerControlsOverlay.swift` (+2), `TVPlayerPanels.swift`, `TVPlayerContent.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 5.3 Full-Screen Player
Cross-platform full-screen player. iOS/tvOS: fullScreenCover. macOS: separate WindowGroup. Drives media through engine priority list.
- **Files:** `FullScreenPlayerView.swift`, `TVPlaybackEngine.swift`, `KSTVPlaybackEngine.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 5.4 External Player Hand-off
Send streams to Infuse or VLC (external apps) via deep-link URL schemes.
- **Files:** `ExternalPlayer.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 5.5 PlayableMedia (Unified Playback Model)
Value-type description of anything playable, independent of SwiftData. Prioritizes local downloads over remote URLs.
- **Files:** `PlayableMedia.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 5.6 Watch Progress Recording
Buffers progress during playback to UserDefaults (avoids SwiftData hitches), flushes at safe boundaries. Recovers unflushed progress after crash.
- **Files:** `WatchProgressBuffer.swift`, `WatchProgressWriter.swift`
- **Status:** Core — **Decision:** ✅ Keep
- **Cleanup note:** launch-time reconciliation now runs through a main-actor-safe path before replaying any buffered progress into SwiftData.

### 5.7 Autoplay Next Episode
Automatically starts next episode when current one finishes. **Currently premium-gated.**
- **Files:** `NextEpisodeResolver.swift`, `PlayerSettings.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 5.8 Next Episode Button
Shows focused "Next Episode" button near episode end (≥90%). **Currently premium-gated.**
- **Files:** `PlayerNextUpOverlay.swift`, `NextEpisodeResolver.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 5.9 Skip Intro / Skip Recap
Detects intro/recap segments via IntroDB crowd-sourced timestamps. Shows "Skip Intro" button when enabled in Settings (not Premium-gated; autoplay/next episode remain Premium).
- **Files:** `PlayerSkipIntroOverlay.swift`, `IntroSkipResolver.swift`, `IntroDBClient.swift`, `EpisodeSeriesResolver.swift`, `FullScreenPlayerView.swift`, `PlaybackClock.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 5.10 VLCKit Per-Engine Settings
Configurable VLC options: hardware decode, decode threads, skip/drop late frames, HTTP reconnect, deinterlace, buffer sizes, clock jitter.
- **Files:** `PlayerSettings.swift` (VLC namespace), `PlayerEngineSettingsViews.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 5.11 KSPlayer Per-Engine Settings
Configurable KSPlayer options: hardware decode, async decompression, primary engine, adaptive bitrate, deinterlace, auto-rotate, PiP, buffer presets.
- **Files:** `PlayerSettings.swift` (KSPlayer namespace), `PlayerEngineOptions.swift`, `PlayerEngineSettingsViews.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 5.12 Player Error/Retry UI
Loading indicator, error state with retry, video info overlay (codec/resolution/fps).
- **Files:** `PlayerLoadingIndicator.swift`, `PlayerErrorIndicator.swift`, `PlaybackRetryController.swift`, `PlayerVideoInfo.swift`, `PlaybackClock.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 5.13 Video Codec/Format Info Overlay
Shows active codec, resolution, frame rate for the current stream.
- **Files:** `PlayerVideoInfo.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 5.14 Subtitle Appearance and Placement
Settings → Subtitles → Appearance controls Bottom/Center placement, size, color, background opacity, and bottom offset. Bottom placement respects platform safe areas and moves above visible player controls (iOS/iPadOS orientation-aware, macOS desktop controls, and the larger tvOS overlay); Center remains geometrically centered. Control visibility is shared across KSPlayer, VLCKit, and AVPlayer so external subtitles react consistently.
- **Files:** `OpenSubtitlesSettings.swift`, `OpenSubtitlesSettingsView.swift`, `ExternalSubtitleOverlay.swift`, `FullScreenPlayerView.swift`, `KSPlayerSubtitleOverlay.swift`, `KSPlayerEngineView.swift`, `VLCPlayerEngineView.swift`, `AVPlayerEngineView.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 6. EPG / TV Guide

### 6.1 EPG Source Management
Standalone XMLTV guide sources per playlist. Auto-created via reconciler. Users can add manual EPG URLs. Enable/disable individually.
- **Files:** `EPGSource.swift`, `EPGSourceReconciler.swift`, `EPGSettingsView.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 6.2 EPG Sync (Independent Pipeline)
Downloads XMLTV files, stream-parses with SAX parser, inserts only programmes for known channel IDs. Independent of content sync.
- **Files:** `EPGSyncManager.swift`, `EPGSyncService.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 6.3 EPG Now/Next on Channel Cards
Each channel card shows current and next programme from EPG.
- **Files:** `ChannelEPGSnapshot.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 6.4 EPG Guide Grid View
Full TV guide grid with timeline. Tappable programmes for detail/catch-up. List/Guide mode toggle.
- **Files:** `EPGGuideView.swift`, `EPGTimeline.swift`, `EPGProgramDetailView.swift`, `EPGComponents.swift`
- **Status:** Core — **Decision:** 🔧 Rework — Navigation and scrolling needs improvement; it's not smooth

### 6.5 EPG Programme Detail
Detail screen for a specific programme: title, description, times, Play Catch-up button.
- **Files:** `EPGProgramDetailView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 6.6 Synced EPG Sources (iCloud)
Manual EPG sources synced across devices via CloudKit.
- **Files:** `SyncedEPGSource.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

---

## 7. Metadata & Enrichment

### 7.1 TMDB Metadata Enrichment
Fetches movie/series details: backdrop, logo, tagline, content rating, genres, cast, similar titles, collections, trailers, IMDB id. Cached 14 days. Trending feed for Home hero.
- **Files:** `TMDBClient.swift`, `ContentSyncManager+TMDB.swift`, `Movie.swift`, `Series.swift`, `CastMember.swift`, `TitleVideo.swift`, `ExternalRating.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.2 TMDB Language Watching
Detects language override changes, invalidates cached TMDB enrichment for re-fetch.
- **Files:** `TMDBLanguageWatcher.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.3 OMDb Ratings Enrichment
Fetches IMDb, Rotten Tomatoes, Metacritic scores. Rendered as colored chips on detail screens. Cached 14 days.
- **Files:** `OMDBClient.swift`, `ContentSyncManager+OMDB.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.4 Trakt Integration (Scrobbling)
Device OAuth connect/disconnect. Syncs watched state to Trakt. Shows Trakt watchlist on Home. **Currently premium-gated.**
- **Files:** `TraktService.swift`, `TraktClient.swift`, `TraktTokenStore.swift`, `TraktWatchedImporter.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 7.5 Trakt Watched History Import
Imports Trakt watched history into local catalog, marking matching movies/episodes as watched. **Currently premium-gated.**
- **Files:** `TraktWatchedImporter.swift`, `TraktService.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 7.6 "You May Also Like" / Similar Titles
Shows similar titles from TMDB on movie/series detail screens.
- **Files:** Built into `MovieDetailView.swift`, `SeriesDetailView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.7 TMDB Collection Section
Shows other movies in the same TMDB collection on detail screens.
- **Files:** Built into `MovieDetailView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.8 "Other Sources" Section
Shows the same title from other playlists, allowing cross-playlist playback.
- **Files:** `OtherSources.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 7.9 YouTube Trailer / Video Playback
Opens YouTube trailers and videos in YouTube app or browser. Fallback URL schemes on tvOS.
- **Files:** `TitleVideo.swift`, `VideoComponents.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

---

## 8. User Management

### 8.1 User Profiles (Multi-Profile)
Named profiles with customizable avatar (SF Symbol) and color tint. Separate watch history, progress, favorites, recommendation votes per profile. **Currently premium-gated.**
- **Files:** `UserProfile.swift`, `ProfileManager.swift`, `ActiveProfileStore.swift`, `ProfileSettings.swift`, `ProfileSelectionView.swift`, `ManageProfilesView.swift`, `ProfileEditorView.swift`, `ProfileAvatarView.swift`, `ProfileMenu.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 8.2 Profile Switching
Switch active profile with catalog re-projection (content state re-reads from new profile's records).
- **Files:** `ProfileManager.swift`, `CloudSyncEngine+Profiles.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 8.3 Parental Controls (PIN)
Optional 4-digit PIN stored in keychain. Required to leave child profile or access Content Management.
- **Files:** `ParentalControls.swift`, `ParentalControlsStore.swift`, `ContentRestriction.swift`, `ParentalGateView.swift`, `PINEntryViews.swift`, `PINPadView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 8.4 Content Restriction (Child Profiles)
When child profile is active, restricted categories and their content are hidden from browsing, Home, and Search.
- **Files:** `ContentRestriction.swift`, `Category.swift`, `ParentalControlsSettings.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 8.5 UserContentState (Per-Profile Cloud State)
CloudKit-synced per-content user state: watch progress, watched flag, favorites, watchlist dates, recommendation votes. Keyed by profile ID.
- **Files:** `UserContentState.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

---

## 9. Sync & Cloud

### 9.1 Content Sync (Playlist Catalog)
Actor-based background sync for Xtream, M3U, Stalker. Downloads catalogs in batches, upserts into SwiftData, prunes stale items. Stalker imports page 1 of every VOD/series category during visible sync and loads remaining pages 2–20 for all categories afterward at utility priority. Cancellable with progress reporting.
- **Files:** `ContentSyncManager.swift`, `ContentSyncManager+Helpers.swift`, `ContentSyncManager+M3U.swift`, `ContentSyncManager+Stalker.swift`, `SyncProgress.swift`, `SyncFrequency.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 9.2 Auto-Sync on Launch/Foreground/Add
Playlists sync automatically on launch, playlist add, foreground return, and playlist switch. Configurable frequency (hourly, daily, weekly, manual). Catalog providers (Xtream / M3U / Stalker) enqueue ahead of Stremio. On tvOS, first-time syncs (`lastSyncDate == nil`) always present the sync cover; routine refreshes still defer when browsing Home (Build 41).
- **Files:** `MainTabView.swift`, `SyncProgressView.swift`, `SettingsView+AutoSync.swift`, `PlaylistSwitcher.swift` (`orderedForAutoSync`)
- **Status:** Core — **Decision:** ✅ Keep

### 9.3 iCloud Sync (CloudKit)
Two-container architecture: local catalog store + CloudKit user data store. Three-way merge reconcile engine. Account status detection, initial sync gate, background reconciliation.
- **Files:** `CloudSyncCoordinator.swift`, `CloudSyncEngine.swift` (+5 extensions), `CloudSyncMerge.swift`, `CloudSyncShadow.swift`, `CloudSyncStatus.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 9.4 SyncedPlaylist (iCloud Playlist Mirror)
Lightweight CloudKit mirror of playlists (credentials + config only, not catalog data). Preserves UUID across devices. Fresh restore leaves `lastSyncDate == nil` so auto-sync pulls catalogs locally.
- **Files:** `SyncedPlaylist.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 9.5 Cloud Sync Launch / Initial Sync
Fresh-device handling: waits for initial iCloud sync before showing login form so cloud playlists arrive first. After restore, empty `apex.selectedPlaylistID` prefers **Xtream → M3U → Stalker → Stremio** (`preferredDefault`); progressive imports that pinned Stremio first are promoted when a never-synced catalog playlist arrives (Build 41).
- **Files:** `CloudSyncLaunchView.swift`, `PlaylistSwitcher.swift`, `MainTabView.swift` (`settleDefaultPlaylistSelection`)
- **Status:** Core — **Decision:** ✅ Keep

### 9.6 Recovery of Interrupted Syncs
On launch, resets any playlist or EPG source left in `.syncing` state by a previous crashed session.
- **Files:** `ContentSyncManager.swift`, `EPGSyncManager.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 10. Downloads

### 10.1 Offline Downloads
Download movies and episodes for offline playback via URLSession background downloads. Configurable concurrency (1-5). **Currently premium-gated.**
- **Files:** `DownloadManager.swift`, `DownloadButton.swift`, `DownloadsView.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 10.2 Auto-Delete Downloads After Watching
Optionally remove local file when content is marked watched.
- **Files:** `DownloadManager.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 10.3 Download Speed/ETA Display
Shows download speed and estimated time remaining for active downloads.
- **Files:** `DownloadManager.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

---

## 11. Home Screen

### 11.1 Hero Carousel
Full-bleed TMDB backdrop carousel on Home: trending movies/series with artwork, title logo, overview. Auto-rotates every 6s with horizontal paging. Matches library by TMDB id or cleaned title; falls back to library artwork when trending overlap is thin. iPhone: inline carousel. iPad/tvOS: immersive full-screen backdrop.
- **Files:** `HomeHeroController.swift`, `HomeHeroArtworkPager.swift`, `HomeHeroBuilder.swift`, `HomeHeroCarousel.swift`, `HomeImmersiveHomeScreen.swift`, `HeroItem.swift`, `HeroInfo.swift`, `HeroPageIndicator.swift`, `HomeMediaItem.swift`, `HomeView.swift`, `TVHomeScreen.swift`, `TVHomeFold.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 11.2 Home Content Rows (User-Configurable)
Reorderable, toggleable horizontal content rails: Recently Watched, Favorites, For You, Trending Movies, Trending Series, Trakt Watchlist. Order/visibility configurable in Settings → Layout → Home (iOS/macOS) or Settings → Home (tvOS). **Recently Watched Includes** (Build 41): independently include Movies, Series, and/or Live Channels (all on by default; per-device `@AppStorage`, not iCloud).
- **Files:** `HomeView.swift`, `HomeRows.swift`, `HomeLayoutSettings.swift` (`RecentlyWatchedIncludeSettings`), `HomeLayoutSettingsView.swift`, `SettingsView+TVHome.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 11.3 For You Row (AI Recommendations)
Personalized recommendations on-device. Primary path: embedding vectors + cosine similarity (iPhone/iPad/Mac after indexing). Fallback path: genre overlap + TMDB similar-title ids when embeddings unavailable (tvOS). Requires Premium + at least one watch/favorite/vote signal.
- **Files:** `RecommendationEngine.swift`, `RecommendationMetadataRanker.swift`, `RecommendationScoring.swift`, `RecommendationCacheStore.swift`, `RecommendationSettings.swift`, `HomeView.swift` (ForYouRow), `RecommendationVote.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 11.4 Trending Movies/Series Rows
Shows trending titles from TMDB that match content in the user's active playlist.
- **Files:** `HomeView.swift`, `TMDBClient.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 11.5 Trakt Watchlist Row
Displays connected Trakt account's watchlist on Home, matched to active playlist catalog. **Currently premium-gated.**
- **Files:** `HomeView.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

---

## 12. Search

### 12.1 Global Search
Search across movies, series, and live TV. Debounced keystrokes (300ms), background context fetches. Filter by type. Option to search all playlists or active only. Bounded results (50 per type).
- **Files:** `SearchView.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 12.2 Search Result Rows
Thumbnail + title + subtitle + type badge per result. Tappable to detail or play live channel.
- **Files:** `SearchView.swift` (SearchResultRow)
- **Status:** Core — **Decision:** ✅ Keep

---

## 13. Settings

### 13.1 General Settings View
Grouped list with sections for: Premium, Profiles, Playlists, Library, Layout, Search, Auto-Sync, EPG, Cloud Sync, Integrations, Playback, Downloads, Storage, Support, Developer debug.
- **Files:** `SettingsView.swift`, `SettingsView+Playlists.swift`, `SettingsView+Profiles.swift`, `SettingsView+Premium.swift`, `SettingsView+AutoSync.swift`, `SettingsView+Support.swift`, `SettingsView+TVComponents.swift`, `SettingsView+TVHome.swift`, `SettingsView+TVPlayer.swift`, `TVSettingsComponents.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 13.2 Content Management (Hide/Reorder)
PIN-gated UI to hide categories/channels, reorder categories and channels, reset ordering. Custom category names.
- **Files:** `ContentManagementView.swift`, `TVReorderableContentList.swift`, `ContentOrganizing.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 13.3 Storage & Cache Management
View on-device storage: image disk cache size, download files. Clear cache button.
- **Files:** `StorageManagementView.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 13.4 Cloud Sync Settings View
iCloud sync status (account status, last reconcile, errors). Troubleshooting info.
- **Files:** `CloudSyncSettingsView.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 13.5 Trakt Integration Settings
Connect/disconnect Trakt via device OAuth. Shows connection status, username. Import watched history button. **Currently premium-gated.**
- **Files:** `TraktIntegrationView.swift`, `TVTraktIntegrationView.swift`
- **Status:** Auxiliary (Premium) — **Decision:** ✅ Keep

### 13.6 Player Engine Priority Configuration
Reorder engine fallback list (KSPlayer, VLCKit, AVPlayer) via drag-and-drop.
- **Files:** `PlayerEnginePriorityView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 13.7 Credits / About Screen
Open-source credits, app version info, build details.
- **Files:** `CreditsView.swift`, `CreditsInfo.swift`, `SupportInfo.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 13.8 Sort Options (Categories and Content)
Per-tab sort options: Playlist Order, Name A-Z/Z-A, Newest/Oldest First. Persisted per tab. On iOS, the up/down button beside the Live TV category bar opens the reorder sheet directly in edit mode.
- **Files:** `SortOption.swift`, `SortMenu.swift`
- **Status:** Core — **Decision:** ✅ Keep

---

## 14. Premium / Monetization

### 14.1 PremiumManager (StoreKit 2)
In-app purchases: monthly subscription + lifetime unlock. Purchase flow, restore, transaction observation. Sideloaded builds auto-premium. Debug override.
- **Files:** `PremiumManager.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 14.2 Premium Feature Gating
Six gated features: Unlimited Playlists, Offline Downloads, Multiple Profiles, Trakt Integration, Smart Playback (autoplay/next episode; skip intro is free when enabled in Settings), For You Recommendations.
- **Files:** `PremiumFeature.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 14.3 Paywall UI
Full paywall sheet with feature benefits, plan buttons, redeem code, restore purchases, terms/privacy links.
- **Files:** `PaywallView.swift`, `PaywallModifier.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

---

## 15. AI / Indexing

### 15.1 On-Device Content Indexing
Background process indexing all movies/series: resolves TMDB ids, applies enrichment, computes embedding vectors via NLContextualEmbedding. Pauses during syncs and playback.
- **Files:** `ContentIndexer.swift`, `ContentIndexingService.swift`, `ContentIndexText.swift`, `TextEmbedder.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 15.2 NLP Embedding for Recommendations
Text embedding via NaturalLanguage framework. Builds textual document per title, generates mean-pooled embedding vector for taste matching.
- **Files:** `TextEmbedder.swift`, `RecommendationScoring.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

---

## 16. UI / Infrastructure

### 16.1 Deep Links
Custom `apex://` URL scheme: `apex://movie/{tmdbId}` and `apex://series/{tmdbId}`. Switches tab and pushes detail.
- **Files:** `DeepLink.swift`, `DeepLinkRouter.swift`, `MainTabView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 16.2 Image Caching (Two-Tier)
Memory cache (256 MB NSCache) + disk cache (Caches directory, SHA256-keyed). Purges on memory warnings and background.
- **Files:** `ImageCache.swift`, `ImagePipeline.swift`, `CachedAsyncImage.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 16.3 tvOS-Specific UI
Immersive Apple TV home with full-screen backdrop and fold-snapping scroll. Two-pane settings. Dedicated tvOS player overlay. Focus management for remote navigation.
- **Files:** `TVHomeScreen.swift`, `TVHomeFold.swift`, `TVMovieDetailView.swift`, `TVSeriesDetailView.swift`, `TVDetailComponents.swift`, `TVDetailButtons.swift`, `TVVideoCard.swift`, `TVAboutText.swift`, `TVPlaybackEngine.swift`, `KSTVPlaybackEngine.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 16.4 Platform-Adaptive Navigation
Conditional iOS/tvOS/macOS layouts via `#if os()`. Tab bar minimize on scroll (iOS), grouped form (macOS), full-screen immersive (tvOS).
- **Files:** `PlatformNavigationTitle.swift`, `GlassEffectCompat.swift`, `NavigationBehaviorCompat.swift`, `PosterCardMetrics.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 16.5 Library Toolbar
Shared toolbar for content tabs: playlist switcher, category sort, content sort, sync trigger, settings. Profile menu included.
- **Files:** `LibraryToolbar.swift`, `ProfileMenu.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 16.6 QR Code Display (tvOS)
QR code display for Trakt device-code authorization (tvOS has no web browser).
- **Files:** `QRCodeView.swift`
- **Status:** Auxiliary — **Decision:** ✅ Keep

### 16.7 Localization
Multi-language support via String Catalogs. English + German implemented. Scripts for xcstrings normalization.
- **Files:** `Assets.xcassets` (language strings), `normalize-xcstrings.swift`, `check-translations.swift`
- **Status:** Core — **Decision:** ✅ Keep

### 16.8 Preview Data
Shared preview data factory for SwiftUI previews across the app.
- **Files:** `PreviewData.swift`
- **Status:** Utility — **Decision:** ✅ Keep

### 16.9 Utility Files
Logging, gzip handling, credits info, app icon brand assets.
- **Files:** `Logger.swift`, `GzipFile.swift`, `CreditsInfo.swift`, `SupportInfo.swift`
- **Status:** Core Utility — **Decision:** ✅ Keep

---

## 17. New Features & Improvements

### 🔜 Manifest URL Support (NEW)
Add support for manifest-based URL sources in addition to Xtream/M3U/Stalker.
- **Status:** ⬜ Not started

### 🔜 EPG Guide Performance (IMPROVEMENT)
The EPG guide grid navigation and scrolling needs improvement — it's currently not smooth.
- **Files to investigate:** `EPGGuideView.swift`, `EPGTimeline.swift`, `EPGComponents.swift`
- **Status:** ⬜ Not started

### 🔜 Enhanced Metadata for VODs (IMPROVEMENT)
Show richer IMDb + TMDB data on VOD detail screens. Currently metadata enrichment focuses on Movies/Series — extend to VOD content.
- **Files to investigate:** `MovieDetailView.swift`, `ContentSyncManager+TMDB.swift`, `ContentSyncManager+OMDB.swift`
- **Status:** ⬜ Not started

### 🔜 Enhanced Metadata for Series (IMPROVEMENT)
Bring Series detail screen to parity with Movies — add the same IMDb/TMDB collection data, ratings chips, and cast richness.
- **Files to investigate:** `SeriesDetailView.swift`, `TVSeriesDetailView.swift`
- **Status:** ⬜ Not started

### 🔜 Mini Player / Inline Playback (NEW)
Persistent mini player that continues playing the current live TV stream while browsing channels, categories, or other tabs. The full-screen player state is extracted into a shared `@Observable` session so playback survives navigation. Mini view appears at the top/bottom of the channel list with play/pause, channel name, and close.
- **Files to investigate:** `FullScreenPlayerView.swift`, `LiveTVView.swift`, `MainTabView.swift`
- **Status:** ⬜ Not started

---

## Quick-Reference: Premium-Gated Features

| # | Feature | Decision |
|---|---------|----------|
| 14.1 | PremiumManager + StoreKit 2 IAP | ✅ Keep |
| 14.2 | Premium Feature Gating (6 gates) | ✅ Keep |
| 14.3 | Paywall UI | ✅ Keep |
| 5.7 | Autoplay Next Episode | ✅ Keep |
| 5.8 | Next Episode Button | ✅ Keep |
| 5.9 | Skip Intro / Skip Recap | ✅ Keep |
| 7.4 | Trakt Scrobbling | ✅ Keep |
| 7.5 | Trakt Watched History Import | ✅ Keep |
| 8.1 | User Profiles (Multi-Profile) | ✅ Keep |
| 8.2 | Profile Switching | ✅ Keep |
| 10.1 | Offline Downloads | ✅ Keep |
| 10.2 | Auto-Delete Downloads After Watching | ✅ Keep |
| 10.3 | Download Speed/ETA Display | ✅ Keep |
| 11.3 | For You AI Recommendations | ✅ Keep |
| 11.5 | Trakt Watchlist Home Row | ✅ Keep |
| 13.5 | Trakt Integration Settings | ✅ Keep |

---

## Summary

| Category | Keep | Rework | Strip | Total |
|---|---|---|---|---|
| Content Sources | 5 | 0 | 0 | 5 |
| Live TV | 7 | 0 | 0 | 7 |
| Movies | 4 | 1 | 0 | 5 |
| Series | 5 | 1 | 0 | 6 |
| Playback | 13 | 0 | 0 | 13 |
| EPG / Guide | 5 | 1 | 0 | 6 |
| Metadata & Enrichment | 9 | 0 | 0 | 9 |
| User Management | 5 | 0 | 0 | 5 |
| Sync & Cloud | 6 | 0 | 0 | 6 |
| Downloads | 3 | 0 | 0 | 3 |
| Home Screen | 5 | 0 | 0 | 5 |
| Search | 2 | 0 | 0 | 2 |
| Settings | 10 | 0 | 0 | 10 |
| Premium / Monetization | 3 | 0 | 0 | 3 |
| AI / Indexing | 2 | 0 | 0 | 2 |
| UI / Infrastructure | 9 | 0 | 0 | 9 |
| **Existing Total** | **93** | **3** | **0** | **96** |
| New Features (section 17) | — | — | — | 5 ⬜ |

### Items needing rework
1. **3.2 Movie Detail** — Add IMDb + TMDB collections data, improve VOD metadata display
2. **4.2 Series Detail** — Bring to parity with Movie detail (IMDb, TMDB, ratings)
3. **6.4 EPG Guide Grid** — Fix scrolling/performance issues

### New features to build
4. **Manifest URL support** — Add manifest-based content source type

---

*Last updated: July 20, 2026 (Build 46)*


---

## 2. Live TV

### 2.1 Live TV Channel Browsing
Category sidebar/rail + channel list with lazy loading. EPG now/next info on each channel card. Category search on iOS. The browse header shows the active playlist's visible channel count.
- **Files:** `LiveTVView.swift`, `LiveTVSection.swift`, `LiveTVTVComponents.swift`
- **Status:** Core
- **Decision:** keep

### 2.2 Channel Surfing (Next/Previous)
Navigate to adjacent channels within the current category from the player. Used by tvOS Siri Remote up/down.
- **Files:** `LiveChannelNavigator.swift`, `KSPlayerEngineView+TVChannels.swift`, `TVChannelBrowserOverlay.swift`
- **Status:** Core
- **Decision:** keep

### 2.3 Live Channel Recall (Last Channel)
Track current and previous live channel — "recall" button to jump back. Recent channels rail (up to 12). Profile-isolated.
- **Files:** `LiveChannelHistory.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 2.4 Catch-up / Timeshift
Play past programmes on live channels that support it (Xtream-only). Modelled as VOD (seekable, no live controls).
- **Files:** `PlayableMedia.swift` (catchup method), `XtreamClient.swift` (buildCatchupURL)
- **Status:** Core
- **Decision:** keep

### 2.5 Favorite Channels
Toggle channels as favorites from the player or channel list. Favorited channel rows show a filled red heart inline beside the channel name. Independent Favorites ordering.
- **Files:** `LiveStream.swift`, `PlayerFavorites.swift`
- **Status:** Core
- **Decision:** keep

### 2.6 Channel Management (Hide/Reorder)
Hide channels from browsing, reorder channels within categories, reorder Favorites list. Survives re-syncs.
- **Files:** `ChannelManagementView.swift`, `FavoriteChannelManagementView.swift`, `ContentOrganizing.swift`
- **Status:** Core
- **Decision:** keep

### 2.7 Recent Channels List
Recently Watched section in the Live TV rail.
- **Files:** Built into `LiveTVView.swift`
- **Status:** Core
- **Decision:** keep

---

## 3. Movies

### 3.1 Movie Browsing
Browse movies by category with preview rows, "Show All" per category, compact grid tiles for remaining categories, and an active-playlist movie count at the top. Smart collections (Recently Watched, Favorites, Recently Added). Favorited posters show a top-left heart without overlapping the top-right rating badge.
- **Files:** `MoviesView.swift`, `LibraryCollectionRows.swift`, `CategoryContentGrid.swift`
- **Status:** Core
- **Decision:** keep

### 3.2 Movie Detail Screen
Full-bleed backdrop hero, metadata line, Play/Resume and Start from Beginning buttons, expandable synopsis, cast row with photos, "You May Also Like", TMDB collection, "Other Sources", external ratings chips, trailer/video rows. Start from Beginning appears when resume progress exists.
- **Files:** `MovieDetailView.swift`, `TVMovieDetailView.swift`, `TVDetailComponents.swift`, `TVDetailButtons.swift`, `MediaDetailComponents.swift`, `ExternalRatingsView.swift`, `ExpandableText.swift`, `VideoComponents.swift`
- **Status:** Core
- **Decision:** Keep but I want to add the IMDM and TMDB Collections and show the data for the VODs

### 3.3 Movie Favorites
Mark movies as favorites with watchlist date. Drives the Favorites home row and the shared top-left poster badge across category grids, Home rails, collection rows, similar-title strips, and tvOS recommendation rails.
- **Files:** `Movie.swift`, `PlayerFavorites.swift`, `MovieCardView.swift`, `HomeRows.swift`, `PosterRatingBadge.swift`
- **Status:** Core
- **Decision:** keep

### 3.4 Watched / Unwatched Toggle for Movies
Toggle watched state from detail screen toolbar. Auto-deletes downloads when marked watched.
- **Files:** `MovieDetailView.swift`
- **Status:** Core
- **Decision:** keep

### 3.5 Movie Genre Browsing
Derive genres from TMDB/provider data and browse by genre.
- **Files:** `GenreBrowse.swift`, `Genre.swift`
- **Status:** Core
- **Decision:** keep

---

## 4. Series

### 4.1 Series Browsing
Browse series by category with preview rows, Recently Watched/Favorites/Recently Added collections, genre grid, and an active-playlist series count at the top. Favorited posters use the same top-left heart as movies.
- **Files:** `SeriesView.swift`, `LibraryCollectionRows.swift`
- **Status:** Core
- **Decision:** keep

### 4.2 Series Detail Screen
Backdrop hero, season/episode list, metadata, cast, trailers, "You May Also Like", similar titles.
- **Files:** `SeriesDetailView.swift`, `SeriesDetailViewPreviews.swift`, `TVSeriesDetailView.swift`
- **Status:** Core
- **Decision:** keep, I want to add the metadata and the IMDB and TMDB data like in Movies

### 4.3 Episode Management
Mark episodes watched/unwatched individually or in batch (mark all earlier/later). Episode context menus include Play from Beginning when saved progress exists, on iOS, macOS, and tvOS.
- **Files:** `Episode.swift`, `EpisodeCard.swift`, `EpisodeWatchedMenu.swift`
- **Status:** Core
- **Decision:** Keep

### 4.4 Series Favorites
Favorite series via detail screen or player controls. Favorite state drives the shared top-left badge across all series poster variants.
- **Files:** `Series.swift`, `PlayerFavorites.swift`, `SeriesCardView.swift`, `HomeRows.swift`, `PosterRatingBadge.swift`
- **Status:** Core
- **Decision:** Keep

### 4.5 Series Genre Browsing
Browse series by genre from TMDB enrichment and provider data.
- **Files:** `GenreBrowse.swift`, `Genre.swift`
- **Status:** Core
- **Decision:** Keep

### 4.6 Episode Fetching (Lazy)
Episode lists fetched on demand when the detail screen opens, not during initial sync.
- **Files:** `ContentSyncManager.swift` (fetchEpisodes), `ContentSyncManager+Stalker.swift` (fetchStalkerEpisodes)
- **Status:** Core
- **Decision:** Keep

---

## 5. Playback

### 5.1 Three Interchangeable Playback Engines
KSPlayer (default), VLCKit (fallback), AVPlayer (tertiary). User-configurable priority. Auto-fallback if one fails.
- **Files:** `PlayerSettings.swift`, `PlayerEngineOptions.swift`, `KSPlayerEngineView.swift` (+6 extensions), `VLCPlayerEngineView.swift`, `VLCPlayerCoordinator.swift` (+1 extension), `AVPlayerEngineView.swift`, `AVPlayerCoordinator.swift`
- **Status:** Core
- **Decision:** Keep

### 5.2 Player Controls Overlays
Three platform-appropriate control overlays with close, transport, scrubber, favorite toggle, live indicator. tvOS immersive overlay with channel surf, EPG, season rail, recent channels.
- **Files:** `KSPlayerControlsOverlay.swift`, `VLCPlayerControlsOverlay.swift`, `AVPlayerControlsOverlay.swift`, `TVPlayerControlsOverlay.swift` (+2), `TVPlayerPanels.swift`, `TVPlayerContent.swift`
- **Status:** Core
- **Decision:** Keep

### 5.3 Full-Screen Player
Cross-platform full-screen player. iOS/tvOS: fullScreenCover. macOS: separate WindowGroup. Drives media through engine priority list.
- **Files:** `FullScreenPlayerView.swift`, `TVPlaybackEngine.swift`, `KSTVPlaybackEngine.swift`
- **Status:** Core
- **Decision:** Keep

### 5.4 External Player Hand-off
Send streams to Infuse or VLC (external apps) via deep-link URL schemes.
- **Files:** `ExternalPlayer.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 5.5 PlayableMedia (Unified Playback Model)
Value-type description of anything playable, independent of SwiftData. Prioritizes local downloads over remote URLs.
- **Files:** `PlayableMedia.swift`
- **Status:** Core
- **Decision:** Keep

### 5.6 Watch Progress Recording
Buffers progress during playback to UserDefaults (avoids SwiftData hitches), flushes at safe boundaries. Recovers unflushed progress after crash.
- **Files:** `WatchProgressBuffer.swift`, `WatchProgressWriter.swift`
- **Status:** Core
- **Decision:** Keep

### 5.7 Autoplay Next Episode
Automatically starts next episode when current one finishes. **Currently premium-gated.**
- **Files:** `NextEpisodeResolver.swift`, `PlayerSettings.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 5.8 Next Episode Button
Shows focused "Next Episode" button near episode end (≥90%). **Currently premium-gated.**
- **Files:** `PlayerNextUpOverlay.swift`, `NextEpisodeResolver.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 5.9 Skip Intro / Skip Recap
Detects intro/recap segments via IntroDB crowd-sourced timestamps. Shows "Skip Intro" button when enabled in Settings (not Premium-gated; autoplay/next episode remain Premium).
- **Files:** `PlayerSkipIntroOverlay.swift`, `IntroSkipResolver.swift`, `IntroDBClient.swift`, `EpisodeSeriesResolver.swift`, `FullScreenPlayerView.swift`, `PlaybackClock.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 5.10 VLCKit Per-Engine Settings
Configurable VLC options: hardware decode, decode threads, skip/drop late frames, HTTP reconnect, deinterlace, buffer sizes, clock jitter.
- **Files:** `PlayerSettings.swift` (VLC namespace), `PlayerEngineSettingsViews.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 5.11 KSPlayer Per-Engine Settings
Configurable KSPlayer options: hardware decode, async decompression, primary engine, adaptive bitrate, deinterlace, auto-rotate, PiP, buffer presets.
- **Files:** `PlayerSettings.swift` (KSPlayer namespace), `PlayerEngineOptions.swift`, `PlayerEngineSettingsViews.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 5.12 Player Error/Retry UI
Loading indicator, error state with retry, video info overlay (codec/resolution/fps).
- **Files:** `PlayerLoadingIndicator.swift`, `PlayerErrorIndicator.swift`, `PlaybackRetryController.swift`, `PlayerVideoInfo.swift`, `PlaybackClock.swift`
- **Status:** Core
- **Decision:** ⬜

### 5.13 Video Codec/Format Info Overlay
Shows active codec, resolution, frame rate for the current stream.
- **Files:** `PlayerVideoInfo.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 5.14 Subtitle Appearance and Placement
Settings → Subtitles → Appearance controls Bottom/Center placement, size, color, background opacity, and bottom offset. Bottom placement respects platform safe areas and moves above visible player controls (iOS/iPadOS orientation-aware, macOS desktop controls, and the larger tvOS overlay); Center remains geometrically centered. Control visibility is shared across KSPlayer, VLCKit, and AVPlayer so external subtitles react consistently.
- **Files:** `OpenSubtitlesSettings.swift`, `OpenSubtitlesSettingsView.swift`, `ExternalSubtitleOverlay.swift`, `FullScreenPlayerView.swift`, `KSPlayerSubtitleOverlay.swift`, `KSPlayerEngineView.swift`, `VLCPlayerEngineView.swift`, `AVPlayerEngineView.swift`
- **Status:** Core
- **Decision:** Keep

---

## 6. EPG / TV Guide

### 6.1 EPG Source Management
Standalone XMLTV guide sources per playlist. Auto-created via reconciler. Users can add manual EPG URLs. Enable/disable individually.
- **Files:** `EPGSource.swift`, `EPGSourceReconciler.swift`, `EPGSettingsView.swift`
- **Status:** Core
- **Decision:** Keep

### 6.2 EPG Sync (Independent Pipeline)
Downloads XMLTV files, stream-parses with SAX parser, inserts only programmes for known channel IDs. Independent of content sync.
- **Files:** `EPGSyncManager.swift`, `EPGSyncService.swift`
- **Status:** Core
- **Decision:** Keep

### 6.3 EPG Now/Next on Channel Cards
Each channel card shows current and next programme from EPG.
- **Files:** `ChannelEPGSnapshot.swift`
- **Status:** Core
- **Decision:** Keep

### 6.4 EPG Guide Grid View
Full TV guide grid with timeline. Tappable programmes for detail/catch-up. List/Guide mode toggle.
- **Files:** `EPGGuideView.swift`, `EPGTimeline.swift`, `EPGProgramDetailView.swift`, `EPGComponents.swift`
- **Status:** Core
- **Decision:** Keep

### 6.5 EPG Programme Detail
Detail screen for a specific programme: title, description, times, Play Catch-up button.
- **Files:** `EPGProgramDetailView.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 6.6 Synced EPG Sources (iCloud)
Manual EPG sources synced across devices via CloudKit.
- **Files:** `SyncedEPGSource.swift`
- **Status:** Auxiliary
- **Decision:** Keep

---

## 7. Metadata & Enrichment

### 7.1 TMDB Metadata Enrichment
Fetches movie/series details: backdrop, logo, tagline, content rating, genres, cast, similar titles, collections, trailers, IMDB id. Cached 14 days. Trending feed for Home hero.
- **Files:** `TMDBClient.swift`, `ContentSyncManager+TMDB.swift`, `Movie.swift`, `Series.swift`, `CastMember.swift`, `TitleVideo.swift`, `ExternalRating.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 7.2 TMDB Language Watching
Detects language override changes, invalidates cached TMDB enrichment for re-fetch.
- **Files:** `TMDBLanguageWatcher.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 7.3 OMDb Ratings Enrichment
Fetches IMDb, Rotten Tomatoes, Metacritic scores. Rendered as colored chips on detail screens. Cached 14 days.
- **Files:** `OMDBClient.swift`, `ContentSyncManager+OMDB.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 7.4 Trakt Integration (Scrobbling)
Device OAuth connect/disconnect. Syncs watched state to Trakt. Shows Trakt watchlist on Home. **Currently premium-gated.**
- **Files:** `TraktService.swift`, `TraktClient.swift`, `TraktTokenStore.swift`, `TraktWatchedImporter.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 7.5 Trakt Watched History Import
Imports Trakt watched history into local catalog, marking matching movies/episodes as watched. **Currently premium-gated.**
- **Files:** `TraktWatchedImporter.swift`, `TraktService.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 7.6 "You May Also Like" / Similar Titles
Shows similar titles from TMDB on movie/series detail screens.
- **Files:** Built into `MovieDetailView.swift`, `SeriesDetailView.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 7.7 TMDB Collection Section
Shows other movies in the same TMDB collection on detail screens.
- **Files:** Built into `MovieDetailView.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 7.8 "Other Sources" Section
Shows the same title from other playlists, allowing cross-playlist playback.
- **Files:** `OtherSources.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 7.9 YouTube Trailer / Video Playback
Opens YouTube trailers and videos in YouTube app or browser. Fallback URL schemes on tvOS.
- **Files:** `TitleVideo.swift`, `VideoComponents.swift`
- **Status:** Auxiliary
- **Decision:** Keep

---

## 8. User Management

### 8.1 User Profiles (Multi-Profile)
Named profiles with customizable avatar (SF Symbol) and color tint. Separate watch history, progress, favorites, recommendation votes per profile. **Currently premium-gated.**
- **Files:** `UserProfile.swift`, `ProfileManager.swift`, `ActiveProfileStore.swift`, `ProfileSettings.swift`, `ProfileSelectionView.swift`, `ManageProfilesView.swift`, `ProfileEditorView.swift`, `ProfileAvatarView.swift`, `ProfileMenu.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 8.2 Profile Switching
Switch active profile with catalog re-projection (content state re-reads from new profile's records).
- **Files:** `ProfileManager.swift`, `CloudSyncEngine+Profiles.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** Keep

### 8.3 Parental Controls (PIN)
Optional 4-digit PIN stored in keychain. Required to leave child profile or access Content Management.
- **Files:** `ParentalControls.swift`, `ParentalControlsStore.swift`, `ContentRestriction.swift`, `ParentalGateView.swift`, `PINEntryViews.swift`, `PINPadView.swift`
- **Status:** Auxiliary
- **Decision:** Keep

### 8.4 Content Restriction (Child Profiles)
When child profile is active, restricted categories and their content are hidden from browsing, Home, and Search.
- **Files:** `ContentRestriction.swift`, `Category.swift`, `ParentalControlsSettings.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 8.5 UserContentState (Per-Profile Cloud State)
CloudKit-synced per-content user state: watch progress, watched flag, favorites, watchlist dates, recommendation votes. Keyed by profile ID.
- **Files:** `UserContentState.swift`
- **Status:** Auxiliary
- **Decision:** keep
---

## 9. Sync & Cloud

### 9.1 Content Sync (Playlist Catalog)
Actor-based background sync for Xtream, M3U, Stalker. Downloads catalogs in batches, upserts into SwiftData, prunes stale items. Stalker imports page 1 of every VOD/series category during visible sync and loads remaining pages 2–20 for all categories afterward at utility priority. Cancellable with progress reporting.
- **Files:** `ContentSyncManager.swift`, `ContentSyncManager+Helpers.swift`, `ContentSyncManager+M3U.swift`, `ContentSyncManager+Stalker.swift`, `SyncProgress.swift`, `SyncFrequency.swift`
- **Status:** Core
- **Decision:** keep

### 9.2 Auto-Sync on Launch/Foreground/Add
Playlists sync automatically on launch, playlist add, foreground return, and playlist switch. Configurable frequency (hourly, daily, weekly, manual). Catalog providers (Xtream / M3U / Stalker) enqueue ahead of Stremio. On tvOS, first-time syncs (`lastSyncDate == nil`) always present the sync cover; routine refreshes still defer when browsing Home (Build 41).
- **Files:** `MainTabView.swift`, `SyncProgressView.swift`, `SettingsView+AutoSync.swift`, `PlaylistSwitcher.swift` (`orderedForAutoSync`)
- **Status:** Core
- **Decision:** keep

### 9.3 iCloud Sync (CloudKit)
Two-container architecture: local catalog store + CloudKit user data store. Three-way merge reconcile engine. Account status detection, initial sync gate, background reconciliation.
- **Files:** `CloudSyncCoordinator.swift`, `CloudSyncEngine.swift` (+5 extensions), `CloudSyncMerge.swift`, `CloudSyncShadow.swift`, `CloudSyncStatus.swift`
- **Status:** Core
- **Decision:** keep

### 9.4 SyncedPlaylist (iCloud Playlist Mirror)
Lightweight CloudKit mirror of playlists (credentials + config only, not catalog data). Preserves UUID across devices. Fresh restore leaves `lastSyncDate == nil` so auto-sync pulls catalogs locally.
- **Files:** `SyncedPlaylist.swift`
- **Status:** Core
- **Decision:** keep

### 9.5 Cloud Sync Launch / Initial Sync
Fresh-device handling: waits for initial iCloud sync before showing login form so cloud playlists arrive first. After restore, empty `apex.selectedPlaylistID` prefers **Xtream → M3U → Stalker → Stremio** (`preferredDefault`); progressive imports that pinned Stremio first are promoted when a never-synced catalog playlist arrives (Build 41).
- **Files:** `CloudSyncLaunchView.swift`, `PlaylistSwitcher.swift`, `MainTabView.swift` (`settleDefaultPlaylistSelection`)
- **Status:** Core
- **Decision:** keep

### 9.6 Recovery of Interrupted Syncs
On launch, resets any playlist or EPG source left in `.syncing` state by a previous crashed session.
- **Files:** `ContentSyncManager.swift`, `EPGSyncManager.swift`
- **Status:** Core
- **Decision:** keep

---

## 10. Downloads

### 10.1 Offline Downloads
Download movies and episodes for offline playback via URLSession background downloads. Configurable concurrency (1-5). **Currently premium-gated.**
- **Files:** `DownloadManager.swift`, `DownloadButton.swift`, `DownloadsView.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

### 10.2 Auto-Delete Downloads After Watching
Optionally remove local file when content is marked watched.
- **Files:** `DownloadManager.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

### 10.3 Download Speed/ETA Display
Shows download speed and estimated time remaining for active downloads.
- **Files:** `DownloadManager.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

---

## 11. Home Screen

### 11.1 Hero Carousel
Full-bleed TMDB backdrop carousel on Home: trending movies/series with artwork, title logo, overview. Auto-rotates every 6s with horizontal paging. Matches library by TMDB id or cleaned title; falls back to library artwork when trending overlap is thin. iPhone: inline carousel. iPad/tvOS: immersive full-screen backdrop.
- **Files:** `HomeHeroController.swift`, `HomeHeroArtworkPager.swift`, `HomeHeroBuilder.swift`, `HomeHeroCarousel.swift`, `HomeImmersiveHomeScreen.swift`, `HeroItem.swift`, `HeroInfo.swift`, `HeroPageIndicator.swift`, `HomeMediaItem.swift`, `HomeView.swift`, `TVHomeScreen.swift`, `TVHomeFold.swift`
- **Status:** Core
- **Decision:** keep

### 11.2 Home Content Rows (User-Configurable)
Reorderable, toggleable horizontal content rails: Recently Watched, Favorites, For You, Trending Movies, Trending Series, Trakt Watchlist. Order/visibility configurable in Settings → Layout → Home (iOS/macOS) or Settings → Home (tvOS). **Recently Watched Includes** (Build 41): independently include Movies, Series, and/or Live Channels (all on by default; per-device `@AppStorage`, not iCloud).
- **Files:** `HomeView.swift`, `HomeRows.swift`, `HomeLayoutSettings.swift` (`RecentlyWatchedIncludeSettings`), `HomeLayoutSettingsView.swift`, `SettingsView+TVHome.swift`
- **Status:** Core
- **Decision:** keep

### 11.3 For You Row (AI Recommendations)
Personalized recommendations on-device. Primary path: embedding vectors + cosine similarity (iPhone/iPad/Mac after indexing). Fallback path: genre overlap + TMDB similar-title ids when embeddings unavailable (tvOS). Requires Premium + at least one watch/favorite/vote signal.
- **Files:** `RecommendationEngine.swift`, `RecommendationMetadataRanker.swift`, `RecommendationScoring.swift`, `RecommendationCacheStore.swift`, `RecommendationSettings.swift`, `HomeView.swift` (ForYouRow), `RecommendationVote.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

### 11.4 Trending Movies/Series Rows
Shows trending titles from TMDB that match content in the user's active playlist.
- **Files:** `HomeView.swift`, `TMDBClient.swift`
- **Status:** Core
- **Decision:** keep

### 11.5 Trakt Watchlist Row
Displays connected Trakt account's watchlist on Home, matched to active playlist catalog. **Currently premium-gated.**
- **Files:** `HomeView.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

---

## 12. Search

### 12.1 Global Search
Search across movies, series, and live TV. Debounced keystrokes (300ms), background context fetches. Filter by type. Option to search all playlists or active only. Bounded results (50 per type).
- **Files:** `SearchView.swift`
- **Status:** Core
- **Decision:** keep

### 12.2 Search Result Rows
Thumbnail + title + subtitle + type badge per result. Tappable to detail or play live channel.
- **Files:** `SearchView.swift` (SearchResultRow)
- **Status:** Core
- **Decision:** keep

---

## 13. Settings

### 13.1 General Settings View
Grouped list with sections for: Premium, Profiles, Playlists, Library, Layout, Search, Auto-Sync, EPG, Cloud Sync, Integrations, Playback, Downloads, Storage, Support, Developer debug.
- **Files:** `SettingsView.swift`, `SettingsView+Playlists.swift`, `SettingsView+Profiles.swift`, `SettingsView+Premium.swift`, `SettingsView+AutoSync.swift`, `SettingsView+Support.swift`, `SettingsView+TVComponents.swift`, `SettingsView+TVHome.swift`, `SettingsView+TVPlayer.swift`, `TVSettingsComponents.swift`
- **Status:** Core
- **Decision:** keep

### 13.2 Content Management (Hide/Reorder)
PIN-gated UI to hide categories/channels, reorder categories and channels, reset ordering. Custom category names.
- **Files:** `ContentManagementView.swift`, `TVReorderableContentList.swift`, `ContentOrganizing.swift`
- **Status:** Core
- **Decision:** keep

### 13.3 Storage & Cache Management
View on-device storage: image disk cache size, download files. Clear cache button.
- **Files:** `StorageManagementView.swift`
- **Status:** Core
- **Decision:** keep

### 13.4 Cloud Sync Settings View
iCloud sync status (account status, last reconcile, errors). Troubleshooting info.
- **Files:** `CloudSyncSettingsView.swift`
- **Status:** Core
- **Decision:** keep

### 13.5 Trakt Integration Settings
Connect/disconnect Trakt via device OAuth. Shows connection status, username. Import watched history button. **Currently premium-gated.**
- **Files:** `TraktIntegrationView.swift`, `TVTraktIntegrationView.swift`
- **Status:** Auxiliary (Premium)
- **Decision:** keep

### 13.6 Player Engine Priority Configuration
Reorder engine fallback list (KSPlayer, VLCKit, AVPlayer) via drag-and-drop.
- **Files:** `PlayerEnginePriorityView.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 13.7 Credits / About Screen
Open-source credits, app version info, build details.
- **Files:** `CreditsView.swift`, `CreditsInfo.swift`, `SupportInfo.swift`
- **Status:** Core
- **Decision:** keep

### 13.8 Sort Options (Categories and Content)
Per-tab sort options: Playlist Order, Name A-Z/Z-A, Newest/Oldest First. Persisted per tab. On iOS, the up/down button beside the Live TV category bar opens the reorder sheet directly in edit mode.
- **Files:** `SortOption.swift`, `SortMenu.swift`
- **Status:** Core
- **Decision:** keep

---

## 14. Premium / Monetization

### 14.1 PremiumManager (StoreKit 2)
In-app purchases: monthly subscription + lifetime unlock. Purchase flow, restore, transaction observation. Sideloaded builds auto-premium. Debug override.
- **Files:** `PremiumManager.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 14.2 Premium Feature Gating
Six gated features: Unlimited Playlists, Offline Downloads, Multiple Profiles, Trakt Integration, Smart Playback (autoplay/next episode; skip intro is free when enabled in Settings), For You Recommendations.
- **Files:** `PremiumFeature.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 14.3 Paywall UI
Full paywall sheet with feature benefits, plan buttons, redeem code, restore purchases, terms/privacy links.
- **Files:** `PaywallView.swift`, `PaywallModifier.swift`
- **Status:** Auxiliary
- **Decision:** keep

---

## 15. AI / Indexing

### 15.1 On-Device Content Indexing
Background process indexing all movies/series: resolves TMDB ids, applies enrichment, computes embedding vectors via NLContextualEmbedding. Pauses during syncs and playback.
- **Files:** `ContentIndexer.swift`, `ContentIndexingService.swift`, `ContentIndexText.swift`, `TextEmbedder.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 15.2 NLP Embedding for Recommendations
Text embedding via NaturalLanguage framework. Builds textual document per title, generates mean-pooled embedding vector for taste matching.
- **Files:** `TextEmbedder.swift`, `RecommendationScoring.swift`
- **Status:** Auxiliary
- **Decision:** keep

---

## 16. UI / Infrastructure

### 16.1 Deep Links
Custom `lume://` URL scheme: `lume://movie/{tmdbId}` and `lume://series/{tmdbId}`. Switches tab and pushes detail.
- **Files:** `DeepLink.swift`, `DeepLinkRouter.swift`, `MainTabView.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 16.2 Image Caching (Two-Tier)
Memory cache (256 MB NSCache) + disk cache (Caches directory, SHA256-keyed). Purges on memory warnings and background.
- **Files:** `ImageCache.swift`, `ImagePipeline.swift`, `CachedAsyncImage.swift`
- **Status:** Core
- **Decision:** keep

### 16.3 tvOS-Specific UI
Immersive Apple TV home with full-screen backdrop and fold-snapping scroll. Two-pane settings. Dedicated tvOS player overlay. Focus management for remote navigation.
- **Files:** `TVHomeScreen.swift`, `TVHomeFold.swift`, `TVMovieDetailView.swift`, `TVSeriesDetailView.swift`, `TVDetailComponents.swift`, `TVDetailButtons.swift`, `TVVideoCard.swift`, `TVAboutText.swift`, `TVPlaybackEngine.swift`, `KSTVPlaybackEngine.swift`
- **Status:** Core
- **Decision:** keep

### 16.4 Platform-Adaptive Navigation
Conditional iOS/tvOS/macOS layouts via `#if os()`. Tab bar minimize on scroll (iOS), grouped form (macOS), full-screen immersive (tvOS).
- **Files:** `PlatformNavigationTitle.swift`, `GlassEffectCompat.swift`, `NavigationBehaviorCompat.swift`, `PosterCardMetrics.swift`
- **Status:** Core
- **Decision:** keep

### 16.5 Library Toolbar
Shared toolbar for content tabs: playlist switcher, category sort, content sort, sync trigger, settings. Profile menu included.
- **Files:** `LibraryToolbar.swift`, `ProfileMenu.swift`
- **Status:** Core
- **Decision:** keep

### 16.6 QR Code Display (tvOS)
QR code display for Trakt device-code authorization (tvOS has no web browser).
- **Files:** `QRCodeView.swift`
- **Status:** Auxiliary
- **Decision:** keep

### 16.7 Localization
Multi-language support via String Catalogs. English + German implemented. Scripts for xcstrings normalization.
- **Files:** `Assets.xcassets` (language strings), `normalize-xcstrings.swift`, `check-translations.swift`
- **Status:** Core
- **Decision:** keep

### 16.8 Preview Data
Shared preview data factory for SwiftUI previews across the app.
- **Files:** `PreviewData.swift`
- **Status:** Utility
- **Decision:** keep

### 16.9 Utility Files
Logging, gzip handling, credits info, app icon brand assets.
- **Files:** `Logger.swift`, `GzipFile.swift`, `CreditsInfo.swift`, `SupportInfo.swift`
- **Status:** Core Utility
- **Decision:** keep

---

## Quick-Reference: Premium-Gated Features ( need to review)

These are the features currently locked behind the StoreKit 2 paywall. Each one needs an explicit decision.

| # | Feature | Decision |
|---|---------|----------|
| 14.1 | PremiumManager + StoreKit 2 IAP | ⬜ |
| 14.2 | Premium Feature Gating (6 gates) | ⬜ |
| 14.3 | Paywall UI | ⬜ |
| 5.7 | Autoplay Next Episode | ⬜ |
| 5.8 | Next Episode Button | ⬜ |
| 5.9 | Skip Intro / Skip Recap | ⬜ |
| 7.4 | Trakt Scrobbling | ⬜ |
| 7.5 | Trakt Watched History Import | ⬜ |
| 8.1 | User Profiles (Multi-Profile) | ⬜ |
| 8.2 | Profile Switching | ⬜ |
| 10.1 | Offline Downloads | ⬜ |
| 10.2 | Auto-Delete Downloads After Watching | ⬜ |
| 10.3 | Download Speed/ETA Display | ⬜ |
| 11.3 | For You AI Recommendations | ⬜ |
| 11.5 | Trakt Watchlist Home Row | ⬜ |
| 13.5 | Trakt Integration Settings | ⬜ |

---

## Summary Stats

| Category | Core | Auxiliary | Total |
|---|---|---|---|
| Content Sources | 5 | 0 | 5 |
| Live TV | 6 | 1 | 7 |
| Movies | 5 | 0 | 5 |
| Series | 6 | 0 | 6 |
| Playback | 6 | 7 | 13 |
| EPG / Guide | 4 | 2 | 6 |
| Metadata & Enrichment | 0 | 9 | 9 |
| User Management | 0 | 5 | 5 |
| Sync & Cloud | 6 | 0 | 6 |
| Downloads | 0 | 3 | 3 |
| Home Screen | 4 | 1 | 5 |
| Search | 2 | 0 | 2 |
| Settings | 8 | 2 | 10 |
| Premium / Monetization | 0 | 3 | 3 |
| AI / Indexing | 0 | 2 | 2 |
| UI / Infrastructure | 6 | 3 | 9 |
| **Total** | **58** | **38** | **96** |

---
I would like to add the option for mainfeast URL support. Also with this app I have notice the EPG guide navagation and scrolling needs improvement its not smooth
*Use this document to mark your decisions, then we'll execute them systematically.*
