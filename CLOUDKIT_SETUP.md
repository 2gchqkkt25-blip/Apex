# CloudKit Setup — Apex

Container: **`iCloud.com.streaminfinity.apex`**

SwiftData syncs four lightweight user-data models (not the catalog):

| Model | What syncs |
|-------|------------|
| `SyncedPlaylist` | Playlist credentials + config (catalog re-fetched per device) |
| `UserContentState` | Watch progress, favorites, watchlist, recommendation votes |
| `UserProfile` | Profile roster (names, avatars, child flag) |
| `SyncedEPGSource` | Manual EPG sources only |

Catalog models (`Movie`, `Series`, etc.) stay in local `default.store` only.

---

## 1. Apple Developer Portal (one-time)

1. [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles**
2. **Identifiers** → App ID `com.streaminfinity.apex`
3. Confirm **iCloud** is enabled with container **`iCloud.com.streaminfinity.apex`**
4. If you add the container here, regenerate provisioning profiles in Xcode (**Signing & Capabilities** → refresh)

Entitlements in this repo already reference the container (`Apex.entitlements`, `Apex-Release.entitlements`).

---

## 2. Bootstrap the Development schema

CloudKit creates the schema automatically when a signed build first writes to the private database.

**Before running the app:**

1. [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles** → **Identifiers**
2. Open App ID **`com.streaminfinity.apex`**
3. Enable **iCloud** → **Configure** → check **CloudKit**
4. Under Containers, ensure **`iCloud.com.streaminfinity.apex`** exists (create it if missing)
5. Save, then in Xcode: **Signing & Capabilities** → **+ Capability** → **iCloud** → check **CloudKit** and select **`iCloud.com.streaminfinity.apex`**
6. **Product → Clean Build Folder**, delete Apex from the phone, run again

**Then on device:**

1. Build **Debug** or **Release** from Xcode (not an old TestFlight build from before CloudKit was re-enabled)
2. Device signed into **iCloud** (Settings → Apple Account → iCloud → Apex allowed)
3. Open Apex and do a few actions that write user data:
   - Ensure a playlist is synced
   - Watch part of a title (progress)
   - Favorite something
4. **Settings → iCloud Sync** should show **On** (not stuck on **Checking…**)
5. In Xcode console, filter for `CloudKit sync enabled: true`

**CloudKit Console — where to look:**

- URL: [icloud.developer.apple.com](https://icloud.developer.apple.com)
- Select container **`iCloud.com.streaminfinity.apex`**
- Environment dropdown (top left): **Development** (Production stays empty until you deploy)
- **Schema** tab: record types appear after the app’s first successful export (can take a minute). Confirmed July 2, 2026: `CD_SyncedPlaylist`, `CD_UserContentState`, `CD_UserProfile`.

If Settings shows **Off**, you’re in a SwiftUI preview or test run — reinstall a normal **Debug** or **Release** build from Xcode on your phone.

If Settings shows **Unavailable** after ~10 seconds, the container isn’t provisioned for this App ID / signing profile yet.

---

## 3. Deploy schema to Production (required before TestFlight)

TestFlight and App Store builds use the **Production** CloudKit environment.

1. Open [CloudKit Console](https://icloud.developer.apple.com)
2. Select container **`iCloud.com.streaminfinity.apex`**
3. **Development** → **Schema** → confirm record types exist. SwiftData creates **`CD_`-prefixed** types, e.g.:
   - `CD_SyncedPlaylist`
   - `CD_UserContentState`
   - `CD_UserProfile`
   - `CD_SyncedEPGSource` (after a manual EPG source is saved)
4. **Deploy Schema Changes…** → choose **Development → Production**
5. Review the diff and confirm deploy

Do **not** skip this step — Production builds without a deployed schema fail sync with opaque `CKError` / partial-failure logs.

---

## 4. Verify before TestFlight

1. Archive with **Release** configuration (uses `Apex-Release.entitlements`)
2. Install the archived build on a device (or wait for TestFlight)
3. Settings → **iCloud Sync** → **On**, no sync error line
4. Optional second device: same Apple ID → playlist + progress should appear after catalog sync

---

## 5. Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| iCloud Sync stuck on **Checking…** | Old TestFlight build with CloudKit disabled, or container not provisioned |
| **Schema** tab empty in CloudKit Console | App hasn’t exported yet — fix sync first; confirm **Development** environment |
| iCloud Sync **No iCloud Account** | Device not signed into iCloud |
| Sync works in Xcode Debug but not TestFlight | Production schema not deployed |
| iCloud Sync shows **Off** | SwiftUI preview / test build only — reinstall Debug or Release from Xcode |
| App crashes at launch in previews/tests | Expected — CloudKit is disabled for previews, unit tests, and UI tests |

CloudKit is disabled only for **SwiftUI previews** and **automated tests**. Unsigned community sideload IPAs from GitHub Actions won’t sync (re-signing strips entitlements).

---

## Status (July 2, 2026)

| Step | Status |
|------|--------|
| Container + App ID iCloud capability | ✅ |
| Development schema bootstrapped | ✅ (`CD_SyncedPlaylist`, `CD_UserContentState`, `CD_UserProfile`) |
| Device Settings → iCloud Sync **On** | ✅ |
| **Production schema deploy** | ✅ Deployed |
| **Production sync verified** (playlist + user data) | ✅ TestFlight |
| External TestFlight Beta App Review | 🔄 Per build (build **17** uploading) |

---

## Code reference

- Container ID: `ApexApp.cloudKitContainerIdentifier`
- Cloud store: `CloudUserData` configuration in `ApexApp.makeCloudContainer()`
- Reconcile engine: `CloudSyncEngine`, `CloudSyncCoordinator`
- Settings UI: `CloudSyncSettingsView`
