//
//  MediaServerClient.swift
//  Apex
//
//  Shared client surface for Jellyfin, Emby, and Plex.
//

import Foundation

nonisolated enum MediaServerError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case serverUnreachable
    case connectionTimeout
    case notFound
    case noStreams
    case plexPinExpired
    case plexNoServers

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL."
        case .unauthorized: "Authentication failed. Check your credentials."
        case .serverUnreachable: "Could not reach the media server. Check the address and that you're on the same network (or VPN)."
        case .connectionTimeout: "Could not reach your Plex server on the local network. Make sure Apple TV and Plex are on the same Wi‑Fi and that local network access is allowed for Apex in Settings → Privacy."
        case .notFound: "Item not found on the server."
        case .noStreams: "No playable stream available for this title."
        case .plexPinExpired: "Plex sign-in timed out. Try again."
        case .plexNoServers: "No Plex servers found for this account."
        }
    }
}

nonisolated protocol MediaServerClient: Sendable {
    var kind: MediaServerKind { get }

    func authenticate(baseURL: URL, username: String, password: String) async throws -> MediaServerAuthResult
    func listLibraries(baseURL: URL, userId: String, token: String) async throws -> [MediaServerLibrary]
    func listItems(
        baseURL: URL,
        userId: String,
        token: String,
        parentId: String?,
        includeTypes: [String],
        startIndex: Int,
        limit: Int
    ) async throws -> MediaServerItemsPage
    func itemDetails(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerItem
    func seasons(baseURL: URL, userId: String, token: String, seriesId: String) async throws -> [MediaServerItem]
    func episodes(baseURL: URL, userId: String, token: String, seriesId: String, seasonId: String) async throws -> [MediaServerItem]
    func playbackInfo(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerPlaybackResult
    func imageURL(baseURL: URL, itemId: String, imageTag: String?, token: String, kind: String) -> URL?
    func reportProgress(baseURL: URL, userId: String, token: String, itemId: String, positionTicks: Int64, isPaused: Bool) async
    func markPlayed(baseURL: URL, userId: String, token: String, itemId: String, played: Bool) async
}

nonisolated enum MediaServerClientFactory {
    static func client(for kind: MediaServerKind) -> any MediaServerClient {
        switch kind {
        case .jellyfin: JellyfinClient()
        case .emby: EmbyClient()
        case .plex: PlexClient()
        }
    }
}
