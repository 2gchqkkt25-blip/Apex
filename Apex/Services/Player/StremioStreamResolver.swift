//
//  StremioStreamResolver.swift
//  Apex
//
//  Resolves Stremio placeholder URLs to actual playable stream URLs at
//  playback time.  Follows the same pattern as StalkerStreamResolver.
//

import Foundation

enum StremioStreamResolver {
    private static let client = StremioClient()

    /// Attempts to resolve a Stremio placeholder to a real stream URL.
    ///
    /// The placeholder encodes `baseURL|type|id` in its path, which is stored
    /// in `directURL` on the content model during sync.
    static func resolve(placeholder: String) async throws -> URL {
        let parts = placeholder.components(separatedBy: "|")
        guard parts.count == 3,
              let baseURL = URL(string: parts[0])
        else { throw StremioError.invalidURL }

        let type = parts[1]
        let id = parts[2]

        let streams = try await client.fetchStreams(baseURL: baseURL, type: type, id: id)
        guard let first = streams.first,
              let url = first.bestURL
        else { throw StremioError.noCompatibleStreams }

        return url
    }

    /// Resolves a Stremio `PlayableMedia` by replacing its placeholder URL with
    /// a real stream URL fetched from the addon.  Follows the same pattern as
    /// `StalkerStreamResolver.resolve`.
    static func resolve(_ media: PlayableMedia) async throws -> PlayableMedia {
        let urlString = media.url.absoluteString
        // Strip the stremio:// scheme to recover the placeholder.
        guard urlString.hasPrefix("stremio://") else { throw StremioError.invalidURL }
        let placeholder = String(urlString.dropFirst("stremio://".count))
        guard let decoded = placeholder.removingPercentEncoding else { throw StremioError.invalidURL }

        let resolvedURL = try await resolve(placeholder: decoded)
        return PlayableMedia(
            id: media.id,
            url: resolvedURL,
            title: media.title,
            subtitle: media.subtitle,
            posterURL: media.posterURL,
            kind: media.kind,
            startTime: media.startTime,
            contentRef: media.contentRef
        )
    }
}
