# Apex Screenshot Capture Workflow — Build 64

## Pre-Capture Setup (Do This Once)

### 1. Prepare Your Demo Content
- **Live TV:** Add at least one Xtream or M3U playlist with working EPG data. Ensure 5+ channels have current programme listings spanning the next 4 hours.
- **Movies/Series:** Sync a playlist that pulls TMDB metadata. Verify at least one series has future-dated episodes showing "Upcoming" status with fallback artwork.
- **Profiles:** Create 2–3 user profiles in Settings → Profiles. Use different avatar symbols and color tints (e.g., blue person, green star, orange crown).
- **Favorites/Watched:** Mark 2–3 movies as watched and 2–3 as favorites so those states are visible in screenshots.

### 2. Configure Appearance
- Open Settings → Appearance → Theme → select **Midnight** or **Ocean**.
- Disable any debug overlays, developer menus, or test banners.
- Set device language to **English**.
- Ensure status bar shows full battery + Wi-Fi (no cellular on tvOS/macOS). Hide personal info (real usernames, server URLs).

### 3. Device-Specific Prep
| Platform | Orientation | Notes |
|----------|-------------|-------|
| iPhone 6.7" | Portrait | Disable Dynamic Island crop if using simulator |
| iPhone 5.5" | Portrait | Use SE 3rd gen or 8 Plus simulator |
| iPad 12.9" | Landscape | Enable sidebar in Live TV settings |
| Apple TV | Landscape (16:9) | Use Apple TV 4K simulator; connect Siri Remote |
| macOS | Windowed | Resize window to 2560×1600 logical; hide dock |

---

## Capture Order (Follow This Sequence)

Capture in this order to avoid re-setup between shots:

1. **iPhone 6.7"** — Shots 1→5 (all portrait, same session)
2. **iPad 12.9"** — Shots 1→3 (landscape, same session)
3. **Apple TV** — Shots 1→5 (landscape, same session)
4. **macOS** — Shots 1→2 (windowed, same session)
5. **iPhone 5.5"** — Re-capture Shots 1 & 3 only (required sizes differ)

---

## Shot-by-Shot Capture Instructions

### iPhone 6.7" Shot 1: Live TV Guide with Mini Preview
1. Open app → Live TV tab → EPG view.
2. Wait 3 seconds for mini preview to start playing (verify no spinner).
3. Scroll horizontally so the red "now" line is centered.
4. Verify: timeline shows current time, mini preview video frames visible, channel column aligned.
5. Capture via Xcode Simulator → File → Save Screen (or ⌘+S on device).
6. **Check:** No loading wheel in preview corner. Now-line visible on ruler. At least 4 channel rows shown.

### iPhone 6.7" Shot 2: Movie Detail Page
1. Navigate to Movies tab → tap a movie with full TMDB metadata (backdrop image loaded).
2. Scroll down to reveal cast carousel and description.
3. Verify: Play button, heart (favorite), checkmark (watched) all visible. Backdrop extends behind title.
4. Capture.
5. **Check:** No placeholder images. Cast headshots loaded. Rating badge visible.

### iPhone 6.7" Shot 3: Series Season with Mixed States
1. Navigate to Series tab → open a series with upcoming episodes.
2. Scroll to show at least one "Upcoming" episode with backdrop fallback art AND one playable episode.
3. Verify: "Upcoming" label visible, fallback art is series backdrop (not blank box), playable episode has thumbnail.
4. Capture.
5. **Check:** No empty grey boxes. Episode titles readable. Mixed states clearly distinguishable.

### iPhone 6.7" Shot 4: In-Player Guide Overlay
1. Play a live channel from EPG.
2. After 2 seconds of playback, swipe up (or tap Info) to open guide overlay.
3. Verify: Video playing underneath, guide panel overlaid, current channel highlighted, timeline synced to playback position.
4. Capture immediately (overlay auto-hides after 8 seconds).
5. **Check:** Guide shows current time marker. Channel row matches playing stream. No black screen under overlay.

### iPhone 6.7" Shot 5: Multi-Source Playlist Switcher
1. Go to Settings → Playlists.
2. Verify at least 2 playlists of different types (e.g., Xtream + M3U) with green sync badges.
3. Capture.
4. **Check:** Source type labels visible ("Xtream Codes", "M3U Playlist"). Sync indicators green. No Stremio references.

### iPad 12.9" Shot 1: Split View Browsing
1. Open Live TV in landscape. Sidebar should auto-appear.
2. Select a category in sidebar; right pane shows EPG grid.
3. Verify: Sidebar width ~280pt, right pane shows 6+ channel rows, mini preview active.
4. Capture.
5. **Check:** No horizontal scrolling needed. Text readable at native resolution. Sidebar categories populated.

### iPad 12.9" Shot 2: Wide EPG Timeline
1. In Live TV EPG, pinch-zoom out to show ~6 hours of timeline.
2. Scroll vertically to center current time.
3. Verify: Time ruler labels readable, programme blocks show titles, progress bars on live items.
4. Capture.
5. **Check:** No clipped text. At least 8 channel rows visible. Now-line positioned correctly.

