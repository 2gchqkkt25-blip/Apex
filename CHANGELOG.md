# Changelog

All notable changes to Apex Stream Player.

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
