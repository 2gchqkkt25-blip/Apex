# EPG (TV Guide) — Architecture Notes

> Last updated: **July 15, 2026 (Build 41)**  
> Status: **Generic providers** — offset-honest `xmltv.php` bulk sync works. **StreamInfinity test panel** — 14 external epgshare01 feeds + structural West/Pacific `+3h` insert + **single-pass parse** + **playlist-bundled fast sync**. Browse persist + warm live cache (Build 41) so the guide no longer needs a manual Sync Now after gap-fill. See § "StreamInfinity panel — status" below.

## StreamInfinity panel — status (July 7, 2026 — evening update)

**Status: ✅ Working — expanded external sources + safe West/Pacific offset**

### What works now
- ✅ EPG data loads in both List and Grid views
- ✅ No freezing when switching categories
- ✅ External EPG sources (14 epgshare01 feeds: US1/US2/Locals 1-4/Sports/Movies/UK1/UK2/CA1/CA2/IE1/AU1) provide CURRENT, accurate data
- ✅ Display-name fuzzy matching maps external EPG channels to provider streams
- ✅ Major channels (HBO Drama, ESPN, ABC, FOX, etc.) show correct current titles
- ✅ Store-first approach; live-API gap-fill **only for channels with zero store rows** (Jul 7 late — fixes multi-minute post-sync delay)
- ✅ **Browse gap-fill persists on every platform** and warm live cache paints UI after `forceGuideRefresh` (Jul 15 / Build 41 — fixes blank guide until resync on iOS)
- ✅ **iOS guide scroll** — details via context menu; long-press only on tvOS (Jul 15 / Build 41)
- ✅ **Network West/Pacific variants populated via structural `+3h` insert** — accepts `hbowest.us ↔ hbo.us`, `tbswest.us ↔ tbs.us`, `fyiwest.us ↔ fyi.us`; rejects cross-network (`mtv2west.us ↔ mtv.us`) and cross-affiliate (`abcktrkhoustontx.us ↔ abcwsbatlantaga.us`) false positives
- ✅ **Playlist refresh includes TV guide** in one branded sync screen with **% progress** on the guide step (Jul 7 late)
- ✅ **Guide data persists across app restarts** — stored locally in SwiftData (`EPGListing`); no manual re-sync needed to see programmes again

### What doesn't work yet
- ❌ Local-affiliate West variants (KOVR, KTRK, KTLA, etc.) — external EPG covers only the national feed, not per-station schedules; these fall through to per-channel API gap-fill
- ❌ Channels with no external EPG match AND no `epg_channel_id` — nothing to key against; live-API only

### Root cause (confirmed July 7 with curl)
- Provider's `xmltv.php` is 8 days stale (June 29 - July 2 data)
- Provider's `get_short_epg` is equally stale
- Other apps (Dion, Chilli) use **external EPG services** (epgshare01.online) that have current data
- They match channels by display name, not by `epg_channel_id`
- Confirmed: `epgshare01/epg_ripper_US2.xml.gz` has "The Batman" on HBO Drama at the correct time while provider's xmltv.php has "Bang My Box" (from 8 days ago)

### Architecture (current — July 7 late evening)

**Two EPG sync modes (`EPGSyncMode`):**

| Mode | When | Feeds | Behaviour |
|------|------|-------|-----------|
| **`.withPlaylist`** | Playlist refresh / auto-sync cover | US-only (8) | Single-pass parse; stop at **≥88%** channel coverage; skip `US_LOCALS1` at **≥75%**; live **%** in sync UI |
| **`.full`** | Settings → Sync Now | All 14 regional | Full coverage pass; same single-pass parser |

**Pipeline:**
1. **Playlist sync** → content steps → **`epgGuide`** step → `EPGSyncService.syncAwaiting(mode: .withPlaylist)` → external epgshare01 feeds → display-name match → insert with real timestamps → West/Pacific `+3h` copies.
2. **Settings → Sync Now** → same manager with **`mode: .full`** (includes UK/CA/IE/AU feeds).
3. **App launch** → guide loads **immediately from local SwiftData** → `syncIfDue()` in background if stale (default: daily), deferred 90 s (iOS) / 60 s (tvOS) so Home paints first.
4. **Browse** → `programsFromStore` (background thread) → live API **only if store is empty for that channel** → show cards/grid.

Provider's own `xmltv.php` only used as fallback if external EPG download fails entirely.

### West/Pacific structural matching (rule)

`EPGChannelCatalog.fromExternalEPG` pairs an unmatched West/Pacific stream to a matched East stream **only when both hold**:

1. West stream's `name.lowercased()` contains `"west"` or `"pacific"` (cheap filter).
2. West stream's `epgChannelId` (minus TLD via `\.[a-z]{2,4}$`) literally contains a `west`/`pacific` token, and stripping that token yields a string that exactly equals a matched East stream's `epgChannelId` (minus TLD).

Examples:
| Case | East ID | West ID | West-stripped | Verdict |
|---|---|---|---|---|
| Network west feed | `hbo.us` | `hbowest.us` | `hbo` | ✅ accepted |
| Network west feed | `tbs.us` | `tbswest.us` | `tbs` | ✅ accepted |
| Cross-network (MTV vs MTV2) | `mtv.us` | `mtv2west.us` | `mtv2` | ❌ rejected |
| Cross-affiliate (WSB vs KTRK) | `abcwsbatlantaga.us` | `abcktrkhoustontx.us` | (no `west` in ID) | ❌ rejected |
| Local station (KOVR) | any CBS East | `cbskovrstocktonsacramentoca.us` | (no `west` in ID) | ❌ rejected |

**Name-based matching for this purpose is banned.** Network prefixes (`cbs`, `abc`, `mtv`, ...) collapse too many unrelated local affiliates once name normalisation is applied. The provider-issued `epgChannelId` is stable and unambiguous — use it as the source of truth for structural pairing.

### Normalizer scope (July 7 evening revision)

`EPGNameNormalizer.normalize` strips:
- Quality tokens: `hd`, `fhd`, `uhd`, `4k`, `sd`, `hevc`, `h265`, `h.265`
- Country codes / TLD suffixes: `us`, `usa`, `uk`, `gb`, `ca`, `au`, `nz`, `ie`, `de`, `fr`, `es`, `it`, `nl`, `pt`, `br`, `mx`, `ar`, `in`, `ph`, `tr`, `pl`, `ro`, `se`, `no`, `dk`, `fi`

It **intentionally does NOT strip** region words (`east`, `eastern`, `atlantic`, `central`, `mountain`, `west`, `pacific`, `feed`). Stripping these was tried and reverted the same day — it collapsed distinct local affiliates ("ABC WSB Atlanta" and "ABC KTRK Houston" both to `abc`), which is exactly how bogus West/Pacific pairings appeared in the console. The east-feed matching case that motivated the strip is instead handled by epgshare01 publishing multiple `<display-name>` entries per channel row (e.g. both `HBO` and `HBO East`) and by the fuzzy `namesMatch` substring fallback.

### What to fix next session
1. **Local-affiliate West/Pacific channels** (KOVR, KTRK, KTLA, ...) — external EPG doesn't ship per-affiliate schedules; live-API gap-fill only when store is empty.
2. ~~**Trim external feeds by observed match rate**~~ — **partially done (Jul 7 late):** bundled mode skips `US_LOCALS1` at 75% coverage and stops at 88%; full mode still runs all 14. Log per-feed insert counts to tune further.
3. **Consider paid EPG service** — EPG.best ($5/month) for per-affiliate West/Pacific schedules. Plumbing exists via `EPGSettingsView → Add EPG Source`.

