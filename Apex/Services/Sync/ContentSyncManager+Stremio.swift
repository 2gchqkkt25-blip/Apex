//
//  ContentSyncManager+Stremio.swift
//  Apex
//
//  Stremio addon sync pipeline.  Fetches a manifest, walks every catalog,
//  and upserts movies / series / channels into the SwiftData store.
//

import Foundation
import OSLog
import SwiftData

extension ContentSyncManager {

    // MARK: - Entry point

    /// The official Stremio catalog addon — provides movie/series browsing.
    /// Used automatically when a stream-only addon (AIOStreams, Torrentio) is
    /// added, so the user has content to browse + play via their stream addon.
    private static let cinemetaBaseURL = URL(string: "https://v3-cinemeta.strem.io")!

    func performStremioSync(playlist: Playlist, playlistId: UUID, progress: SyncProgress?) async throws {
        let client = StremioClient()
        guard let base = StremioURL.normalize(playlist.serverURL) else {
            throw StremioError.invalidURL
        }

        // Step 1: Fetch manifest (shown as "Downloading playlist")
        await progress?.start(.playlistDownload)
        let ctx = ModelContext(modelContainer)
        let manifest: StremioManifest
        do {
            manifest = try await client.fetchManifest(baseURL: base)
        } catch {
            Logger.database.error("Stremio manifest fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        playlist.name = manifest.name
        try ctx.save()
        await progress?.update(detail: manifest.name, fraction: 1)
        await progress?.complete(.playlistDownload)

        // Determine catalog source: use the addon's own catalogs if it has them,
        // otherwise use Cinemeta (the standard Stremio catalog) so stream-only
        // addons (AIOStreams, Torrentio) still have browsable content.
        let catalogBase: URL
        let catalogs: [StremioCatalogDef]

        if manifest.hasCatalogs, !manifest.catalogs.isEmpty {
            // Addon has its own catalog — use it directly
            catalogBase = base
            catalogs = manifest.catalogs
            Logger.database.info("Stremio addon '\(manifest.name, privacy: .public)' has \(manifest.catalogs.count) catalogs")
        } else {
            // Stream-only addon — fetch Cinemeta catalog for browsing
            Logger.database.info("Stremio addon '\(manifest.name, privacy: .public)' is stream-only — using Cinemeta catalog for browsing")
            do {
                let cinemetaManifest = try await client.fetchManifest(baseURL: Self.cinemetaBaseURL)
                catalogBase = Self.cinemetaBaseURL
                catalogs = cinemetaManifest.catalogs
            } catch {
                Logger.database.warning("Stremio Cinemeta fetch failed: \(error.localizedDescription, privacy: .public) — no catalog available")
                return
            }
        }

        var seenMovieIDs = Set<String>()
        var seenSeriesIDs = Set<String>()
        var seenChannelIDs = Set<String>()

        // Step 2: Import catalogs (shown as "Importing content")
        await progress?.start(.playlistImport)
        let totalCatalogs = catalogs.count

        for (catalogIndex, catalog) in catalogs.enumerated() {
            guard !Task.isCancelled else { break }
            let ct = catalog.type
            let fraction = Double(catalogIndex) / Double(max(totalCatalogs, 1))
            await progress?.update(detail: catalog.name, fraction: fraction)

            let all: [StremioMetaPreview]
            do {
                // Cap at 100 items per catalog — one page. Large catalogs
                // (Netflix 2000+, HBO 2000+) take minutes to paginate fully.
                // 100 popular titles per category is enough for browse; the user
                // can search for anything else. Matches what Stremio's home shows.
                all = try await client.fetchAllCatalog(baseURL: catalogBase, type: ct, catalogId: catalog.id, maxItems: 100)
            } catch {
                Logger.database.warning("Stremio catalog '\(catalog.name, privacy: .public)' (\(ct, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }

            guard !all.isEmpty else { continue }
            Logger.database.info("Stremio catalog '\(catalog.name, privacy: .public)' returned \(all.count) items")

            // Ensure a Category exists for this catalog so Movies/Series tabs
            // can find and display the content.
            let categoryTypeRaw: String
            switch ct {
            case "movie": categoryTypeRaw = "vod"
            case "series": categoryTypeRaw = "series"
            case "channel", "tv": categoryTypeRaw = "live"
            default: categoryTypeRaw = ct
            }
            let categoryApiId = catalog.id
            let categoryId = "\(playlist.id.uuidString)-\(categoryTypeRaw)-\(categoryApiId)"
            let catCtx = ModelContext(modelContainer)
            catCtx.autosaveEnabled = false
            let existingCat = try? catCtx.fetch(
                FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryId })
            ).first
            if existingCat == nil {
                let category = Category(
                    apiId: categoryApiId,
                    name: catalog.name,
                    parentId: 0,
                    typeRaw: categoryTypeRaw,
                    playlist: nil
                )
                category.id = categoryId
                catCtx.insert(category)
                try? catCtx.save()
                Logger.database.info("Stremio created category '\(catalog.name, privacy: .public)' (type: \(categoryTypeRaw, privacy: .public))")
            }

            let batchCtx = ModelContext(modelContainer)
            switch ct {
            case "movie":
                seenMovieIDs.formUnion(importStremioMovies(all, playlist: playlist, baseURL: base, categoryId: categoryId, context: batchCtx))
            case "series":
                seenSeriesIDs.formUnion(importStremioSeries(all, playlist: playlist, baseURL: base, categoryId: categoryId, context: batchCtx))
            case "channel", "tv":
                seenChannelIDs.formUnion(importStremioChannels(all, playlist: playlist, baseURL: base, categoryId: categoryId, context: batchCtx))
            default:
                continue
            }
            try batchCtx.save()
        }

        await progress?.update(detail: "Cleaning up", fraction: 1)
        pruneStaleMovies(playlistId: playlistId, seenIds: seenMovieIDs)
        pruneStaleSeries(playlistId: playlistId, seenIds: seenSeriesIDs)
        pruneStaleLiveStreams(playlistId: playlistId, seenIds: seenChannelIDs)
        await progress?.complete(.playlistImport)
    }

    // MARK: - Import helpers

    private func importStremioMovies(
        _ metas: [StremioMetaPreview],
        playlist: Playlist,
        baseURL: URL,
        categoryId: String,
        context: ModelContext
    ) -> Set<String> {
        var seen = Set<String>()
        let prefix = playlist.id.uuidString
        for meta in metas {
            let stremioID = "\(baseURL.absoluteString)|\(meta.type)|\(meta.id)"
            let movieID = "\(prefix)-movie-\(stremioID.hash)"
            seen.insert(movieID)

            let existing = try? context.fetch(
                FetchDescriptor<Movie>(predicate: #Predicate { $0.id == movieID })
            ).first

            let movie = existing ?? Movie(id: movieID, streamId: movieID.hashValue & 0x7FFF_FFFF, name: meta.name)
            movie.name = meta.name
            movie.streamIcon = meta.poster
            movie.plot = meta.description
            movie.releaseDate = meta.releaseInfo
            movie.rating = Double(meta.imdbRating ?? "0") ?? 0
            movie.genre = meta.genres?.joined(separator: ", ")
            movie.directURL = stremioID
            movie.categoryId = categoryId
            movie.num = 0

            if existing == nil {
                context.insert(movie)
            }
        }
        return seen
    }

    private func importStremioSeries(
        _ metas: [StremioMetaPreview],
        playlist: Playlist,
        baseURL: URL,
        categoryId: String,
        context: ModelContext
    ) -> Set<String> {
        var seen = Set<String>()
        let prefix = playlist.id.uuidString
        for meta in metas {
            let stremioID = "\(baseURL.absoluteString)|\(meta.type)|\(meta.id)"
            let seriesID = "\(prefix)-series-\(stremioID.hash)"
            seen.insert(seriesID)

            let existing = try? context.fetch(
                FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesID })
            ).first

            let series = existing ?? Series(id: seriesID, seriesId: stremioID.hashValue & 0x7FFF_FFFF, name: meta.name, num: 0)
            series.name = meta.name
            series.cover = meta.poster
            series.plot = meta.description
            series.releaseDate = meta.releaseInfo
            series.rating = meta.imdbRating
            series.genre = meta.genres?.joined(separator: ", ")
            series.categoryId = categoryId
            series.num = 0
            // Store the original Stremio meta ID (usually IMDB like "tt1234567")
            // so fetchStremioEpisodes can use it immediately without waiting for
            // TMDB enrichment.
            if meta.id.hasPrefix("tt") {
                series.imdbId = meta.id
            } else if meta.id.hasPrefix("tmdb:"), let tmdbNum = Int(meta.id.dropFirst(5)) {
                series.tmdbId = tmdbNum
            }

            if existing == nil {
                context.insert(series)
            }
        }
        return seen
    }

    private func importStremioChannels(
        _ metas: [StremioMetaPreview],
        playlist: Playlist,
        baseURL: URL,
        categoryId: String,
        context: ModelContext
    ) -> Set<String> {
        var seen = Set<String>()
        let prefix = playlist.id.uuidString
        for (index, meta) in metas.enumerated() {
            let stremioID = "\(baseURL.absoluteString)|\(meta.type)|\(meta.id)"
            let streamID = "\(prefix)-live-\(stremioID.hash)"
            seen.insert(streamID)

            let existing = try? context.fetch(
                FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == streamID })
            ).first

            let stream = existing ?? LiveStream(
                id: streamID,
                streamId: stremioID.hashValue & 0x7FFF_FFFF,
                name: meta.name,
                epgChannelId: meta.id,
                tvArchive: 0,
                tvArchiveDuration: 0,
                num: index
            )
            stream.name = meta.name
            stream.streamIcon = meta.poster
            stream.directURL = stremioID
            stream.epgChannelId = meta.id
            stream.categoryId = categoryId
            stream.num = index

            if existing == nil {
                context.insert(stream)
            }
        }
        return seen
    }

    // MARK: - Episode fetch (lazy, on detail screen open)

    /// Fetches episodes for a Stremio series from the addon's /meta endpoint.
    /// Returns ParsedEpisode values that the caller inserts into SwiftData.
    func fetchStremioEpisodes(seriesElementId: String, playlist: Playlist) async throws -> [ParsedEpisode] {
        let client = StremioClient()
        guard let base = StremioURL.normalize(playlist.serverURL) else { return [] }

        // The series stores the stremio ID in its id field as "{playlistUUID}-series-{hash}".
        // We need the original Stremio content ID. It was stored in the series during import
        // — we need to recover it. The series' `directURL` equivalent isn't stored, but we
        // can fetch from Cinemeta using the series name or TMDB ID if available.
        // Actually, let's look at what we have: the seriesId field is set to stremioID.hashValue.
        // We need the original meta id (like "tt1234567") to fetch from Cinemeta/addon.

        // Recover the stremio meta ID from the series. During import, the series object
        // doesn't store the raw Stremio ID directly. Let's check if we can get it from
        // the catalog metadata. The simplest approach: fetch meta from Cinemeta using
        // the series' tmdbId or imdb-style ID.

        // For Cinemeta, the meta endpoint accepts IMDB IDs directly.
        // The series was imported from Cinemeta catalog which uses IMDB IDs as the meta.id.
        // Let's try to recover the ID from the series model.
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let series = try? context.fetch(
            FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesElementId })
        ).first else { return [] }

        // Try to find the original Stremio meta ID. During Stremio import, the catalog
        // returns items with `id` being the IMDB ID (e.g. "tt1234567"). We need that.
        // The series' tmdbId might help, but Cinemeta uses IMDB IDs.
        // Let's check if the series has an imdbId set.
        let metaId: String
        if let imdbId = series.imdbId, !imdbId.isEmpty {
            metaId = imdbId
        } else if let tmdbId = series.tmdbId {
            metaId = "tmdb:\(tmdbId)"
        } else {
            // Fall back: try the series name as a search — but Stremio doesn't support search on meta.
            // Without a known ID, we can't fetch episodes.
            Logger.database.warning("Stremio series '\(series.name, privacy: .public)' has no IMDB/TMDB ID — cannot fetch episodes")
            return []
        }

        // Fetch from the addon's base URL first, then Cinemeta as fallback
        let metaURLs: [URL] = [base, Self.cinemetaBaseURL]
        var meta: StremioMeta?
        for metaBase in metaURLs {
            if let fetched = try? await client.fetchMeta(baseURL: metaBase, type: "series", id: metaId) {
                if fetched.videos != nil, !(fetched.videos?.isEmpty ?? true) {
                    meta = fetched
                    break
                }
            }
        }

        guard let videos = meta?.videos, !videos.isEmpty else {
            Logger.database.warning("Stremio series '\(series.name, privacy: .public)' returned no episodes from meta")
            return []
        }

        // Convert StremioVideos to ParsedEpisodes
        let playlistPrefix = playlist.id.uuidString
        var episodes: [ParsedEpisode] = []
        for video in videos {
            let season = video.season ?? 1
            let episode = video.episode ?? (episodes.count + 1)
            let episodeId = "\(playlistPrefix)-ep-\(video.id.hash)"
            // The stream resolution ID: for Stremio, streams are fetched via
            // /stream/series/{videoId}.json where videoId is the video's id field
            let stremioStreamId = "stremio://\(base.absoluteString)|\("series")|\(video.id)"

            episodes.append(ParsedEpisode(
                id: episodeId,
                episodeId: video.id,
                title: video.title ?? "Episode \(episode)",
                containerExtension: "mp4",
                seasonNum: season,
                episodeNum: episode,
                added: nil,
                directSource: stremioStreamId,
                durationSecs: nil,
                movieImage: video.thumbnail,
                rating: nil,
                airDate: video.released,
                plot: video.overview
            ))
        }

        Logger.database.info("Stremio fetched \(episodes.count) episodes for '\(series.name, privacy: .public)'")
        return episodes
    }
}
