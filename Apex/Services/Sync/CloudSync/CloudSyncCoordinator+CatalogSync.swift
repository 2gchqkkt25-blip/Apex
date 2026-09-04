//
//  CloudSyncCoordinator+CatalogSync.swift
//  Apex
//
//  Quiet-period lease so a playlist catalog fetch on one device does not pop
//  the blocking sync cover on the others.
//

import Foundation
import OSLog

extension CloudSyncCoordinator {
    func observePlaylistCatalogSync() {
        let start = NotificationCenter.default.addObserver(
            forName: .apexPlaylistCatalogSyncWillStart,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let playlistID = note.object as? UUID else { return }
            MainActor.assumeIsolated {
                self?.claimCatalogSyncLease(playlistID)
            }
        }
        observers.append(start)

        let abort = NotificationCenter.default.addObserver(
            forName: .apexPlaylistCatalogSyncDidAbort,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let playlistID = note.object as? UUID else { return }
            MainActor.assumeIsolated {
                self?.releaseCatalogSyncLease(playlistID)
            }
        }
        observers.append(abort)
    }

    /// True when another signed-in device is fetching this playlist (or just
    /// finished), so this device must not present the blocking auto-sync cover.
    func hasRemoteCatalogSyncLease(for playlistID: UUID) -> Bool {
        catalogSyncLeases[playlistID]?.isHeldByAnotherDevice(CatalogSyncDeviceIdentity.id) == true
    }

    func claimCatalogSyncLease(_ playlistID: UUID) {
        guard isCloudKitEnabled else { return }
        let deviceID = CatalogSyncDeviceIdentity.id
        Task {
            do {
                try await engine.claimCatalogSyncLease(playlistID: playlistID, deviceID: deviceID)
                await refreshCatalogSyncLeases()
            } catch {
                Logger.sync.error("Catalog sync lease claim failed: \(error.localizedDescription)")
            }
        }
    }

    func releaseCatalogSyncLease(_ playlistID: UUID) {
        guard isCloudKitEnabled else { return }
        let deviceID = CatalogSyncDeviceIdentity.id
        Task {
            do {
                try await engine.releaseCatalogSyncLease(playlistID: playlistID, deviceID: deviceID)
                await refreshCatalogSyncLeases()
            } catch {
                Logger.sync.error("Catalog sync lease release failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshCatalogSyncLeases() async {
        do {
            catalogSyncLeases = try await engine.catalogSyncLeases()
            catalogSyncEpoch += 1
        } catch {
            Logger.sync.error("Catalog sync lease snapshot failed: \(error.localizedDescription)")
        }
    }
}