---

## Parse speed (July 7 late evening)

**Problem:** Each external feed was parsed twice (channel pass + programme pass). All 14 feeds ran sequentially during playlist sync with no meaningful progress reporting. `US_LOCALS1` (~550 MB) ran even when national feeds already matched most channels.

**Fixes:**

| Change | File | Effect |
|--------|------|--------|
| **`importExternalEPG` single-pass SAX** | `XtreamClient.swift` | ~50% less XML I/O per feed |
| **Name-filtered channel table** | `XMLTVExternalEPGImporter` | Skips unrelated channels in huge files |
| **US-first feed order** | `ExternalEPGSources.swift` | Guide fills from US2/US1/Sports/Movies first |
| **`urlsForBundledSync()`** | `ExternalEPGSources.swift` | Playlist sync: 8 US feeds, not 14 |
| **Early stop at 88% coverage** | `EPGSyncManager.syncExternalEPG` | Bundled mode exits when enough channels matched |
| **Skip `US_LOCALS1` at 75%** | `EPGSyncManager` | Avoids 550 MB parse when yield is low |
| **Mid-sync `refreshGeneration`** | `EPGSyncService.signalGuideRefreshDuringSync` | Grid/cards update every ~5 s during sync |
| **`.userInitiated` parse priority** | `EPGSyncManager` detached task | Parser gets more CPU during active sync |
| **Per-channel insert cap (16)** | external import path | Aligns with `EPGRetention.maxListingsPerChannel` |
| **Live progress callbacks** | `syncExternalEPG` → `EPGSyncService` | Feed index + matched channel count → sync UI **%** |

**Console signatures (parse speed):**
```
EPG trying 8 external EPG source(s) (mode: bundled)
EPG external source matched N channel IDs … (single-pass, M/T programmes)
EPG skipping heavy external source — coverage X/Y
EPG bundled sync complete early — X/Y channels matched
```

---

## Playlist sync + branded UI (July 7 late evening)

**`SyncProgressView`** is now a full-screen Apex-branded experience:
- **`ApexBrandColors`** — logo-matched electric blue (`#0070FF`) → purple (`#A020F0`) gradient
- **`ApexSyncHero`** — animated peak mark + progress ring
- Final step **`epgGuide`** ("TV guide") with **bold %**, feed label (`US National 2 (2/8)`), and channel counts
- Xtream / M3U / Stalker: content steps + guide. Stremio: guide step omitted (no live EPG pipeline).

**After guide step:** `forceGuideRefresh()` bumps `refreshGeneration` so Live TV reads fresh store data before the sync sheet dismisses.

**Key files:** `SyncProgressView.swift`, `ApexSyncBrandView.swift`, `ApexBrandColors.swift`, `SyncProgress.swift` (`.epgGuide` step).

---

## Local persistence (survives app restart)

- **`EPGListing`** rows are stored in the **local catalog SwiftData store** (`default.store`) — **not** CloudKit-synced.
- Closing and reopening the app **does not wipe the guide**. Live TV / EPG grid read from disk immediately.
- Programmes that have ended are pruned on launch (`pruneExpiredListings`).
- Background refresh: `EPGSyncService.syncIfDue()` on launch (if due per Settings → EPG frequency, default **daily**) and when opening the Live TV tab.
- **Manual re-sync is optional** — use playlist refresh (content + guide together) or Settings → Sync Now for a full 14-feed pass.

---

### Files modified during July 7 late evening session (parse speed + playlist sync)
- `XtreamClient.swift` — `importExternalEPG`, `XMLTVExternalEPGImporter` (single-pass SAX)
- `ExternalEPGSources.swift` — US-first order, `urlsForBundledSync()`, `urlsForFullSync()`
- `EPGSyncManager.swift` — `EPGSyncMode`, progress callbacks, bundled early stop, single-pass external import
- `EPGSyncService.swift` — `syncAwaiting(mode:)`, `updateSyncProgress`, `forceGuideRefresh`, `signalGuideRefreshDuringSync`
- `EPGLiveLoader.swift` — `EPGBrowseLoader`: live API only when store empty for channel
- `SyncProgressView.swift` — branded UI, inline `epgGuide` step, % formatting
- `ApexSyncBrandView.swift`, `ApexBrandColors.swift` — logo-gradient sync shell
- `SyncProgress.swift` — `.epgGuide` step
- `ApexApp.swift` — deferred launch EPG (90 s iOS)
- `HomeHeroBuilder.swift`, `HomeView+Trending.swift` — first-launch Home perf (related; see `PROJECT_REFERENCE.md`)

### Files modified during July 7 evening session (cross-device parity)
- `MainTabView.swift` — kick `EPGSyncService.syncIfDue()` when Live TV tab is selected (all platforms)
- `SyncProgressView.swift` — ~~schedule `syncIfDue()` after content sync~~ **superseded:** inline guide step (Jul 7 late)
- `EPGSyncService.swift` — sync timeout 1 200 → 3 600 s for 14-feed external download
- `TVChannelBrowserOverlay.swift` — watch `refreshGeneration` to refresh now-titles + focused guide after Sync Now
- `TVPlayerControlsOverlay.swift` — watch `refreshGeneration` to refresh live now/next caption after Sync Now

### Files modified during July 7 evening session (coverage + West/Pacific)
- `ExternalEPGSources.swift` — 3 → 14 built-in epgshare01 feeds (`US1/US2/Locals 1-4/Sports/Movies/UK1/UK2/CA1/CA2/IE1/AU1`)
- `EPGSyncManager.swift` — West/Pacific `+3h` insert pass in `syncExternalEPG`'s parseProgrammes callback; captures `westMappings` into the detached task
- `EPGLiveLoader.swift` — `synchronousFetchCap` 12 → 24, `emptyTTL` 10 min → 3 min
- `Models/LiveStream+EPG.swift` — `EPGChannelCatalog.fromExternalEPG` rewritten to use structural `epgChannelId` matching (added `stripTLD` helper); `EPGNameNormalizer` expanded country-code list, reverted region-word strip

### Files modified during July 7 morning session (earlier)
- `ExternalEPGSources.swift` — NEW: built-in external EPG source URLs (initial 3-source US/UK/CA set)
- `EPGSyncManager.swift` — external EPG as primary source with display-name matching
- `EPGSyncService.swift` — rebuilt from documentation (was destroyed by git checkout)
- `EPGLiveLoader.swift` — store-first + live API gap-fill, makeChannelEPG prefer-upcoming logic
- `EPGInserter.swift` — diagnostic logging, preferred source filter, most-recent-day logic
- `LiveStream+EPG.swift` — `fromExternalEPG` catalog builder, `EPGChannelCatalog.register` lowercase collision fix, internal init
- `ApexApp.swift` — pruneExpiredListings restored

### Console log signatures
```
# External EPG working (14 feeds attempted)
EPG trying 14 external EPG source(s)
EPG external source downloaded — 72906892 bytes from https://epgshare01.online/epgshare01/epg_ripper_US2.xml.gz
EPG external source matched N channel IDs, M west/pacific offsets

# West/Pacific pairings (structural — should all be <base>west variants)
EPG WEST MAP: hbo.us → hbowest.us
EPG WEST MAP: tbs.us → tbswest.us
EPG WEST MAP: fyi.us → fyiwest.us
EPG external source inserted NNNN listings   # includes +3h shifted copies

# Live API for gaps (cap 24, not 12)
EPG live — channels with data: 24/24, airingOrUpcoming: 24
```

