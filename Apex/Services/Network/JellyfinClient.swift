//
//  JellyfinClient.swift
//  Apex
//
//  Jellyfin REST client (Emby-compatible API).
//

import Foundation
import OSLog

nonisolated final class JellyfinClient: MediaServerClient, @unchecked Sendable {
    let kind: MediaServerKind = .jellyfin
    private let session: URLSession
    private let deviceID: String

    init(session: URLSession? = nil, deviceID: String = JellyfinClient.defaultDeviceID) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            config.httpShouldUsePipelining = true
            self.session = URLSession(configuration: config)
        }
        self.deviceID = deviceID
    }

    /// Parses Jellyfin/Emby `ProviderIds` into TMDB / IMDb ids for enrichment.
    nonisolated static func parseProviderIDs(_ providerIds: [String: String]?) -> (tmdb: Int?, imdb: String?) {
        guard let providerIds else { return (nil, nil) }
        let tmdbRaw = providerIds["Tmdb"] ?? providerIds["TMDB"] ?? providerIds["tmdb"]
        let imdbRaw = providerIds["Imdb"] ?? providerIds["IMDB"] ?? providerIds["imdb"]
        let tmdb = tmdbRaw.flatMap { Int($0) }
        let imdb: String? = imdbRaw.map { raw in
            raw.hasPrefix("tt") ? raw : "tt\(raw)"
        }
        return (tmdb, imdb)
    }

    private static let defaultDeviceID: String = {
        if let stored = UserDefaults.standard.string(forKey: "apex.jellyfin.deviceId") {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "apex.jellyfin.deviceId")
        return id
    }()

    func authenticate(baseURL: URL, username: String, password: String) async throws -> MediaServerAuthResult {
        let url = baseURL.appendingPathComponent("Users/AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        let body = ["Username": username, "Pw": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
        return MediaServerAuthResult(
            accessToken: decoded.accessToken,
            userId: decoded.user.id,
            serverName: nil
        )
    }

    func listLibraries(baseURL: URL, userId: String, token: String) async throws -> [MediaServerLibrary] {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Views")
        let data = try await get(url, token: token)
        let decoded = try JSONDecoder().decode(JellyfinViewsResponse.self, from: data)
        return decoded.items.map {
            MediaServerLibrary(id: $0.id, name: $0.name, collectionType: $0.type)
        }
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
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "Recursive", value: parentId == nil ? "true" : "false"),
            URLQueryItem(name: "IncludeItemTypes", value: includeTypes.joined(separator: ",")),
            URLQueryItem(name: "Fields", value: "Overview,Genres,UserData,RunTimeTicks,ProductionYear,ImageTags,ProviderIds"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "true")
        ]
        if let parentId {
            query.append(URLQueryItem(name: "ParentId", value: parentId))
        }
        components.queryItems = query
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await get(url, token: token)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return MediaServerItemsPage(
            items: decoded.items.map { $0.asMediaItem() },
            totalCount: decoded.totalRecordCount
        )
    }

    func itemDetails(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerItem {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Fields", value: "Overview,Genres,People,UserData,ParentIndexNumber,IndexNumber,SeriesId,SeasonId,RunTimeTicks,ProductionYear,ImageTags,BackdropImageTags")
        ]
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await get(url, token: token)
        let item = try JSONDecoder().decode(JellyfinBaseItem.self, from: data)
        return item.asMediaItem()
    }

    func seasons(baseURL: URL, userId: String, token: String, seriesId: String) async throws -> [MediaServerItem] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Shows/\(seriesId)/Seasons"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,UserData,IndexNumber,ImageTags")
        ]
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await get(url, token: token)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return decoded.items.map { $0.asMediaItem() }
    }

    func episodes(baseURL: URL, userId: String, token: String, seriesId: String, seasonId: String) async throws -> [MediaServerItem] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "SeasonId", value: seasonId),
            URLQueryItem(name: "Fields", value: "Overview,UserData,IndexNumber,ParentIndexNumber,RunTimeTicks,ImageTags")
        ]
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await get(url, token: token)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return decoded.items.map { $0.asMediaItem() }
    }

    func playbackInfo(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerPlaybackResult {
        let clientPlaySessionId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "UserId", value: userId)]
        guard let url = components.url else { throw MediaServerError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader(token: token), forHTTPHeaderField: "X-Emby-Authorization")
        let body: [String: Any] = [
            "UserId": userId,
            "MaxStreamingBitrate": 120_000_000,
            "AutoOpenLiveStream": true,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "DeviceProfile": Self.minimalDeviceProfile()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(JellyfinPlaybackInfoResponse.self, from: data)
        let playSessionId = decoded.playSessionId ?? clientPlaySessionId
        var streams: [MediaServerStreamInfo] = []
        let mediaSourceId = decoded.mediaSources.first?.id

        for source in decoded.mediaSources {
            let meta = Self.streamMetadata(from: source)
            if source.supportsDirectPlay == true,
               let direct = buildDirectURL(
                   baseURL: baseURL,
                   itemId: itemId,
                   mediaSourceId: source.id,
                   container: source.container,
                   userId: userId,
                   token: token
               )
            {
                streams.append(Self.makeStreamInfo(
                    url: direct,
                    method: .directPlay,
                    container: source.container,
                    metadata: meta
                ))
            }
            if let directStream = source.directStreamUrl,
               let raw = URL(string: directStream, relativeTo: baseURL)?.absoluteURL,
               isClientReachableStreamURL(raw, serverBase: baseURL)
            {
                streams.append(Self.makeStreamInfo(
                    url: withAPIKey(raw, token: token),
                    method: .directStream,
                    container: source.container,
                    metadata: meta
                ))
            } else if source.supportsDirectStream == true,
                      let streamURL = buildDirectStreamURL(
                          baseURL: baseURL,
                          itemId: itemId,
                          mediaSourceId: source.id,
                          container: source.container,
                          userId: userId,
                          token: token
                      )
            {
                streams.append(Self.makeStreamInfo(
                    url: streamURL,
                    method: .directStream,
                    container: source.container,
                    metadata: meta
                ))
            }
            if let transcodePath = source.transcodingUrl, !transcodePath.isEmpty {
                let raw = URL(string: transcodePath, relativeTo: baseURL)?.absoluteURL
                    ?? baseURL.appendingPathComponent(transcodePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                streams.append(Self.makeStreamInfo(
                    url: withAPIKey(raw, token: token),
                    method: .transcode,
                    container: source.container,
                    metadata: meta
                ))
            }
            if let hls = buildHLSTranscodeURL(
                baseURL: baseURL,
                itemId: itemId,
                mediaSourceId: source.id,
                userId: userId,
                playSessionId: playSessionId,
                token: token
            ) {
                streams.append(Self.makeStreamInfo(
                    url: hls,
                    method: .transcode,
                    container: "m3u8",
                    metadata: meta,
                    videoCodec: "h264",
                    audioCodec: "aac"
                ))
            }
            if let liveHLS = buildLiveHLSURL(
                baseURL: baseURL,
                itemId: itemId,
                mediaSourceId: source.id,
                userId: userId,
                playSessionId: playSessionId,
                token: token
            ) {
                streams.append(Self.makeStreamInfo(
                    url: liveHLS,
                    method: .transcode,
                    container: "m3u8",
                    metadata: meta,
                    videoCodec: "h264",
                    audioCodec: "aac"
                ))
            }
        }

        if streams.isEmpty {
            let fallbackMeta = decoded.mediaSources.first.map { Self.streamMetadata(from: $0) }
            if let fallback = buildDirectURL(
                baseURL: baseURL,
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                container: decoded.mediaSources.first?.container,
                userId: userId,
                token: token
            ) {
                streams.append(Self.makeStreamInfo(
                    url: fallback,
                    method: .directPlay,
                    container: decoded.mediaSources.first?.container,
                    metadata: fallbackMeta
                ))
            } else if let download = buildDownloadURL(baseURL: baseURL, itemId: itemId, userId: userId, token: token) {
                streams.append(Self.makeStreamInfo(
                    url: download,
                    method: .directPlay,
                    container: nil,
                    metadata: fallbackMeta
                ))
            }
        }

        guard !streams.isEmpty else { throw MediaServerError.noStreams }
        // HLS + api_key first — AVPlayer cannot send Jellyfin auth headers on direct file URLs.
        let ordered = streams.sorted { lhs, rhs in
            streamPriority(lhs) < streamPriority(rhs)
        }
        return MediaServerPlaybackResult(streams: ordered)
    }

    private func streamPriority(_ stream: MediaServerStreamInfo) -> Int {
        switch stream.method {
        case .transcode where stream.container == "m3u8": 0
        case .transcode: 1
        case .directStream: 2
        case .directPlay: 3
        }
    }

    func imageURL(baseURL: URL, itemId: String, imageTag: String?, token: String, kind: String = "Primary") -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemId)/Images/\(kind)"),
            resolvingAgainstBaseURL: false
        )!
        if let imageTag {
            components.queryItems = [URLQueryItem(name: "tag", value: imageTag)]
        }
        return components.url
    }

    func reportProgress(baseURL: URL, userId: String, token: String, itemId: String, positionTicks: Int64, isPaused: Bool) async {
        let url = baseURL.appendingPathComponent("Sessions/Playing/Progress")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader(token: token), forHTTPHeaderField: "X-Emby-Authorization")
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "PlayMethod": "DirectStream"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await perform(request)
    }

    func markPlayed(baseURL: URL, userId: String, token: String, itemId: String, played: Bool) async {
        let path = played ? "Played" : "Unplayed"
        let url = baseURL.appendingPathComponent("Users/\(userId)/PlayedItems/\(itemId)/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader(token: token), forHTTPHeaderField: "X-Emby-Authorization")
        _ = try? await perform(request)
    }

    // MARK: - Private

    private struct StreamMetadata {
        let videoCodec: String?
        let audioCodec: String?
        let width: Int?
        let height: Int?
        let frameRate: Double?
        let videoBitrate: Int?
    }

    private static func streamMetadata(from source: JellyfinMediaSource) -> StreamMetadata {
        let video = source.mediaStreams?.first { $0.type == "Video" }
        let audio = source.mediaStreams?.first { $0.type == "Audio" }
        let fps = video?.realFrameRate ?? video?.averageFrameRate
        return StreamMetadata(
            videoCodec: video?.codec,
            audioCodec: audio?.codec,
            width: video?.width,
            height: video?.height,
            frameRate: fps,
            videoBitrate: video?.bitRate
        )
    }

    private static func makeStreamInfo(
        url: URL,
        method: MediaServerPlaybackMethod,
        container: String?,
        metadata: StreamMetadata?,
        videoCodec: String? = nil,
        audioCodec: String? = nil
    ) -> MediaServerStreamInfo {
        MediaServerStreamInfo(
            url: url,
            method: method,
            container: container,
            videoCodec: videoCodec ?? metadata?.videoCodec,
            audioCodec: audioCodec ?? metadata?.audioCodec,
            width: metadata?.width,
            height: metadata?.height,
            frameRate: metadata?.frameRate,
            videoBitrate: metadata?.videoBitrate
        )
    }

    private func authHeader(token: String?) -> String {
        if let token {
            return "MediaBrowser Client=\"Apex\", Device=\"Apex\", DeviceId=\"\(deviceID)\", Version=\"1.0\", Token=\"\(token)\""
        }
        return "MediaBrowser Client=\"Apex\", Device=\"Apex\", DeviceId=\"\(deviceID)\", Version=\"1.0\""
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(authHeader(token: token), forHTTPHeaderField: "X-Emby-Authorization")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaServerError.serverUnreachable }
        switch http.statusCode {
        case 200 ... 299: return data
        case 401: throw MediaServerError.unauthorized
        case 404: throw MediaServerError.notFound
        default:
            Logger.database.warning("Jellyfin HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
            throw MediaServerError.serverUnreachable
        }
    }

    private func buildDirectURL(
        baseURL: URL,
        itemId: String,
        mediaSourceId: String?,
        container: String?,
        userId: String,
        token: String
    ) -> URL? {
        let streamPath = streamPath(for: itemId, container: container)
        var components = URLComponents(
            url: baseURL.appendingPathComponent(streamPath),
            resolvingAgainstBaseURL: false
        )!
        var query = jellyfinStreamQuery(userId: userId, token: token, mediaSourceId: mediaSourceId)
        query.append(URLQueryItem(name: "Static", value: "true"))
        components.queryItems = query
        return components.url
    }

    private func buildDirectStreamURL(
        baseURL: URL,
        itemId: String,
        mediaSourceId: String,
        container: String?,
        userId: String,
        token: String
    ) -> URL? {
        let streamPath = streamPath(for: itemId, container: container)
        var components = URLComponents(
            url: baseURL.appendingPathComponent(streamPath),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = jellyfinStreamQuery(
            userId: userId,
            token: token,
            mediaSourceId: mediaSourceId
        )
        return components.url
    }

    private func buildDownloadURL(baseURL: URL, itemId: String, userId: String, token: String) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemId)/Download"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = jellyfinStreamQuery(userId: userId, token: token, mediaSourceId: nil)
        return components.url
    }

    private func buildHLSTranscodeURL(
        baseURL: URL,
        itemId: String,
        mediaSourceId: String,
        userId: String,
        playSessionId: String,
        token: String
    ) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemId)/master.m3u8"),
            resolvingAgainstBaseURL: false
        )!
        var query = jellyfinStreamQuery(userId: userId, token: token, mediaSourceId: mediaSourceId)
        query.append(contentsOf: [
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "TranscodingMaxAudioChannels", value: "2"),
            URLQueryItem(name: "SegmentContainer", value: "ts"),
            URLQueryItem(name: "MinSegments", value: "1"),
            URLQueryItem(name: "BreakOnNonKeyFrames", value: "true"),
            URLQueryItem(name: "DeviceId", value: deviceID),
            URLQueryItem(name: "PlaySessionId", value: playSessionId)
        ])
        components.queryItems = query
        return components.url
    }

    /// Progressive HLS fallback used by some Jellyfin builds when master.m3u8 fails.
    private func buildLiveHLSURL(
        baseURL: URL,
        itemId: String,
        mediaSourceId: String,
        userId: String,
        playSessionId: String,
        token: String
    ) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemId)/live.m3u8"),
            resolvingAgainstBaseURL: false
        )!
        var query = jellyfinStreamQuery(userId: userId, token: token, mediaSourceId: mediaSourceId)
        query.append(contentsOf: [
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "DeviceId", value: deviceID),
            URLQueryItem(name: "PlaySessionId", value: playSessionId)
        ])
        components.queryItems = query
        return components.url
    }

    private func jellyfinStreamQuery(userId: String, token: String, mediaSourceId: String?) -> [URLQueryItem] {
        var query = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "api_key", value: token)
        ]
        if let mediaSourceId {
            query.append(URLQueryItem(name: "MediaSourceId", value: mediaSourceId))
        }
        return query
    }

    private func streamPath(for itemId: String, container: String?) -> String {
        guard let container, !container.isEmpty else {
            return "Videos/\(itemId)/stream"
        }
        let ext = container.split(separator: ",").first.map(String.init) ?? container
        return "Videos/\(itemId)/stream.\(ext)"
    }

    private func withAPIKey(_ url: URL, token: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name.lowercased() == "api_key" }) {
            query.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = query
        return components.url ?? url
    }

    /// Server-side direct stream URLs often point at localhost; ignore those.
    private func isClientReachableStreamURL(_ url: URL, serverBase: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        if host == "127.0.0.1" || host == "localhost" { return false }
        if let serverHost = serverBase.host?.lowercased(), host == serverHost { return true }
        // Allow same-scheme remote URLs the server advertises (e.g. LAN).
        return !host.hasPrefix("127.")
    }

    private static nonisolated func minimalDeviceProfile() -> [String: Any] {
        [
            "MaxStreamingBitrate": 120_000_000,
            "MaxStaticBitrate": 100_000_000,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                ["Container": "mp4,m4v,mkv,webm", "Type": "Video"],
                ["Container": "mp3,aac,flac", "Type": "Audio"]
            ],
            "TranscodingProfiles": [
                [
                    "Container": "ts",
                    "Type": "Video",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac,mp3",
                    "Protocol": "hls"
                ],
                [
                    "Container": "mp4",
                    "Type": "Video",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac,mp3",
                    "Protocol": "http"
                ]
            ],
            "ContainerProfiles": [] as [[String: Any]],
            "CodecProfiles": [] as [[String: Any]],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "External"],
                ["Format": "ass", "Method": "External"],
                ["Format": "sub", "Method": "External"]
            ]
        ]
    }
}
