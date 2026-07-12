//
//  XtreamClient.swift
//  Apex
//
//  Xtream Codes API client
//

import Foundation
import OSLog

enum XtreamError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The server URL is invalid."
        case .authenticationFailed:
            "Authentication failed. The provider rejected the request (this can also happen when the account's connection limit is reached)."
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .decodingError(error):
            "Failed to read the server response: \(error.localizedDescription)"
        case .invalidResponse:
            "Received an invalid response from the server."
        case let .serverError(code):
            "Server error (HTTP \(code))."
        }
    }

    /// True when the request was cancelled (view scroll, task restart) — not a real failure.
    var isCancellation: Bool {
        switch self {
        case let .networkError(error):
            if error is CancellationError { return true }
            if let urlError = error as? URLError, urlError.code == .cancelled { return true }
            return false
        default:
            return false
        }
    }

    /// Whether the failure is likely transient and worth retrying.
    /// Note: `authenticationFailed` (HTTP 401/403) is *not* retriable by
    /// default — for login it means bad credentials. During an
    /// already-authenticated sync it's usually the provider's connection /
    /// rate limit, so those call sites opt in via `retryAuthFailure`.
    var isRetriable: Bool {
        switch self {
        case .networkError:
            // Timeouts, connection reset (RST), lost connection — transient.
            // Cancellations are not worth retrying in the same task.
            return !isCancellation
        case let .serverError(code):
            return code >= 500
        case .invalidURL, .authenticationFailed, .decodingError, .invalidResponse:
            return false
        }
    }

    var isAuthFailure: Bool {
        if case .authenticationFailed = self { return true }
        return false
    }
}

// MARK: - XtreamClient

class XtreamClient: APIClient {
    nonisolated struct Configuration {
        let serverURL: String
        let username: String
        let password: String
        let timeout: TimeInterval

        init(serverURL: String, username: String, password: String, timeout: TimeInterval = 30) {
            self.serverURL = serverURL
            self.username = username
            self.password = password
            self.timeout = timeout
        }
    }

    let configuration: Configuration
    let session: URLSession

    nonisolated init(configuration: Configuration, urlSession: URLSession? = nil) {
        self.configuration = configuration
        session = urlSession ?? Self.makeSession(timeout: configuration.timeout)
    }

    /// Convenience initializer for backward compatibility
    convenience nonisolated init(urlSession: URLSession? = nil) {
        let config = Configuration(
            serverURL: "",
            username: "",
            password: "",
            timeout: 30
        )
        self.init(configuration: config, urlSession: urlSession)
    }

    /// Builds a dedicated session for Xtream API calls.
    ///
    /// Uses a single connection per host: many Xtream providers cap an account
    /// to one concurrent connection and reject extra requests with 401/403.
    /// Serializing connections (instead of reusing `.shared`'s pool, which the
    /// server may RST after a heavy transfer) avoids tripping that limit. Also
    /// applies the configured timeout, which was previously ignored.
    private nonisolated static func makeSession(timeout: TimeInterval) -> URLSession {
        return ProviderURLSession.make(
            timeout: timeout,
            resourceTimeout: 120,
            maxConnectionsPerHost: 1,
            additionalHeaders: ["User-Agent": apexCatalogUserAgent]
        )
    }

    // MARK: - Helper Methods

