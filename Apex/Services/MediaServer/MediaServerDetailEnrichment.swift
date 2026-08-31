//
//  MediaServerDetailEnrichment.swift
//  Apex
//
//  Lazy TMDB + OMDb enrichment for media-server library titles on detail screens.
//

import Foundation
import SwiftData

enum MediaServerDetailEnrichment {
    @MainActor
    static func enrichMovieIfNeeded(_ movie: Movie, context: ModelContext) async {
        guard let tmdbId = await resolveMovieTMDBId(movie, context: context) else { return }
        if let enrichedAt = movie.tmdbEnrichedAt,
           Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
        {
            await enrichMovieRatingsIfNeeded(movie, context: context)
            return
        }
        let manager = ContentSyncManager(modelContainer: context.container)
        guard let details = try? await manager.fetchTMDBMovieDetails(tmdbId: tmdbId) else { return }
        applyMovieDetails(details, to: movie, context: context)
        try? context.save()
        await enrichMovieRatingsIfNeeded(movie, context: context)
    }

    @MainActor
    static func enrichSeriesIfNeeded(_ series: Series, context: ModelContext) async {
        guard let tmdbId = await resolveSeriesTMDBId(series, context: context) else { return }
        if let enrichedAt = series.tmdbEnrichedAt,
           Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
        {
            return
        }
        let manager = ContentSyncManager(modelContainer: context.container)
        guard let details = try? await manager.fetchTMDBTVDetails(tmdbId: tmdbId) else { return }
        applySeriesDetails(details, to: series, context: context)
        try? context.save()
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
            try? context.save()
            return id
        }
        if year != nil, let id = try? await client.searchMovieID(query: query.title, year: nil) {
            movie.tmdbId = id
            try? context.save()
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
            try? context.save()
            return id
        }
        if year != nil, let id = try? await client.searchTVID(query: query.title, year: nil) {
            series.tmdbId = id
            try? context.save()
            return id
        }
        return nil
    }
}
