# TestFlight Checklist — Build 46

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
