# Privacy Policy

**Last updated:** July 15, 2026

Apex is built by StreamInfinity. This policy explains what data the app handles and how.

---

## What Apex Does NOT Collect

Apex does **not** collect, transmit, or sell any personal data to StreamInfinity or any third-party analytics service. Specifically:

- **No analytics SDKs.** No Firebase, no Google Analytics, no Mixpanel — nothing that tracks your usage.
- **No accounts with us.** Apex has no first-party login. Your profiles, watch history, favorites, and playlist credentials live on your device and in your personal iCloud account (CloudKit private database, credentials encrypted).
- **No ad networks.** The app contains no third-party advertisements.

## What Stays On Your Device

| Data | Where it lives |
|---|---|
| Playlist credentials (Xtream Codes, M3U URLs, Stalker portals, Stremio) | Your device (SwiftData) + your personal iCloud (`SyncedPlaylist`, CloudKit-encrypted fields) |
| Watch history & progress | Your device + your personal iCloud |
| User profiles & favorites | Your device + your personal iCloud |
| TV guide (EPG) listings | Your device only (not synced via iCloud) |
| App theme & settings | Your device (+ theme via iCloud Key-Value store) |
| Trakt tokens / parental PIN | Keychain (device-local) |

## Third-Party Services You May Choose to Use

Apex integrates with external services that **you** configure. When you provide credentials for these services, data flows directly between the app and their servers — StreamInfinity never sees it.

| Service | What it processes | Privacy policy |
|---|---|---|
| **Apple CloudKit** | Syncs your playlist credentials/config, profiles, watch progress, and favorites across your devices via your iCloud account (catalog content re-downloads per device) | [Apple Privacy Policy](https://www.apple.com/legal/privacy/) |
| **TMDB** (The Movie Database) | Fetches posters, backdrops, cast info, and descriptions for movies and series | [TMDB Privacy Policy](https://www.themoviedb.org/privacy-policy) |
| **OMDb** (Open Movie Database) | Fetches IMDb, Rotten Tomatoes, and Metacritic ratings | [OMDb Disclaimer](https://www.omdbapi.com) |
| **Trakt** | Scrobbles watch activity if you sign in (optional) | [Trakt Privacy Policy](https://trakt.tv/privacy) |
| **IPTV Providers** (Xtream Codes, M3U, Stalker, Stremio addons) | Streams content you request using credentials or URLs you provide | Check with your provider |

## In-App Purchases

Purchases (Apex Pro monthly subscription and lifetime unlock) are processed entirely by **Apple** via StoreKit. StreamInfinity does not receive or store your payment details. Apple's own privacy policy governs the transaction.

## Data Retention & Deletion

To remove all Apex data:

1. Delete your user profiles and saved playlists within the app
2. Delete the app from your device
3. To remove synced data from iCloud: go to **Settings → [Your Name] → iCloud → Manage Account Storage → Apex → Delete Data**

## Children

Apex is not directed at children under 13. It does not knowingly collect data from anyone.

## Changes to This Policy

This policy may be updated over time. Changes will be posted to this page.

## Contact

If you have questions about this policy:

📧 **support@streaminfinitytv.com**

---

*Apex is open-source software licensed under the GNU AGPL v3.*