If you see `EPG WEST MAP` output pairing IDs that don't share a `<base>` prefix (`mtv.us → mtv2west.us`, or a west entry with no `west` token in the ID), the structural check in `EPGChannelCatalog.fromExternalEPG` has regressed. Rule 20 is the fix.

### Console log signatures
```
# Successful sync with shifted data
EPG insert done — matched: 95937, inserted: 9XXX, upcoming: 7XXX

# Live API working (per-channel, correct data)
EPG live — channels with data: 12/12, airingOrUpcoming: 12

# Stale data detection
EPG schedule probe — maxEndDeltaMin=-7XXX (anything < -120 means stale)
```

### Files modified during July 7 session
- `EPGLiveLoader.swift` — cache TTL fix (10min), preferGuideWindow shift, makeChannelEPG nearest-programme
- `EPGAPISync.swift` — parse without shift (live API uses preferGuideWindow)
- `EPGInserter.swift` — saveBuffers shift-to-today, removed early abort, removed stale-break
- `EPGSyncManager.swift` — M3U discovery, external EPG URL flow, API prime 100 channels
- `XtreamClient.swift` — M3U header discovery (streaming bytes), unmatched channel logging
- `XtreamDTOs.swift` — programmeTimes closest-to-now field selection
- `EPGProviderStrategy.swift` — stale cache reduced to 1h
- `EPGSourceReconciler.swift` — prefer discovered epgURL
- `LiveStream+EPG.swift` — name normalizer handles `|` prefix + quality suffixes
- `M3UClient.swift` — removed VLC UA for EPG downloads
- `XMLTVChannelDiskCache.swift` — unmatched channel logging
- `XtreamEPGTimestampTests.swift` — updated for new behavior

---

## Current status (July 4, 2026 — xmltv.php bulk, offset-honest parse)

**For panels with a fresh `xmltv.php` dump**, the July 4 architecture stands.
The StreamInfinity test panel is an exception — see blocked section above.

This is a **published app for arbitrary providers** (the maintainer is not the
panel owner and cannot inspect the server). The design must therefore be the
generic thing every working IPTV player does — **download the whole guide in
one request and read the provider's real timestamps** — not a hack tuned to one
panel.

| Area | Status | What changed |
|------|--------|-------------|
| **Sync took 25+ min / app slow to open VOD during sync** | ✅ Fixed | Bulk sync no longer makes ~1,600 sequential `get_short_epg` calls. That approach is inherently slow (many minutes) **and** it saturates the provider's shared connection pool, which is why movies/shows were slow to open mid-sync. Bulk sync is now **one `xmltv.php` download** — the same thing mainstream players (TiviMate/Smarters) do to load a guide in seconds. |
| **Guide doesn't match the stream** | ✅ Fixed | Two fabrication sources removed: (1) the shifting heuristics (`alignIfStale` per-channel + `alignLatestToNow` global XMLTV shift) that slid schedules onto "now"; (2) `XMLTVDate.parseEPG` used to **discard the timestamp's explicit `+ZZZZ` offset**, keep the 14 wall-clock digits, and guess a timezone by whichever landed "closest to now". Standard XMLTV timestamps are self-describing, so `parseEPG` now honours the stated offset as an absolute instant. Correct data is shown correctly. |
| **Device freeze / unusable after load** | ✅ Fixed | Removed the `refreshNowPlaying` storm and the XMLTV **double parse** (a full-file timezone-detection pass ran before the real parse of a 50+ MB dump). One parse, one save. |
| **Poisoned cache from old builds** | ✅ Fixed | The `EPGListing` store still held *shifted* rows from the alignment era. `EPGSyncService` wipes the store once on upgrade (`epg.store.reset.noAlignV1`) so it rebuilds from real data. |

### The one rule that matters now

**Never shift, realign, or timezone-guess EPG timestamps. Display exactly what the provider returns.**

- **Bulk (Xtream Sync Now):** one `xmltv.php` download, stream-parsed. Programme timestamps carry their own UTC offset (`YYYYMMDDHHMMSS +ZZZZ`), which `XMLTVDate.parseEPG` honours as an absolute instant. Only *offset-less* dumps fall back to the server timezone. **No** `alignLatestToNow` shift, **no** "closest to now" timezone scoring.
- **Per-channel API (`get_short_epg`):** used only as a *fallback* when `xmltv.php` yields nothing, and for on-demand gap-fill of *visible* channels. It reads the provider's real unix `start_timestamp`/`stop_timestamp` via `EPGAPISync.parse` — also no shifting.

Do **not** re-add a per-channel bulk pass over the whole catalog (slow + pool exhaustion), a `refreshNowPlaying` overwrite, or any "make it land near now" heuristic. Faking timestamps is why Apex's guide disagreed with the live stream when every other player was fine.

### If the guide looks wrong or empty: get ground truth first

We can't hit the panel directly. The per-channel path (`EPGAPISync.sync`, used as fallback / on-demand) logs a one-shot probe:

```
EPG raw sample — channel <id> first "<title>" start <date> end <date> now <date> startDeltaMinutes=<n>
```

- `startDeltaMinutes` near 0 → the provider's feed is **live**; the guide should be correct.
- `startDeltaMinutes` in the thousands (days) → that provider's feed genuinely lags. No client code can invent current data — the remedy is an external EPG source (Settings → TV Guide → Add EPG Source). **Decide with the log, don't re-add shifting.**

---

This document is the durable reference for how Apex loads programme guide data and what **not** to regress. Historical sections below describe the *reverted* alignment approach — kept so nobody reintroduces it.

## Performance incident: "loading some data but not all, app buggy/unresponsive"

After stale-timestamp alignment shipped, the guide worked but the app became janky and inconsistent while scrolling. Root cause, found by tracing every call into `EPGLiveLoader.programsFromStore`:

- It ran an **unscoped** `FetchDescriptor<EPGListing>` — no `channelId` filter — with a 7-day lookback, sorted and grouped the result. Once Sync Now had populated the store for a large playlist (~1.6K channels × up to 16 rows), that scanned **tens of thousands of rows**.
- It was called directly from the `@MainActor` `EPGBrowseLoader.load`, so this scan ran **on the main thread**.
- Four separate SwiftUI triggers per list (`task(id: sectionToken)`, `onChange(visibleCount)`, `onChange(isSyncing)`, `onChange(refreshGeneration)`) could each invoke it, and `isSyncing → false` and `refreshGeneration += 1` fire in the same tick — a guaranteed double reload on every sync.

Fix (see rules 10–12 below): scope the store query to the requested channels' EPG ids, hop the fetch onto a background thread via `Task.detached`, make `EPGAPISync.persist` fire-and-forget, cache empty API results briefly instead of never, and drop the redundant `isSyncing`-driven reload. Also deleted `EPGOnDemandFetcher`/`ChannelEPGLoader` (dead code with the identical unscoped-fetch bug — a regression trap if ever wired back in).

## Speeding up "Sync Now" (full-catalog sync) — and the regression it caused

Once the guide itself was smooth, the remaining complaint was that the full **Sync Now** pass over ~1.6K channels was slow next to other IPTV apps. Two independent multipliers were stacking:

1. **`fetchChannelEPG`'s fallback cascade ran for every channel with no EPG.** `get_short_epg` (limit) → `get_short_epg` (no limit) → `get_simple_data_table` is up to 3 sequential round trips per channel. Fine for a handful of on-demand browse fetches; multiplied across a large catalog where a meaningful fraction of channels have no EPG at all, it roughly tripled sync time for no benefit.
2. **Concurrency (6) and per-request timeout (30s) were tuned for browse, not bulk sync.**

