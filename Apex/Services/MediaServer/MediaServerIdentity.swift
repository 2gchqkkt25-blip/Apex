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

    /// True when `categoryId` is a media-server library id (`{serverUUID}-library-…`).
    ///
    /// IPTV / M3U / Stremio rows use `{playlistUUID}-vod-…` / `-series-…` and must
    /// not match. A group title that happens to contain "library" is still safe:
    /// the UUID has to sit immediately before `-library-`.
    static func isMediaServerCategoryID(_ categoryId: String?) -> Bool {
        guard let categoryId, let range = categoryId.range(of: "-library-") else { return false }
        return UUID(uuidString: String(categoryId[..<range.lowerBound])) != nil
    }

    static func belongsToServer(catalogID: String, serverUUID: UUID) -> Bool {
        catalogID.hasPrefix("\(serverUUID.uuidString)-")
    }

    /// Parses `{uuid}-movie-{remoteId}` (and series/episode variants).
    ///
    /// IPTV playlist rows use this same shape (`{playlistUUID}-movie-{streamId}`),
    /// so a successful parse is **not** proof the item came from Jellyfin/Emby/Plex.
    /// Use `belongsToKnownMediaServer` or `isMediaServerCategoryID` for that.
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
    /// True when this row was imported from Jellyfin / Emby / Plex.
    /// Catalog ids share `{UUID}-movie-…` with IPTV, so the library category
    /// (or a `mediaserver://` stream URL) is what distinguishes them.
    var isMediaServerCatalogItem: Bool {
        MediaServerIdentity.isMediaServerCategoryID(categoryId)
            || (directURL?.hasPrefix("mediaserver://") == true)
    }
}

extension Series {
    var isMediaServerCatalogItem: Bool {
        MediaServerIdentity.isMediaServerCategoryID(categoryId)
    }
}

/// Shared fetch/sync batch sizes for media-server catalog work. Keeps peak
/// memory bounded on every platform (tvOS has ~1.5 GB; iOS/macOS can still
/// spike during a full-library import without paging).
enum MediaServerCatalogLimits {
    /// Set true while `MediaServerSyncService` is actively syncing; relaxes tvOS
    /// limits since the player isn't consuming memory during a dedicated sync screen.
    nonisolated(unsafe) static var syncActive = false

    /// Items fetched from Jellyfin/Emby/Plex per API request during sync.
    static var syncPageSize: Int {
        #if os(tvOS)
        syncActive ? 100 : 10
        #else
        150
        #endif
    }

    /// Rows loaded or deleted per SwiftData batch during sync purge / server delete.
    static var catalogBatchSize: Int {
        #if os(tvOS)
        syncActive ? 100 : 20
        #else
        200
        #endif
    }

    /// Existing catalog rows looked up per predicate chunk during upsert.
    static var lookupChunkSize: Int {
        #if os(tvOS)
        syncActive ? 50 : 15
        #else
        50
        #endif
    }

    /// Apple TV syncs in small passes so peak memory stays under the ~1.5 GB limit.
    /// During an active sync the player isn't loaded, so we can import far more
    /// per pass and avoid forcing the user to tap Sync repeatedly.
    static var maxItemsPerSyncPass: Int? {
        #if os(tvOS)
        syncActive ? 2000 : 250
        #else
        nil
        #endif
    }

    /// Fewer SwiftData saves → fewer main-context merges while Home stays mounted on tvOS.
    static var syncPagesPerSave: Int {
        #if os(tvOS)
        syncActive ? 3 : 5
        #else
        1
        #endif
    }

    /// Pause between save batches on Apple TV so merges can settle.
    /// Reduced during active sync since the player isn't competing for resources.
    static var syncBatchPause: Duration {
        #if os(tvOS)
        syncActive ? .milliseconds(50) : .milliseconds(350)
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
