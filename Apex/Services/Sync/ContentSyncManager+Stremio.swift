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

        // Stream-only addons (Torrentio, etc.) have no catalogs — sync is instant.
        guard manifest.hasCatalogs, !manifest.catalogs.isEmpty else {
            Logger.database.info("Stremio addon '\(manifest.name, privacy: .public)' has no catalogs — stream-only addon, sync complete")
            return
        }

        var seenMovieIDs = Set<String>()
        var seenSeriesIDs = Set<String>()
        var seenChannelIDs = Set<String>()

        for catalog in manifest.catalogs {
            guard !Task.isCancelled else { break }
            let ct = catalog.type

            let all: [StremioMetaPreview]
            do {
                all = try await client.fetchAllCatalog(baseURL: base, type: ct, catalogId: catalog.id)
            } catch {
                Logger.database.warning("Stremio catalog '\(catalog.name, privacy: .public)' (\(ct, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }

            guard !all.isEmpty else { continue }
            Logger.database.info("Stremio catalog '\(catalog.name, privacy: .public)' returned \(all.count) items")

            let batchCtx = ModelContext(modelContainer)
            switch ct {
            case "movie":
                seenMovieIDs.formUnion(importStremioMovies(all, playlist: playlist, baseURL: base, context: batchCtx))
            case "series":
                seenSeriesIDs.formUnion(importStremioSeries(all, playlist: playlist, baseURL: base, context: batchCtx))
            case "channel", "tv":
                seenChannelIDs.formUnion(importStremioChannels(all, playlist: playlist, baseURL: base, context: batchCtx))
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
            stream.num = index

            if existing == nil {
                context.insert(stream)
            }
        }
        return seen
    }
}