**First attempt (reverted) — raised concurrency to 12 with a dedicated, shorter-timeout session. This broke Live TV playback entirely.** Xtream panels commonly cap the *whole account* — API calls and video-stream connections together — to a small number of concurrent connections (`XtreamClient`'s own default session already documents this: "many Xtream providers cap an account to one concurrent connection"). Running 12 concurrent EPG requests exhausted that pool and starved the actual video stream connection, causing `XtreamError.authenticationFailed` ("connection limit reached") on playback and general app-wide slowness while the sync ran.

**What shipped instead:**
- `XtreamClient.fetchChannelEPG(..., thorough:)` — `thorough: false` (used only by `EPGAPISync.sync`) stops after the first `get_short_epg` call instead of cascading through the no-limit retry and `get_simple_data_table`. This cuts request *count* per channel without adding any concurrency, so it's safe. On-demand browse (`EPGLiveLoader`) keeps `thorough: true` (the default).
- Concurrency and the session (`makeEPGImportSession`, 6 connections / 30s timeout) were **left unchanged** at their known-safe values. **Do not raise `maxConcurrent` in `EPGAPISync` or `EPGLiveLoader`, or `maxConnectionsPerHost` in `makeEPGImportSession`, without confirming the specific provider's concurrent-connection allowance** — there is no generic way to discover it, and guessing wrong takes down live playback, which is far worse than a slow guide refresh.

Net: Sync Now is somewhat faster (fewer wasted round trips for no-EPG channels) without touching the connection budget that playback depends on.

## Bulk sync timeout + save fixes (July 3, 2026 evening)

Despite the `thorough: false` optimisation, Sync Now was still taking over an
hour to reach 14% on ~1.6K channels. Two independent causes:

### 1. Per-request timeout was 60 seconds

The bulk sync shared `makeEPGImportSession()` with on-demand browse — 30s idle
/ 60s resource timeout. A single slow or unresponsive channel could hold a
connection slot for a full minute. With 6 concurrent connections, the
worst-case throughput was 6 channels per minute → ~4.5 hours for a full sync.

**Fix:** Introduced `makeEPGBulkSyncSession()` — 10s idle / 20s resource
timeout, same 6-connection cap. Used only by the "Sync Now" bulk pass
(`EPGSyncManager.bulkSyncClient`). Channels that fail here are harmless —
on-demand browse fills them in later with the standard 30/60s session.

### 2. Bulk source: `xmltv.php` for Xtream (July 4 — final)

Two intermediate attempts thrashed on this before landing:

1. **XMLTV-first *with shifting* + `refreshNowPlaying` (reverted).** Downloaded
   `xmltv.php` but applied `alignLatestToNow` (one global shift from the single
   newest-ending channel, misplacing every other channel) and then ran a
   `refreshNowPlaying` pass writing per-channel `alignIfStale`-shifted rows into
   the same store — two incompatible timestamp systems → grid ≠ cards ≠ feed —
   plus ~4,800 `thorough` requests that froze the device.
2. **Per-channel API as the *bulk* source (reverted).** Removed XMLTV entirely
   and synced ~1,600 channels via `get_short_epg`. Correct-ish, but **~25 min
   to reach 66%** and it saturated the provider's shared connection pool so VOD/
   live were slow to open during sync.

**What shipped (final):** `EPGSyncManager.syncXtreamAPI` downloads **`xmltv.php`
once** (`syncXMLTV(..., alignToNow: false)`) and stream-parses it. This is the
mainstream approach — one request loads the whole guide in seconds. Correctness
comes from **honouring each timestamp's explicit UTC offset** (`XMLTVDate.parseEPG`,
see §4 below) instead of shifting or timezone-guessing. Per-channel
`get_short_epg` remains only as a *fallback* (if `xmltv.php` is empty/broken)
and for on-demand gap-fill of visible channels.

Why this is both fast **and** correct where the earlier attempts weren't:
- One HTTP request, not 1,600 → seconds, and no connection-pool exhaustion, so
  playback/VOD stay responsive during sync.
- Timestamps are shown exactly as stated (their own offset), so the grid and
  cards match the live stream — no fabricated "near now" data.

### 4. XMLTV timestamps: honour the explicit offset

The reason XMLTV *looked* wrong in earlier debugging (and got abandoned) was a
parser bug, not the source. `XMLTVDate.parseEPG` extracted the 14 wall-clock
digits (`wallClockDigits`) and interpreted them in a *guessed* timezone,
**silently dropping the `+ZZZZ` offset** that standard XMLTV timestamps carry
(`20260704060000 +0100`). `parseProgrammeTimes` then chose whichever zone landed
"closest to now" — actively selecting a wrong interpretation.

Fixed: `parseEPG` now calls `parseWithExplicitOffset` first. If the timestamp
states an offset (`+HHMM`, `-HH:MM`, `Z`), it's parsed as an **absolute instant**
and the fallback timezone is ignored. Only genuinely offset-less digits use the
server (else device) zone. `parseProgrammeTimes` just parses start/stop and
checks `end > start` — no multi-zone candidates, no "closest to now" scoring.
The old full-file `detectTimezone` sampling pass and its `EPGSampleCollector`
were deleted (they were the XMLTV double-parse and a fabrication-lite heuristic).

### 3. SwiftData saves caused device freezing

`InsertSession` (both in `EPGAPISync` and `EPGInserter`) saved repeatedly
during the processing loop — every 400–2,500 inserts. Each `context.save()`
posted a change notification that the main `ModelContext` had to merge,
triggering main-thread work on every batch. With many batches, this
accumulated into the "device freezing" symptom other IPTV apps don't have.

**Fix (both files):** Accumulate all data first, then insert + save **once**
at the end. One save = one notification = one brief main-context merge. For
the per-channel API path (~1,600 channels × 12 programmes ≈ 19K rows), the
single save takes < 1 second. For the XMLTV path, stream parse accumulates
into `ChannelBuffer` structs in memory, then inserts + saves once. No
intermediate saves at all. Also added in-session dedup (`Set<String>`) and
timing diagnostics (slow fetches >15s, total wall-clock time).

---

## "Now Playing" label going stale after the initial fetch (frozen snapshot bug)

After the guide became fast and stable, the next complaint was **the displayed
programme not matching what's actually airing** ("says it's playing a show
but when you watch it, that is not the correct show"). Two distinct causes:

1. **Genuine provider lag** (see "User-facing expectations" below) — not
   fixable client-side, and not what most of this was.
2. **A real app bug**: `ChannelsList`/`TVChannelsList` computed `epgByChannel`
   (a `[String: ChannelEPG]` of frozen "current"/"next" strings + dates)
   **once**, at the moment a page of channels was fetched, via
   `EPGLiveLoader.makeChannelEPG(from: slots, now: Date())`. That dictionary
   was never recomputed afterward. If a user lingered on a list — browsing,
   reading, or just leaving the app foregrounded on that screen — for longer
   than the current programme's remaining runtime, the card kept showing the
   *previous* "Now" title long after that programme had actually ended,
   because nothing re-derived `current`/`next` from the wall clock. Tapping
   play at that point shows a stream whose real live content no longer
   matches the frozen label.

