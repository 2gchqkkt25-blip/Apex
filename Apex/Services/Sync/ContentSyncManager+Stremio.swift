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

        for catalog in catalogs {
            guard !Task.isCancelled else { break }
            let ct = catalog.type

            let all: [StremioMetaPreview]
            do {
                all = try await client.fetchAllCatalog(baseURL: catalogBase, type: ct, catalogId: catalog.id)
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

        pruneStaleMovies(playlistId: playlistId, seenIds: seenMovieIDs)
        pruneStaleSeries(playlistId: playlistId, seenIds: seenSeriesIDs)
        pruneStaleLiveStreams(playlistId: playlistId, seenIds: seenChannelIDs)
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
}
