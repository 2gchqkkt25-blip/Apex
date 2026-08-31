import Foundation
import OSLog
import SwiftData

/// The local-store integrity gate: the guard against catastrophic, cross-device
/// data loss. Split out of `CloudSyncEngine.swift` to keep that file within the
/// project's size limit.
///
/// If the local catalog store is unreadable or has come up empty (a
/// missing/recreated `default.store`, or a transient `no such table` detach
/// while `NSPersistentCloudKitContainer` re-adds stores on the shared
/// coordinator), a naive reconcile would read every absent local item as a
/// *user deletion* and push those deletions to the CloudKit mirrors — wiping the
/// data on every synced device. `reconcile()` consults this before mutating
/// anything.
extension CloudSyncEngine {
    /// The state of the local catalog store as a source of "local" truth.
    enum LocalCatalogReadiness {
        /// Catalog is readable with data (or legitimately empty on a fresh
        /// device, where the shadow is empty too) — reconcile normally.
        case ready
        /// A probe fetch threw: the store is mid-detach or corrupt. Skip the pass.
        case unreadable
        /// Catalog reads completely empty while the shadow baseline still holds
        /// playlists or content — a store that previously synced data cannot go
        /// empty in one legitimate step, so this is a lost/recreated store, not a
        /// mass deletion. Recover by re-pulling from the cloud.
        case emptiedButHadData
    }

    /// The state of the CloudKit mirror store as a source of "cloud" truth.
    ///
    /// The mirror image of `LocalCatalogReadiness`, and it was missing. A local
    /// playlist with no cloud mirror but a shadow baseline reads as "a sibling
    /// device deleted this", so reconcile deletes the playlist and every catalog
    /// row it brought in. That verdict is right only if the mirror store is
    /// actually complete — and at launch it frequently isn't, because
    /// `NSPersistentCloudKitContainer` imports asynchronously. On Apple TV HD the
    /// launch pass is deliberately delayed 30s to protect startup, which is still
    /// no guarantee the import has landed. So a slow import looked identical to a
    /// remote deletion and wiped a 37K-item library.
    enum CloudMirrorReadiness {
        /// Mirror holds records (or is empty on a genuinely fresh account, where
        /// the shadow is empty too) — reconcile normally.
        case ready
        /// A probe fetch threw. Skip the pass rather than guess.
        case unreadable
        /// The mirror is *entirely* empty while the shadow still holds baselines:
        /// an account that previously synced cannot lose every record in one
        /// legitimate step, so treat this as an import that hasn't arrived.
        case emptyButHadData
    }

    /// Note the deliberate asymmetry with a real remote deletion: if a user
    /// genuinely deletes their last playlist on another device, this suppresses
    /// that deletion and re-pushes from local instead. That's the intended
    /// trade — re-adding an unwanted playlist costs one more delete, whereas
    /// destroying the local catalog is unrecoverable. Requiring *total*
    /// emptiness keeps the false-positive window narrow: a partially populated
    /// mirror still reconciles normally, so ordinary per-item deletions sync.
    func cloudMirrorReadiness() -> CloudMirrorReadiness {
        let mirrorCount: Int
        let localPlaylistCount: Int
        do {
            mirrorCount = try cloudContext.fetchCount(FetchDescriptor<SyncedPlaylist>())
                + cloudContext.fetchCount(FetchDescriptor<UserContentState>())
                + cloudContext.fetchCount(FetchDescriptor<SyncedMediaServer>())
            localPlaylistCount = try catalogContext.fetchCount(FetchDescriptor<Playlist>())
        } catch {
            Logger.sync.error("Cloud mirror unreadable (\(error.localizedDescription, privacy: .public)) — skipping reconcile, not deleting local content")
            return .unreadable
        }
        let shadowHasBaseline = !shadow.playlistShadowIDs().isEmpty || !shadow.contentShadowIDs().isEmpty
        if mirrorCount == 0, shadowHasBaseline, localPlaylistCount > 0 {
            return .emptyButHadData
        }
        return .ready
    }

    func localCatalogReadiness() -> LocalCatalogReadiness {
        let catalogCount: Int
        do {
            catalogCount = try catalogContext.fetchCount(FetchDescriptor<Playlist>())
                + catalogContext.fetchCount(FetchDescriptor<Movie>())
                + catalogContext.fetchCount(FetchDescriptor<Series>())
                + catalogContext.fetchCount(FetchDescriptor<Episode>())
                + catalogContext.fetchCount(FetchDescriptor<LiveStream>())
        } catch {
            Logger.sync.error("Local catalog unreadable (\(error.localizedDescription, privacy: .public)) — skipping reconcile, not pushing deletions to iCloud")
            return .unreadable
        }
        let shadowHasBaseline = !shadow.playlistShadowIDs().isEmpty || !shadow.contentShadowIDs().isEmpty
        if catalogCount == 0, shadowHasBaseline {
            return .emptiedButHadData
        }
        return .ready
    }
}