**Fix**: both list views now also retain the raw `[EPGProgram]` list
(`programsByChannel`) behind `epgByChannel`, and re-run
`EPGLiveLoader.makeChannelEPG(from:now:)` **locally, every 60 seconds** (no
network call — same data already in memory) via a loop in the same
`.task(id: sectionToken)` that does the initial load. This keeps "Now/Next"
honest as programmes transition without needing a full reload or hitting the
network again. `EPGGuideView`'s grid does not have this problem — its cells
are laid out directly from absolute programme timestamps, not a cached
"current title" string, so they're inherently correct regardless of how long
the screen has been open (only the moving "now" line/highlight depends on a
periodically-updated clock, which it already has via `TimelineView`).

**Rule going forward: never cache a computed "is this the current programme"
label without a plan to re-derive it as time passes.** Store the raw
programme list and recompute on a timer instead of freezing the derived
value at fetch time.

---

## Sync Now progress percentage

Added a real percentage indicator instead of a bare spinner, since a silent
multi-minute "Sync Now" looked hung compared to other IPTV apps. Plumbing:

- `EPGAPISync.sync(..., onProgress: (@Sendable (Int) -> Void)?)` — called
  (throttled, every 5 channels) with channels completed so far in this
  source's `identities` array.
- `EPGSyncManager.syncAllSources(onProgress: (Int, Int) -> Void)` —
  pre-scopes every enabled source's channel count to compute an **overall**
  total across all Xtream sources (XMLTV import has no granular progress, so
  it isn't counted toward the total or the percentage — only reflected as a
  plain spinner), then offsets each source's per-channel callback by
  `completedSoFar` before forwarding.
- `EPGSyncService` exposes `@MainActor syncProgress: Double?` and
  `syncProgressLabel: String?` ("842 / 1,600 channels"), reset to `nil` at
  sync start/end. `EPGSettingsView` renders a percentage + `ProgressView(value:)`
  when non-nil, falling back to the plain indeterminate spinner otherwise
  (e.g. XMLTV-only setups, or before the first progress callback lands).

---

## Root cause (StreamInfinity / similar Xtream panels)

| Observation | Detail |
|-------------|--------|
| API works | `get_short_epg` returns HTTP 200 with ~12 programmes per channel |
| Timestamps are real | e.g. `start_timestamp=1782799200`, `start=2026-06-30 06:00:00` |
| Data is **stale** | Absolute times are days behind “now” (e.g. June 30 when today is July 3) |
| Relative schedule is fine | Durations and order are usable |
| XMLTV dump "looked" historical | This was the **parser bug**, not the data — `parseEPG` dropped the explicit `+ZZZZ` offset and guessed a zone, making current rows read as expired. Fixed by honouring the offset (see §4). |
| Other IPTV apps “work” | They download `xmltv.php` once and read the real timestamps — exactly what Apex now does. |

> ⚠️ **Reverted (July 4).** An earlier rule here was: "when every programme is
> already expired, **shift the whole block** so the earliest starts 30 minutes
> before now" (`EPGAPISync.alignIfStale`), plus the XMLTV `alignLatestToNow`
> global shift. **Both removed.** The maintainer confirmed every *other* IPTV
> player shows correct current EPG for the same providers — the data is current;
> the shifting (and the offset-dropping parse) were corrupting it. Apex now
> downloads `xmltv.php` and shows the provider's real timestamps. If a
> provider's feed really is days old, that surfaces honestly (see the
> `EPG raw sample` probe) and the fix is an external EPG source, **not** shifting.

---

## Architecture (all platforms)

```
┌─────────────────────────────────────────────────────────────┐
│  UI (iOS / iPad / tvOS / macOS)                             │
│  Live TV cards · EPG grid · tvOS in-player browser          │
│  → EPGBrowseLoader.load(...)                                │
└───────────────────────────┬─────────────────────────────────┘
                            │
         ┌──────────────────┴──────────────────┐
         ▼                                     ▼
  SwiftData EPGListing                  EPGLiveLoader (memory)
  (Lume-style store)                    get_short_epg /
         ▲                              get_simple_data_table
         │                                     │
         └──────── EPGAPISync.persist ─────────┘
                            ▲
                            │
              Settings → Sync Now
              EPGSyncManager → xmltv.php (primary)
              → per-channel API (fallback, gap-fill)
```

| Path | When | Behaviour |
|------|------|-----------|
| **Browse / Guide** | Open Live TV or Guide | Store first → per-channel API **only when store has zero rows** for that channel → show. |
| **Sync Now (Xtream)** | Settings → TV Guide | **14 epgshare01 feeds downloaded and matched by display name** → for each matched East programme, insert a `+3h` copy under every structurally-paired West/Pacific ID. If external feeds fail entirely, fall back to provider `xmltv.php` (offset-honest parse, no shifting), then per-channel `get_short_epg` prime. |
| **M3U / manual XMLTV** | Non-Xtream sources | File/URL XMLTV import only |

Shared entry point: **`EPGBrowseLoader`** (used by iOS/macOS Live TV, EPG grid, tvOS Live TV, tvOS player channel browser).

---

## Key files

| File | Role |
|------|------|
| `EPGBrowseLoader` in `EPGLiveLoader.swift` | UI entry: store first; live API only for empty store rows |
| `EPGLiveLoader.swift` | In-memory cache, per-channel fetch, parse |
| `EPGAPISync.swift` | Per-channel sync (fallback + on-demand) + `parse` (real unix timestamps, no shift) + persist + `EPG raw sample` probe |
| `EPGSyncManager.swift` | Sync orchestration — `EPGSyncMode.full` vs `.withPlaylist`, `importExternalEPG` single-pass |
| `EPGSyncService.swift` | UI spinner, `refreshGeneration`, `syncAwaiting`, `forceGuideRefresh`, mid-sync refresh |
| `ExternalEPGSources.swift` | Built-in epgshare01 URLs; US-first order; `urlsForBundledSync()` / `urlsForFullSync()` |
| `ApexSyncBrandView.swift` / `ApexBrandColors.swift` | Branded playlist sync screen (logo gradient) |
| `SyncProgressView.swift` | Playlist sync UI; inline `epgGuide` step with % |
| `XMLTVDate.swift` | Timestamp parsing — **honours explicit `+ZZZZ` offsets** (`parseWithExplicitOffset`), server-zone fallback only when offset-less. No shifting/guessing. |
| `XtreamClient.swift` | `XMLTVParser` (SAX stream parse), `fetchChannelEPG` (`thorough:`), `makeEPGImportSession` (do not raise its connection count) |
| `XtreamDTOs.swift` / `XtreamEPGText` | Timestamp formats (unix, SQL, XMLTV compact) |
| `EPGInserter.swift` | XMLTV file import — single parse, no timezone-detection pass, no shift (`alignLatestToNow` param retained but ignored) |
| `EPGGuideView.swift` | Grid: logos first, programmes async |
| `LiveTVView.swift` / `LiveTVTVComponents.swift` | Channel cards |
| `TVChannelBrowserOverlay.swift` | tvOS in-player guide |

---

## Timestamp parsing (`XtreamEPGText.parseTimestamp`)

Handle all of:

1. Unix seconds (`1751569200` / int) — **not** 14-digit strings  
2. Unix milliseconds (13 digits)  
3. SQL wall clock (`2026-07-03 15:00:00`)  
4. XMLTV compact (`20260703150000`) — must **not** be parsed as `TimeInterval` (that lands in year ~642000)

When the server reports `GMT`/`UTC` but stamps local wall-clock digits, prefer the **device** timezone (`XMLTVDate.resolveWallClockTimezone`).

---

## Stability rules (do not regress)

