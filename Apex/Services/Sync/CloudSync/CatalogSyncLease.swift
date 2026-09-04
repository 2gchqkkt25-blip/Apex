//
//  CatalogSyncLease.swift
//  Apex
//
//  Cross-device quiet period for playlist catalog sync. The catalog itself is
//  local — each device still fetches from the provider — but two devices must
//  not run that fetch (or present the blocking progress cover) at the same time.
//

import Foundation

/// Stable per-install id written onto `SyncedPlaylist` while this device is
/// fetching a playlist's catalog (and for a short quiet period afterwards).
enum CatalogSyncDeviceIdentity {
    static let storageKey = "apex.catalogSyncDeviceID"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: storageKey)
        return id
    }
}

/// A device's claim that it is syncing — or just finished syncing — a playlist.
nonisolated struct CatalogSyncLease: Equatable {
    var deviceID: String
    var startedAt: Date

    /// Long enough for a large Xtream pull, plus CloudKit delivery to siblings.
    static let ttl: TimeInterval = 30 * 60

    func isHeldByAnotherDevice(_ thisDeviceID: String, now: Date = Date()) -> Bool {
        guard !deviceID.isEmpty, deviceID != thisDeviceID else { return false }
        return now.timeIntervalSince(startedAt) < Self.ttl
    }
}