### iPad 12.9" Shot 3: Series Grid with Fallback Art
1. Open same series as iPhone Shot 3, in landscape.
2. Verify multi-column layout shows 3–4 episodes per row.
3. Capture.
4. **Check:** Upcoming episodes show backdrop fallback. Grid alignment consistent. No orphaned single-column rows.

### Apple TV Shot 1: Home Hero Carousel with Focus Ring
1. Navigate to home screen.
2. Use Siri Remote to focus on a movie/show poster.
3. **Hold focus for 1 second** to let scale-up animation complete.
4. Verify: Focused poster visibly larger than neighbors, white ring around artwork, unfocused posters dimmed.
5. Capture via Xcode Simulator → Window → Save Screen.
6. **Check:** Focus ring crisp (not blurry). Scale difference obvious. Hero backdrop loaded.

### Apple TV Shot 2: EPG Grid with Synced Frozen Column
1. Open Live TV → EPG.
2. Press Down on Siri Remote 5 times to scroll vertically.
3. **Capture mid-scroll** (press capture while pressing Down again).
4. Verify: Channel logos/names in frozen column align perfectly with programme rows. No vertical offset drift.
5. **Check:** Alignment holds during motion blur. Text sharp. At least 6 rows visible. This is your most important tvOS shot.

### Apple TV Shot 3: Mini Preview While Browsing
1. Start playing a live channel.
2. Press Menu to return to EPG browse view.
3. Verify: Corner PiP playing video, no spinner, EPG grid navigable underneath.
4. Capture.
5. **Check:** Video frames rendering (not black). Spinner absent. Preview size appropriate for 10-foot viewing.

### Apple TV Shot 4: Profile Switcher
1. Navigate to Settings → Profiles (or long-press avatar on home).
2. Verify 2+ profiles displayed with distinct avatars and color tints.
3. Focus on non-active profile to show selection state.
4. Capture.
5. **Check:** Avatar symbols distinct. Color tints visible against dark background. Active indicator clear.

### Apple TV Shot 5: Top Shelf Extension
1. From tvOS home screen, scroll UP to Top Shelf area.
2. Navigate horizontally to Apex row.
3. Verify: Continue-watching items and favorite channels populated with real artwork.
4. Capture.
5. **Check:** Row title reads "Apex". Items have thumbnails. No empty placeholders. Focus state visible on one item.

### macOS Shot 1: Windowed EPG Guide
1. Launch Apex on Mac. Resize window to fill 2560×1600 logical space.
2. Open Live TV → EPG. Hover pointer over a programme block to show hover state.
3. Capture via ⌘+Shift+4 (select window).
4. **Check:** Pointer cursor visible. Compact metrics appropriate for desktop. Sidebar navigation visible.

### macOS Shot 2: Movie Detail in Window
1. Open a movie detail page.
2. Verify backdrop, metadata, action buttons all rendered at desktop scale.
3. Capture.
4. **Check:** Text crisp at Retina resolution. Button hit targets appropriately sized for mouse. No touch-only UI elements.

---

## Post-Capture Processing

### Cropping & Cleanup
- Remove status bar if it shows personal info (time/battery/WiFi OK to keep).
- Crop to exact export dimensions listed in SHOT_LIST.md.
- Do NOT add device frames or bezels.
- Do NOT add shadows or reflections.

### Annotation Placement
- Add annotations AFTER cropping to final size.
- Position text in bottom 15% of frame.
- Use SF Pro Display Bold 48–64pt (scale proportionally for smaller sizes).
- White text with 2px black drop shadow OR theme accent color with no shadow.
- Never exceed 6 words headline + 8 words subline.

### Export Checklist Per File
- [ ] Correct pixel dimensions for platform
- [ ] PNG-24 format (no JPEG compression)
- [ ] sRGB color profile embedded
- [ ] Filename matches convention: `{platform}_{size}_{shot_number}_{description}.png`
- [ ] No alpha transparency artifacts
- [ ] Annotation text legible at App Store thumbnail size (test by shrinking to 200px wide)

---

## Common Pitfalls to Avoid

| Mistake | Fix |
|---------|-----|
| Empty EPG grid | Wait 30s after app launch for sync; verify playlist has active EPG source |
| Spinner stuck in preview | Build 60 fix deployed; if still visible, restart app and wait 5s |
| Poster focus ring not visible | Hold Siri Remote focus for full 1 second before capture |
| Frozen column misaligned | This was fixed in Build 60; if drifting, pull latest code and rebuild |
| Blank episode boxes | Verify TMDB sync completed; check series has future episodes in metadata |
| Status bar shows phone number/name | Enable Airplane Mode or use simulator with clean profile |
| Stremio references visible | Pull commit `7a3c669`; verify LoginView and PlaylistDetailView cleaned |
| Wrong orientation | iPhone/iPad = portrait; Apple TV/macOS = landscape (no exceptions) |

---

## Submission Notes for App Store Connect

When uploading screenshots:
- **iPhone 6.7"** is required; 5.5" is optional but recommended for older device coverage.
- **iPad 12.9"** is required if submitting universal app.
- **Apple TV** screenshots are mandatory for tvOS target.
- **macOS** screenshots required only if submitting Mac App Store build.
- Upload in the order listed above — first screenshot appears as search result thumbnail.
- For localization: duplicate this workflow per language, but prioritize English for initial submission.