1. **Never clear the entire `EPGListing` store at sync start** — blanks the UI; if sync fails, guide stays empty. Upsert; prune expired only after success. **The Jul 7 "full replace at the start of `syncExternalEPG`" exception was reverted Jul 10** — it was scoped correctly for tvOS (Build 19, Jul 8: `preserveExistingStore` on for `bundled` passes) but iOS/macOS kept the unconditional clear, so *every* routine playlist-refresh sync and every periodic background `syncIfDue()` blanked the whole store on those platforms — not just the one-time provider-migration case the exception was written for. `preserveExistingStore = bundled` now applies on **every platform**: bundled passes (`.withPlaylist`, `.tvOSQuick` — routine/background sync) preserve existing rows and upsert only new ids; only an explicit `.full` pass (Settings → Sync Now) does a hard replace.  
1b. **De-dupe inserted listing ids across the *entire* multi-feed pass, not per-feed.** `syncExternalEPG` runs each of up to 14 feeds in its own `Task.detached` with its own `ModelContext`. Until Jul 10, each feed's dedup `Set` was re-seeded from a snapshot taken *before the loop started* and never learned what earlier feeds in the same pass had already committed — so two feeds covering the same channel/timeslot (common; that's the point of having overlapping regional feeds) would both try to insert the same listing id from two different contexts. The second insert hits SwiftData's unique-attribute upsert path, which remaps the persistent identifier and **crashes** ("fatal logic error in DefaultStore") — the same failure signature Build 19 fixed for concurrent on-demand browse writes, just via an unguarded sequential path instead. Fix: thread an accumulated `insertedIDsSoFar` set forward across feed iterations (seed each feed's local set from it, fold the feed's result back in after it completes) instead of resetting to a static pre-loop snapshot.  
1c-confirmed. **`syncIfDue()` (the silent periodic background refresh) must never run `mode: .full`.** Confirmed Jul 10 from an actual device console log, not inferred: a background `syncIfDue()` on iOS defaulted to `.full` (all 14 feeds, unfiltered at the URL-list level), downloaded and parsed the ~541MB `US_LOCALS1` feed while the user was actively using the app, and the process was killed by the kernel ~35s later for exceeding its 6GB entitled memory limit (`memorystatus: exceeded mem limit: ActiveHard 6144 MB (fatal)` → `killed by jetsam reason per-process-limit`). `urlsForBundledSync()` (used by `mode: .withPlaylist`) already excludes `US_LOCALS1` outright — its own doc comment says *"it drove memory warnings even on iPhone"* — but that protection only covered the routine playlist-refresh path, not the separate background due-check. tvOS's `syncIfDue()` already used `.withPlaylist` for exactly this reason (tight jetsam headroom); iOS's `#else` branch fell through to the `.full` default. Fixed by making `syncIfDue()` use `.withPlaylist` unconditionally on every platform — only the explicit Settings → Sync Now button (`syncNow()`) should still trigger `.full`.
1c. **`maxListingsPerChannel` must cap a channel's *total* row count, not one feed's local contribution.** Until Jul 10, `listingsPerChannel` (the cap counter) reset to `[:]` at the start of every feed's `Task.detached` closure — it only ever knew about rows *that same feed* had inserted *this pass*. That was fine when every sync started from a wiped store (a channel could gain at most ~`cap × feeds-covering-it` rows before the next wipe reset it to zero), but is unsafe now that bundled syncs preserve the store (rule 1 above): a channel covered by several feeds gains a fresh capful from *each* feed, on *every* playlist refresh and every background sync, forever — nothing ever brought the total back down. Guide screens render every row as a cell (unlike the list, which only ever shows now/next), so an unbounded per-channel row count directly bloats grid-build time and cell count until it renders slowly or crashes outright. Fix: thread a cross-feed, cross-sync cumulative `listingCountSoFar`/`totalCountByChannel` (seeded from the store's actual existing count per channel) into the cap check, mirroring the id-dedup fix in 1b. Also added `EPGSyncManager.trimExcessListings(in:)` (called alongside `pruneExpiredListings` after every successful sync) to trim any channel already over the cap back down, keeping the earliest (soonest-airing) rows — this self-heals devices that ran the unbounded version for a while before this fix shipped, without requiring a fresh install.  
2. **Never block browse persist on `EPGSyncGate`.** Gate pauses the background indexer / heavy XMLTV parse — it must **not** skip `EPGAPISync.persist` on iOS/macOS. Bundled sync preserves the store (Build 25+); blocking persist left gap-fill data only in memory so `forceGuideRefresh` re-read empty SwiftData until a manual Sync Now (Build 41).  
2b. **`EPGBrowseLoader` must merge warm `EPGLiveLoader` cache after the store read.** Gap-fill may already have programmes in memory while persist settles; without the warm merge, refresh can still paint blank rows (EPG.md rule 531 — UI already has data in memory).  
3. **Cache empty API results too, briefly (`emptyTTL`, 2 min)** — never-cache sounds safer but re-requests every channel with no EPG on every scroll tick / reload trigger, flooding the panel. A short TTL still recovers quickly from a transient miss.  
4. **Never shift/realign timestamps on read or write** — display the provider's real times; a cached block simply expires and is refetched (TTL), never slid onto "now".  
5. **Paint channel logos before EPG network work** — logos must not wait on programme fetch.  
6. **Pass sendable `EPGPlaylistCredentials`**, not SwiftData `Playlist`, into background actors.  
7. **Bulk sync uses `xmltv.php` (one download); per-channel `get_short_epg` is for on-demand gap-fill + fallback only.** A per-channel pass over the whole catalog is slow (many minutes) and exhausts the provider's connection pool (breaks VOD/live during sync). The dump parses fine once `parseEPG` honours each timestamp's UTC offset.  
8. **Do not put `visible.count` in `.task(id:)`** — scroll pagination cancels in-flight fetches (`Network error: cancelled`) and wiped cards. Load the first page in `.task(id: sectionToken)`; load further pages with an unstructured `Task` and **merge** into existing EPG state.  
9. **Ignore cancellation in logs** — `URLError.cancelled` / `CancellationError` are normal when leaving a screen; do not treat as failures.  
10. **Never fetch `EPGListing` without a `channelId` predicate** — `epgIds.contains($0.channelId)` scoped to the requested snapshots, same pattern as `TVPlayerContent.nowProgrammeTitles`. An unscoped fetch over a large synced store is tens of thousands of rows and was the main cause of "buggy and unresponsive".  
11. **Run `programsFromStore` (and any other SwiftData read used by browse) off the main thread**, even though it's `nonisolated` — `nonisolated` alone does not hop threads. Wrap in `Task.detached { ... }.value` from the `@MainActor` call site. Same for `EPGAPISync.persist`: fire-and-forget via `Task.detached`, do not `await` it — the UI already has the fetched data in memory.  
12. **One reload trigger per event, not one per observed property.** `EPGSyncService.isSyncing → false` and `refreshGeneration += 1` land in the same MainActor tick; watching both in a view double-fires the load. Watch `refreshGeneration` only.  
13. **Never freeze a "current programme" label at fetch time without a plan to re-derive it.** Keep the raw `[EPGProgram]` list alongside any cached `ChannelEPG`/"now" string and periodically recompute (`EPGLiveLoader.makeChannelEPG(from:now:)`) client-side as real time passes — otherwise the label silently goes stale once the programme it names has ended.
14. **Bulk sync (Sync Now) must use a fast-fail session** (`makeEPGBulkSyncSession`, 10s/20s timeouts), **not** the on-demand browse session (`makeEPGImportSession`, 30s/60s). A single slow channel holding a slot for 60s × 6 concurrent = 6 channels/minute worst-case; 20s timeouts triple that floor. Browse keeps the longer timeout so the guide fills in thoroughly for whatever the user is actually looking at.
15. **Never save synchronously inside the `for await` processing loop.** Hand the dirty context to `Task.detached` and swap in a fresh one immediately so the network pipeline stays full. The old pattern of inline `context.save()` + `ModelContext(container)` recreation on the actor executor was the primary cause of "device freezing" during sync.
16. **Never fabricate timestamps.** Show exactly what the provider returns. For XMLTV that means honouring the timestamp's explicit UTC offset (`XMLTVDate.parseEPG` → `parseWithExplicitOffset`); for the per-channel API that means the real unix `start_timestamp`/`stop_timestamp`. Do **not** re-add `alignLatestToNow`, `alignIfStale`, `bestTimes`/`detectTimezone` "closest to now" scoring, or a `refreshNowPlaying` overwrite. Faking times made the guide disagree with the live stream while every other player was correct.
17. **Never run a per-channel pass across the whole catalog for bulk sync.** ~1,600 sequential `get_short_epg` calls take many minutes **and** exhaust the provider's shared connection pool, freezing playback + UI. Bulk = one `xmltv.php` download. Per-channel API is only for on-demand *visible* channels (and the empty-xmltv fallback), where the count is small.
18. **Parse XMLTV in a single pass.** The old timezone-detection pre-pass parsed the whole 50+ MB dump a second time (slow, freeze risk) and used a "closest to now" heuristic. Because timestamps carry their own offset, no detection is needed — one `XMLTVParser.parseProgrammes` pass, then one save.
19. **When the guide looks wrong, read the `EPG raw sample` log before changing code.** `startDeltaMinutes` tells you whether the provider's feed is live (≈0) or genuinely lagging (thousands). This is the only ground truth available when you can't hit the panel — decide from data, not by re-adding shifting.
20. **West/Pacific pairing must use `epgChannelId`, not display names.** The provider-issued ID is stable and structurally encodes the relationship (`hbowest.us` ↔ `hbo.us`). Display names collapse unrelated local affiliates that share a network prefix after normalisation, and produce false pairings like `mtv.us → mtv2west.us` or `cbswupaatlantaga.us → cbskovrstocktonsacramentoca.us`. The rule: west ID minus TLD minus `west`/`pacific` token must exactly equal east ID minus TLD (see § "West/Pacific structural matching").
21. **Do not strip region words in `EPGNameNormalizer`.** `east`, `eastern`, `atlantic`, `central`, `mountain`, `west`, `pacific`, `feed` mark distinct local content and must survive normalisation. Stripping was tried July 7 to help "HBO East" ↔ "HBO" match and reverted the same day because it caused affiliate collisions. Country codes and quality tokens are the only safe strips.
22. **Playlist refresh uses `EPGSyncMode.withPlaylist`.** US-only feeds, 88% early stop, skip `US_LOCALS1` at 75%. Settings → Sync Now uses `.full` (all 14 feeds). Do not run the full 14-feed pass on every playlist refresh — it blocks the sync sheet for 5+ minutes on large playlists.
23. **Do not live-API gap-fill when the store already has rows for a channel.** `EPGBrowseLoader` must trust bulk-imported SwiftData after sync. Re-fetching via `get_short_epg` (2 concurrent, 200 ms stagger × 24 channels) added several minutes of blank channel cards even though the guide step had already finished.
24. **External EPG: one SAX pass per feed.** Use `XMLTVParser.importExternalEPG` — never `parseChannels` + `parseProgrammes` sequentially on the same file.