    /// Strips path/query cruft from stored portal URLs (`/get.php`, etc.) so
    /// `player_api.php` and `xmltv.php` resolve at the panel root.
    nonisolated static func normalizedPortalBaseURL(from serverURL: String) -> String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host
        else { return trimmed }
        var base = URLComponents()
        base.scheme = components.scheme ?? "http"
        base.host = host
        base.port = components.port
        guard let url = base.url else { return trimmed }
        var absolute = url.absoluteString
        while absolute.hasSuffix("/") { absolute.removeLast() }
        return absolute
    }

    /// The provider's XMLTV guide URL for a playlist (`xmltv.php` with the
    /// account credentials). Exposed so `EPGSourceReconciler` can store it as a
    /// standalone EPG source — the guide is no longer fetched during a playlist
    /// sync.
    nonisolated static func xmltvURL(for playlist: Playlist) -> URL? {
        let base = normalizedPortalBaseURL(from: playlist.serverURL)
        guard !base.isEmpty else { return nil }
        guard var components = URLComponents(string: base + "/xmltv.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password)
        ]
        return components.url
    }

    private func buildURL(serverURL: String, path: String, queryItems: [URLQueryItem]) -> URL? {
        let base = Self.normalizedPortalBaseURL(from: serverURL)
        guard var components = URLComponents(string: base + "/" + path) else { return nil }
        components.queryItems = queryItems
        return components.url
    }

    /// Maximum number of attempts (1 initial + retries) for a single request.
    private static let maxAttempts = 3

    /// Performs a request with retry-and-backoff for transient failures.
    ///
    /// - Parameter retryAuthFailure: when `true`, HTTP 401/403 is also treated
    ///   as transient. Sync/content calls set this because, after `getInfo`
    ///   has already proven the credentials, a 401/403 is almost always the
    ///   provider's connection/rate limit rather than bad credentials. Login
    ///   (`getInfo`) leaves it `false` so wrong credentials fail fast.
    private func request<T: Decodable>(_ url: URL, retryAuthFailure: Bool = true) async throws -> T {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await performRequest(url)
            } catch let error as XtreamError {
                let retriable = error.isRetriable || (retryAuthFailure && error.isAuthFailure)
                guard retriable, attempt < Self.maxAttempts else { throw error }

                // Exponential backoff: 2s, then 4s. Gives the provider time to
                // release the connection slot / clear the rate-limit window.
                let delay = pow(2.0, Double(attempt))
                Logger.network.warning(
                    "Xtream request failed (\(error.localizedDescription)); retry \(attempt)/\(Self.maxAttempts - 1) in \(delay)s"
                )
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// A single request attempt. Network-level failures are wrapped into
    /// `XtreamError.networkError` so callers see a consistent error type.
    private func performRequest<T: Decodable>(_ url: URL) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw XtreamError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw XtreamError.authenticationFailed
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw XtreamError.serverError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw XtreamError.decodingError(error)
        }
    }

    // MARK: - API Methods

    /// 1. Get Server and User Info
    func getInfo(playlist: Playlist) async throws -> XtreamAuthResponse {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password)
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        // Login: a 401/403 means bad credentials, so don't retry it.
        return try await request(url, retryAuthFailure: false)
    }

    /// 2. Get Live Categories
    func getLiveCategories(playlist: Playlist) async throws -> [XtreamCategory] {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_live_categories")
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 3. Get Live Streams
    func getLiveStreams(playlist: Playlist, categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        var queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_live_streams")
        ]
        if let categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: categoryId))
        }

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 4. Get VOD Categories
    func getVODCategories(playlist: Playlist) async throws -> [XtreamCategory] {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_vod_categories")
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 5. Get VOD Streams
    func getVODStreams(playlist: Playlist, categoryId: String? = nil) async throws -> [XtreamVODStream] {
        var queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_vod_streams")
        ]
        if let categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: categoryId))
        }

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 6. Get VOD Info
    func getVODInfo(playlist: Playlist, vodId: Int) async throws -> XtreamVODInfo {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_vod_info"),
            URLQueryItem(name: "vod_id", value: String(vodId))
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 7. Get Series Categories
    func getSeriesCategories(playlist: Playlist) async throws -> [XtreamCategory] {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_series_categories")
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 8. Get Series
    func getSeries(playlist: Playlist, categoryId: String? = nil) async throws -> [XtreamSeries] {
        var queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_series")
        ]
        if let categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: categoryId))
        }

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 9. Get Series Info
    func getSeriesInfo(playlist: Playlist, seriesId: Int) async throws -> XtreamSeriesInfoResponse {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password),
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: String(seriesId))
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await request(url)
    }

    /// 10. Get Short EPG
    func getShortEPG(playlist: Playlist, streamId: Int, limit: Int? = nil) async throws -> [XtreamShortEPG] {
        try await getShortEPG(
            serverURL: playlist.serverURL,
            username: playlist.username,
            password: playlist.password,
            streamId: streamId,
            limit: limit
        )
    }

    /// Short EPG using plain credentials — safe from background actors without
    /// touching a SwiftData `Playlist` model.
    func getShortEPG(
        serverURL: String,
        username: String,
        password: String,
        streamId: Int,
        limit: Int? = nil,
        diagnosticLabel: String? = nil
    ) async throws -> [XtreamShortEPG] {
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "get_short_epg"),
            URLQueryItem(name: "stream_id", value: String(streamId))
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        guard let url = buildURL(serverURL: serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        return try await fetchEPGListings(url: url, diagnosticLabel: diagnosticLabel)
    }

    /// Decodes the many shapes Xtream panels use for `epg_listings`.
    private func fetchEPGListings(url: URL, diagnosticLabel: String? = nil) async throws -> [XtreamShortEPG] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw XtreamError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw XtreamError.authenticationFailed
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw XtreamError.serverError(httpResponse.statusCode)
        }

        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
        if let diagnosticLabel {
            Logger.network.warning(
                "EPG probe \(diagnosticLabel, privacy: .public) HTTP \(httpResponse.statusCode) bytes=\(data.count) body=\(preview, privacy: .public)"
            )
        }

        // Empty / "no EPG" payloads.
        if data.isEmpty { return [] }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty || text == "[]" || text == "null" || text == "false" || text == "{}"
        {
            return []
        }

        let listings = Self.decodeEPGListings(from: data)
        if listings.isEmpty, let diagnosticLabel {
            Logger.network.warning(
                "EPG probe \(diagnosticLabel, privacy: .public) decoded 0 listings from: \(preview, privacy: .public)"
            )
        }
        return listings
    }

    /// Tolerant decode for short/simple EPG payloads.
    nonisolated private static func decodeEPGListings(from data: Data) -> [XtreamShortEPG] {
        let decoder = JSONDecoder()

        // Bare array.
        if let array = try? decoder.decode([XtreamShortEPG].self, from: data) {
            return array
        }

        // {"epg_listings":[...]} — decode each element individually so one bad
        // row cannot wipe the whole guide.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let rawList: [Any]
        if let list = root["epg_listings"] as? [Any] {
            rawList = list
        } else if let dict = root["epg_listings"] as? [String: Any] {
            // Some panels nest listings under stream-id keys.
            rawList = dict.values.flatMap { value -> [Any] in
                if let rows = value as? [Any] { return rows }
                if let row = value as? [String: Any] { return [row] }
                return []
            }
        } else if root["epg_listings"] is Bool || root["epg_listings"] is NSNull {
            return []
        } else {
            return []
        }

        var listings: [XtreamShortEPG] = []
        listings.reserveCapacity(rawList.count)
        for item in rawList {
            guard let row = item as? [String: Any],
                  let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let listing = try? decoder.decode(XtreamShortEPG.self, from: rowData)
            else { continue }
            listings.append(listing)
        }
        return listings
    }

    /// Full per-channel EPG (`get_simple_data_table`) — more programmes than short EPG.
    func getSimpleDataTable(playlist: Playlist, streamId: Int, limit: Int? = nil) async throws -> [XtreamDataTableEPG] {
        try await getSimpleDataTable(
            serverURL: playlist.serverURL,
            username: playlist.username,
            password: playlist.password,
            streamId: streamId,
            limit: limit
        )
    }

    func getSimpleDataTable(
        serverURL: String,
        username: String,
        password: String,
        streamId: Int,
        limit: Int? = nil,
        diagnosticLabel: String? = nil
    ) async throws -> [XtreamDataTableEPG] {
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: "get_simple_data_table"),
            URLQueryItem(name: "stream_id", value: String(streamId))
        ]
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        guard let url = buildURL(serverURL: serverURL, path: "player_api.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        // Reuse tolerant short-EPG decode, then map fields (same JSON shape).
        let short = try await fetchEPGListings(url: url, diagnosticLabel: diagnosticLabel)
        return short.map { row in
            XtreamDataTableEPG(
                epgId: nil,
                title: row.title,
                description: row.description,
                startTimestamp: row.startTimestamp,
                endTimestamp: row.endTimestamp ?? row.stopTimestamp,
                start: row.start,
                end: row.end,
                channelId: nil,
                streamId: nil,
                id: nil
            )
        }
    }

    /// Best-effort per-channel EPG: `get_short_epg`, then (when `thorough`)
    /// a no-limit retry and `get_simple_data_table`. Returns raw listing rows
    /// as a common shape for the live loader.
    ///
    /// - Parameter thorough: When `false`, stop after the single `get_short_epg`
    ///   call even if it comes back empty. A full-catalog sync hits thousands of
    ///   channels; for the ones with genuinely no EPG, the extra no-limit retry
    ///   and `get_simple_data_table` fallback each add a full round trip for no
    ///   benefit and were the main reason "Sync Now" was slow. Bulk sync passes
    ///   `false` and lets on-demand browse (small channel counts, `thorough:
    ///   true`) fill in any channel that actually needed the fallback.
    func fetchChannelEPG(
        serverURL: String,
        username: String,
        password: String,
        streamId: Int,
        limit: Int = 12,
        thorough: Bool = true,
        diagnosticLabel: String? = nil
    ) async throws -> [XtreamShortEPG] {
        let short = try await getShortEPG(
            serverURL: serverURL,
            username: username,
            password: password,
            streamId: streamId,
            limit: limit,
            diagnosticLabel: diagnosticLabel.map { "\($0)/short" }
        )
        if !short.isEmpty || !thorough { return short }

        // Retry short EPG without limit — some panels ignore/break with limit=.
        if limit != 0 {
            let unlimited = try await getShortEPG(
                serverURL: serverURL,
                username: username,
                password: password,
                streamId: streamId,
                limit: nil,
                diagnosticLabel: diagnosticLabel.map { "\($0)/short-nolimit" }
            )
            if !unlimited.isEmpty { return unlimited }
        }

        let table = try await getSimpleDataTable(
            serverURL: serverURL,
            username: username,
            password: password,
            streamId: streamId,
            limit: limit,
            diagnosticLabel: diagnosticLabel.map { "\($0)/table" }
        )
        return table.map { row in
            XtreamShortEPG(
                start: row.start,
                end: row.end,
                startTimestamp: row.startTimestamp,
                endTimestamp: row.endTimestamp,
                stopTimestamp: nil,
                title: row.title,
                description: row.description
            )
        }
    }

    /// A session tuned for parallel per-channel EPG fetches (on-demand browse fill).
    ///
    /// IMPORTANT: many Xtream panels cap the *whole account* — API calls and
    /// video stream connections together — to a small number of concurrent
    /// connections (see `XtreamError.authenticationFailed`'s message). A prior
    /// attempt raised this to 12 to speed up Sync Now and it broke Live TV
    /// playback entirely: the EPG sync was consuming the connection slots the
    /// video stream needed. Do not raise this without confirming the specific
    /// provider's concurrent-connection allowance — it is not something we can
    /// discover generically, and getting it wrong takes down playback, which is
    /// far worse than a slow guide refresh.
    nonisolated static func makeEPGImportSession() -> URLSession {
        ProviderURLSession.make(
            timeout: 30,
            resourceTimeout: 60,
            maxConnectionsPerHost: 6,
            additionalHeaders: ["User-Agent": apexCatalogUserAgent]
        )
    }

    /// A session for the full "Sync Now" bulk pass over every channel. Uses
    /// much shorter timeouts than on-demand browse so a slow or dead channel
    /// fails fast rather than holding a connection slot for 60 seconds.
    /// Channels that fail here are harmless — on-demand browse fills them in
    /// later with the standard-timeout session above.
    ///
    /// The 6-connection cap stays; see `makeEPGImportSession`'s doc comment.
    nonisolated static func makeEPGBulkSyncSession() -> URLSession {
        ProviderURLSession.make(
            timeout: 10,
            resourceTimeout: 20,
            maxConnectionsPerHost: 6,
            additionalHeaders: ["User-Agent": apexCatalogUserAgent]
        )
    }

    /// Discovers the external EPG URL embedded in the Xtream M3U playlist header.
    ///
    /// Many Xtream panels include a `url-tvg="…"` attribute in their M3U output
    /// that points to a current, external XMLTV guide (e.g. from epgshare or
    /// iptv-org). Apps like Chilli and SwipTV use this to get live guide data
    /// even when the panel's built-in `xmltv.php` is days behind.
    ///
    /// Uses streaming bytes to read just the first line without downloading the
    /// full (often 100+ MB) playlist, even if the server ignores Range headers.
    func discoverM3UHeaderEPGURL(
        serverURL: String,
        username: String,
        password: String
    ) async -> String? {
        let base = Self.normalizedPortalBaseURL(from: serverURL)
        guard !base.isEmpty else { return nil }
        guard var components = URLComponents(string: base + "/get.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "ts")
        ]
        guard let url = components.url else { return nil }

        Logger.network.warning("EPG M3U discovery — fetching header from \(url.absoluteString, privacy: .public)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        do {
            // Stream the response so we can cancel after reading the first line.
            let (bytes, response) = try await session.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                Logger.network.info("EPG M3U discovery — HTTP \(httpResponse.statusCode)")
                return nil
            }

            // Read bytes until we hit a newline (first line = #EXTM3U header).
            var headerBytes: [UInt8] = []
            headerBytes.reserveCapacity(2048)
            for try await byte in bytes {
                if byte == 0x0A { break } // newline
                if byte == 0x0D { continue } // skip CR
                headerBytes.append(byte)
                if headerBytes.count > 4096 { break } // safety cap
            }

            guard let firstLine = String(bytes: headerBytes, encoding: .utf8),
                  firstLine.hasPrefix("#EXTM3U") else {
                Logger.network.info("EPG M3U discovery — response is not an M3U playlist")
                return nil
            }

            let header = M3UParser.parseHeader(firstLine)
            if let epgURL = header.epgURL, !epgURL.isEmpty {
                Logger.network.warning(
                    "EPG discovered url-tvg from Xtream M3U: \(epgURL, privacy: .public)"
                )
                return epgURL
            }
            Logger.network.info("EPG M3U discovery — #EXTM3U header has no url-tvg attribute")
            return nil
        } catch {
            Logger.network.info("EPG M3U header discovery failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 11. Get XMLTV — download to temp file, then stream-parse in batches.
    /// Returns the local file URL so the caller can parse incrementally.
    func downloadXMLTV(playlist: Playlist) async throws -> URL {
        let queryItems = [
            URLQueryItem(name: "username", value: playlist.username),
            URLQueryItem(name: "password", value: playlist.password)
        ]

        guard let url = buildURL(serverURL: playlist.serverURL, path: "xmltv.php", queryItems: queryItems) else {
            throw XtreamError.invalidURL
        }

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(from: url)
        } catch {
            throw XtreamError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw XtreamError.serverError(httpResponse.statusCode)
        }

        // Move to a stable location before the system cleans it up
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xmltv")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return try EPGDownload.preparedXMLTV(at: destination, deleteOriginalIfGzip: false)
    }

    // MARK: - Stream URL Building

    /// Builds a playback URL for a movie
    func buildMovieURL(for movie: Movie, playlist: Playlist) -> URL? {
        let ext = movie.containerExtension ?? "mp4"
        return URL(string: "\(playlist.serverURL)/movie/\(playlist.username)/\(playlist.password)/\(movie.streamId).\(ext)")
    }

    /// Builds a playback URL for an episode. Tries the stated container extension
    /// first; if it's a raw file format (mkv, avi, mp4) that some providers don't
    /// serve directly, also provides an m3u8 fallback URL.
    func buildEpisodeURL(for episode: Episode, playlist: Playlist) -> URL? {
        let ext = episode.containerExtension.isEmpty ? "m3u8" : episode.containerExtension
        let base = playlist.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Many providers report mkv/avi as container_extension but only serve
        // via m3u8 or ts. Use the reported extension — if it fails, the player's
        // engine fallback mechanism retries.
        return URL(string: "\(base)/series/\(playlist.username)/\(playlist.password)/\(episode.episodeId).\(ext)")
    }

    /// Builds a playback URL for a live stream
    func buildLiveStreamURL(for stream: LiveStream, playlist: Playlist, format: StreamFormat = .m3u8) -> URL? {
        URL(string: "\(playlist.serverURL)/live/\(playlist.username)/\(playlist.password)/\(stream.streamId).\(format.rawValue)")
    }

    /// `Y-m-d:H-i` is the start format Xtream Codes panels expect in a timeshift
    /// path. Formatted in the device's local timezone — the panel interprets the
    /// value as wall-clock time, and EPG `start` dates are absolute instants, so
    /// this keeps the requested moment aligned with what the guide showed.
    private nonisolated static let timeshiftStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Builds a catch-up / timeshift URL for a past programme on a live stream.
    ///
    /// Uses the Xtream Codes timeshift path
    /// `…/timeshift/user/pass/{durationMinutes}/{Y-m-d:H-i}/{streamId}.{ext}`,
    /// where the duration is the programme length in minutes and the start is the
    /// programme's air time. Only meaningful for Xtream streams (m3u channels
    /// carry no credentials).
    nonisolated func buildCatchupURL(
        for stream: LiveStream,
        playlist: Playlist,
        start: Date,
        durationMinutes: Int,
        format: StreamFormat = .m3u8
    ) -> URL? {
        guard durationMinutes > 0 else { return nil }
        let startString = Self.timeshiftStartFormatter.string(from: start)
        return URL(string: "\(playlist.serverURL)/timeshift/\(playlist.username)/\(playlist.password)/\(durationMinutes)/\(startString)/\(stream.streamId).\(format.rawValue)")
    }
}

