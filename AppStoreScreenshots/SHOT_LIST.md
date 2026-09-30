# Apex App Store Screenshot Shot List — Build 63

## Capture Checklist Before You Start

- [ ] Use a **real IPTV source** with populated EPG data (not empty/test playlists)
- [ ] Set theme to **Midnight** or **Ocean** for dark screenshots (looks best in App Store)
- [ ] Ensure at least 3 channels have live EPG data spanning the current time window
- [ ] Have at least one series with TMDB metadata showing upcoming + available episodes
- [ ] Create 2+ user profiles with distinct avatars/colors before capturing tvOS shots
- [ ] Disable any test/debug overlays or developer menus
- [ ] Set device language to **English** for primary screenshots
- [ ] Use real movie/series artwork (no placeholder images visible)

---

## iPhone 6.7" (iPhone 15 Pro Max / 14 Pro Max) — Primary

### Shot 1: Live TV Guide with Mini Preview
**What to show:** Full EPG grid with timeline anchored to "now", mini preview playing in corner (no spinner), red now-indicator line visible on ruler.
**Setup:** Open Live TV → EPG tab. Navigate so current time is centered. Ensure mini preview is active and playing.
**Annotation:** `Live Guide · Always Anchored to Now`
**Why this matters:** Shows the Build 60 EPG re-anchor fix + spinner-free mini preview.

### Shot 2: Movie Detail Page
**What to show:** Rich movie detail with backdrop hero image, title, rating, play button, favorite heart, watched checkmark, cast row, and description.
**Setup:** Browse Movies → tap any movie with full TMDB metadata. Scroll to show cast carousel.
**Annotation:** `Rich Details · One Tap to Play`
**Why this matters:** Demonstrates metadata depth and clean UI hierarchy.

### Shot 3: Series Season with Mixed Episode States
**What to show:** Episode list showing playable episodes, "Upcoming" episodes with fallback backdrop art, and "Not available" labels.
**Setup:** Open a series that has future-dated TMDB episodes. Ensure at least one upcoming episode shows the series backdrop as fallback art.
**Annotation:** `Full Seasons · Upcoming & Available`
**Why this matters:** Highlights the Build 60 TMDB integration and fallback artwork.

### Shot 4: In-Player Guide Overlay
**What to show:** Video playing fullscreen with EPG guide panel overlaid, showing current channel highlighted and timeline synced to playback time.
**Setup:** Play a live channel → open guide overlay (swipe up or press info). Ensure guide shows current time position.
**Annotation:** `Guide Overlay · Never Lose Your Place`
**Why this matters:** Shows the player-integrated guide experience.

### Shot 5: Multi-Source Playlist Switcher
**What to show:** Settings or playlist view showing multiple configured sources (Xtream + M3U + Stalker) with sync status indicators.
**Setup:** Go to Settings → Playlists. Show at least 2 different source types with green sync badges.
**Annotation:** `Any Source · Xtream, M3U, Stalker`
**Why this matters:** Demonstrates broad provider compatibility (without mentioning removed Stremio).

---

## iPad 12.9" (iPad Pro) — Secondary

### Shot 1: Split View Browsing
**What to show:** Left sidebar with category/channel navigation, right pane showing EPG grid or movie detail. Emphasize spacious layout.
**Setup:** Open Live TV on iPad. Sidebar should be visible with categories. Right pane shows EPG with multiple rows.
**Annotation:** `Designed for iPad · Browse & Watch`

### Shot 2: Wide EPG Timeline
**What to show:** Horizontal guide spanning many hours with multiple channel rows, programme blocks with progress bars, and clear time ruler.
**Setup:** Landscape orientation. Zoom level showing ~6 hours of guide data. Red now-line visible.
**Annotation:** `24-Hour Guide · Scroll Anywhere`

### Shot 3: Series Grid with Fallback Art
**What to show:** Multi-column episode grid on larger screen, showing upcoming episodes with backdrop fallback art clearly visible.
**Setup:** Same series as iPhone Shot 3, but in iPad landscape to show more columns.
**Annotation:** `Complete Season Data · From TMDB`

