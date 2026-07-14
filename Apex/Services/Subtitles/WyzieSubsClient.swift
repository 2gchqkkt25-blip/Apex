//
//  WyzieSubsClient.swift
//  Apex
//
//  Client for the Wyzie Subs API (sub.wyzie.io). Simple GET-based subtitle
//  search that returns download URLs directly — no login or separate download
//  step required. Aggregates multiple subtitle sources behind one request.
//
//  Free tier: 1,000 requests/day with a free API key from store.wyzie.io/redeem.
//

import Foundation
import OSLog

enum WyzieSubsError: Error, LocalizedError {
    case notConfigured
    case invalidResponse(Int)
    case noSubtitlesFound
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Wyzie Subs API key not configured."
        case .invalidResponse(let code): "Wyzie Subs returned status \(code)."
        case .noSubtitlesFound: "No subtitles found for this content."
        case .downloadFailed: "Failed to download subtitle file."
        }
    }
}

final class WyzieSubsClient {
    static let shared = WyzieSubsClient()

    private let baseURL = URL(string: "https://sub.wyzie.io")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - Settings

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: SubtitleSettings.wyzieApiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preferredLanguage: String {
        UserDefaults.standard.string(forKey: SubtitleSettings.languageKey) ?? "en"
    }

    var isConfigured: Bool {
        guard let key = apiKey, !key.isEmpty else { return false }
        return true
    }

    // MARK: - Search + Download (one step)

    /// Searches for subtitles and returns the best match's download URL.
    /// Wyzie returns direct download links in the search response — no separate
    /// download endpoint needed.
    func fetchBestSubtitle(imdbId: String, season: Int? = nil, episode: Int? = nil) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else { throw WyzieSubsError.notConfigured }

        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "id", value: imdbId),
            URLQueryItem(name: "language", value: preferredLanguage),
            URLQueryItem(name: "format", value: "srt"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let season { queryItems.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode { queryItems.append(URLQueryItem(name: "episode", value: String(episode))) }
        components.queryItems = queryItems

        guard let url = components.url else { throw WyzieSubsError.notConfigured }

        var request = URLRequest(url: url)
        request.setValue("Apex IPTV v1.2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Logger.player.error("[Subtitles] Wyzie search failed: status \(code) for id=\(imdbId)")
            throw WyzieSubsError.invalidResponse(code)
        }

        let results = try JSONDecoder().decode([WyzieSubtitleResult].self, from: data)
        guard let best = results.first, let downloadLink = best.url, let downloadURL = URL(string: downloadLink) else {
            throw WyzieSubsError.noSubtitlesFound
        }

        // Download the subtitle file to a temp location
        let (fileData, _) = try await session.data(from: downloadURL)

        // Detect if the response is a ZIP archive (some sources wrap SRT in ZIP).
        // ZIP files start with "PK\x03\x04".
        let isZip = fileData.count > 4 && fileData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
        if isZip {
            Logger.player.warning("[Subtitles] Wyzie returned a ZIP file — skipping (unsupported)")
            throw WyzieSubsError.downloadFailed
        }

        // Try to decode as text to verify it's a valid subtitle file.
        // Many subtitle files use Latin-1 or Windows-1252 instead of UTF-8.
        let textContent: String?
        if let utf8 = String(data: fileData, encoding: .utf8) {
            textContent = utf8
        } else if let latin1 = String(data: fileData, encoding: .isoLatin1) {
            textContent = latin1
        } else {
            textContent = String(data: fileData, encoding: .windowsCP1252)
        }

        guard let content = textContent, content.contains("-->") else {
            Logger.player.warning("[Subtitles] Wyzie downloaded file is not a valid SRT (no timestamps found, \(fileData.count) bytes)")
            throw WyzieSubsError.downloadFailed
        }

        // Write as UTF-8 so the SRT parser can read it reliably
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".srt")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)

        Logger.player.info("[Subtitles] Wyzie downloaded subtitle to \(tempURL.lastPathComponent) (\(content.count) chars)")
        return tempURL
    }
}

// MARK: - Response Models

struct WyzieSubtitleResult: Decodable {
    let url: String?
    let lang: String?
    let author: String?
    let releaseName: String?
    let isHearingImpaired: Bool?

    enum CodingKeys: String, CodingKey {
        case url, lang, author
        case releaseName = "release_name"
        case isHearingImpaired = "hi"
    }
}
