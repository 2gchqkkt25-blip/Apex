//
//  PlexClient.swift
//  Apex
//
//  Plex REST client with PIN-based auth (tvOS-friendly — no web view required).
//

import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

nonisolated final class PlexClient: MediaServerClient, @unchecked Sendable {
    let kind: MediaServerKind = .plex
    private let session: URLSession
    private let probeSession: URLSession
    private let clientIdentifier: String

    init(session: URLSession? = nil, probeSession: URLSession? = nil) {
        self.session = session ?? Self.makeSession(requestTimeout: 120, resourceTimeout: 180, waitsForConnectivity: true)
        self.probeSession = probeSession ?? Self.makeProbeSession()
        clientIdentifier = PlexClient.storedClientID()
    }

    private static func makeSession(requestTimeout: TimeInterval, resourceTimeout: TimeInterval, waitsForConnectivity: Bool) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = waitsForConnectivity
        return URLSession(configuration: config)
    }

    private static func makeProbeSession() -> URLSession {
        #if os(tvOS)
        let requestTimeout: TimeInterval = 4
        let resourceTimeout: TimeInterval = 6
        #else
        let requestTimeout: TimeInterval = 6
        let resourceTimeout: TimeInterval = 10
        #endif
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        // Fail fast while probing dead Plex URLs — waiting for connectivity can
        // stack minutes of hung tasks and memory pressure on Apple TV.
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }

    private static func storedClientID() -> String {
        let key = "apex.plex.clientId"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: - PIN auth (used by connect UI)

    func createPin() async throws -> PlexPinResponse {
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.applyIdentityHeaders(to: &request, token: nil, clientIdentifier: clientIdentifier)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(PlexPinResponse.self, from: data)
    }

    func pollPin(id: Int) async throws -> PlexPinResponse {
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins/\(id)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(PlexPinResponse.self, from: data)
    }

    func listResources(token: String) async throws -> [PlexResource] {
        var components = URLComponents(string: "https://plex.tv/api/v2/resources")!
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "includeIPv6", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([PlexResource].self, from: data)
    }

    /// Servers the signed-in account can browse.
    func listBrowsableServers(from resources: [PlexResource]) -> [PlexResource] {
        resources.filter { $0.provides?.contains("server") == true }
    }

    /// Picks the first reachable Plex server URL, probing candidates in priority order.
    func resolveReachableConnection(
        token: String,
        preferredIdentifier: String?,
        manualURL: String? = nil,
        currentURL: String? = nil,
        knownServers: [PlexResource]? = nil
    ) async throws -> (url: URL, identifier: String, name: String) {
        if let manualURL, let normalized = MediaServerURL.normalize(manualURL) {
            if await probe(baseURL: normalized, token: token) {
                let resources = try await listResources(token: token)
                let match = resources.first(where: { $0.provides?.contains("server") == true && preferredIdentifier == $0.clientIdentifier })
                    ?? resources.first(where: { $0.provides?.contains("server") == true })
                return (normalized, match?.clientIdentifier ?? preferredIdentifier ?? "plex", match?.name ?? "Plex")
            }
            throw MediaServerError.serverUnreachable
        }

        if let currentURL, let normalized = MediaServerURL.normalize(currentURL),
           await probe(baseURL: normalized, token: token) {
            let resources = try await listResources(token: token)
            let match = resources.first(where: { $0.clientIdentifier == preferredIdentifier })
                ?? resources.first(where: { $0.provides?.contains("server") == true })
            guard let server = match else { throw MediaServerError.plexNoServers }
            return (normalized, server.clientIdentifier, server.name)
        }

        let resources: [PlexResource]
        if let knownServers, !knownServers.isEmpty {
            resources = knownServers
        } else {
            resources = try await listResources(token: token)
        }
        let servers = listBrowsableServers(from: resources)
        guard !servers.isEmpty else { throw MediaServerError.plexNoServers }

        // 1. GDM — same LAN discovery official Plex apps use (real IP, not .plex.direct).
        let gdmTimeout: TimeInterval = {
            #if os(tvOS)
            DeviceMemoryTier.current.isConstrained ? 1.5 : 2.0
            #else
            2.5
            #endif
        }()
        let gdmServers = await PlexGDMDiscovery.discover(timeout: gdmTimeout)
        let gdmCandidates = gdmServers.compactMap { gdm -> (URL, String, String)? in
            guard let url = gdm.baseURL else { return nil }
            if let preferredIdentifier, gdm.resourceIdentifier != preferredIdentifier { return nil }
            let name = servers.first(where: { $0.clientIdentifier == gdm.resourceIdentifier })?.name ?? gdm.name
            return (url, gdm.resourceIdentifier, name)
        }
        for candidate in gdmCandidates {
            if await probe(baseURL: candidate.0, token: token) {
                Logger.network.info("Plex: using GDM \(candidate.0.absoluteString, privacy: .public)")
                return (candidate.0, candidate.1, candidate.2)
            }
        }

        // 2. Derive plain http://LAN:32400 from .plex.direct hostnames (192.168.x.x etc.).
        var derived: [(URL, String, String)] = []
        for server in servers {
            if let preferredIdentifier, server.clientIdentifier != preferredIdentifier { continue }
            for conn in server.connections {
                guard let uri = URL(string: conn.uri),
                      let direct = Self.directHTTPURL(fromPlexDirect: uri) else { continue }
                derived.append((direct, server.clientIdentifier, server.name))
            }
        }
        for candidate in derived {
            if await probe(baseURL: candidate.0, token: token) {
                Logger.network.info("Plex: using derived LAN \(candidate.0.absoluteString, privacy: .public)")
                return (candidate.0, candidate.1, candidate.2)
            }
        }

        let ordered = deduplicatedCandidates(from: servers, preferredIdentifier: preferredIdentifier)

        for candidate in ordered where !Self.shouldSkipProbe(url: candidate.0, relay: candidate.3) {
            if await probe(baseURL: candidate.0, token: token) {
                Logger.network.info("Plex: using \(candidate.0.absoluteString, privacy: .public)")
                return (candidate.0, candidate.1, candidate.2)
            }
        }

        // Last resort: Plex relay URLs (often slow, but reachable off-LAN).
        for candidate in ordered where candidate.3 {
            if Self.shouldSkipProbe(url: candidate.0, relay: true, allowRelay: true) { continue }
            if await probe(baseURL: candidate.0, token: token) {
                Logger.network.info("Plex: using relay \(candidate.0.absoluteString, privacy: .public)")
                return (candidate.0, candidate.1, candidate.2)
            }
        }

        throw MediaServerError.connectionTimeout
    }

    /// Builds a de-duplicated, priority-sorted probe list for the selected server(s).
    private func deduplicatedCandidates(
        from servers: [PlexResource],
        preferredIdentifier: String?
    ) -> [(URL, String, String, Bool)] {
        var seen = Set<String>()
        var rows: [(URL, String, String, Int, Bool)] = []

        for server in servers {
            for conn in server.connections {
                guard let url = URL(string: conn.uri) else { continue }
                let key = url.absoluteString.lowercased()
                guard seen.insert(key).inserted else { continue }
                let score = Self.connectionPriority(
                    conn,
                    url: url,
                    preferredIdentifier: preferredIdentifier,
                    serverIdentifier: server.clientIdentifier
                )
                rows.append((url, server.clientIdentifier, server.name, score, conn.relay == true))
            }
        }

        let cap = Self.maxProbeCandidates
        return rows
            .sorted { $0.3 > $1.3 }
            .prefix(cap)
            .map { ($0.0, $0.1, $0.2, $0.4) }
    }

    private static var maxProbeCandidates: Int {
        #if os(tvOS)
        DeviceMemoryTier.current.isConstrained ? 4 : 6
        #else
        12
        #endif
    }

    /// Skips Plex-advertised URLs that almost never work from a living-room device
    /// (Docker bridge `.plex.direct` hosts, etc.).
    private static func shouldSkipProbe(url: URL, relay: Bool, allowRelay: Bool = false) -> Bool {
        if relay, !allowRelay { return true }
        let host = url.host?.lowercased() ?? ""
        if isDockerBridgePlexDirect(host) { return true }
        return false
    }

    /// `.plex.direct` hostname embedding `172.17.x`, `172.18.x`, or `172.19.x`
    /// — Plex Docker installs advertise these but they are not reachable from Apple TV.
    private static func isDockerBridgePlexDirect(_ host: String) -> Bool {
        guard host.contains(".plex.direct"), let embedded = embeddedIP(fromPlexDirectHost: host) else {
            return isDockerBridgeHost(host)
        }
        let parts = embedded.split(separator: ".")
        guard parts.count == 4,
              parts[0] == "172",
              let second = Int(parts[1])
        else { return false }
        return (17 ... 19).contains(second)
    }

    private static func embeddedIP(fromPlexDirectHost host: String) -> String? {
        guard host.contains(".plex.direct") else { return nil }
        let prefix = host.split(separator: ".").first.map(String.init) ?? ""
        let octets = prefix.split(separator: "-")
        guard octets.count == 4, octets.allSatisfy({ Int($0) != nil }) else { return nil }
        return octets.joined(separator: ".")
    }

    /// Turns `https://192-168-1-50.xxx.plex.direct:32400` into `http://192.168.1.50:32400`.
    private static func directHTTPURL(fromPlexDirect url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host.contains(".plex.direct"),
              let ip = embeddedIP(fromPlexDirectHost: host),
              isPrivateLANHost(ip),
              !isDockerBridgeHost(ip),
              !isDockerBridgePlexDirect(host) else { return nil }
        let port = url.port ?? 32400
        return URL(string: "http://\(ip):\(port)")
    }

    func bestServerConnection(from resources: [PlexResource]) -> (url: URL, identifier: String, name: String)? {
        let servers = listBrowsableServers(from: resources)
        guard let server = servers.first else { return nil }
        let ranked = server.connections.compactMap { conn -> (URL, Int)? in
            guard let url = URL(string: conn.uri) else { return nil }
            return (url, Self.connectionPriority(conn, url: url, preferredIdentifier: nil, serverIdentifier: server.clientIdentifier))
        }
        .sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        return (best.0, server.clientIdentifier, server.name)
    }

    // MARK: - MediaServerClient

    func authenticate(baseURL: URL, username: String, password: String) async throws -> MediaServerAuthResult {
        throw MediaServerError.unauthorized
    }

    func authenticateWithToken(baseURL: URL, token: String, userLabel: String) -> MediaServerAuthResult {
        MediaServerAuthResult(accessToken: token, userId: "plex", serverName: userLabel)
    }

    func listLibraries(baseURL: URL, userId: String, token: String) async throws -> [MediaServerLibrary] {
        let url = baseURL.appendingPathComponent("library/sections")
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        return (decoded.mediaContainer.directory ?? []).map {
            MediaServerLibrary(id: $0.key, name: $0.title, collectionType: $0.type)
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
        guard let parentId else { return MediaServerItemsPage(items: [], totalCount: 0) }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/sections/\(parentId)/all"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Container-Start", value: String(startIndex)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
        ]
        guard let url = components.url else { throw MediaServerError.invalidURL }
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        let items = (decoded.mediaContainer.metadata ?? []).compactMap { mapPlexMetadata($0) }
        let total = decoded.mediaContainer.size ?? items.count
        return MediaServerItemsPage(items: items, totalCount: total)
    }

    func itemDetails(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerItem {
        let url = baseURL.appendingPathComponent("library/metadata/\(itemId)")
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        guard let meta = decoded.mediaContainer.metadata?.first,
              let item = mapPlexMetadata(meta)
        else { throw MediaServerError.notFound }
        return item
    }

    func seasons(baseURL: URL, userId: String, token: String, seriesId: String) async throws -> [MediaServerItem] {
        let url = baseURL.appendingPathComponent("library/metadata/\(seriesId)/children")
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        return (decoded.mediaContainer.metadata ?? []).compactMap { mapPlexMetadata($0) }
    }

    func episodes(baseURL: URL, userId: String, token: String, seriesId: String, seasonId: String) async throws -> [MediaServerItem] {
        let url = baseURL.appendingPathComponent("library/metadata/\(seasonId)/children")
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        return (decoded.mediaContainer.metadata ?? []).compactMap { mapPlexMetadata($0) }
    }

    func playbackInfo(baseURL: URL, userId: String, token: String, itemId: String) async throws -> MediaServerPlaybackResult {
        let url = baseURL.appendingPathComponent("library/metadata/\(itemId)")
        let data = try await plexGET(url, token: token)
        let decoded = try JSONDecoder().decode(PlexLibrarySections.self, from: data)
        guard let meta = decoded.mediaContainer.metadata?.first else {
            throw MediaServerError.notFound
        }

        var streams: [MediaServerStreamInfo] = []
        let plexMedia = meta.media?.first

        if let partKey = plexMedia?.part?.first?.key,
           let directURL = buildStreamURL(baseURL: baseURL, path: partKey, token: token)
        {
            streams.append(MediaServerStreamInfo(
                url: directURL,
                method: .directPlay,
                container: plexMedia?.part?.first?.file.flatMap { ($0 as NSString).pathExtension },
                videoCodec: plexMedia?.videoCodec,
                audioCodec: plexMedia?.audioCodec,
                width: plexMedia?.width ?? plexMedia?.parsedWidth,
                height: plexMedia?.height ?? plexMedia?.parsedHeight,
                frameRate: plexMedia?.parsedFrameRate,
                videoBitrate: plexMedia?.bitrate
            ))
        }

        // Transcode URL is session-bound — built at playback time via
        // `prepareTranscodeStream`, not here (probing start.m3u8 consumes the session).
        if let placeholder = streams.first?.url {
            streams.append(MediaServerStreamInfo(
                url: placeholder,
                method: .transcode,
                container: "m3u8",
                videoCodec: plexMedia?.videoCodec,
                audioCodec: plexMedia?.audioCodec,
                width: plexMedia?.width ?? plexMedia?.parsedWidth,
                height: plexMedia?.height ?? plexMedia?.parsedHeight,
                frameRate: plexMedia?.parsedFrameRate,
                videoBitrate: plexMedia?.bitrate
            ))
        }

        guard !streams.isEmpty else { throw MediaServerError.noStreams }
        return MediaServerPlaybackResult(streams: streams)
    }

    func imageURL(baseURL: URL, itemId: String, imageTag: String?, token: String, kind: String = "Primary") -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/metadata/\(itemId)/thumb"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url
    }

    func reportProgress(baseURL: URL, userId: String, token: String, itemId: String, positionTicks: Int64, isPaused: Bool) async {
        let ms = positionTicks / 10_000
        var components = URLComponents(
            url: baseURL.appendingPathComponent(":/progress"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "key", value: "/library/metadata/\(itemId)"),
            URLQueryItem(name: "time", value: String(ms)),
            URLQueryItem(name: "state", value: isPaused ? "paused" : "playing")
        ]
        guard let url = components.url else { return }
        _ = try? await plexGET(url, token: token)
    }

    func markPlayed(baseURL: URL, userId: String, token: String, itemId: String, played: Bool) async {
        let endpoint = played ? "scrobble" : "unscrobble"
        var components = URLComponents(
            url: baseURL.appendingPathComponent(":/\(endpoint)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "key", value: "/library/metadata/\(itemId)")
        ]
        guard let url = components.url else { return }
        _ = try? await plexGET(url, token: token)
    }

    // MARK: - Private

    private func probe(baseURL: URL, token: String) async -> Bool {
        let url = baseURL.appendingPathComponent("library/sections")
        do {
            _ = try await plexGET(url, token: token, session: probeSession)
            return true
        } catch {
            Logger.network.debug("Plex probe failed for \(baseURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func connectionPriority(
        _ conn: PlexConnection,
        url: URL,
        preferredIdentifier: String?,
        serverIdentifier: String
    ) -> Int {
        var score = 0
        let host = url.host?.lowercased() ?? ""

        if preferredIdentifier == serverIdentifier { score += 500 }
        if isPrivateLANHost(host), !isPlexDirectHost(host) { score += 400 }
        if conn.local, !isPlexDirectHost(host) { score += 250 }
        if conn.local { score += 80 }
        if url.scheme?.lowercased() == "http", isPrivateLANHost(host) { score += 120 }
        if url.scheme?.lowercased() == "http" { score += 30 }
        if isPlexDirectHost(host) { score -= 100 }
        if isDockerBridgePlexDirect(host) { score -= 500 }
        if conn.relay == true { score -= 300 }
        if isDockerBridgeHost(host) { score -= 200 }

        return score
    }

    private static func isPrivateLANHost(_ host: String) -> Bool {
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            guard parts.count >= 2, let second = Int(parts[1]) else { return false }
            return (16 ... 31).contains(second)
        }
        return false
    }

    private static func isPlexDirectHost(_ host: String) -> Bool {
        host.contains(".plex.direct")
    }

    private static func isDockerBridgeHost(_ host: String) -> Bool {
        host.hasPrefix("172.17.") || host.hasPrefix("172.18.") || host.hasPrefix("172.19.")
            || host.contains("172-17-0-") || host.contains("172-18-0-") || host.contains("172-19-0-")
    }

    private func plexGET(_ url: URL, token: String, session: URLSession? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "X-Plex-Accept")
        Self.applyIdentityHeaders(to: &request, token: token, clientIdentifier: clientIdentifier)

        let activeSession = session ?? self.session
        do {
            let (data, response) = try await activeSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw MediaServerError.serverUnreachable
            }
            return data
        } catch let error as URLError where error.code == .timedOut {
            throw MediaServerError.connectionTimeout
        } catch let error as MediaServerError {
            throw error
        } catch {
            throw MediaServerError.serverUnreachable
        }
    }

    private func buildStreamURL(baseURL: URL, path: String, token: String) -> URL? {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        guard let streamBase = URL(string: normalized, relativeTo: baseURL)?.absoluteURL else { return nil }
        var components = URLComponents(url: streamBase, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components?.url
    }

    /// Keeps a universal transcode session warm and, more importantly, matches
    /// what every well-behaved Plex client does: official apps ping roughly
    /// every 30s (more often while paused, when no segment requests are
    /// implicitly doing the same job). Skipping this is a plausible
    /// contributor to a transcode session never being told "the client is
    /// still here" during pauses/seeks, on top of just being non-standard
    /// client behavior. `playbackURL` is the resolved `start.m3u8` URL, which
    /// already carries the session id, token and client identity.
    static func pingTranscodeSession(playbackURL: URL) async {
        guard let components = URLComponents(url: playbackURL, resolvingAgainstBaseURL: false),
              let sessionID = components.queryItems?.first(where: { $0.name == "session" })?.value,
              let token = components.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value
        else { return }

        var pingComponents = components
        pingComponents.path = "/video/:/transcode/universal/ping"
        pingComponents.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        guard let pingURL = pingComponents.url else { return }

        var request = URLRequest(url: pingURL)
        applyIdentityHeaders(to: &request, token: token, clientIdentifier: storedClientID())
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Opens a fresh Plex transcode session at playback time: decision only, then
    /// return the `start.m3u8` URL for AVPlayer. Never GETs `start.m3u8` here —
    /// that call belongs to the player or the session returns 400 on replay.
    func prepareTranscodeStream(baseURL: URL, ratingKey: String, token: String) async -> URL? {
        let queryItems = buildTranscodeQueryItems(ratingKey: ratingKey, token: token)
        guard await callTranscodeDecision(baseURL: baseURL, queryItems: queryItems, token: token) else {
            return nil
        }
        return buildTranscodeStartURL(baseURL: baseURL, queryItems: queryItems)
    }

    /// Shared query items for `/decision` and `/start.m3u8` — must be byte-identical.
    private func buildTranscodeQueryItems(ratingKey: String, token: String) -> [URLQueryItem] {
        let sessionID = "apex-\(clientIdentifier)-\(UUID().uuidString)"
        let constrained = DeviceMemoryTier.current.isConstrained
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),
            // `directStream=1` lets Plex remux (stream-copy) video that's already
            // compatible with the client profile — but that keeps the source
            // bitrate untouched. A 1080p Blu-ray remux can be 80+ Mbps, which no
            // home Wi-Fi link sustains to Apple TV HD; the "transcode" session
            // would remux, not re-encode, and stall identically to direct play.
            // Force a real, bitrate-capped re-encode on constrained devices.
            URLQueryItem(name: "directStream", value: constrained ? "0" : "1"),
            URLQueryItem(name: "directStreamAudio", value: constrained ? "0" : "1"),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(name: "subtitleSize", value: "100"),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "mediaBufferSize", value: constrained ? "4096" : "102400"),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionID),
            URLQueryItem(name: "X-Plex-Client-Profile-Name", value: Self.plexClientProfileName),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: Self.plexClientProfileExtra)
        ]
        if constrained {
            // Plex's documented way to disable subtitles in the transcode session.
            // An earlier build sent an invalid `subtitles=none` param here, which
            // could break the generated manifest and fail AVPlayer outright.
            queryItems.append(URLQueryItem(name: "subtitleStreamID", value: "0"))
            // Use Plex's conventional fixed-quality tuple. `videoBitrate` and
            // `peakBitrate` are not the controls Plex's own clients send to the
            // universal-transcode endpoint, so PMS could ignore them and leave
            // the Apple TV stream effectively uncapped. Apple TV HD's hardware
            // decoder tops out at 1080p; 12 Mbps leaves ample quality without a
            // buffer-growth path into tvOS jetsam.
            queryItems += Self.constrainedTranscodeQualityQueryItems
        }
        queryItems += Self.plexIdentityQueryItems(clientIdentifier: clientIdentifier, token: token)
        return queryItems
    }

    /// Kept separately so tests can lock down the Plex parameter names. These
    /// names are part of the server request contract, not interchangeable labels.
    nonisolated static let constrainedTranscodeQualityQueryItems: [URLQueryItem] = [
        URLQueryItem(name: "videoQuality", value: "100"),
        URLQueryItem(name: "videoResolution", value: "1920x1080"),
        URLQueryItem(name: "maxVideoBitrate", value: "12000")
    ]

    private func buildTranscodeStartURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL? {
        guard let transcodeBase = URL(
            string: "/video/:/transcode/universal/start.m3u8",
            relativeTo: baseURL
        )?.absoluteURL else { return nil }
        var components = URLComponents(url: transcodeBase, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url
    }

    private func callTranscodeDecision(
        baseURL: URL,
        queryItems: [URLQueryItem],
        token: String
    ) async -> Bool {
        guard let decisionBase = URL(
            string: "/video/:/transcode/universal/decision",
            relativeTo: baseURL
        )?.absoluteURL else { return false }
        var components = URLComponents(url: decisionBase, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { return false }

        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        Self.applyIdentityHeaders(to: &request, token: token, clientIdentifier: clientIdentifier)

        do {
            let (data, response) = try await probeSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse {
                    Logger.network.warning("Plex transcode decision HTTP \(http.statusCode)")
                }
                return false
            }
            return Self.isPlexDecisionPlayable(data)
        } catch {
            Logger.network.warning("Plex transcode decision failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func isPlexDecisionPlayable(_ data: Data) -> Bool {
        guard let xml = String(data: data, encoding: .utf8) else { return true }
        guard let range = xml.range(of: "generalDecisionCode=\""),
              let end = xml[range.upperBound...].firstIndex(of: "\"")
        else { return true }
        let codeStr = xml[range.upperBound ..< end]
        guard let code = Int(codeStr) else { return true }
        return (1000 ... 1999).contains(code)
    }

    /// Plex HLS sessions read client identity from the query string (AVPlayer
    /// cannot attach headers to segment requests).
    private static func plexIdentityQueryItems(clientIdentifier: String, token: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
            URLQueryItem(name: "X-Plex-Product", value: "Apex"),
            URLQueryItem(name: "X-Plex-Version", value: "1.0"),
            URLQueryItem(name: "X-Plex-Device", value: plexDevice),
            URLQueryItem(name: "X-Plex-Device-Name", value: plexDeviceName),
            URLQueryItem(name: "X-Plex-Platform", value: plexPlatform),
            URLQueryItem(name: "X-Plex-Platform-Version", value: plexPlatformVersion)
        ]
    }

    private static func applyIdentityHeaders(to request: inout URLRequest, token: String?, clientIdentifier: String) {
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("Apex", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
        request.setValue(plexDevice, forHTTPHeaderField: "X-Plex-Device")
        request.setValue(plexDeviceName, forHTTPHeaderField: "X-Plex-Device-Name")
        request.setValue(plexPlatform, forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(plexPlatformVersion, forHTTPHeaderField: "X-Plex-Platform-Version")
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
    }

    private static var plexPlatform: String {
        #if os(tvOS)
        "tvOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #else
        "Apple"
        #endif
    }

    private static var plexDevice: String {
        #if os(tvOS)
        "Apple TV"
        #elseif os(iOS)
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        "iOS"
        #endif
        #elseif os(macOS)
        "Mac"
        #else
        "Apple"
        #endif
    }

    private static let plexDeviceName = "Apex"

    private static var plexPlatformVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    private static var plexClientProfileName: String {
        #if os(tvOS)
        "tvOS"
        #elseif os(iOS)
        "iOS"
        #else
        "Generic"
        #endif
    }

    /// HLS + mpegts — required for AVPlayer; mkv-in-HLS breaks on Apple platforms.
    private static let plexClientProfileExtra =
        "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264,hevc&audioCodec=aac,mp3,ac3,eac3&replace=true)"

    private static func incompatibleDirectPlayContainer(_ ext: String) -> Bool {
        MediaPlaybackResolver.incompatibleDirectPlayContainer(ext)
    }

    private static func parseProviderIDs(from guids: [PlexGuid]?) -> (tmdb: Int?, imdb: String?) {
        var tmdb: Int?
        var imdb: String?
        for guid in guids ?? [] {
            let raw = guid.id
            if raw.hasPrefix("tmdb://") {
                let idPart = raw.dropFirst("tmdb://".count).split(separator: "?").first ?? Substring()
                tmdb = Int(idPart)
            } else if raw.hasPrefix("imdb://") {
                let idPart = String(raw.dropFirst("imdb://".count).split(separator: "?").first ?? Substring())
                imdb = idPart.hasPrefix("tt") ? idPart : "tt\(idPart)"
            }
        }
        return (tmdb, imdb)
    }

    private func plexProductHeaders() -> String { clientIdentifier }

    private func mapPlexMetadata(_ meta: PlexMetadata) -> MediaServerItem? {
        let type: String
        switch meta.type.lowercased() {
        case "movie": type = "Movie"
        case "show": type = "Series"
        case "season": type = "Season"
        case "episode": type = "Episode"
        default: return nil
        }
        let ticks: Int64? = meta.duration.map { Int64($0) * 10_000 }
        let userData: MediaServerUserData? = {
            guard meta.viewOffset != nil || meta.viewCount != nil else { return nil }
            return MediaServerUserData(
                played: (meta.viewCount ?? 0) > 0 && (meta.viewOffset ?? 0) == 0,
                playCount: meta.viewCount ?? 0,
                playbackPositionTicks: Int64(meta.viewOffset ?? 0) * 10_000,
                lastPlayedDate: meta.lastViewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }()
        let providerIDs = Self.parseProviderIDs(from: meta.guid)
        return MediaServerItem(
            id: meta.ratingKey,
            name: meta.title,
            type: type,
            overview: meta.summary,
            imageTag: meta.thumb,
            backdropTag: meta.art,
            productionYear: meta.year,
            runTimeTicks: ticks,
            parentBackdropItemId: nil,
            seriesId: meta.grandparentKey,
            seasonId: meta.parentKey,
            indexNumber: meta.index,
            parentIndexNumber: meta.parentIndex,
            userData: userData,
            genres: [],
            people: [],
            providerTMDBId: providerIDs.tmdb,
            providerIMDBId: providerIDs.imdb
        )
    }
}
