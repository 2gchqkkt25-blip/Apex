# Apex — AI Agent Guide

Apex is a native, multi-platform IPTV player (iOS 18+, macOS 15+, tvOS 18+, visionOS 2+) built with SwiftUI + SwiftData. Single Swift codebase with three interchangeable playback engines: KSPlayer (default) → VLCKit → AVPlayer. It is built with the iOS 26 SDK and uses Liquid Glass / iOS 26 navigation APIs where available, falling back to system materials on older OS versions.

---

## Build & run

```bash
# Open in Xcode
open Apex.xcodeproj   # pick scheme "Apex", any destination

# CLI build (iOS Simulator)
xcodebuild build \
  -project Apex.xcodeproj -scheme Apex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The project injects API secrets from a repo-root `.env` file via `Scripts/inject-env.sh`. The file is gitignored; features degrade gracefully when it's absent.

---

## Testing

Tests deploy to **iOS 26.4+ Simulator only** — never tvOS. Use an iPhone 17 Pro or newer sim; iOS 26.2 sims fail with a deployment-target mismatch (exit 65).

```bash
# Full suite
xcodebuild test -project Apex.xcodeproj -scheme Apex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests only
xcodebuild test -project Apex.xcodeproj -scheme Apex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ApexTests

# UI tests only
xcodebuild test -project Apex.xcodeproj -scheme Apex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ApexUITests
```

Every test `ModelConfiguration` must set `cloudKitDatabase: .none` — `@Attribute(.unique)` models + the default `.automatic` crashes on entitled simulator hosts.

---

## Architecture

```
Apex/
├── ApexApp.swift            App entry + SwiftData containers
├── Models/                  SwiftData @Model types (Playlist, LiveStream, Movie, Series, …)
├── Services/
│   ├── Network/             XtreamClient, M3UClient, TMDBClient, OMDbClient, TraktService
│   ├── Sync/                ContentSyncManager (background catalog indexing + enrichment)
│   ├── Player/              PlayerSettings, PlayerHistory, NextUp resolver
│   └── Images/              CachedAsyncImage, ImagePipeline
└── Views/                   SwiftUI, platform-adaptive
    ├── Home/                Hero carousel, immersive iPad/tvOS backdrop, rails, tvOS fold
    ├── Player/              Engine wrappers + unified overlay
    └── …
```

Two separate `ModelContainer`s:
- **Catalog** (`default.store`) — local-only, what all `@Query` bindings target
- **CloudKit mirror** (`CloudUserData.store`) — user state (profiles, watch progress, favorites); never bind `@Query` against this container

---

## Key patterns & gotchas

### Swift concurrency
`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` is set project-wide. Value types and DTOs used by `nonisolated` callers must be explicitly marked `nonisolated` (type + every extension).

### SwiftData
- Enrichment saves run on a **background** `ModelContext` (`ContentSyncManager.enrich*`) — not the view context.
- Main-thread saves during playback stall KSPlayer every ~5 s. Buffer to `UserDefaults`; flush at playback boundaries.
- `PlaylistDeletion` helper must be used for any playlist removal (UI **and** iCloud reconcile) — `Movie`/`Series`/`LiveStream` have no cascade relationship to `Playlist`. Call `CloudSyncCoordinator.deletePlaylist(id:)` so CloudKit gets a `SyncedPlaylist.deletedAt` tombstone. A missing mirror **without** a tombstone is treated as a slow import and re-published, not as a delete.
- The reconciler after `switchProfile` rebuilds the dropped content shadow — don't remove that pass; optimize the fetch predicate instead.

### iCloud sync
- Guard reconcile against `LocalCatalogReadiness`; an empty `default.store` would push mass deletions to CloudKit.
- `UserProfile` must be deduped on every reconcile (not just launch) — fixed-id default profiles multiply per device in CloudKit.
- `CatalogSyncLease` (30 min on `SyncedPlaylist`) — the device that started Sync Now keeps the blocking cover; siblings must not treat an iCloud-imported `lastSyncDate == nil` playlist as first-time auto-sync.

### tvOS-specific
- `Color.accentColor` resolves to white on tvOS — never use it for fills/tints.
- `.onMoveCommand` runs inside the focus engine's animated context; defer layout mutations with `Task { }`.
- Full-width focus targets needed for vertical navigation — a narrow target won't catch "down" from a full-width section.
- `@FocusState` must not drive layout sizing in the hero fold — use `TVHomeScreen`'s `ScrollTargetBehavior`.
- `lazyTab` keeps **Home** mounted on tvOS (same as iOS/macOS). Do not unmount Home when leaving the tab — that rebuilds hero + trending from scratch. Other tabs still unmount; do not keep Media mounted with Home on Apple TV HD.
- Movies/Series: local `NavigationStack` path on tvOS + `consumeDeepLinkPath()` — do not bind `path` to `DeepLinkRouter` (focus engine ignores it).
- Settings → Media Servers: tvOS `tvBody` in-pane drill. Never nest a `List` inside Settings’ outer `ScrollView`.
- Live TV player: Up/Down on Siri Remote **always** surf channels (`onSwitchChannel`) during live playback, whether controls are visible or hidden. The Guide panel is reachable only via its tab pill — do not re-add the old "Up opens Guide" shortcut in `TVPlayerControlsOverlay.onMoveCommand`.
- Live TV rail: `LiveTVSectionSettings.showAllChannelsKey` gates the `.all` section in `sortedSections`. When off, Favorites (or Recents / Categories) leads the rail. Toggle lives in EPG Settings alongside Channel Preview.

### Media servers
- IPTV catalog ids are `{playlistUUID}-movie-…` / `-series-…`. Media-server detection is `{serverUUID}-library-…` or `mediaserver://` only — never treat IPTV rows as Plex/Jellyfin/Emby.

