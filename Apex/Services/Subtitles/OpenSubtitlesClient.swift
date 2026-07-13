//
//  OpenSubtitlesClient.swift
//  Apex
//
//  Client for the OpenSubtitles.com REST API (v1). Searches and downloads
//  subtitles by IMDB ID + season/episode for content without embedded subs.
//

import Foundation
import OSLog

enum OpenSubtitlesError: Error, LocalizedError {
    case notConfigured
    case invalidResponse(Int)
    case noSubtitlesFound
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "OpenSubtitles API key not configured."
        case .invalidResponse(let code): "OpenSubtitles returned status \(code)."
        case .noSubtitlesFound: "No subtitles found for this content."
        case .downloadFailed: "Failed to download subtitle file."
        }
    }
}

final class OpenSubtitlesClient {
    static let shared = OpenSubtitlesClient()

    private let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - Settings

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: OpenSubtitlesSettings.apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preferredLanguage: String {
        UserDefaults.standard.string(forKey: OpenSubtitlesSettings.languageKey) ?? "en"
    }

    var isConfigured: Bool {
        guard let key = apiKey, !key.isEmpty else { return false }
        return true
    }

    // MARK: - Search

    /// Searches for subtitles by IMDB ID (movies/series episodes).
    func searchSubtitles(imdbId: String, season: Int? = nil, episode: Int? = nil) async throws -> [OpenSubtitleResult] {
        guard let apiKey, !apiKey.isEmpty else { throw OpenSubtitlesError.notConfigured }

        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbId),
            URLQueryItem(name: "languages", value: preferredLanguage)
        ]
        if let season { queryItems.append(URLQueryItem(name: "season_number", value: String(season))) }
        if let episode { queryItems.append(URLQueryItem(name: "episode_number", value: String(episode))) }
        components.queryItems = queryItems

        guard let url = components.url else { throw OpenSubtitlesError.notConfigured }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Apex IPTV v1.2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OpenSubtitlesError.invalidResponse(code)
        }

        let decoded = try JSONDecoder().decode(OpenSubtitlesSearchResponse.self, from: data)
        return decoded.data
    }

    // MARK: - Download

    /// Downloads a subtitle file and returns the local file URL (SRT format).
    func downloadSubtitle(fileId: Int) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else { throw OpenSubtitlesError.notConfigured }

        let url = baseURL.appendingPathComponent("download")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Apex IPTV v1.2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["file_id": fileId])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OpenSubtitlesError.downloadFailed
        }

        let decoded = try JSONDecoder().decode(OpenSubtitlesDownloadResponse.self, from: data)
        guard let downloadURL = URL(string: decoded.link) else { throw OpenSubtitlesError.downloadFailed }

        // Download the actual subtitle file
        let (fileData, _) = try await session.data(from: downloadURL)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".srt")
        try fileData.write(to: tempURL)

        Logger.player.info("OpenSubtitles downloaded subtitle to \(tempURL.lastPathComponent)")
        return tempURL
    }

    /// Convenience: search + download the best matching subtitle.
    func fetchBestSubtitle(imdbId: String, season: Int? = nil, episode: Int? = nil) async throws -> URL {
        let results = try await searchSubtitles(imdbId: imdbId, season: season, episode: episode)
        guard let best = results.first,
              let file = best.attributes.files.first
        else { throw OpenSubtitlesError.noSubtitlesFound }

        return try await downloadSubtitle(fileId: file.fileId)
    }
}

// MARK: - Response Models

struct OpenSubtitlesSearchResponse: Decodable {
    let data: [OpenSubtitleResult]
}

struct OpenSubtitleResult: Decodable {
    let id: String
    let attributes: OpenSubtitleAttributes
}

struct OpenSubtitleAttributes: Decodable {
    let language: String
    let release: String?
    let files: [OpenSubtitleFile]

    enum CodingKeys: String, CodingKey {
        case language, release, files
    }
}

struct OpenSubtitleFile: Decodable {
    let fileId: Int
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
    }
}

struct OpenSubtitlesDownloadResponse: Decodable {
    let link: String
    let fileName: String?
    let requests: Int?

    enum CodingKeys: String, CodingKey {
        case link
        case fileName = "file_name"
        case requests
    }
}