---

## Apple TV (tvOS) — Critical Platform

### Shot 1: Home Hero Carousel with Focus Ring
**What to show:** Large cinematic hero banner with focused poster visibly scaled up and white ring highlight around it. Unfocused posters smaller/dimmer.
**Setup:** Navigate to home screen. Focus on a movie/show poster. Ensure the scale-up animation and white ring are captured mid-focus.
**Annotation:** `Cinematic Home · Focus That Pops`
**Why this matters:** Shows the Build 60 poster focus visibility fix.

### Shot 2: EPG Grid with Synced Frozen Column
**What to show:** Programme grid scrolling vertically with frozen channel column perfectly aligned — no lag, no offset drift. Channel logos/names match their programme rows exactly.
**Setup:** Open Live TV guide. Scroll down several rows. Capture mid-scroll to prove alignment holds during motion.
**Annotation:** `Synced Guide · No Drift, Ever`
**Why this matters:** This is THE key tvOS differentiator after the Build 60 focus fix.

### Shot 3: Mini Preview While Browsing
**What to show:** Corner PiP playing live video while EPG grid is browsed. No loading spinner visible. Video frames rendering cleanly.
**Setup:** Start playing a channel → navigate back to guide. Ensure preview is active and spinner-free.
**Annotation:** `Preview While You Browse · Instant`
**Why this matters:** Shows the Build 60 spinner fix in action.

### Shot 4: Profile Switcher
**What to show:** Multiple user profiles displayed with distinct avatars, colors, and names. Active profile highlighted.
**Setup:** Open profile switcher from settings or top menu. Show at least 2 profiles with different avatar symbols and color tints.
**Annotation:** `Family Profiles · Synced via iCloud`
**Why this matters:** Demonstrates multi-user support and CloudKit sync.

### Shot 5: Top Shelf Extension
**What to show:** tvOS home screen with Apex Top Shelf row visible, showing continue-watching items and favorite channels.
**Setup:** From home screen, scroll up to Top Shelf area. Ensure Apex row is populated with real content.
**Annotation:** `Quick Access · Right From Home`
**Why this matters:** Shows system integration beyond the app itself.

---

## macOS (Mac App Store) — If Submitting

### Shot 1: Windowed EPG Guide
**What to show:** App window showing EPG grid with pointer-hover states, compact metrics, and sidebar navigation.
**Annotation:** `Native Mac · Keyboard & Mouse Ready`

### Shot 2: Movie Detail in Window
**What to show:** Movie detail page in macOS window with backdrop, metadata, and action buttons.
**Annotation:** `Full Metadata · Beautiful at Any Size`

---

## Annotation Style Guide

| Element | Rule |
|---------|------|
| Font | SF Pro Display Bold or Helvetica Neue Bold |
| Size | 48–64pt for headline, 28–36pt for subline |
| Color | White text with subtle drop shadow, or accent color matching theme |
| Position | Bottom 15% of frame, left-aligned or centered |
| Length | Max 6 words headline + 8 words subline |
| Emoji | Never |
| ALL CAPS | Never (use title case) |

## File Naming Convention

```
{platform}_{size}_{shot_number}_{description}.png
Examples:
iphone_6.7_01_live_guide.png
ipad_12.9_02_wide_epg.png
appletv_01_hero_focus.png
macos_01_windowed_guide.png
```

## Export Specs

| Platform | Size (px) | Format | Color Space |
|----------|-----------|--------|-------------|
| iPhone 6.7" | 1290 × 2796 | PNG-24 | sRGB |
| iPhone 5.5" | 1242 × 2208 | PNG-24 | sRGB |
| iPad 12.9" | 2048 × 2732 | PNG-24 | sRGB |
| Apple TV | 3840 × 2160 | PNG-24 | sRGB |
| macOS | 2560 × 1600 | PNG-24 | sRGB |

All screenshots must be **portrait** for iPhone/iPad, **landscape** for Apple TV/macOS.
No device frames. No status bar (or clean status bar with full battery/wifi). No personal info visible.