// MARK: - XMLTV Parser

/// A parsed XMLTV programme ready for direct insertion.
struct ParsedProgramme {
    let channelId: String
    let title: String
    let description: String
    let start: Date
    let end: Date
}

/// Streaming SAX parser that yields batches via a callback to keep memory flat.
final nonisolated class XMLTVParser: NSObject, XMLParserDelegate {
    private var batch: [ParsedProgramme] = []
    private let batchSize: Int
    private let onBatch: ([ParsedProgramme]) -> Void
    private(set) var totalCount: Int = 0

    private var currentStart: String?
    private var currentStop: String?
    private var currentChannel: String?
    private var currentTitle: String?
    private var currentDesc: String?
    private var currentText: String = ""

    init(batchSize: Int = 2000, onBatch: @escaping ([ParsedProgramme]) -> Void) {
        self.batchSize = batchSize
        self.onBatch = onBatch
    }

    /// Result counters from a combined channel-table + programme import pass.
    struct ImportStats: Sendable {
        let totalProgrammes: Int
        let matchedProgrammes: Int
        let channelTableSize: Int
        let parseFailures: Int
    }

    /// One SAX pass over the XMLTV file: collects the channel table, enriches
    /// the catalog on the first programme, and streams matched programmes in
    /// batches so the file is never parsed twice.
    static func importGuide<C: EPGChannelIdentity>(
        fileURL: URL,
        baseCatalog: EPGChannelCatalog,
        identities: [C],
        timezone: TimeZone? = nil,
        treatExplicitZeroOffsetAsLocal: Bool = false,
        interpretZeroOffsetIn zeroOffsetZone: TimeZone? = nil,
        batchSize: Int = 500,
        shouldAbort: (@Sendable () -> Bool)? = nil,
        onBatch: @escaping (EPGChannelCatalog, [ParsedProgramme]) -> Void
    ) -> ImportStats {
        guard let xmlParser = makeStreamingXMLParser(fileURL: fileURL) else {
            return ImportStats(totalProgrammes: 0, matchedProgrammes: 0, channelTableSize: 0, parseFailures: 0)
        }
        let delegate = XMLTVGuideImporter(
            baseCatalog: baseCatalog,
            identities: identities,
            exactNameIndex: EPGStreamExactNameIndex(identities: identities),
            timezone: timezone,
            treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
            interpretZeroOffsetIn: zeroOffsetZone,
            batchSize: batchSize,
            shouldAbort: shouldAbort,
            onBatch: onBatch
        )
        xmlParser.delegate = delegate
        xmlParser.parse()
        delegate.flushBatch()
        return ImportStats(
            totalProgrammes: delegate.totalProgrammes,
            matchedProgrammes: delegate.matchedProgrammes,
            channelTableSize: delegate.channelTableSize,
            parseFailures: delegate.parseFailures
        )
    }

    /// Parse only `<programme>` elements, yielding batches of catalog matches.
    static func parseProgrammes(
        fileURL: URL,
        catalog: EPGChannelCatalog,
        timezone: TimeZone? = nil,
        treatExplicitZeroOffsetAsLocal: Bool = false,
        interpretZeroOffsetIn zeroOffsetZone: TimeZone? = nil,
        batchSize: Int = 500,
        onBatch: @escaping ([ParsedProgramme]) -> Void
    ) -> (totalProgrammes: Int, matchedProgrammes: Int) {
        guard let xmlParser = makeStreamingXMLParser(fileURL: fileURL) else {
            return (0, 0)
        }
        let delegate = XMLTVProgrammeParser(
            catalog: catalog,
            timezone: timezone,
            treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
            interpretZeroOffsetIn: zeroOffsetZone,
            batchSize: batchSize,
            onBatch: onBatch
        )
        xmlParser.delegate = delegate
        xmlParser.parse()
        delegate.flushBatch()
        return (delegate.totalProgrammes, delegate.matchedProgrammes)
    }

    /// Parse an XMLTV file from disk, calling `onBatch` for every `batchSize` programmes.
    static func parse(fileURL: URL, batchSize: Int = 2000, onBatch: @escaping ([ParsedProgramme]) -> Void) -> Int {
        guard let xmlParser = makeStreamingXMLParser(fileURL: fileURL) else { return 0 }
        let delegate = XMLTVParser(batchSize: batchSize, onBatch: onBatch)
        xmlParser.delegate = delegate
        xmlParser.parse()
        // Flush remaining
        if !delegate.batch.isEmpty {
            onBatch(delegate.batch)
        }
        return delegate.totalCount
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == "programme" {
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"] ?? attributeDict["end"]
            currentChannel = attributeDict["channel"]
            currentTitle = nil
            currentDesc = nil
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == "programme" {
            if let times = XMLTVDate.parseProgrammeTimes(start: currentStart, stop: currentStop),
               let channel = currentChannel,
               let title = currentTitle, !title.isEmpty
            {
                batch.append(ParsedProgramme(
                    channelId: channel,
                    title: title,
                    description: currentDesc ?? "",
                    start: times.start,
                    end: times.end
                ))
                totalCount += 1

                if batch.count >= batchSize {
                    onBatch(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            currentStart = nil
            currentStop = nil
            currentChannel = nil
            currentTitle = nil
            currentDesc = nil
        } else if elementName == "title" {
            currentTitle = (currentTitle ?? "") + currentText
        } else if elementName == "desc" {
            currentDesc = (currentDesc ?? "") + currentText
        }
    }

    /// Parse only the `<channel>` table — used to map XMLTV ids to streams by name.
    static func parseChannels(fileURL: URL) -> XMLTVChannelIndex {
        guard let xmlParser = makeStreamingXMLParser(fileURL: fileURL) else { return .empty }
        let delegate = XMLTVChannelParser()
        xmlParser.delegate = delegate
        xmlParser.parse()
        return XMLTVChannelIndex(idToDisplayNames: delegate.channels)
    }

    /// Result from a single-pass external EPG import (channel table + programmes).
    struct ExternalEPGImportStats: Sendable {
        let totalProgrammes: Int
        let matchedProgrammes: Int
        let channelTableSize: Int
        let catalog: EPGChannelCatalog
        let westMappings: [String: [String]]
    }

    /// One SAX pass for external EPG: filters the channel table by playlist
    /// display names, builds the display-name catalog on the first programme,
    /// and streams matched programmes in batches (avoids parsing each file twice).
    static func importExternalEPG<C: EPGChannelIdentity>(
        fileURL: URL,
        identities: [C],
        batchSize: Int = 2000,
        onBatch: @escaping (EPGChannelCatalog, [String: [String]], [ParsedProgramme]) -> Void
    ) -> ExternalEPGImportStats {
        guard let xmlParser = makeStreamingXMLParser(fileURL: fileURL) else {
            return ExternalEPGImportStats(
                totalProgrammes: 0,
                matchedProgrammes: 0,
                channelTableSize: 0,
                catalog: EPGChannelCatalog(identities: identities),
                westMappings: [:]
            )
        }
        let delegate = XMLTVExternalEPGImporter(
            identities: identities,
            nameIndex: EPGStreamNameIndex(identities: identities),
            batchSize: batchSize,
            onBatch: onBatch
        )
        xmlParser.delegate = delegate
        xmlParser.parse()
        delegate.flushBatch()
        return ExternalEPGImportStats(
            totalProgrammes: delegate.totalProgrammes,
            matchedProgrammes: delegate.matchedProgrammes,
            channelTableSize: delegate.channelTableSize,
            catalog: delegate.resolvedCatalog,
            westMappings: delegate.resolvedWestMappings
        )
    }
}

/// Builds an incremental, stream-backed XML parser.
///
/// `XMLParser(contentsOf:)` loads the *entire* file into memory before parsing —
/// fatal for large decompressed XMLTV guides (a single epgshare01 feed like US2
/// is ~70 MB gzipped and expands to several hundred MB of XML). On a
/// memory-constrained device like Apple TV that allocation triggers a memory
/// warning and then a jetsam kill mid-sync. An `InputStream` lets `XMLParser`
/// read incrementally so its footprint stays flat regardless of file size.
nonisolated func makeStreamingXMLParser(fileURL: URL) -> XMLParser? {
    guard let stream = InputStream(url: fileURL) else { return nil }
    return XMLParser(stream: stream)
}

/// Combined XMLTV delegate — channel table + programme batches in one pass.
private let xmltvMaxTextLength = 512
/// Cap retained channel rows when a provider ships a worldwide guide (50MB+).
private let xmltvMaxChannelTableEntries = 2_500

private final nonisolated class XMLTVGuideImporter<C: EPGChannelIdentity>: NSObject, XMLParserDelegate {
    private let baseCatalog: EPGChannelCatalog
    private let identities: [C]
    private let exactNameIndex: EPGStreamExactNameIndex
    private let timezone: TimeZone?
    private let treatExplicitZeroOffsetAsLocal: Bool
    private let interpretZeroOffsetIn: TimeZone?
    private let batchSize: Int
    private let shouldAbort: (@Sendable () -> Bool)?
    private let onBatch: (EPGChannelCatalog, [ParsedProgramme]) -> Void

    private var channelTable: [String: [String]] = [:]
    private var enrichedCatalog: EPGChannelCatalog?
    private var batch: [ParsedProgramme] = []

    private(set) var totalProgrammes = 0
    private(set) var matchedProgrammes = 0
    private(set) var parseFailures = 0
    private var loggedRawTimestamp = false
    private var unmatchedSamples = Set<String>()
    private var loggedCurrentUnmatched = false
    private var loggedCurrentMatched = false

    var channelTableSize: Int { channelTable.count }

    private var currentChannelID: String?
    private var currentChannelNames: [String] = []
    private var currentDisplayName: String?
    private var currentStart: String?
    private var currentStop: String?
    private var currentProgrammeChannel: String?
    private var currentTitle: String?
    private var currentDesc: String?
    private var currentText = ""

    init(
        baseCatalog: EPGChannelCatalog,
        identities: [C],
        exactNameIndex: EPGStreamExactNameIndex,
        timezone: TimeZone? = nil,
        treatExplicitZeroOffsetAsLocal: Bool = false,
        interpretZeroOffsetIn zeroOffsetZone: TimeZone? = nil,
        batchSize: Int,
        shouldAbort: (@Sendable () -> Bool)? = nil,
        onBatch: @escaping (EPGChannelCatalog, [ParsedProgramme]) -> Void
    ) {
        self.baseCatalog = baseCatalog
        self.identities = identities
        self.exactNameIndex = exactNameIndex
        self.timezone = timezone
        self.treatExplicitZeroOffsetAsLocal = treatExplicitZeroOffsetAsLocal
        self.interpretZeroOffsetIn = zeroOffsetZone
        self.batchSize = batchSize
        self.shouldAbort = shouldAbort
        self.onBatch = onBatch
    }

    func flushBatch() {
        guard !batch.isEmpty else { return }
        let catalog = enrichedCatalog ?? baseCatalog
        onBatch(catalog, batch)
        batch.removeAll(keepingCapacity: true)
    }

    private func ensureCatalog() {
        guard enrichedCatalog == nil else { return }
        let index = XMLTVChannelIndex(idToDisplayNames: channelTable)
        enrichedCatalog = baseCatalog.enriching(with: index, identities: identities)
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "channel":
            currentChannelID = attributeDict["id"]
            currentChannelNames = []
            currentDisplayName = nil
        case "programme":
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"] ?? attributeDict["end"]
            currentProgrammeChannel = attributeDict["channel"]
            currentTitle = nil
            currentDesc = nil
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard currentText.count < xmltvMaxTextLength else { return }
        let remaining = xmltvMaxTextLength - currentText.count
        currentText += String(string.prefix(remaining))
    }

    private func commitChannelIfRelevant() {
        guard let channelID = currentChannelID else { return }
        guard !currentChannelNames.isEmpty else { return }
        let idMatch = baseCatalog.matches(channelID)
        let nameMatch = exactNameIndex.matches(displayNames: currentChannelNames)
        guard idMatch || nameMatch else { return }
        guard idMatch || channelTable.count < xmltvMaxChannelTableEntries else { return }
        channelTable[channelID] = currentChannelNames
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        switch elementName {
        case "display-name":
            if currentChannelID != nil {
                let name = (currentDisplayName ?? "") + currentText
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    currentChannelNames.append(trimmed)
                }
                currentDisplayName = name
            }
        case "channel":
            commitChannelIfRelevant()
            currentChannelID = nil
            currentChannelNames = []
            currentDisplayName = nil
        case "programme":
            defer {
                currentStart = nil
                currentStop = nil
                currentProgrammeChannel = nil
                currentTitle = nil
                currentDesc = nil
            }
            guard let channel = currentProgrammeChannel,
                  let title = currentTitle, !title.isEmpty
            else { return }
            totalProgrammes += 1
            if totalProgrammes.isMultiple(of: 25_000) {
                Logger.database.info(
                    "EPG XMLTV parse progress: \(self.totalProgrammes) programmes, \(self.matchedProgrammes) matched"
                )
            }

            var catalog = enrichedCatalog
            if catalog == nil {
                if baseCatalog.matches(channel) {
                    catalog = baseCatalog
                } else {
                    ensureCatalog()
                    catalog = enrichedCatalog
                }
            }
            guard let catalog, catalog.matches(channel) else {
                if totalProgrammes <= 5 || (totalProgrammes.isMultiple(of: 50_000) && unmatchedSamples.count < 10) {
                    if !unmatchedSamples.contains(channel) && unmatchedSamples.count < 10 {
                        unmatchedSamples.insert(channel)
                        Logger.database.warning(
                            "EPG XMLTV unmatched channel: \(channel, privacy: .public) title: \(title, privacy: .public) start: \(self.currentStart ?? "nil", privacy: .public)"
                        )
                    }
                }
                // Log ANY unmatched programme with a CURRENT timestamp (today).
                if !loggedCurrentUnmatched,
                   let startStr = currentStart,
                   startStr.hasPrefix("202607070") || startStr.hasPrefix("202607071") || startStr.hasPrefix("2026070716") || startStr.hasPrefix("2026070715") || startStr.hasPrefix("2026070714") || startStr.hasPrefix("2026070713") || startStr.hasPrefix("2026070712")
                {
                    loggedCurrentUnmatched = true
                    Logger.database.warning(
                        "EPG XMLTV ** CURRENT unmatched ** channel: \(channel, privacy: .public) title: \(title, privacy: .public) start: \(startStr, privacy: .public)"
                    )
                }
                return
            }
            if !loggedRawTimestamp {
                loggedRawTimestamp = true
                let rawStart = currentStart ?? "nil"
                let rawStop = currentStop ?? "nil"
                Logger.database.warning(
                    "EPG XMLTV raw timestamp — start: \(rawStart, privacy: .public), stop: \(rawStop, privacy: .public)"
                )
            }
            guard let times = XMLTVDate.parseProgrammeTimes(
                start: currentStart,
                stop: currentStop,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
            )
            else {
                parseFailures += 1
                return
            }
            matchedProgrammes += 1
            // Log if we find a matched programme from TODAY.
            if !loggedCurrentMatched,
               let startStr = currentStart,
               startStr.hasPrefix("20260707")
            {
                loggedCurrentMatched = true
                Logger.database.warning(
                    "EPG XMLTV ** TODAY matched ** channel: \(channel, privacy: .public) title: \(title, privacy: .public) start: \(startStr, privacy: .public)"
                )
            }
            batch.append(ParsedProgramme(
                channelId: channel,
                title: String(title.prefix(xmltvMaxTextLength)),
                description: String((currentDesc ?? "").prefix(xmltvMaxTextLength)),
                start: times.start,
                end: times.end
            ))
            if batch.count >= batchSize {
                onBatch(catalog, batch)
                batch.removeAll(keepingCapacity: true)
            }
            if matchedProgrammes >= 50, shouldAbort?() == true {
                parser.abortParsing()
            }
        case "title":
            currentTitle = (currentTitle ?? "") + currentText
        case "desc":
            currentDesc = (currentDesc ?? "") + currentText
        default:
            break
        }
        currentText = ""
    }
}

/// Programme-only XMLTV delegate — no channel table retained in memory.
private final nonisolated class XMLTVProgrammeParser: NSObject, XMLParserDelegate {
    private let catalog: EPGChannelCatalog
    private let timezone: TimeZone?
    private let treatExplicitZeroOffsetAsLocal: Bool
    private let interpretZeroOffsetIn: TimeZone?
    private let batchSize: Int
    private let onBatch: ([ParsedProgramme]) -> Void
    private var batch: [ParsedProgramme] = []

    private(set) var totalProgrammes = 0
    private(set) var matchedProgrammes = 0

    private var currentStart: String?
    private var currentStop: String?
    private var currentChannel: String?
    private var currentTitle: String?
    private var currentDesc: String?
    private var currentText = ""

    init(
        catalog: EPGChannelCatalog,
        timezone: TimeZone? = nil,
        treatExplicitZeroOffsetAsLocal: Bool = false,
        interpretZeroOffsetIn zeroOffsetZone: TimeZone? = nil,
        batchSize: Int,
        onBatch: @escaping ([ParsedProgramme]) -> Void
    ) {
        self.catalog = catalog
        self.timezone = timezone
        self.treatExplicitZeroOffsetAsLocal = treatExplicitZeroOffsetAsLocal
        self.interpretZeroOffsetIn = zeroOffsetZone
        self.batchSize = batchSize
        self.onBatch = onBatch
    }

    func flushBatch() {
        guard !batch.isEmpty else { return }
        onBatch(batch)
        batch.removeAll(keepingCapacity: false)
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == "programme" {
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"] ?? attributeDict["end"]
            currentChannel = attributeDict["channel"]
            currentTitle = nil
            currentDesc = nil
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard currentText.count < xmltvMaxTextLength else { return }
        let remaining = xmltvMaxTextLength - currentText.count
        currentText += String(string.prefix(remaining))
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == "programme" {
            defer {
                currentStart = nil
                currentStop = nil
                currentChannel = nil
                currentTitle = nil
                currentDesc = nil
            }
            guard let channel = currentChannel,
                  let title = currentTitle, !title.isEmpty
            else { return }
            totalProgrammes += 1
            if totalProgrammes.isMultiple(of: 25_000) {
                Logger.database.info(
                    "EPG XMLTV parse progress: \(self.totalProgrammes) programmes, \(self.matchedProgrammes) matched"
                )
            }
            guard catalog.matches(channel) else { return }
            guard let times = XMLTVDate.parseProgrammeTimes(
                start: currentStart,
                stop: currentStop,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
            )
            else { return }
            matchedProgrammes += 1
            batch.append(ParsedProgramme(
                channelId: channel,
                title: String(title.prefix(xmltvMaxTextLength)),
                description: String((currentDesc ?? "").prefix(128)),
                start: times.start,
                end: times.end
            ))
            if batch.count >= batchSize {
                onBatch(batch)
                batch.removeAll(keepingCapacity: false)
            }
        } else if elementName == "title" {
            currentTitle = (currentTitle ?? "") + currentText
        } else if elementName == "desc" {
            currentDesc = (currentDesc ?? "") + currentText
        }
        currentText = ""
    }
}

/// Lightweight delegate that collects XMLTV channel ids and display names.
private final nonisolated class XMLTVChannelParser: NSObject, XMLParserDelegate {
    private(set) var channels: [String: [String]] = [:]
    private var currentChannelID: String?
    private var currentDisplayName: String?
    private var currentText = ""

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == "channel" {
            currentChannelID = attributeDict["id"]
            currentDisplayName = nil
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        if elementName == "display-name", let channelID = currentChannelID {
            let name = (currentDisplayName ?? "") + currentText
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                channels[channelID, default: []].append(trimmed)
            }
            currentDisplayName = name
        } else if elementName == "channel" {
            currentChannelID = nil
            currentDisplayName = nil
        }
        currentText = ""
    }
}

/// Single-pass external EPG delegate — name-filtered channel table + programmes.
private final nonisolated class XMLTVExternalEPGImporter<C: EPGChannelIdentity>: NSObject, XMLParserDelegate {
    private let identities: [C]
    private let nameIndex: EPGStreamNameIndex
    private let batchSize: Int
    private let onBatch: (EPGChannelCatalog, [String: [String]], [ParsedProgramme]) -> Void

    private var channelTable: [String: [String]] = [:]
    private var catalog: EPGChannelCatalog?
    private var westMappings: [String: [String]] = [:]
    private var batch: [ParsedProgramme] = []

    private(set) var totalProgrammes = 0
    private(set) var matchedProgrammes = 0

    var channelTableSize: Int { channelTable.count }
    var resolvedCatalog: EPGChannelCatalog {
        catalog ?? EPGChannelCatalog(identities: identities)
    }

    var resolvedWestMappings: [String: [String]] { westMappings }

    private var currentChannelID: String?
    private var currentChannelNames: [String] = []
    private var currentDisplayName: String?
    private var currentStart: String?
    private var currentStop: String?
    private var currentProgrammeChannel: String?
    private var currentTitle: String?
    private var currentDesc: String?
    private var currentText = ""

    init(
        identities: [C],
        nameIndex: EPGStreamNameIndex,
        batchSize: Int,
        onBatch: @escaping (EPGChannelCatalog, [String: [String]], [ParsedProgramme]) -> Void
    ) {
        self.identities = identities
        self.nameIndex = nameIndex
        self.batchSize = batchSize
        self.onBatch = onBatch
    }

    func flushBatch() {
        guard !batch.isEmpty else { return }
        ensureCatalog()
        guard let catalog else { return }
        onBatch(catalog, westMappings, batch)
        batch.removeAll(keepingCapacity: true)
    }

    private func ensureCatalog() {
        guard catalog == nil else { return }
        let index = XMLTVChannelIndex(idToDisplayNames: channelTable)
        let result = EPGChannelCatalog.fromExternalEPG(xmltvChannels: index, identities: identities)
        catalog = result.catalog
        westMappings = result.westMappings
    }

    private func commitChannelIfRelevant() {
        guard let channelID = currentChannelID else { return }
        guard !currentChannelNames.isEmpty else { return }
        guard nameIndex.mightMatch(displayNames: currentChannelNames) else { return }
        guard channelTable.count < xmltvMaxChannelTableEntries else { return }
        channelTable[channelID] = currentChannelNames
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "channel":
            currentChannelID = attributeDict["id"]
            currentChannelNames = []
            currentDisplayName = nil
        case "programme":
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"] ?? attributeDict["end"]
            currentProgrammeChannel = attributeDict["channel"]
            currentTitle = nil
            currentDesc = nil
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard currentText.count < xmltvMaxTextLength else { return }
        let remaining = xmltvMaxTextLength - currentText.count
        currentText += String(string.prefix(remaining))
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        switch elementName {
        case "display-name":
            if currentChannelID != nil {
                let name = (currentDisplayName ?? "") + currentText
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    currentChannelNames.append(trimmed)
                }
                currentDisplayName = name
            }
        case "channel":
            commitChannelIfRelevant()
            currentChannelID = nil
            currentChannelNames = []
            currentDisplayName = nil
        case "programme":
            defer {
                currentStart = nil
                currentStop = nil
                currentProgrammeChannel = nil
                currentTitle = nil
                currentDesc = nil
            }
            guard let channel = currentProgrammeChannel,
                  let title = currentTitle, !title.isEmpty
            else { return }
            totalProgrammes += 1
            ensureCatalog()
            guard let catalog, catalog.matches(channel) else { return }
            guard let times = XMLTVDate.parseProgrammeTimes(start: currentStart, stop: currentStop)
            else { return }
            matchedProgrammes += 1
            batch.append(ParsedProgramme(
                channelId: channel,
                title: String(title.prefix(xmltvMaxTextLength)),
                description: String((currentDesc ?? "").prefix(xmltvMaxTextLength)),
                start: times.start,
                end: times.end
            ))
            if batch.count >= batchSize {
                onBatch(catalog, westMappings, batch)
                batch.removeAll(keepingCapacity: true)
            }
        case "title":
            currentTitle = (currentTitle ?? "") + currentText
        case "desc":
            currentDesc = (currentDesc ?? "") + currentText
        default:
            break
        }
        currentText = ""
    }
}

// MARK: - Supporting Types

enum StreamFormat: String {
    case m3u8
    case tsStream = "ts"
}

