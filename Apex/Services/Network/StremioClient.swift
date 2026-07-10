//
//  StremioClient.swift
//  Apex
//
//  API client for the Stremio addon protocol.  Fetches manifests, catalogs,
//  metadata and streams from community addons.
//

import Foundation

// MARK: - URL normalization

/// Normalizes user-pasted Stremio addon URLs to a canonical base for API requests.
enum StremioURL {
    /// Converts pasted install links (`…/manifest.json`, `stremio+https://…`) to the
    /// addon base URL stored on the playlist and used for catalog/stream requests.
    static func normalize(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("stremio+") {
            trimmed = String(trimmed.dropFirst("stremio+".count))
        } else if trimmed.hasPrefix("stremio://") {
            if let hash = trimmed.firstIndex(of: "#") {
                trimmed = String(trimmed[trimmed.index(after: hash)...])
            } else {
                trimmed = String(trimmed.dropFirst("stremio://".count))
            }
        }

        guard var url = URL(string: trimmed) else { return nil }

        if url.lastPathComponent == "manifest.json" {
            url.deleteLastPathComponent()
        }

        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var path = components.path
            if path == "/" {
                components.path = ""
            } else if path.hasSuffix("/") {
                components.path = String(path.dropLast())
            }
            url = components.url ?? url
        }

        return url
    }

    /// Resolves the manifest fetch URL for a normalized addon base.
    static func manifestURL(base: URL) -> URL {
        let path = base.path
        if path.hasSuffix("/stremio/v1") || path.hasSuffix("stremio/v1") {
            return base
        }
        if base.lastPathComponent == "manifest.json" {
            return base
        }
        return base.appendingPathComponent("manifest.json")
    }
}

// MARK: - Error

enum StremioError: Error, LocalizedError {
    case invalidURL
    case notConfigured
    case httpError(Int)
    case decodingError(Error)
    case manifestNotFound
    case noCompatibleStreams

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid addon URL."
        case .notConfigured: "Stremio client not configured."
        case .httpError(let code): "Server returned status \(code)."
        case .decodingError(let error): "Failed to parse manifest: \(error.localizedDescription)"
        case .manifestNotFound: "No manifest found at this URL."
        case .noCompatibleStreams: "No playable streams returned by this addon."
        }
    }
}

// MARK: - Client

final class StremioClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .stremio) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Manifest

    /// Fetches the addon manifest. The URL should be the addon's base URL;
    /// `manifest.json` is appended automatically (legacy `/stremio/v1` URLs are
    /// fetched as-is).
    func fetchManifest(baseURL: URL) async throws -> StremioManifest {
        let manifestURL = StremioURL.manifestURL(base: baseURL)
        let data = try await get(manifestURL)
        do {
            return try decoder.decode(StremioManifest.self, from: data)
        } catch {
            throw StremioError.decodingError(error)
        }
    }

    /// Convenience: fetch manifest from a string URL (what the user enters).
    func fetchManifest(from urlString: String) async throws -> StremioManifest {
        guard let url = StremioURL.normalize(urlString) else { throw StremioError.invalidURL }
        return try await fetchManifest(baseURL: url)
    }

    // MARK: - Catalog

    /// Fetches one page of a catalog.  Stremio paginates with a `skip` parameter.
    func fetchCatalog(
        baseURL: URL,
        type: String,
        catalogId: String,
        skip: Int = 0
    ) async throws -> StremioCatalog {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("catalog/\(type)/\(catalogId).json"),
            resolvingAgainstBaseURL: false
        )!
        if skip > 0 {
            components.queryItems = [URLQueryItem(name: "skip", value: String(skip))]
        }
        guard let url = components.url else { throw StremioError.invalidURL }
        let data = try await get(url)
        do {
            return try decoder.decode(StremioCatalog.self, from: data)
        } catch {
            throw StremioError.decodingError(error)
        }
    }

    /// Fetches all pages of a catalog until exhausted.
    func fetchAllCatalog(
        baseURL: URL,
        type: String,
        catalogId: String,
        maxItems: Int = 10_000
    ) async throws -> [StremioMetaPreview] {
        var all: [StremioMetaPreview] = []
        var skip = 0
        while all.count < maxItems {
            let page = try await fetchCatalog(baseURL: baseURL, type: type, catalogId: catalogId, skip: skip)
            if page.metas.isEmpty { break }
            all.append(contentsOf: page.metas)
            skip += page.metas.count
        }
        return all
    }

    // MARK: - Meta

    /// Fetches full metadata for a single item.
    func fetchMeta(baseURL: URL, type: String, id: String) async throws -> StremioMeta {
        let url = baseURL.appendingPathComponent("meta/\(type)/\(id).json")
        let data = try await get(url)
        do {
            let response = try decoder.decode(StremioMetaResponse.self, from: data)
            return response.meta
        } catch {
            throw StremioError.decodingError(error)
        }
    }

    // MARK: - Streams

    /// Fetches playable streams for an item.  Filters out torrent-only streams
    /// (infoHash without a URL) since those require a P2P backend.
    func fetchStreams(baseURL: URL, type: String, id: String) async throws -> [StremioStream] {
        let url = baseURL.appendingPathComponent("stream/\(type)/\(id).json")
        let data = try await get(url)
        let response: StremioStreamResponse
        do {
            response = try decoder.decode(StremioStreamResponse.self, from: data)
        } catch {
            throw StremioError.decodingError(error)
        }
        // Only keep streams that have a direct URL — infoHash-only streams need
        // a torrent backend, which we don't bundle.
        return response.streams.filter { $0.bestURL != nil }
    }

    // MARK: - Helpers

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(apexCatalogUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StremioError.invalidURL
        }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 404 { throw StremioError.manifestNotFound }
            throw StremioError.httpError(http.statusCode)
        }
        return data
    }
}

private extension URLSession {
    static let stremio: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()
}
