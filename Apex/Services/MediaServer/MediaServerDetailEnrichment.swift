//
//  MediaServerDetailEnrichment.swift
//  Apex
//
//  Lazy TMDB + OMDb enrichment for media-server library titles on detail screens.
//

import Foundation
import OSLog
import SwiftData

enum MediaServerDetailEnrichment {
    @MainActor
    static func enrichMovieIfNeeded(_ movie: Movie, context: ModelContext) async {
        let container = context.container
        let movieID = movie.persistentModelID

        // Resolve TMDB ID on main actor (needs model access), save deferred
        guard let tmdbId = await resolveMovieTMDBId(movie, context: context) else { return }

        if let enrichedAt = movie.tmdbEnrichedAt,
           Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
        {
            await enrichMovieRatingsIfNeeded(movie, context: context)
            return
        }

        // Fetch TMDB details off-main to avoid blocking UI
        let manager = ContentSyncManager(modelContainer: container)
        guard let details = try? await manager.fetchTMDBMovieDetails(tmdbId: tmdbId) else { return }

        // Apply details and save on background context to avoid main-thread stalls
        await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.persistentModelID == movieID })
            guard let bgMovie = try? bgContext.fetch(descriptor).first else {
                Logger.database.error("enrichMovieIfNeeded: could not re-fetch movie \(movieID.hashValue) on background context")
                return
            }
            applyMovieDetails(details, to: bgMovie, context: bgContext)
            do {
                try bgContext.save()
            } catch {
                Logger.database.error("enrichMovieIfNeeded background save failed: \(error.localizedDescription)")
            }
        }.value

        // Refresh main-context model so SwiftUI picks up changes
        context.processPendingChanges()
        await enrichMovieRatingsIfNeeded(movie, context: context)
    }

    @MainActor
    static func enrichSeriesIfNeeded(_ series: Series, context: ModelContext) async {
        let container = context.container
        let seriesID = series.persistentModelID

        guard let tmdbId = await resolveSeriesTMDBId(series, context: context) else { return }

        if let enrichedAt = series.tmdbEnrichedAt,
           Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
        {
            return
        }

        let manager = ContentSyncManager(modelContainer: container)
        guard let details = try? await manager.fetchTMDBTVDetails(tmdbId: tmdbId) else { return }

        await Task.detached(priority: .userInitiated) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            let descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.persistentModelID == seriesID })
            guard let bgSeries = try? bgContext.fetch(descriptor).first else {
                Logger.database.error("enrichSeriesIfNeeded: could not re-fetch series \(seriesID.hashValue) on background context")
                return
            }
            applySeriesDetails(details, to: bgSeries, context: bgContext)
            do {
                try bgContext.save()
            } catch {
                Logger.database.error("enrichSeriesIfNeeded background save failed: \(error.localizedDescription)")
            }
        }.value

        context.processPendingChanges()
    }

    @MainActor
    private static func resolveMovieTMDBId(_ movie: Movie, context: ModelContext) async -> Int? {
        if let tmdbId = movie.tmdbId { return tmdbId }
        guard TMDBClient.shared.isConfigured else { return nil }
        let query = ContentIndexText.searchQuery(for: movie.name)
        let year = ContentIndexText.year(fromReleaseDate: movie.releaseDate) ?? query.year
        let client = TMDBClient.shared
        if let id = try? await client.searchMovieID(query: query.title, year: year) {
            movie.tmdbId = id
            do {
                try context.save()
            } catch {
                Logger.database.error("resolveMovieTMDBId save failed: \(error.localizedDescription)")
            }
            return id
        }
        if year != nil, let id = try? await client.searchMovieID(query: query.title, year: nil) {
            movie.tmdbId = id
            do {
                try context.save()
            } catch {
                Logger.database.error("resolveMovieTMDBId fallback save failed: \(error.localizedDescription)")
            }
            return id
        }
        return nil
    }

    @MainActor
    private static func resolveSeriesTMDBId(_ series: Series, context: ModelContext) async -> Int? {
        if let tmdbId = series.tmdbId { return tmdbId }
        guard TMDBClient.shared.isConfigured else { return nil }
        let query = ContentIndexText.searchQuery(for: series.name)
        let year = ContentIndexText.year(fromReleaseDate: series.releaseDate) ?? query.year
        let client = TMDBClient.shared
        if let id = try? await client.searchTVID(query: query.title, year: year) {
            series.tmdbId = id
            do {
                try context.save()
            } catch {
                Logger.database.error("resolveSeriesTMDBId save failed: \(error.localizedDescription)")
            }
            return id
        }
        if year != nil, let id = try? await client.searchTVID(query: query.title, year: nil) {
            series.tmdbId = id
            do {
                try context.save()
            } catch {
                Logger.database.error("resolveSeriesTMDBId fallback save failed: \(error.localizedDescription)")
            }
            return id
        }
        return nil
    }
}