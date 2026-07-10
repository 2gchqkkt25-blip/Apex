//
//  EPGProviderStrategy.swift
//  Apex
//
//  Per-playlist EPG strategy for App Store builds with arbitrary providers.
//  Chosen automatically on each Sync Now — never a global setting.
//

import Foundation
import OSLog

/// How Sync Now loads guide data for one playlist.
nonisolated enum EPGProviderStrategy: String, Sendable {
    /// One `xmltv.php` / XMLTV file download — seconds for providers with a
    /// current bulk dump (most Xtream panels, M3U `url-tvg` feeds).
    case xmltvBulk
    /// `xmltv.php` is days behind but `get_short_epg` is live. Sync primes a
    /// small slice; browse loads the rest on demand (StreamInfinity-style).
    case apiOnDemand
    /// XMLTV failed or didn't match channels; live API fills gaps as you browse.
    case apiFallback

    var logLabel: String { rawValue }
}

/// Per-playlist memory of whether `xmltv.php` bulk is historically stale.
/// Keys are playlist UUIDs so multiple providers on one device stay independent.
nonisolated enum EPGStaleXMLTVCache {
    private static let recheckInterval: TimeInterval = 3600 // Retry hourly instead of daily

    private static func staleKey(_ playlistID: UUID) -> String {
        "epg.xmltv.stale.\(playlistID.uuidString)"
    }

    private static func markedAtKey(_ playlistID: UUID) -> String {
        "epg.xmltv.staleMarkedAt.\(playlistID.uuidString)"
    }

    /// Call only when `EPGInserter.Result.isStaleBulkFeed` is true — matched
    /// programmes exist but every one already ended. Do **not** call for channel
    /// matching failures or timestamp parse issues.
    static func markXMLTVBulkStale(playlistID: UUID) {
        UserDefaults.standard.set(true, forKey: staleKey(playlistID))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: markedAtKey(playlistID))
    }

    static func clearXMLTVBulkStale(playlistID: UUID) {
        UserDefaults.standard.removeObject(forKey: staleKey(playlistID))
        UserDefaults.standard.removeObject(forKey: markedAtKey(playlistID))
    }

    /// Skip `xmltv.php` when we've *confirmed* the bulk dump lags the live API.
    /// Re-probes once per day in case the provider fixes their feed.
    static func shouldSkipXMLTVDownload(playlistID: UUID) -> Bool {
        guard UserDefaults.standard.bool(forKey: staleKey(playlistID)) else { return false }
        let markedAt = UserDefaults.standard.double(forKey: markedAtKey(playlistID))
        guard markedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - markedAt < recheckInterval
    }

    static func logStrategy(_ strategy: EPGProviderStrategy, playlistName: String, playlistID: UUID) {
        Logger.database.warning(
            "EPG strategy [\(strategy.logLabel, privacy: .public)] — playlist \(playlistName, privacy: .public) (\(playlistID.uuidString, privacy: .public))"
        )
    }
}
