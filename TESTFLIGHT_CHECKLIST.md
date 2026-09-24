# TestFlight Checklist — Build 61

## What to Test (paste in App Store Connect → TestFlight → What to Test)

```
Build 61 (1.2.0)

Apex is an IPTV player—users add their own Xtream or M3U playlist. No content is bundled.

1. On Apple TV, play a movie or episode, bring up the controls, and swipe the clickpad left and right. The picture and the progress bar should both jump.
2. Open Subtitles and move through the list. The menu should stay open until you pick a track or dismiss it.
3. Play a title whose file has no built-in captions (Wyzie on in Settings). After a few seconds the captions button should appear with Off and a language. Titles that already have tracks should still list those tracks.
4. Watch a long programme, then exit to the TV Guide. The guide should open at the current time, not the time you pressed play.
5. On Apple TV, scroll the Guide. Programme titles should stay readable, and the selected poster on Movies and Series should be obvious.

Contact: support@streaminfinitytv.com
```

## Build 61 Focused Checklist

- [ ] Apple TV clickpad swipe rewinds and fast-forwards while the controls are up
- [ ] Subtitle menu stays open long enough to read the list
- [ ] Wyzie download shows a captions button when the file has no embedded track
- [ ] Embedded subtitle tracks still appear in the menu when the file has them
- [ ] Leaving playback returns the TV Guide to the current time
- [ ] Guide titles stay readable and Apple TV poster focus is easy to see
- [ ] Settings → iCloud Sync does not sit on “CKErrorDomain error 2” after a normal launch

**Release metadata:** Apex app and Top Shelf extension are both Build **61** (version 1.2.0).

---

## Build 59 Focused Checklist

- [ ] tvOS playlist refresh completes its TV Guide step and the app is usable immediately afterward
- [ ] Returning from playlist-settings refresh restores a valid focus target
- [ ] On iOS, macOS, and tvOS, the coloured live overlay intersects the red Now line and matches the programme shown as currently airing
- [ ] HBO East HD and rows containing short/back-to-back programmes remain aligned with the time ruler while scrolling
- [ ] Empty-EPG channels remain normal-height rows and do not make the Guide jump
- [ ] Vertical and horizontal Guide scrolling remains smooth on iOS, macOS, and tvOS
- [ ] Guide data remains available after force-quit and relaunch

**Release metadata:** Apex app and Top Shelf extension are both Build **59** (version 1.2.0).

---

## September 4 — in-player Guide, playback, hidden iCloud (Build 55)

- [ ] CloudKit Console: deploy Development → Production so `CD_UserContentState` has `isHidden` (hide-sync). Build 53 playlist tombstone / catalog-sync lease fields should already be in Production
- [ ] tvOS live TV: open in-player Guide — overlay is compact (not full screen); Down/Up scroll the full category; focus is a tight highlight on the programme; scrolling is smooth
- [ ] tvOS: switch channel from the Guide; live playback starts without a long hitch
- [ ] tvOS: Settings → Subtitles → OpenSubtitles chips — focus is not a huge white rectangle
- [ ] tvOS: play something, Stop, return to Home/Movies — posters are not stuck spinning
- [ ] iPhone portrait live TV: open Guide — 16:9 picture at the top, Guide underneath, no black band above
- [ ] Play a series, close it, immediately play a movie — only the movie’s audio
- [ ] Add a second playlist while the first is still syncing — spinner does not hang forever; Cancel works; timeout ~20s if the provider never answers
- [ ] Hide a Live TV category on iPhone, go to Home for a few seconds, open the same profile on Apple TV — category is hidden (and the reverse)
- [ ] Hide a single channel; it stays hidden on the other device after iCloud flush
- [ ] Un-hide on one device; it returns on the other
- [ ] Sync Now completes without waiting on the full XMLTV TV Guide download
- [ ] Live TV channel up/down surfs the full category, not a short window of ~40

## September 3 catalog, episodes, subtitles, skip (Build 54)

