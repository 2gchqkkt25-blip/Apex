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
    func fetchBestSubtitle(imdbId: String, season: Int? = nil, episode: Int? = nil) async throws -> WyzieSubtitleFile {
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
        guard !results.isEmpty else { throw WyzieSubsError.noSubtitlesFound }

        // The first hit is often a ZIP. Keep going until one file is a real SRT.
        var lastError: Error = WyzieSubsError.noSubtitlesFound
        for result in results {
            guard let downloadLink = result.url, let downloadURL = URL(string: downloadLink) else { continue }
            do {
                let file = try await downloadSRT(from: downloadURL, language: result.lang)
                return file
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func downloadSRT(from downloadURL: URL, language: String?) async throws -> WyzieSubtitleFile {
        let (fileData, _) = try await session.data(from: downloadURL)

        // ZIP files start with "PK\x03\x04". Those are skipped so a later result can win.
        let isZip = fileData.count > 4 && fileData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
        if isZip {
            Logger.player.warning("[Subtitles] Wyzie returned a ZIP file — trying the next result")
            throw WyzieSubsError.downloadFailed
        }

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

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".srt")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)

        Logger.player.info("[Subtitles] Wyzie downloaded subtitle to \(tempURL.lastPathComponent) (\(content.count) chars)")
        return WyzieSubtitleFile(url: tempURL, label: Self.languageLabel(language))
    }

    private static func languageLabel(_ code: String?) -> String {
        switch String(code?.lowercased().prefix(2) ?? "") {
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "pt": return "Portuguese"
        case "it": return "Italian"
        case "nl": return "Dutch"
        case "pl": return "Polish"
        case "sv": return "Swedish"
        case "no", "nb": return "Norwegian"
        case "da": return "Danish"
        case "fi": return "Finnish"
        case "ar": return "Arabic"
        case "hi": return "Hindi"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh": return "Chinese"
        default:
            if let code, !code.isEmpty { return code.uppercased() }
            return "Subtitles"
        }
    }
}

struct WyzieSubtitleFile {
    let url: URL
    let label: String
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