### KSPlayer
- Hardware decode requires **both** `asynchronousDecompression = true` **and** `hardwareDecode = true`; `async` defaults to `false` → silent software decode → frame drops on tvOS.
- Never call `layer.prepareToPlay()` on a running session — use `player.replace()` (`rebuildStream(on:)`) to avoid a UAF crash.
- Frozen image + healthy audio on live TV = MPEG-TS 2³³ clock wrap; fixed by the `noteClockDrift()` watchdog.

### VLCKit (Live TV mini preview)
- `stop()` is **asynchronous** (queued on VLC's player thread). Never mutate `mediaPlayer.media` (including setting it to `nil`) right after `stop()` — it races the media-changed handler and aborts in `libvlc_media_retain`. `stop()` alone closes the input and ends the HLS PlaylistManager thread.

### SwiftUI safe areas
- To extend a background under the bars, scope `ignoresSafeArea()` to the fill — `background(fill.ignoresSafeArea())` — never to the container view. Applying it to the view strips the safe area from all of its content; on macOS that draws every page under the titlebar (Build 50→51 regression).

### VLCKit (Live TV mini preview)
- `stop()` is **asynchronous** (queued on VLC's player thread). Never mutate `mediaPlayer.media` (including setting it to `nil`) right after `stop()` — it races the media-changed handler and aborts in `libvlc_media_retain`. `stop()` alone closes the input and ends the HLS PlaylistManager thread.

### SwiftUI safe areas
- To extend a background under the bars, scope `ignoresSafeArea()` to the fill — `background(fill.ignoresSafeArea())` — never to the container view. Applying it to the view strips the safe area from all of its content; on macOS that draws every page under the titlebar (Build 50→51 regression).

### Localization
String Catalogs (English + German). Run `xcstringstool sync` and include the tvOS stringsdata. Normalize `.xcstrings` with `Scripts/normalize-xcstrings.swift` (pre-commit hook) to avoid format churn.

### Pre-commit hooks (lefthook)
SwiftFormat + SwiftLint run as errors. Notable: `String(decoding:)` is banned; `redundantStaticSelf` crashes on `for x in (try? …) ?? []` — avoid that pattern.

---

## External integrations

| Service | Auth | Notes |
|---------|------|-------|
| TMDB | Bearer token (`.env`) | Metadata, artwork, trailers |
| OMDb | API key (`.env`) | IMDb / RT / Metacritic ratings |
| Trakt | Device OAuth (Keychain) | Scrobbling; no web view — works on tvOS |

---

## GitHub
Issues & roadmap: <https://github.com/2gchqkkt25-blip/Apex/issues>
