//
//  StremioStreamResolver.swift
//  Apex
//
//  Resolves Stremio placeholder URLs to actual playable stream URLs at
//  playback time. Queries ALL configured Stremio addons that support streams
//  (not just the owning addon), merges results, and auto-selects the best
//  quality. This mirrors how the Stremio desktop app works — catalog addons
//  (Cinemeta) provide browsing, stream addons (AIOStreams, Torrentio) provide
//  playback, and the player queries all of them.
//

import Foundation
import OSLog
import SwiftData

enum StremioStreamResolver {
    private static let client = StremioClient()

    /// Resolves a Stremio `PlayableMedia` by querying ALL configured stream
    /// addons for the content, merging results, and picking the best stream.
    static func resolve(_ media: PlayableMedia, container: ModelContainer? = nil) async throws -> PlayableMedia {
        let urlString = media.url.absoluteString
        guard urlString.hasPrefix("stremio://") else { throw StremioError.invalidURL }
        let placeholder = String(urlString.dropFirst("stremio://".count))
        guard let decoded = placeholder.removingPercentEncoding else { throw StremioError.invalidURL }

        let resolvedURL = try await resolveMultiAddon(placeholder: decoded, container: container)
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

    /// Fetches all available streams from all configured addons, scored and
    /// sorted by quality. Used by the stream picker UI to let the user choose.
    static func fetchAllOptions(for media: PlayableMedia, container: ModelContainer?) async throws -> [StremioStreamOption] {
        let urlString = media.url.absoluteString
        guard urlString.hasPrefix("stremio://") else { throw StremioError.invalidURL }
        let placeholder = String(urlString.dropFirst("stremio://".count))
        guard let decoded = placeholder.removingPercentEncoding else { throw StremioError.invalidURL }

        let parts = decoded.components(separatedBy: "|")
        guard parts.count == 3,
              let sourceBaseURL = URL(string: parts[0])
        else { throw StremioError.invalidURL }

        let type = parts[1]
        let id = parts[2]

        // Gather all addon URLs
        var addonURLs: [(url: URL, name: String?)] = [(sourceBaseURL, nil)]
        if let container {
            let additional = await fetchStreamAddonURLsWithNames(from: container, excluding: sourceBaseURL)
            addonURLs.append(contentsOf: additional)
        }

        // Query all concurrently
        var allOptions: [StremioStreamOption] = []

        await withTaskGroup(of: [(stream: StremioStream, addonName: String?)].self) { group in
            for addon in addonURLs {
                let addonURL = addon.url
                let addonName = addon.name ?? addonURL.host()
                group.addTask {
                    do {
                        let streams = try await client.fetchStreams(baseURL: addonURL, type: type, id: id)
                        return streams.map { ($0, addonName) }
                    } catch {
                        return []
                    }
                }
            }
            for await results in group {
                for result in results {
                    let score = scoreStream(result.stream)
                    let option = StremioStreamOption(stream: result.stream, addonName: result.addonName, score: score)
                    if option.url.absoluteString != "about:blank" {
                        allOptions.append(option)
                    }
                }
            }
        }

        // Sort by score descending (best first)
        allOptions.sort { $0.score > $1.score }
        return allOptions
    }

    /// Fetches addon URLs with their display names for the stream picker.
    @MainActor
    private static func fetchStreamAddonURLsWithNames(from container: ModelContainer, excluding sourceURL: URL) -> [(url: URL, name: String?)] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let stremioType = PlaylistSourceType.stremio.rawValue
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.sourceTypeRaw == stremioType }
        )
        let playlists = (try? context.fetch(descriptor)) ?? []

        var results: [(url: URL, name: String?)] = []
        for playlist in playlists {
            guard let normalized = StremioURL.normalize(playlist.serverURL) else { continue }
            guard normalized.absoluteString != sourceURL.absoluteString else { continue }
            results.append((normalized, playlist.name))
        }
        return results
    }

    /// Scores a single stream for ranking (used by both auto-select and picker).
    private static func scoreStream(_ stream: StremioStream) -> Int {
        var score = 0
        let text = (stream.title ?? "") + " " + (stream.name ?? "") + " " + (stream.description ?? "")
        let lower = text.lowercased()

        if lower.contains("2160p") || lower.contains("4k") || lower.contains("uhd") { score += 400 }
        else if lower.contains("1080p") || lower.contains("1080") { score += 300 }
        else if lower.contains("720p") || lower.contains("720") { score += 200 }
        else if lower.contains("480p") || lower.contains("sd") { score += 100 }

        if lower.contains("hevc") || lower.contains("h.265") || lower.contains("x265") || lower.contains("h265") { score += 50 }
        else if lower.contains("h.264") || lower.contains("x264") || lower.contains("h264") { score += 30 }

        if lower.contains("hdr") || lower.contains("dolby vision") || lower.contains("dv") { score += 60 }

        if let gbMatch = lower.range(of: #"(\d+\.?\d*)\s*gb"#, options: .regularExpression) {
            let numStr = String(lower[gbMatch]).replacingOccurrences(of: "gb", with: "").trimmingCharacters(in: .whitespaces)
            if let gb = Double(numStr) { score += min(Int(gb * 20), 100) }
        }

        if stream.behaviorHints?.notWebReady != true { score += 20 }
        if stream.url != nil { score += 10 }

        return score
    }

    /// Queries all configured Stremio stream addons for this content and picks
    /// the best stream across all of them.
    private static func resolveMultiAddon(placeholder: String, container: ModelContainer?) async throws -> URL {
        let parts = placeholder.components(separatedBy: "|")
        guard parts.count == 3,
              let sourceBaseURL = URL(string: parts[0])
        else { throw StremioError.invalidURL }

        let type = parts[1]
        let id = parts[2]

        // Gather all Stremio addon base URLs that support streams.
        // Always include the source addon (the one that owns this content).
        var addonURLs: [URL] = [sourceBaseURL]

        if let container {
            let additional = await fetchStreamAddonURLs(from: container, excluding: sourceBaseURL)
            addonURLs.append(contentsOf: additional)
        }

        Logger.player.info("Stremio resolving \(type)/\(id, privacy: .public) across \(addonURLs.count) addon(s)")

        // Query all addons concurrently for streams
        var allStreams: [StremioStream] = []

        await withTaskGroup(of: [StremioStream].self) { group in
            for addonURL in addonURLs {
                group.addTask {
                    do {
                        let streams = try await client.fetchStreams(baseURL: addonURL, type: type, id: id)
                        if !streams.isEmpty {
                            Logger.player.info("Stremio addon \(addonURL.host() ?? "unknown", privacy: .public) returned \(streams.count) streams")
                        }
                        return streams
                    } catch {
                        // Addon doesn't have streams for this content — normal
                        Logger.player.debug("Stremio addon \(addonURL.host() ?? "unknown", privacy: .public) — no streams: \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
            for await streams in group {
                allStreams.append(contentsOf: streams)
            }
        }

        guard !allStreams.isEmpty else { throw StremioError.noCompatibleStreams }

        // Auto-select the best stream across all addons
        let best = selectBestStream(from: allStreams)
        guard let url = best.bestURL else { throw StremioError.noCompatibleStreams }

        Logger.player.info("Stremio auto-selected: \"\(best.displayTitle, privacy: .public)\" from \(allStreams.count) total streams across \(addonURLs.count) addon(s)")
        return url
    }

    /// Fetches all Stremio playlist base URLs that support streams, excluding
    /// the source addon (already included by the caller).
    @MainActor
    private static func fetchStreamAddonURLs(from container: ModelContainer, excluding sourceURL: URL) -> [URL] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let stremioType = PlaylistSourceType.stremio.rawValue
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.sourceTypeRaw == stremioType }
        )
        let playlists = (try? context.fetch(descriptor)) ?? []

        var urls: [URL] = []
        for playlist in playlists {
            guard let normalized = StremioURL.normalize(playlist.serverURL) else { continue }
            // Don't duplicate the source addon
            guard normalized.absoluteString != sourceURL.absoluteString else { continue }
            urls.append(normalized)
        }
        return urls
    }

    // MARK: - Stream Quality Selection

    /// Ranks streams by quality and returns the best one.
    private static func selectBestStream(from streams: [StremioStream]) -> StremioStream {
        guard streams.count > 1 else { return streams[0] }
        let best = streams.max { scoreStream($0) < scoreStream($1) }
        return best ?? streams[0]
    }
}
