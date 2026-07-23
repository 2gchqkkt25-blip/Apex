//
//  StalkerStreamResolver.swift
//  Apex
//
//  Turns a deferred Stalker `PlayableMedia` (whose URL is a `lumestalker://`
//  placeholder carrying a `create_link` command) into one with a real, freshly
//  resolved stream URL. Stalker URLs are short-lived, so resolution happens at
//  playback time — right before the engine loads — rather than at sync time.
//

import Foundation
import OSLog
import SwiftData

nonisolated enum StalkerStreamResolver {
    /// Resolves `media` if it is a deferred Stalker placeholder; otherwise returns
    /// it unchanged. Throws `StalkerError` when the portal can't be reached or
    /// returns no playable URL.
    static func resolve(_ media: PlayableMedia, container: ModelContainer) async throws -> PlayableMedia {
        Logger.player.info("StalkerResolver: checking \(media.title, privacy: .public)")
        guard let (type, cmd) = StalkerLink.decode(media.url) else { return media }
        Logger.player.info("StalkerResolver: decoded placeholder type=\(type.rawValue, privacy: .public)")
        guard let playlist = playlist(for: media.contentRef, container: container) else {
            Logger.player.error("StalkerResolver: playlist lookup failed for id=\(media.id, privacy: .public)")
            throw StalkerError.invalidURL
        }
        Logger.player.info("StalkerResolver: found playlist, resolving stream...")
        let client = StalkerClient(configuration: StalkerClient.Configuration(playlist: playlist))
        let url = try await client.resolveStreamURL(type: type, cmd: cmd)
        Logger.player.log("Stalker create_link resolved a stream URL for \(media.title, privacy: .public)")
        return media.replacingURL(url)
    }

    /// Fetches the owning playlist. Every catalog id embeds the playlist UUID as
    /// its 36-character prefix, so the playlist is recoverable from the content
    /// reference without threading it through every call site.
    private static func playlist(for ref: PlayableMedia.ContentRef, container: ModelContainer) -> Playlist? {
        let rawId: String = switch ref {
        case let .movie(id), let .episode(id), let .live(id):
            id
        }
        guard let playlistId = UUID(uuidString: String(rawId.prefix(36))) else { return nil }
        let context = ModelContext(container)
        return try? context.fetch(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistId })
        ).first
    }
}
