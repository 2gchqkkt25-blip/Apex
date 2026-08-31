//
//  CloudSyncEngine+MediaServers.swift
//  Apex
//
//  iCloud reconcile for home media server connections.
//

import Foundation
import OSLog
import SwiftData

extension CloudSyncEngine {
    /// Applies an explicit user deletion to both stores in one actor-isolated
    /// operation. Deleting only the catalog row is ambiguous when this device
    /// has not established a shadow baseline yet: the next reconcile sees the
    /// cloud mirror as a new connection and restores it locally.
    func deleteMediaServer(id: UUID) throws {
        defer { releaseHydratedRows() }

        let localDescriptor = FetchDescriptor<MediaServer>(
            predicate: #Predicate { $0.id == id }
        )
        let mirrorDescriptor = FetchDescriptor<SyncedMediaServer>(
            predicate: #Predicate { $0.id == id }
        )

        let locals = try catalogContext.fetch(localDescriptor)
        let mirrors = try cloudContext.fetch(mirrorDescriptor)

        // Retain the last value as a tombstone baseline until the follow-up
        // reconcile observes both rows absent. If CloudKit briefly re-imports
        // the old mirror while its deletion is exporting, the merge still
        // resolves toward deletion instead of resurrecting the connection.
        if let baseline = locals.first.map(Self.mediaServerValues(from:))
            ?? mirrors.first.map(Self.mediaServerValues(from:))
            ?? shadow.mediaServerShadow(id.uuidString)
        {
            shadow.setMediaServerShadow(id.uuidString, baseline)
        }

        for local in locals {
            MediaServerDeletion.delete(local, in: catalogContext)
        }
        for mirror in mirrors {
            cloudContext.delete(mirror)
        }

        try saveStores()
        shadow.persist()
    }

    /// Returns live media-server UUID strings so content-state reconcile keeps
    /// `{serverUUID}-movie-…` rows while the server exists locally or in cloud.
    func reconcileMediaServers(into result: inout CloudSyncReconcileResult) throws -> Set<String> {
        let localByID = try fetchLocalMediaServers()
        let mirrorsByID = try fetchMediaServerMirrors()

        var ids = Set(localByID.keys).union(mirrorsByID.keys)
        ids.formUnion(shadow.mediaServerShadowIDs().compactMap(UUID.init(uuidString:)))

        var live = Set<String>()
        for id in ids {
            var verdict = CloudSyncMerge.reconcile(
                local: localByID[id].map(Self.mediaServerValues(from:)),
                cloud: mirrorsByID[id].map(Self.mediaServerValues(from:)),
                shadow: shadow.mediaServerShadow(id.uuidString),
                mergeConflict: MediaServerConfigValues.mergeConflict
            )
            // Same hole as playlists: a missing `SyncedMediaServer` while the
            // local connection still exists is treated as a remote delete and
            // `MediaServerDeletion` wipes the Plex/Jellyfin catalog. Refuse and
            // re-publish so iCloud can stay enabled.
            if case .pullToLocal(.none) = verdict, let local = localByID[id] {
                Logger.sync.error("Refusing iCloud media-server deletion for \(id.uuidString, privacy: .public) — local connection still present; re-publishing instead of wiping the library")
                verdict = .pushToCloud(Self.mediaServerValues(from: local))
            }
            applyMediaServerVerdict(
                verdict,
                id: id,
                local: localByID[id],
                mirror: mirrorsByID[id],
                into: &result
            )

            if mediaServerRemains(
                verdict: verdict,
                hadLocal: localByID[id] != nil,
                hadCloud: mirrorsByID[id] != nil
            ) {
                live.insert(id.uuidString)
            }
        }
        return live
    }

    private func applyMediaServerVerdict(
        _ verdict: MergeVerdict<MediaServerConfigValues>,
        id: UUID,
        local: MediaServer?,
        mirror: SyncedMediaServer?,
        into result: inout CloudSyncReconcileResult
    ) {
        let key = id.uuidString
        switch verdict {
        case .noChange:
            break
        case let .pushToCloud(value):
            applyMediaServerToCloud(value, id: id, mirror: mirror)
            if value != nil { result.mediaServersPushed += 1 }
            shadow.setMediaServerShadow(key, value)
        case let .pullToLocal(value):
            if applyMediaServerToLocal(value, id: id, local: local) {
                result.mediaServersCreatedLocally += 1
            }
            if value != nil { result.mediaServersPulled += 1 }
            shadow.setMediaServerShadow(key, value)
        case let .writeBoth(value):
            applyMediaServerToCloud(value, id: id, mirror: mirror)
            if applyMediaServerToLocal(value, id: id, local: local) {
                result.mediaServersCreatedLocally += 1
            }
            result.mediaServersPushed += 1
            shadow.setMediaServerShadow(key, value)
        }
    }

