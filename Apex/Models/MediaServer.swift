//
//  MediaServer.swift
//  Apex
//
//  Home media server connection (Jellyfin / Emby / Plex). Kept separate from
//  IPTV `Playlist` — the Media tab scopes catalog rows by this server's UUID.
//

import Foundation
import SwiftData

@Model
final class MediaServer {
    var id: UUID = UUID()
    var name: String
    /// Jellyfin/Emby: server base URL. Plex: chosen server base URL after discovery.
    var baseURL: String
    var kindRaw: String = MediaServerKind.jellyfin.rawValue

    var username: String = ""
    var password: String = ""
    /// Jellyfin/Emby access token from AuthenticateByName.
    var accessToken: String?
    /// Plex: auth token from plex.tv PIN flow.
    var plexToken: String?
    /// Jellyfin/Emby: authenticated user id.
    var userId: String?
    /// Plex: machine identifier for the chosen server.
    var plexServerIdentifier: String?

    var syncEnabled: Bool = true
    var lastSyncDate: Date?
    var syncStatusRaw: String = "idle"
    var sortOrder: Int = 0
    var addedAt: Date = Date()

    init(name: String, baseURL: String, kind: MediaServerKind) {
        self.name = name
        self.baseURL = baseURL
        kindRaw = kind.rawValue
    }
}

enum MediaServerKind: String, Codable, CaseIterable, Identifiable {
    case jellyfin
    case emby
    case plex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .emby: "Emby"
        case .plex: "Plex"
        }
    }

    var systemImage: String {
        switch self {
        case .jellyfin: "server.rack"
        case .emby: "play.rectangle.on.rectangle"
        case .plex: "play.tv"
        }
    }
}

extension MediaServer {
    var kind: MediaServerKind {
        get { MediaServerKind(rawValue: kindRaw) ?? .jellyfin }
        set { kindRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .idle }
        set { syncStatusRaw = newValue.rawValue }
    }

    /// Catalog row ids use `{serverUUID}-movie-…` / `{serverUUID}-series-…`.
    var catalogPrefix: String { id.uuidString }

    var authToken: String? {
        switch kind {
        case .plex: plexToken
        case .jellyfin, .emby: accessToken
        }
    }
}
