//
//  HomeCatalogScope.swift
//  Apex
//
//  Home shows content from the active IPTV playlist *and* connected media
//  servers (Plex/Jellyfin/Emby). Media-server ids use `{serverUUID}-movie-…`,
//  not the playlist prefix, so scoping must include both.
//

import Foundation

enum HomeCatalogScope {
    /// True when a catalog row should appear on Home (hero, trending, rows).
    nonisolated static func includes(_ catalogID: String, playlistPrefix: String?) -> Bool {
        guard let prefix = playlistPrefix, !prefix.isEmpty else { return true }
        if catalogID.hasPrefix(prefix) { return true }
        return MediaServerIdentity.parseCatalogID(catalogID) != nil
    }
}
