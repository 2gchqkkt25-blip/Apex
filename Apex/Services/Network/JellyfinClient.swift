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

    /// AIOStreams packs the catalog id into the Jellyfin item id (mark `0xA1`).
    /// List rows sometimes omit `ProviderIds`, and the packed id is the same TMDB or IMDb value.
    nonisolated static func packedProviderIDs(itemID: String) -> (tmdb: Int?, imdb: String?) {
        let hex = itemID.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32, let bytes = hexBytes(hex), bytes.count == 16, bytes[0] == 0xA1 else {
            return (nil, nil)
        }
        let idType = Int(bytes[1] & 0x0F)
        var numeric: UInt64 = 0
        for byte in bytes[3 ..< 9] {
            numeric = (numeric << 8) | UInt64(byte)
        }
        guard numeric > 0, numeric <= UInt64(Int.max) else { return (nil, nil) }
        let value = Int(numeric)
        switch idType {
        case 1:
            return (nil, String(format: "tt%07d", value))
        case 2:
            return (value, nil)
        default:
            return (nil, nil)
        }
    }

    private nonisolated static func hexBytes(_ hex: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next <= hex.endIndex, let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
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

    func searchItems(
        baseURL: URL,
        userId: String,
        token: String,
        query: String,
        limit: Int
    ) async throws -> [MediaServerItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "SearchTerm", value: trimmed),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
            URLQueryItem(name: "Fields", value: "Overview,Genres,UserData,RunTimeTicks,ProductionYear,ImageTags,ProviderIds"),
            URLQueryItem(name: "Limit", value: String(max(limit, 1))),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false")
        ]
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await get(url, token: token)
        let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
        return decoded.items.map { $0.asMediaItem() }.filter { item in
            let type = item.type.lowercased()
            return type == "movie" || type == "series"
        }
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
        var decoded = try JSONDecoder().decode(JellyfinPlaybackInfoResponse.self, from: data)
        // AIOStreams answers with "Load versions" until a refresh actually asks the addons.
        if decoded.mediaSources.allSatisfy(Self.isVersionPlaceholder), !decoded.mediaSources.isEmpty {
            var retry = body
            retry["Refresh"] = true
            request.httpBody = try JSONSerialization.data(withJSONObject: retry)
            let refreshed = try await perform(request)
            decoded = try JSONDecoder().decode(JellyfinPlaybackInfoResponse.self, from: refreshed)
        }
        let playSessionId = decoded.playSessionId ?? clientPlaySessionId
        var streams: [MediaServerStreamInfo] = []
        let mediaSourceId = decoded.mediaSources.first?.id

        for source in decoded.mediaSources {
            if Self.isVersionPlaceholder(source) { continue }
            let meta = Self.streamMetadata(from: source)
            let hints = Self.audioHints(from: source)
            let details = Self.versionDetails(from: source, hints: hints)
            let label = source.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            // AIOStreams puts each addon result on Path and does not transcode.
            // Playing that URL is the version; a synthetic HLS URL is not a source.
            if let remote = Self.remotePlayURL(source.path) {
                streams.append(Self.makeStreamInfo(
                    url: remote,
                    method: .directPlay,
                    container: source.container,
                    metadata: meta,
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details,
                    videoBitrate: source.bitrate
                ))
                continue
            }
            let path = source.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Unresolved AIOStreams notices have no file and cannot transcode.
            if path.isEmpty, source.supportsTranscoding == false {
                continue
            }
            let allowsTranscode = source.supportsTranscoding != false
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
                    metadata: meta,
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
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
                    metadata: meta,
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
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
                    metadata: meta,
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
                ))
            }
            guard allowsTranscode else { continue }
            if let transcodePath = source.transcodingUrl, !transcodePath.isEmpty {
                let raw = URL(string: transcodePath, relativeTo: baseURL)?.absoluteURL
                    ?? baseURL.appendingPathComponent(transcodePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                streams.append(Self.makeStreamInfo(
                    url: withAPIKey(raw, token: token),
                    method: .transcode,
                    container: source.container,
                    metadata: meta,
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
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
                    audioCodec: "aac",
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
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
                    audioCodec: "aac",
                    label: label,
                    sourceID: source.id,
                    audioTracks: hints, meta: details
                ))
            }
        }

        if streams.isEmpty {
            let hadOnlyPlaceholders = !decoded.mediaSources.isEmpty
                && decoded.mediaSources.allSatisfy(Self.isVersionPlaceholder)
            if hadOnlyPlaceholders {
                throw MediaServerError.noStreams
            }
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
        // Keep each source's rank. Sorting the whole list would put every HLS URL
        // ahead of a higher-ranked AIOStreams version. Within one source, HLS still wins.
        var ordered: [MediaServerStreamInfo] = []
        var seen = Set<String>()
        for stream in streams {
            let key = stream.sourceID ?? stream.url.absoluteString
            guard seen.insert(key).inserted else { continue }
            let group = streams.filter { ($0.sourceID ?? $0.url.absoluteString) == key }
            ordered.append(contentsOf: group.sorted { streamPriority($0) < streamPriority($1) })
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

    /// AIOStreams uses a placeholder row ("Load versions") until PlaybackInfo resolves real addon streams.
    private static func isVersionPlaceholder(_ source: JellyfinMediaSource) -> Bool {
        if source.type?.caseInsensitiveCompare("Placeholder") == .orderedSame { return true }
        let name = source.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch name.lowercased() {
        case "load versions", "no streams found", "streams resolve on play":
            return true
        default:
            return false
        }
    }

    /// Absolute http(s) Path values are the stream itself (AIOStreams). A disk path is not.
    private static func remotePlayURL(_ path: String?) -> URL? {
        guard let path, let url = URL(string: path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    private static func makeStreamInfo(
        url: URL,
        method: MediaServerPlaybackMethod,
        container: String?,
        metadata: StreamMetadata?,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        label: String? = nil,
        sourceID: String? = nil,
        audioTracks: [MediaServerAudioHint] = [],
        meta: StreamVersionMeta = StreamVersionMeta(),
        videoBitrate: Int? = nil
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
            videoBitrate: videoBitrate ?? metadata?.videoBitrate,
            label: label.flatMap { $0.isEmpty ? nil : $0 },
            sourceID: sourceID,
            audioTracks: audioTracks,
            meta: meta
        )
    }

    /// Languages, size, and addon name shown on each stream-version row.
    private static func versionDetails(from source: JellyfinMediaSource, hints: [MediaServerAudioHint]) -> StreamVersionMeta {
        let release = source.aiostreams
        let advertised = (release?.languages ?? []).filter { !$0.isEmpty && $0.caseInsensitiveCompare("Unknown") != .orderedSame }
        let fromHints = hints.map(\.label).filter { label in
            MediaServerAudioLanguage.allCases.contains { $0.matches(label) }
        }
        let audioTags = (release?.audioTags ?? []).filter { $0.caseInsensitiveCompare("Unknown") != .orderedSame }
        var audio = audioTags.joined(separator: " ")
        if let channels = release?.audioChannels, !channels.isEmpty, channels.caseInsensitiveCompare("Unknown") != .orderedSame {
            audio = audio.isEmpty ? channels : "\(audio) \(channels)"
        }
        let resolution = [release?.resolution, release?.quality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.caseInsensitiveCompare("Unknown") != .orderedSame }
        return StreamVersionMeta(
            languages: advertised.isEmpty ? fromHints : advertised,
            resolution: resolution,
            byteSize: release?.size,
            addon: release?.addon,
            audio: audio.isEmpty ? nil : audio,
            filename: release?.filename,
            blurb: release?.summary
        )
    }

    private static func audioHints(from source: JellyfinMediaSource) -> [MediaServerAudioHint] {
        let audios = source.mediaStreams?.filter { $0.type == "Audio" } ?? []
        return audios.enumerated().map { offset, stream in
            let parts = [stream.language, stream.displayTitle].compactMap { raw -> String? in
                guard let raw else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return MediaServerAudioHint(index: offset, label: parts.joined(separator: " "))
        }
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