- [ ] Sync Now on a playlist whose provider added a new episode — the episode appears after Sync Now without opening the show first (Recently Added / Show All / search, not only the 20-poster row)
- [ ] Opening any series refreshes its episode list from the provider
- [ ] After Sync Now, Recently Added on Movies/Series shows titles from **this** playlist only
- [ ] Recently Watched does **not** list titles you never played (open-and-back or Sync Now is not enough)
- [ ] Play a movie/episode, skip forward and back — playhead moves (IPTV files with unknown duration included)
- [ ] tvOS: with player controls hidden, Siri Remote left/right skips 10 seconds on VOD
- [ ] Settings → Subtitles is **On** after launch if you had never toggled it; captions appear when a Wyzie key is set
- [ ] Settings → Automatic Sync defaults to **Daily** on a fresh install (existing 3-day choice stays if already set)

## September 1 tvOS Home, Navigation, and iCloud Sync (Build 53)

- [ ] CloudKit Console: deploy Development → Production so `CD_SyncedPlaylist` has `deletedAt`, `catalogSyncDeviceID`, `catalogSyncHeartbeatAt` (and `CD_SyncedMediaServer.deletedAt` if it is not already in Production)
- [ ] tvOS: open Home, wait until hero + trending settle, switch to Movies, come back — Home is still populated (no full reload)
- [ ] tvOS: Trending Movies and Trending Series show about **20** titles, matching iPhone/Mac (not 6)
- [ ] tvOS: first launch shows the hero without waiting for the whole playlist sync; trending fills in afterwards
- [ ] tvOS: Movies tab — open a title, Play works (not disabled, no “No episodes available” on IPTV movies)
- [ ] tvOS: Series tab — open a series, episodes list, play an episode
- [ ] tvOS: Settings → Media Servers stays in-pane (focus does not jump; pane does not go blank)
- [ ] Delete a playlist on one device; after iCloud reconcile the same playlist is gone on the other (if it was already deleted on Build 52, delete it once more on this build)
- [ ] Sync Now on iPhone — Apple TV does **not** show the full-screen sync cover; iPhone still does
- [ ] Fresh Apple TV with no local catalog still auto-syncs playlists on first launch
- [ ] Sync Now on a playlist whose provider catalog changed — Movies/Series/Live TV pick up new titles and drop removed ones
- [ ] IPTV (Xtream/M3U) movie and series Play still works on iOS and macOS
- [ ] Delete a Plex/Jellyfin/Emby server; after relaunch + iCloud it stays gone

## Build 52 Media Server and iOS Navigation Regression

- [ ] iPhone tab bar shows exactly **Home, Movies, Series, Live TV, Media**; there is no automatic More tab
- [ ] iPhone Home magnifying-glass button opens Search and the sheet dismisses normally
- [ ] iPhone Live TV opens immediately, shows channels/guide, and still works after switching tabs and relaunching
- [ ] iPhone Media is populated after launch without requiring a manual sync; switching tabs and relaunching preserves the selected server and library rails
- [ ] iPhone Media movie and series detail screens show exactly one back button
- [ ] iOS physical-device build signs without the Multicast Networking entitlement or Apple capability approval
- [ ] Plex: play MP4 direct-play and MKV/HLS-transcode samples on iOS and tvOS; playback starts without a crash or runaway buffering
- [ ] Apple TV HD: a high-bitrate Plex source uses a real 1080p/12 Mbps transcode rather than an uncapped remux
- [ ] Jellyfin: sync and play a movie and episode on iOS, macOS, and tvOS; confirm progress returns to the server
- [ ] Emby: sync and play a movie and episode on iOS, macOS, and tvOS; confirm progress returns to the server
- [ ] Configure two servers, delete one, switch tabs, force-quit, relaunch, and allow iCloud reconcile; the deleted server does not return
- [ ] After deleting a server, its movies, series, and episodes are absent from the Media catalog while the remaining server is unchanged

## Build 46 Regression Fixes

