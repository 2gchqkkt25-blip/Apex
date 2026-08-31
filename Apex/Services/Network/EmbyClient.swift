//
//  EmbyClient.swift
//  Apex
//
//  Emby uses the same REST surface as Jellyfin with Emby-branded headers.
//

import Foundation

nonisolated final class EmbyClient: MediaServerClient, @unchecked Sendable {
    let kind: MediaServerKind = .emby
    private let jellyfin: JellyfinClient

    init() {
        jellyfin = JellyfinClient()
    }

    func authenticate(baseURL: URL, username: String, password: String) async throws -> MediaServerAuthResult {
        try await jellyfin.authenticate(baseURL: baseURL, username: username, password: password)
    }

    func listLibraries(baseURL: URL, userId: String, token: String) async throws -> [MediaServerLibrary] {
        try await jellyfin.listLibraries(baseURL: baseURL, userId: userId, token: token)
    }

    func listItems(
        baseURL: URL,
        userId: String,
        token: String,
        parentId: String?,
        includeTypes: [String],
        startIndex: Int,
        limit: Int
    ) async throws -> MediaServerItemsPage {
        try await jellyfin.listItems(
            baseURL: baseURL,
            userId: userId,
            token: token,
            parentId: parentId,
            includeTypes: includeTypes,
            startIndex: startIndex,
            limit: limit
        )
    }

    func itemDetails(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerItem {
        try await jellyfin.itemDetails(baseURL: baseURL, userId: userId, token: token, itemId: itemId)
    }

    func seasons(baseURL: URL, userId: String, token: String, seriesId: String) async throws -> [MediaServerItem] {
        try await jellyfin.seasons(baseURL: baseURL, userId: userId, token: token, seriesId: seriesId)
    }

    func episodes(baseURL: URL, userId: String, token: String, seriesId: String, seasonId: String) async throws -> [MediaServerItem] {
        try await jellyfin.episodes(baseURL: baseURL, userId: userId, token: token, seriesId: seriesId, seasonId: seasonId)
    }

    func playbackInfo(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerPlaybackResult {
        try await jellyfin.playbackInfo(baseURL: baseURL, userId: userId, token: token, itemId: itemId)
    }

    func imageURL(baseURL: URL, itemId: String, imageTag: String?, token: String, kind: String = "Primary") -> URL? {
        jellyfin.imageURL(baseURL: baseURL, itemId: itemId, imageTag: imageTag, token: token, kind: kind)
    }

    func reportProgress(baseURL: URL, userId: String, token: String, itemId: String, positionTicks: Int64, isPaused: Bool) async {
        await jellyfin.reportProgress(baseURL: baseURL, userId: userId, token: token, itemId: itemId, positionTicks: positionTicks, isPaused: isPaused)
    }

    func markPlayed(baseURL: URL, userId: String, token: String, itemId: String, played: Bool) async {
        await jellyfin.markPlayed(baseURL: baseURL, userId: userId, token: token, itemId: itemId, played: played)
    }
}