    func applyMediaServerToCloud(_ value: MediaServerConfigValues?, id: UUID, mirror: SyncedMediaServer?) {
        guard let value else {
            if let mirror { cloudContext.delete(mirror) }
            return
        }
        if let mirror {
            mirror.name = value.name
            mirror.baseURL = value.baseURL
            mirror.kindRaw = value.kindRaw
            mirror.username = value.username
            mirror.password = value.password
            mirror.accessToken = value.accessToken
            mirror.plexToken = value.plexToken
            mirror.userId = value.userId
            mirror.plexServerIdentifier = value.plexServerIdentifier
            mirror.syncEnabled = value.syncEnabled
            mirror.sortOrder = value.sortOrder
            mirror.updatedAt = Date()
        } else {
            cloudContext.insert(SyncedMediaServer(
                id: id,
                name: value.name,
                baseURL: value.baseURL,
                kindRaw: value.kindRaw,
                username: value.username,
                password: value.password,
                accessToken: value.accessToken,
                plexToken: value.plexToken,
                userId: value.userId,
                plexServerIdentifier: value.plexServerIdentifier,
                syncEnabled: value.syncEnabled,
                sortOrder: value.sortOrder
            ))
        }
    }

    /// Returns true when a new local `MediaServer` was created (`lastSyncDate`
    /// stays nil so the Media tab auto-sync fetches its catalog).
    func applyMediaServerToLocal(_ value: MediaServerConfigValues?, id: UUID, local: MediaServer?) -> Bool {
        guard let value else {
            if let local { MediaServerDeletion.delete(local, in: catalogContext) }
            return false
        }
        if let local {
            local.name = value.name
            local.baseURL = value.baseURL
            local.kindRaw = value.kindRaw
            local.username = value.username
            local.password = value.password
            local.accessToken = value.accessToken
            local.plexToken = value.plexToken
            local.userId = value.userId
            local.plexServerIdentifier = value.plexServerIdentifier
            local.syncEnabled = value.syncEnabled
            local.sortOrder = value.sortOrder
            return false
        }
        let server = MediaServer(name: value.name, baseURL: value.baseURL, kind: MediaServerKind(rawValue: value.kindRaw) ?? .jellyfin)
        server.id = id
        server.username = value.username
        server.password = value.password
        server.accessToken = value.accessToken
        server.plexToken = value.plexToken
        server.userId = value.userId
        server.plexServerIdentifier = value.plexServerIdentifier
        server.syncEnabled = value.syncEnabled
        server.sortOrder = value.sortOrder
        catalogContext.insert(server)
        return true
    }

    private func mediaServerRemains(
        verdict: MergeVerdict<MediaServerConfigValues>,
        hadLocal: Bool,
        hadCloud: Bool
    ) -> Bool {
        switch verdict {
        case .noChange: hadLocal || hadCloud
        case let .pushToCloud(value), let .pullToLocal(value): value != nil
        case .writeBoth: true
        }
    }
}

extension CloudSyncEngine {
    static func mediaServerValues(from server: MediaServer) -> MediaServerConfigValues {
        MediaServerConfigValues(
            name: server.name,
            baseURL: server.baseURL,
            kindRaw: server.kindRaw,
            username: server.username,
            password: server.password,
            accessToken: server.accessToken,
            plexToken: server.plexToken,
            userId: server.userId,
            plexServerIdentifier: server.plexServerIdentifier,
            syncEnabled: server.syncEnabled,
            sortOrder: server.sortOrder
        )
    }

    static func mediaServerValues(from mirror: SyncedMediaServer) -> MediaServerConfigValues {
        MediaServerConfigValues(
            name: mirror.name,
            baseURL: mirror.baseURL,
            kindRaw: mirror.kindRaw,
            username: mirror.username,
            password: mirror.password,
            accessToken: mirror.accessToken,
            plexToken: mirror.plexToken,
            userId: mirror.userId,
            plexServerIdentifier: mirror.plexServerIdentifier,
            syncEnabled: mirror.syncEnabled,
            sortOrder: mirror.sortOrder
        )
    }
}
