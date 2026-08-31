//
//  MediaServerIdentity.swift
//  Apex
//
//  Builds stable catalog ids for media-server library items.
//

import Foundation

enum MediaServerIdentity {
    static func movieID(serverUUID: UUID, remoteID: String) -> String {
        "\(serverUUID.uuidString)-movie-\(sanitize(remoteID))"
    }

    static func seriesID(serverUUID: UUID, remoteID: String) -> String {
        "\(serverUUID.uuidString)-series-\(sanitize(remoteID))"
    }

    static func episodeID(serverUUID: UUID, remoteID: String) -> String {
        "\(serverUUID.uuidString)-episode-\(sanitize(remoteID))"
    }

    static func libraryCategoryID(serverUUID: UUID, libraryID: String) -> String {
        "\(serverUUID.uuidString)-library-\(sanitize(libraryID))"
    }

    static func belongsToServer(catalogID: String, serverUUID: UUID) -> Bool {
        catalogID.hasPrefix("\(serverUUID.uuidString)-")
    }

    /// Parses `{serverUUID}-movie-{remoteId}` (and series/episode variants).
    static func parseCatalogID(_ catalogID: String) -> (serverUUID: UUID, remoteID: String)? {
        for marker in ["-movie-", "-series-", "-episode-"] {
            guard let range = catalogID.range(of: marker) else { continue }
            let uuidPart = String(catalogID[..<range.lowerBound])
            let remoteID = String(catalogID[range.upperBound...])
            guard let serverUUID = UUID(uuidString: uuidPart), !remoteID.isEmpty else { continue }
            return (serverUUID, remoteID)
        }
        return nil
    }

    /// True when `catalogID` belongs to one of the configured media servers.
    static func belongsToKnownMediaServer(_ catalogID: String, serverIDs: Set<String>) -> Bool {
        guard let parsed = parseCatalogID(catalogID) else { return false }
        return serverIDs.contains(parsed.serverUUID.uuidString)
    }

    private static func sanitize(_ remoteID: String) -> String {
        remoteID.replacingOccurrences(of: "/", with: "_")
    }
}

extension Movie {
    var isMediaServerCatalogItem: Bool {
        MediaServerIdentity.parseCatalogID(id) != nil
    }
}

extension Series {
    var isMediaServerCatalogItem: Bool {
        MediaServerIdentity.parseCatalogID(id) != nil
    }
}

/// Shared fetch/sync batch sizes for media-server catalog work. Keeps peak
/// memory bounded on every platform (tvOS has ~1.5 GB; iOS/macOS can still
/// spike during a full-library import without paging).
enum MediaServerCatalogLimits {
    /// Items fetched from Jellyfin/Emby/Plex per API request during sync.
    static var syncPageSize: Int {
        #if os(tvOS)
        10
        #else
        150
        #endif
    }

    /// Rows loaded or deleted per SwiftData batch during sync purge / server delete.
    static var catalogBatchSize: Int {
        #if os(tvOS)
        20
        #else
        200
        #endif
    }

    /// Existing catalog rows looked up per predicate chunk during upsert.
    static var lookupChunkSize: Int {
        #if os(tvOS)
        15
        #else
        50
        #endif
    }

    /// Apple TV syncs in small passes so peak memory stays under the ~1.5 GB limit.
    static var maxItemsPerSyncPass: Int? {
        #if os(tvOS)
        250
        #else
        nil
        #endif
    }

    /// Fewer SwiftData saves → fewer main-context merges while Home stays mounted on tvOS.
    static var syncPagesPerSave: Int {
        #if os(tvOS)
        5
        #else
        1
        #endif
    }

    /// Pause between save batches on Apple TV so merges can settle.
    static var syncBatchPause: Duration {
        #if os(tvOS)
        .milliseconds(350)
        #else
        .milliseconds(0)
        #endif
    }

    /// Skip long plot/genre strings during catalog import; detail screens fetch on demand.
    static var liteMetadataDuringSync: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    /// On tvOS, skip long plot/genre/duration during import; poster URLs are still
    /// stored (strings only — images decode lazily when browsed).
    static var minimalCatalogDuringSync: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    /// Posters shown on the Media home rails.
    static var homeRailLimit: Int {
        #if os(tvOS)
        16
        #else
        40
        #endif
    }
    /// Grid / continue-watching page size in full-library browse.
    static var browsePageSize: Int {
        #if os(tvOS)
        30
        #else
        100
        #endif
    }

    /// tvOS cannot survive a full-library import during connect — sync manually.
    static var autoSyncLibraryOnConnect: Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }
}