- [ ] tvOS with a large Xtream playlist: Home, Movies, Series, and Live TV remain responsive after launch and during browsing
- [ ] Next Episode button works near the end of an episode on iOS, macOS, and tvOS
- [ ] With Auto Play Next enabled, finishing an episode advances on KSPlayer, VLCKit, and AVPlayer
- [ ] With Auto Play Next disabled, finishing an episode does not advance
- [ ] macOS subtitles render once; embedded and downloaded subtitle layers are not doubled
- [ ] macOS: moving the pointer toward Next Episode reveals controls without hiding the button
- [ ] Skip Intro moves forward once and dismisses; it does not replay or loop the opening
- [ ] A Stalker stream that cannot resolve stops waiting after 45 seconds and offers a retry
- [ ] macOS app icon is sharp in Finder, the Dock, and the application switcher

## Stalker Playlist (ya.pingtx.me)

- [ ] Add a Stalker playlist with portal URL, MAC, and optional credentials
- [ ] Sync completes — Live TV channels appear, movie/series posters load
- [ ] **Live TV**: Tap a channel → plays immediately (no spinner hang)
- [ ] **Movies**: Browse a movie category → tap a movie → plays successfully
- [ ] **Series**: Browse a series category → tap a series → episodes list shows → tap an episode → attempts playback
- [ ] Switch to a different player engine (VLC/AVPlayer) → live TV still plays

## Channel Switching

- [ ] Play a live TV channel, then tap the chevron buttons (KSPlayer, VLC, AVPlayer) → switches to next/previous channel
- [ ] On iOS/macOS with **multiple playlists**: channel switching stays within the active playlist (doesn't jump to another playlist)
- [ ] tvOS: Siri Remote swipe up/down → channel surfing works within the current section

## Subtitle Appearance

- [ ] Settings → Subtitles → Appearance section visible
- [ ] Change font size → subtitles reflect new size in player
- [ ] Change text color → subtitles reflect new color
- [ ] Change background opacity → subtitle background changes
- [ ] Change bottom offset → subtitle position moves
- [ ] Select Bottom, show player controls → subtitles animate above the controls; hide controls → subtitles return to the safe lower position
- [ ] Rotate iPhone/iPad to landscape → Bottom stays clear of the home indicator and controls
- [ ] Select Center → subtitles remain geometrically centered whether controls are visible or hidden
- [ ] Test macOS and tvOS → Bottom clears each platform's control overlay without sitting unnecessarily high after controls hide
- [ ] Reset to Defaults → returns to platform defaults
- [ ] Test on tvOS: all controls work with remote navigation

## Playback Restart

- [ ] Movie with saved progress: detail screen shows **Start from Beginning** and playback starts at 0
- [ ] Movie without saved progress: Start from Beginning is hidden
- [ ] Episode with saved progress: context menu shows **Play from Beginning** and playback starts at 0
- [ ] Verify movie and episode behavior on iOS, macOS, and tvOS

## Browse Badges and Counts

- [ ] Favorite a movie → filled red heart appears at the poster's top-left in category, Home, Favorites, Recently Watched, and similar-title cards
- [ ] Favorite a series → the same heart appears on all series poster variants
- [ ] Rating badge remains top-right and never overlaps the favorite heart
- [ ] Unfavorite a movie/series → heart disappears immediately
- [ ] Favorite a Live TV channel → inline red heart appears beside its channel name
- [ ] Movies, Series, and Live TV tabs show playlist-scoped content totals; hidden/restricted content is not counted where applicable

## Category Reorder and Stalker Loading

- [ ] iOS Live TV: tap the up/down button on the category bar → sheet opens directly in reorder mode
- [ ] Reorder categories, dismiss, and relaunch → order persists
- [ ] Stalker sync: page-1 posters appear when visible sync completes
- [ ] Continue browsing after sync → remaining VOD and series items from pages 2–20 populate in the background across all categories

## General Regression

- [ ] Xtream playlist: live TV, movies, series all play normally
- [ ] M3U playlist: channels and content play normally
- [ ] EPG guide: now/next data shows on channel cards
- [ ] Player engine fallback: if KSPlayer fails, falls to VLC/AVPlayer
- [ ] PiP: works on iOS/macOS with KSPlayer and AVPlayer
- [ ] No crashes when switching playlists or during auto-sync
