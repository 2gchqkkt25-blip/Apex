//
//  StremioStreamResolver.swift
//  Apex
//
//  Resolves Stremio placeholder URLs to actual playable stream URLs at
//  playback time. Automatically selects the best available stream based on
//  quality indicators (resolution, codec, file size) from the stream title.
//

import Foundation
import OSLog

enum StremioStreamResolver {
    private static let client = StremioClient()

    /// Attempts to resolve a Stremio placeholder to the best playable stream URL.
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
        guard !streams.isEmpty else { throw StremioError.noCompatibleStreams }

        // Auto-select: rank streams by quality and pick the best one
        let best = selectBestStream(from: streams)
        guard let url = best.bestURL else { throw StremioError.noCompatibleStreams }

        Logger.player.info("Stremio auto-selected: \"\(best.displayTitle, privacy: .public)\" from \(streams.count) streams")
        return url
    }

    /// Resolves a Stremio `PlayableMedia` by replacing its placeholder URL with
    /// the best available stream URL fetched from the addon.
    static func resolve(_ media: PlayableMedia) async throws -> PlayableMedia {
        let urlString = media.url.absoluteString
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

    // MARK: - Stream Quality Selection

    /// Ranks streams by quality and returns the best one. Considers:
    /// 1. Resolution (4K > 1080p > 720p > SD)
    /// 2. File size (larger = higher bitrate = better quality)
    /// 3. Known good sources (web-ready streams preferred)
    /// 4. Falls back to first stream if no quality info available
    private static func selectBestStream(from streams: [StremioStream]) -> StremioStream {
        guard streams.count > 1 else { return streams[0] }

        let scored = streams.map { stream -> (stream: StremioStream, score: Int) in
            var score = 0
            let text = (stream.title ?? "") + " " + (stream.name ?? "") + " " + (stream.description ?? "")
            let lower = text.lowercased()

            // Resolution scoring
            if lower.contains("2160p") || lower.contains("4k") || lower.contains("uhd") {
                score += 400
            } else if lower.contains("1080p") || lower.contains("1080") {
                score += 300
            } else if lower.contains("720p") || lower.contains("720") {
                score += 200
            } else if lower.contains("480p") || lower.contains("sd") {
                score += 100
            }

            // Codec preference (H.265/HEVC is better compression = higher quality at same size)
            if lower.contains("hevc") || lower.contains("h.265") || lower.contains("x265") || lower.contains("h265") {
                score += 50
            } else if lower.contains("h.264") || lower.contains("x264") || lower.contains("h264") {
                score += 30
            }

            // HDR bonus
            if lower.contains("hdr") || lower.contains("dolby vision") || lower.contains("dv") {
                score += 60
            }

            // File size (parse GB/MB from title — larger files generally = better quality)
            if let gbMatch = lower.range(of: #"(\d+\.?\d*)\s*gb"#, options: .regularExpression) {
                let numStr = String(lower[gbMatch]).replacingOccurrences(of: "gb", with: "").trimmingCharacters(in: .whitespaces)
                if let gb = Double(numStr) {
                    score += min(Int(gb * 20), 100) // Cap at 100 bonus points for size
                }
            }

            // Prefer web-ready streams (not marked as notWebReady)
            if stream.behaviorHints?.notWebReady != true {
                score += 20
            }

            // Prefer streams with actual URLs over external URLs
            if stream.url != nil {
                score += 10
            }

            return (stream, score)
        }

        // Sort by score descending, return the best
        let best = scored.sorted { $0.score > $1.score }
        return best[0].stream
    }
}