## Live TV UI rules (do not regress — Build 19/24)

These apply to **view layer only** (`LiveTVView`, `EPGGuideView`, `ChannelsList`, `LiveTVTVComponents`, `LiveTVSectionEPGCache`). Full checklist: `PROJECT_REFERENCE.md` § **Do Not Regress**.

25. **Keep list and guide mounted together** — `ZStack` + opacity, not `if/else` that destroys one view on List ↔ Guide toggle.
26. **Never `.id()` on section/category/layout** — destroys EPG state on category switch. Sort-only `.id(contentSort)` is OK.
27. **Never clear `programsByChannel` on category switch** — only reset `visibleCount`; reload merges from store/cache.
28. **List and guide share `LiveTVSectionEPGCache`** keyed by `LiveTVSection.id` — same data, instant toggle.
29. **Same `EPGBrowseLoader.load` for list and guide** — do not pass a narrower `windowStart`/`windowEnd` on guide; grid clamps to timeline at render time.
30. **Pass `playlist:` into guide and list** — do not rely on `playlist(for:)` context fetch (can return nil → skips Xtream store-first path).
31. **Merge loads, never wipe** — use `channelsNeedingLoad` + `epgCache.merge`; avoid `replace: true` that replaces the entire in-memory dict.
32. **iOS/macOS programme details: context menu, not `onLongPressGesture`** — long-press on every guide cell delays UIKit pan recognition (sticky/hard scrolling). Keep press-and-hold Select on tvOS only (Build 41).

---

## Platform coverage

| Surface | Platform | Loader | Refreshes after Sync Now |
|---------|----------|--------|--------------------------|
| Live TV list cards | iOS, iPad, macOS | `EPGBrowseLoader` via `ChannelsList` | ✅ `refreshGeneration` |
| Live TV list cards | tvOS | `EPGBrowseLoader` via `TVChannelsList` | ✅ `refreshGeneration` |
| EPG grid | all | `EPGGuideView` → `EPGBrowseLoader` | ✅ `refreshGeneration` (merge) |
| In-player channel browser | tvOS | Store first, then `EPGBrowseLoader` for gaps | ✅ `refreshGeneration` (Jul 7 pm) |
| In-player controls caption | tvOS | `TVPlayerContent.epgListings` (store) | ✅ `refreshGeneration` (Jul 7 pm) |
| Sync Now | all | `EPGSyncService` → `EPGSyncManager` | — |
| Settings → TV Guide | iOS, iPad, macOS, tvOS | `EPGSettingsView` | — |

### Cross-device behaviour (important)

**EPG data does not sync via iCloud.** `EPGListing` rows live in the local catalog store (`default.store`), which is intentionally **not** CloudKit-mirrored. Playlists, favorites, and progress sync; the TV guide does not. Every device must download its own guide.

| Trigger | iOS / iPad / macOS | tvOS |
|---------|-------------------|------|
| App launch | Guide from **local store immediately**; `syncIfDue()` after **90 s** deferral if stale | Guide from store; `syncIfDue()` after **60 s** |
| **Playlist refresh** | Content + **TV guide inline** (`epgGuide` step, bundled mode, **%** progress) | same |
| Live TV tab selected | `syncIfDue()` if stale | `syncIfDue()` |
| Settings → Sync Now | **Full** sync (14 feeds, `.full` mode) | same |
| Browse / Guide open | store → live API **only for empty store rows** | same |

**First-time setup on a new device:** add playlist → wait for playlist sync (content + guide in one flow) → guide persists locally. Do **not** expect an iPhone EPG sync to appear on Apple TV without that device running its own sync.

**After closing the app:** guide data remains on disk until pruned (expired programmes) or the next scheduled/full refresh. No manual sync required to see programmes on reopen.

**Sync timeout:** 3 600 s (1 hour).

---

## User-facing expectations

