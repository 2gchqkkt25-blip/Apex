//
//  CloudSyncEngine+Playlists.swift
//  Apex
//
//  iCloud reconcile for playlist identity, including explicit deletes.
//

import Foundation
import OSLog
import SwiftData

extension CloudSyncEngine {
    /// Applies an explicit user deletion to both stores in one actor-isolated
    /// operation. Deleting only the catalog row is ambiguous when this device
    /// has not established a shadow baseline yet: the next reconcile sees the
    /// cloud mirror as a new playlist and restores it locally.
    func deletePlaylist(id: UUID) throws {
        defer { releaseHydratedRows() }

        let localDescriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.id == id }
        )
        let mirrorDescriptor = FetchDescriptor<SyncedPlaylist>(
            predicate: #Predicate { $0.id == id }
        )

        let locals = try catalogContext.fetch(localDescriptor)
        let mirrors = try cloudContext.fetch(mirrorDescriptor)

        let baseline = locals.first.map(Self.values(from:))
            ?? mirrors.first.map(Self.values(from:))
            ?? shadow.playlistShadow(id.uuidString)
        // Keep the last live value as a shadow baseline. If CloudKit briefly
        // re-imports the pre-delete record, merge still resolves toward deletion.
        if let baseline {
            shadow.setPlaylistShadow(id.uuidString, baseline)
        }

        for local in locals {
            PlaylistDeletion.delete(local, in: catalogContext)
        }
        if mirrors.isEmpty, let baseline {
            insertPlaylistTombstone(id: id, baseline: baseline)
        } else {
            for mirror in mirrors {
                tombstonePlaylistMirror(mirror)
            }
        }

        try saveStores()
        shadow.persist()
    }

    /// Returns the set of "live" playlist UUID strings (present locally or in the
    /// cloud after this pass) so the content pass can garbage-collect state whose
    /// playlist is gone.
    func reconcilePlaylists(into result: inout CloudSyncReconcileResult) throws -> Set<String> {
        let localByID = try fetchLocalPlaylists()
        let mirrorsByID = try fetchPlaylistMirrors()

        var ids = Set(localByID.keys).union(mirrorsByID.keys)
        ids.formUnion(shadow.playlistShadowIDs().compactMap(UUID.init(uuidString:)))

        var live = Set<String>()
        for id in ids {
            let key = id.uuidString
            let mirror = mirrorsByID[id]
            let isTombstone = mirror?.deletedAt != nil
            let cloudValues: PlaylistConfigValues? = {
                guard let mirror, !isTombstone else { return nil }
                return Self.values(from: mirror)
            }()
            var verdict = CloudSyncMerge.reconcile(
                local: localByID[id].map(Self.values(from:)),
                cloud: cloudValues,
                shadow: shadow.playlistShadow(key),
                mergeConflict: PlaylistConfigValues.mergeConflict
            )
            if isTombstone {
                // Explicit delete from another device always wins, including
                // when this device has no shadow baseline yet (which would
                // otherwise look like a local create and un-delete the tombstone).
                if localByID[id] != nil {
                    verdict = .pullToLocal(nil)
                }
            } else if case .pullToLocal(.none) = verdict, let local = localByID[id] {
                // A missing mirror while the playlist is still here is how a
                // slow/partial CloudKit import looks — applying it would wipe
                // the catalog. Refuse that wipe and re-publish instead.
                Logger.sync.error("Refusing iCloud playlist deletion for \(key, privacy: .public) — local playlist still present; re-publishing instead of wiping the catalog")
                verdict = .pushToCloud(Self.values(from: local))
            }
            applyPlaylistVerdict(verdict, id: id, local: localByID[id], mirror: mirror, into: &result)

            if playlistRemains(
                verdict: verdict,
                hadLocal: localByID[id] != nil,
                hadLiveCloud: mirror != nil && !isTombstone
            ) {
                live.insert(key)
            }
        }
        return live
    }

    private func applyPlaylistVerdict(
        _ verdict: MergeVerdict<PlaylistConfigValues>,
        id: UUID,
        local: Playlist?,
        mirror: SyncedPlaylist?,
        into result: inout CloudSyncReconcileResult
    ) {
        let key = id.uuidString
        switch verdict {
        case .noChange:
            break
        case let .pushToCloud(value):
            applyPlaylistToCloud(value, id: id, mirror: mirror)
            if value != nil { result.playlistsPushed += 1 }
            shadow.setPlaylistShadow(key, value)
        case let .pullToLocal(value):
            if applyPlaylistToLocal(value, id: id, local: local) {
                result.playlistsCreatedLocally += 1
                result.importedPlaylistIDs.insert(id)
            }
            if value != nil { result.playlistsPulled += 1 }
            shadow.setPlaylistShadow(key, value)
        case let .writeBoth(value):
            applyPlaylistToCloud(value, id: id, mirror: mirror)
            if applyPlaylistToLocal(value, id: id, local: local) {
                result.playlistsCreatedLocally += 1
                result.importedPlaylistIDs.insert(id)
            }
            result.playlistsPushed += 1
            shadow.setPlaylistShadow(key, value)
        }
    }

    private func applyPlaylistToCloud(_ value: PlaylistConfigValues?, id: UUID, mirror: SyncedPlaylist?) {
        guard let value else {
            if let mirror {
                tombstonePlaylistMirror(mirror)
            } else {
                insertPlaylistTombstone(id: id, baseline: nil)
            }
            return
        }
        if let mirror {
            mirror.deletedAt = nil
            mirror.name = value.name
            mirror.serverURL = value.serverURL
            mirror.username = value.username
            mirror.password = value.password
            mirror.macAddress = value.macAddress
            mirror.sourceTypeRaw = value.sourceTypeRaw
            mirror.epgURL = value.epgURL
            mirror.syncEnabled = value.syncEnabled
            mirror.updatedAt = Date()
        } else {
            cloudContext.insert(SyncedPlaylist(
                id: id,
                name: value.name,
                serverURL: value.serverURL,
                username: value.username,
                password: value.password,
                macAddress: value.macAddress,
                sourceTypeRaw: value.sourceTypeRaw,
                epgURL: value.epgURL,
                syncEnabled: value.syncEnabled
            ))
        }
    }

    /// Returns true if a new local `Playlist` was created (it has no
    /// `lastSyncDate`, so the UI's auto-sync will fetch its catalog).
    private func applyPlaylistToLocal(_ value: PlaylistConfigValues?, id: UUID, local: Playlist?) -> Bool {
        guard let value else {
            if let local { PlaylistDeletion.delete(local, in: catalogContext) }
            return false
        }
        if let local {
            local.name = value.name
            local.serverURL = value.serverURL
            local.username = value.username
            local.password = value.password
            local.macAddress = value.macAddress.isEmpty ? nil : value.macAddress
            local.sourceTypeRaw = value.sourceTypeRaw
            local.epgURL = value.epgURL
            local.syncEnabled = value.syncEnabled
            return false
        }
        let playlist = Playlist(name: value.name, serverURL: value.serverURL, username: value.username, password: value.password)
        playlist.id = id
        playlist.macAddress = value.macAddress.isEmpty ? nil : value.macAddress
        playlist.sourceTypeRaw = value.sourceTypeRaw
        playlist.epgURL = value.epgURL
        playlist.syncEnabled = value.syncEnabled
        catalogContext.insert(playlist)
        return true
    }

    private func playlistRemains(
        verdict: MergeVerdict<PlaylistConfigValues>,
        hadLocal: Bool,
        hadLiveCloud: Bool
    ) -> Bool {
        switch verdict {
        case .noChange: hadLocal || hadLiveCloud
        case let .pushToCloud(value), let .pullToLocal(value): value != nil
        case .writeBoth: true
        }
    }

    private func tombstonePlaylistMirror(_ mirror: SyncedPlaylist) {
        mirror.deletedAt = Date()
        mirror.updatedAt = Date()
        mirror.username = ""
        mirror.password = ""
        mirror.macAddress = ""
        mirror.catalogSyncDeviceID = ""
        mirror.catalogSyncHeartbeatAt = nil
    }

    private func insertPlaylistTombstone(id: UUID, baseline: PlaylistConfigValues?) {
        cloudContext.insert(SyncedPlaylist(
            id: id,
            name: baseline?.name ?? "",
            serverURL: baseline?.serverURL ?? "",
            username: "",
            password: "",
            macAddress: "",
            sourceTypeRaw: baseline?.sourceTypeRaw ?? PlaylistSourceType.xtream.rawValue,
            epgURL: nil,
            syncEnabled: false,
            deletedAt: Date()
        ))
    }

    /// Publishes a quiet-period lease so sibling devices skip auto-sync. If this
    /// playlist is not yet in the cloud store (first add), the local config is
    /// pushed in the same save so the lease arrives with the playlist.
    func claimCatalogSyncLease(playlistID: UUID, deviceID: String) throws {
        defer { releaseHydratedRows() }

        let locals = try fetchLocalPlaylists()
        let mirrors = try fetchPlaylistMirrors()
        guard let local = locals[playlistID] else { return }
        if let mirror = mirrors[playlistID], mirror.deletedAt != nil { return }

        if mirrors[playlistID] == nil {
            let values = Self.values(from: local)
            applyPlaylistToCloud(values, id: playlistID, mirror: nil)
            shadow.setPlaylistShadow(playlistID.uuidString, values)
        }
        guard let mirror = try fetchPlaylistMirrors()[playlistID], mirror.deletedAt == nil else { return }
        mirror.catalogSyncDeviceID = deviceID
        mirror.catalogSyncHeartbeatAt = Date()
        mirror.updatedAt = Date()
        try saveStores()
        shadow.persist()
    }

    func releaseCatalogSyncLease(playlistID: UUID, deviceID: String) throws {
        defer { releaseHydratedRows() }
        guard let mirror = try fetchPlaylistMirrors()[playlistID],
              mirror.catalogSyncDeviceID == deviceID
        else { return }
        mirror.catalogSyncDeviceID = ""
        mirror.catalogSyncHeartbeatAt = nil
        mirror.updatedAt = Date()
        try saveStores()
    }

    func catalogSyncLeases() throws -> [UUID: CatalogSyncLease] {
        defer { releaseHydratedRows() }
        var map: [UUID: CatalogSyncLease] = [:]
        for (id, mirror) in try fetchPlaylistMirrors() {
            guard mirror.deletedAt == nil,
                  !mirror.catalogSyncDeviceID.isEmpty,
                  let started = mirror.catalogSyncHeartbeatAt
            else { continue }
            map[id] = CatalogSyncLease(deviceID: mirror.catalogSyncDeviceID, startedAt: started)
        }
        return map
    }
}
