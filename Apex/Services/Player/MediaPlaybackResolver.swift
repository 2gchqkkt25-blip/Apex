//
//  MediaPlaybackResolver.swift
//  Apex
//
//  Resolves mediaserver:// placeholders to playable URLs using direct play →
//  remux/direct stream → transcode (AVPlayer-first in FullScreenPlayerView).
//

import Foundation
import OSLog
import SwiftData

nonisolated enum MediaPlaybackResolver {
    /// Parses `mediaserver:///{serverUUID}/{remoteItemId}/{kind}` placeholders.
    static func parsePlaceholder(_ url: URL) -> (serverID: UUID, remoteItemID: String, kind: String)? {
        guard url.scheme?.lowercased() == "mediaserver" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              let serverID = UUID(uuidString: parts[0])
        else { return nil }
        let kind = parts[parts.count - 1]
        let remoteID = parts[1 ..< parts.count - 1].joined(separator: "/")
        guard !remoteID.isEmpty else { return nil }
        return (serverID, remoteID, kind)
    }

    static func isPlaceholder(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "mediaserver"
    }

    @MainActor
    static func resolve(
        _ media: PlayableMedia,
        container: ModelContainer,
        preferDirectPlay: Bool = false
    ) async throws -> PlayableMedia {
        guard let parsed = parsePlaceholder(media.url) else { throw MediaServerError.invalidURL }

        let ctx = ModelContext(container)
        let serverID = parsed.serverID
        guard let server = try ctx.fetch(FetchDescriptor<MediaServer>(
            predicate: #Predicate { $0.id == serverID }
        )).first else { throw MediaServerError.notFound }

        guard let baseURL = MediaServerURL.normalize(server.baseURL),
              let token = server.authToken,
              let userId = server.userId
        else { throw MediaServerError.invalidURL }

        let client = MediaServerClientFactory.client(for: server.kind)
        let playback = try await client.playbackInfo(
            baseURL: baseURL,
            userId: userId,
            token: token,
            itemId: parsed.remoteItemID
        )

        var stream = pickBestStream(
            from: playback.streams,
            serverKind: server.kind,
            preferDirectPlay: preferDirectPlay
        )
        guard var stream else { throw MediaServerError.noStreams }

        #if os(tvOS)
        // A source that's unsafe to direct-play on Apple TV HD (e.g. an 80+ Mbps
        // Blu-ray remux, or an audio codec VLCKit can't decode like TrueHD/DTS-HD)
        // is just as unsafe to remux via a Plex "transcode" session that only
        // stream-copies compatible video — force a real re-encode instead.
        if DeviceMemoryTier.current.isConstrained,
           server.kind == .plex,
           stream.method == .directPlay,
           Self.isUnsafeForConstrainedDirectPlay(stream),
           let transcodeAlt = playback.streams.first(where: { $0.method == .transcode })
        {
            stream = transcodeAlt
        }
        #endif

        var playableURL: URL
        if server.kind == .plex, stream.method == .transcode {
            let plex = PlexClient()
            if let fresh = await plex.prepareTranscodeStream(
                baseURL: baseURL,
                ratingKey: parsed.remoteItemID,
                token: token
            ) {
                playableURL = fresh
            } else if let direct = playback.streams.first(where: { $0.method == .directPlay }) {
                #if os(tvOS)
                if DeviceMemoryTier.current.isConstrained, Self.isUnsafeForConstrainedDirectPlay(direct) {
                    Logger.player.error(
                        "Plex transcode session failed on Apple TV HD and direct play is unsafe (bitrate/codec) — refusing to guarantee a buffer-storm jetsam"
                    )
                    throw MediaServerError.noStreams
                }
                #endif
                // Some playback is better than none — the engine picker routes
                // heavy MKV direct-play to VLC-only with subtitle tracks
                // suppressed to keep memory in check.
                Logger.player.info("Plex transcode session failed; falling back to direct play")
                stream = direct
                playableURL = authenticatedStreamURL(direct.url, token: token, serverKind: server.kind)
            } else {
                throw MediaServerError.noStreams
            }
        } else {
            playableURL = authenticatedStreamURL(stream.url, token: token, serverKind: server.kind)
        }

        Logger.player.info(
            "Media server playback (\(server.kind.rawValue, privacy: .public)): \(stream.method.rawValue, privacy: .public) → \(playableURL.absoluteString.prefix(120), privacy: .public)"
        )
        return media.replacingURL(playableURL, streamContext: MediaServerStreamContext(from: stream))
    }

    /// AVPlayer cannot send Jellyfin/Emby auth headers — ensure `api_key` is present.
    /// Plex URLs already carry `X-Plex-Token` (+ client identity on transcode URLs).
    nonisolated static func authenticatedStreamURL(_ url: URL, token: String, serverKind: MediaServerKind? = nil) -> URL {
        if serverKind == .plex || urlHasPlexToken(url) {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name.lowercased() == "api_key" }) {
            query.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = query
        return components.url ?? url
    }

    nonisolated private static func urlHasPlexToken(_ url: URL) -> Bool {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return query.contains { $0.name.caseInsensitiveCompare("X-Plex-Token") == .orderedSame }
    }

    nonisolated static func pickBestStream(
        from streams: [MediaServerStreamInfo],
        serverKind: MediaServerKind? = nil,
        preferDirectPlay: Bool = false
    ) -> MediaServerStreamInfo? {
        if preferDirectPlay {
            let order: [MediaServerPlaybackMethod] = [.directPlay, .directStream, .transcode]
            for method in order {
                if let match = streams.first(where: { $0.method == method }) {
                    return match
                }
            }
            return streams.first
        }

        if serverKind == .jellyfin || serverKind == .emby {
            if let hls = transcodeHLS(in: streams) { return hls }
            if let transcode = streams.first(where: { $0.method == .transcode }) { return transcode }
        }

        if serverKind == .plex, shouldPreferPlexTranscode(in: streams) {
            if let hls = transcodeHLS(in: streams) { return hls }
            if let transcode = streams.first(where: { $0.method == .transcode }) { return transcode }
        }

        let order: [MediaServerPlaybackMethod] = [.directPlay, .directStream, .transcode]
        for method in order {
            if let match = streams.first(where: { $0.method == method }) {
                return match
            }
        }
        return streams.first
    }

    /// Prefer Plex HLS when direct-play uses a container tvOS/AVPlayer cannot play (e.g. MKV).
    /// On Apple TV HD (~2 GB RAM) this is required — direct MKV remux via KSPlayer/VLC jetsams.
    nonisolated private static func shouldPreferPlexTranscode(in streams: [MediaServerStreamInfo]) -> Bool {
        guard transcodeHLS(in: streams) != nil || streams.contains(where: { $0.method == .transcode }) else {
            return false
        }
        guard let direct = streams.first(where: { $0.method == .directPlay }) else { return false }
        let container = (direct.container ?? direct.url.pathExtension).lowercased()
        return Self.incompatibleDirectPlayContainer(container)
    }

    nonisolated static func incompatibleDirectPlayContainer(_ container: String) -> Bool {
        ["mkv", "mka", "avi", "wmv", "flv"].contains(container.lowercased())
    }

    /// True when a stream is guaranteed to buffer-storm (and eventually jetsam) on
    /// Apple TV HD if played directly: an audio codec VLCKit ships no decoder for
    /// (licensing — TrueHD/DTS-HD/MLP), or a bitrate no home Wi-Fi link sustains.
    nonisolated static func isUnsafeForConstrainedDirectPlay(_ stream: MediaServerStreamInfo) -> Bool {
        let unsupportedAudio: Set<String> = ["truehd", "mlp", "dts", "dtshd", "dca"]
        if let audioCodec = stream.audioCodec?.lowercased(), unsupportedAudio.contains(audioCodec) {
            return true
        }
        if let bitrateKbps = stream.videoBitrate, bitrateKbps > 30000 {
            return true
        }
        return false
    }

    nonisolated private static func transcodeHLS(in streams: [MediaServerStreamInfo]) -> MediaServerStreamInfo? {
        streams.first(where: {
            $0.method == .transcode && ($0.container == "m3u8" || $0.url.pathExtension.lowercased() == "m3u8")
        })
    }

    @MainActor
    static func reportProgress(
        server: MediaServer,
        remoteItemID: String,
        positionSeconds: Double,
        isPaused: Bool
    ) async {
        guard let baseURL = MediaServerURL.normalize(server.baseURL),
              let token = server.authToken,
              let userId = server.userId
        else { return }
        let ticks = Int64(positionSeconds * 10_000_000)
        let client = MediaServerClientFactory.client(for: server.kind)
        await client.reportProgress(
            baseURL: baseURL,
            userId: userId,
            token: token,
            itemId: remoteItemID,
            positionTicks: ticks,
            isPaused: isPaused
        )
    }

    @MainActor
    static func reportProgressForCatalogItem(
        catalogID: String,
        progressSeconds: Double,
        isPaused: Bool,
        container: ModelContainer
    ) async {
        guard let parsed = MediaServerIdentity.parseCatalogID(catalogID) else { return }
        let serverUUID = parsed.serverUUID
        let ctx = ModelContext(container)
        guard let server = try? ctx.fetch(FetchDescriptor<MediaServer>(
            predicate: #Predicate { $0.id == serverUUID }
        )).first else { return }
        await reportProgress(
            server: server,
            remoteItemID: parsed.remoteID,
            positionSeconds: progressSeconds,
            isPaused: isPaused
        )
    }

    @MainActor
    static func markPlayedForCatalogItem(
        catalogID: String,
        played: Bool,
        container: ModelContainer
    ) async {
        guard let parsed = MediaServerIdentity.parseCatalogID(catalogID) else { return }
        let serverUUID = parsed.serverUUID
        let ctx = ModelContext(container)
        guard let server = try? ctx.fetch(FetchDescriptor<MediaServer>(
            predicate: #Predicate { $0.id == serverUUID }
        )).first,
            let baseURL = MediaServerURL.normalize(server.baseURL),
            let token = server.authToken,
            let userId = server.userId
        else { return }
        let client = MediaServerClientFactory.client(for: server.kind)
        await client.markPlayed(
            baseURL: baseURL,
            userId: userId,
            token: token,
            itemId: parsed.remoteID,
            played: played
        )
    }
}