- **Reopening the app:** programmes show from the **local guide store** — no sync required unless data is stale (days old) or you want fresher listings.
- **Playlist refresh:** updates both catalog **and** TV guide in one branded screen; TV Guide step shows **%** and feed progress.
- Opening Live TV / Guide after a fresh sync should show programmes **immediately** for channels covered by the bulk import (no multi-minute live-API wait).
- **Settings → Sync Now** runs the full 14-feed pass for maximum coverage (longer than playlist refresh).
- Programme **titles may not match live airings** when the provider's feed is delayed — that is provider lag, not a blank guide.
- Console: look for `EPG trying N external EPG source(s) (mode: bundled|full)` and `EPG bundled sync complete early`.

---

## Tests

- `XMLTVDateTests` — explicit-offset honouring (`+HHMM`, `Z`), offset-less server-zone fallback, `parseProgrammeTimes` returns the stated absolute interval (no shifting)  
- `XtreamEPGTimestampTests` — unix vs XMLTV compact, SQL wall clock, **parse preserves real provider timestamps**  
- `EPGSyncTests` — XMLTV matching / caps; external single-pass test
- `StremioTests` — manifest object resources, URL normalization

Simulator tests do **not** hit StreamInfinity; device verification is required for the live panel.

---

## What we tried and abandoned

| Approach | Why it failed |
|----------|----------------|
| Bulk `xmltv.php` with a global `alignLatestToNow` shift | The shift (from one channel) misplaced every other channel; "historical" data was actually the offset-dropping parse bug. Fixed by honouring offsets — `xmltv.php` is now the primary bulk source. |
| Per-channel `get_short_epg` as the *bulk* source | ~25 min / saturated the connection pool so VOD/live were slow to open. Reverted to one `xmltv.php` download. |
| Timezone brute-force detection (`detectTimezone`) | A second full-file parse + a "closest to now" heuristic. Unnecessary once offsets are honoured — deleted. |
| Insert expired rows “for diagnosis” | UI filters `end > now` → still blank |
| Clear store + block browse during sync | Guide flickers empty / stays empty on failure |
| Never cache empty API responses | Re-requests every no-EPG channel on every trigger, flooding the panel — switched to a short (2 min) TTL instead |
| Align on **latest** end only | Multi-hour blocks left early slots expired |
| Unscoped `EPGListing` fetch (no `channelId` filter) on the main thread | Scans the whole store (tens of thousands of rows once synced) synchronously on every guide/list reload — the "buggy and unresponsive" bug |
| `onChange(isSyncing)` **and** `onChange(refreshGeneration)` both trigger reload | They fire in the same tick — guaranteed duplicate load on every sync |
| Raising EPG sync to 12 concurrent connections (dedicated bulk session) | Exhausted the provider's whole-account connection limit and broke Live TV playback entirely — reverted to 6 |
| **Name-based West/Pacific detection** (July 7 am) | Collecting `westMappings[basePrimary] = [westPrimary]` by stripping `"west"`/`"pacific"` from `identity.name` and looking up the base in `primaryByNormalizedName` — plus stripping `east/eastern/atlantic/central/mountain/feed` in the normaliser to help "HBO East" ↔ "HBO" match. In practice this collapsed local affiliates ("ABC WSB Atlanta" and "ABC KTRK Houston" both to `abc`) and produced pairings like `mtv.us → mtv2west.us`, `cbswupaatlantaga.us → cbskovrstocktonsacramentoca.us`, `abcwsbatlantaga.us → abcktrkhoustontx.us`. Replaced with structural `epgChannelId` matching (July 7 pm); region-word strip reverted. |
| **`westMappings` collected but no listings inserted** | The July 7 morning code computed the East → West/Pacific pairs, logged them, and added the west primaries to `matchedChannelIDs` (so they were excluded from live-API gap-fill) — but never wrote any `EPGListing` rows for them. Net effect: those channels looked "covered" but had no data at all. Fixed July 7 pm by adding a `+3h` insert pass inside the `parseProgrammes` callback in `EPGSyncManager.syncExternalEPG`. |
| **XMLTV-first for Xtream + `refreshNowPlaying` "now" overwrite** | Two alignment systems (global XMLTV shift vs per-channel `alignIfStale`) wrote incompatible timestamps into one store → grid ≠ cards ≠ feed. The `thorough` now-refresh pass (~4,800 requests) froze the device. Reverted July 4 to a single per-channel path. |
| **`alignIfStale` (slide expired schedule onto "now")** | The root cause of "guide doesn't match the stream." It fabricates a schedule from stale data so titles can never match the live feed. Removed July 4 — every other IPTV player just shows the provider's real timestamps, and so does Apex now. |
| **Live API after store already populated** (Jul 7 late) | Post-sync channel browse re-hit `get_short_epg` for 24 visible channels even when SwiftData had listings → 3+ min before cards showed data. Fixed: gap-fill only when store row count is zero for that channel. |
| **Two-pass external XML parse** (Jul 7 late) | `parseChannels` + `parseProgrammes` on each 550 MB feed doubled sync time. Fixed: `importExternalEPG` single pass. |

---

## Cross-device verification checklist

Run on **each** device after a Release/TestFlight build. EPG is per-device — syncing on iPhone does not populate Apple TV.

| Step | iPhone / iPad | Apple TV | macOS |
|------|---------------|----------|-------|
| 1. Add playlist, wait for sync (content + guide) | ✅ | ✅ | ✅ (if signed) |
| 2. Playlist refresh shows branded UI + TV Guide **%** | ✅ | ✅ | ✅ |
| 3. Settings → TV Guide → **Sync Now** (optional full pass) | ✅ | ✅ (Settings gear tab) | ✅ |
| 4. Console: `EPG trying N external EPG source(s) (mode: bundled|full)` | Device log | Xcode → Apple TV | Console.app |
| 5. Live TV → pick category → cards show Now/Next | ✅ | ✅ | ✅ |
| 6. Live TV → Guide grid → programmes in cells | ✅ | ✅ | ✅ |
| 7. Major channel title matches what's airing | HBO, ESPN, etc. | same | same |
| 8. Network West feed (e.g. HBO West) has data | if in lineup | if in lineup | if in lineup |
| 9. After Sync Now while on Live TV, cards update without restart | ✅ | ✅ | ✅ |
| 10. Force-quit + reopen → guide still shows programmes | ✅ | ✅ | ✅ |
| 11. tvOS only: in-player browser (left on remote) shows guide | — | ✅ | — |

**Red flags:** `EPG sync skipped — container not configured`; sync finishes in <5 s with 0 inserted (external feeds all failed); `EPG WEST MAP` pairing unrelated IDs (regression — see rule 20).

1. Console: `EPG API sync START — N channels` then `EPG API sync DONE — …inserted=N upcoming=N`  
2. Also `EPG live — channels with data: N/M` (browse) with `N > 0`  
3. If `raw=0`: API/auth/URL issue  
4. If `raw>0, parsed=0`: timestamp format — check `XtreamEPGText`  
5. If `parsed>0, inserted=0`: window filter dropped everything → check `EPG raw sample` `startDeltaMinutes` (provider feed is genuinely stale)  
6. UI blank but logs OK: channel id key mismatch (`primaryEPGChannelId`)  
7. **Grid ≠ card "Now":** should no longer happen — both read the same real (unshifted) rows. If it does, something reintroduced shifting or a second writer (rule 16). You should **not** see any `EPG now-refresh …` or `EPG XMLTV align …` logs anymore; if you do, `refreshNowPlaying`/`alignLatestToNow` was re-added.
