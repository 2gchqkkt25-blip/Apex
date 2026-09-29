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

        // Resolve TMDB ID on main actor (needs model access), save deferred
        guard let tmdbId = await resolveMovieTMDBId(movie, context: context) else { return }

        if hasFreshTMDBDetails(enrichedAt: movie.tmdbEnrichedAt, backdropPath: movie.backdropPath, logoPath: movie.logoPath, tagline: movie.tagline, castCount: movie.castMembers.count) {
            await enrichMovieRatingsIfNeeded(movie, context: context)
            return
        }

        // Fetch off the main actor, then apply on the view's own model. A background
        // save does not update the title already on screen, so artwork and cast
        // stay blank until the screen is opened again.
        let manager = ContentSyncManager(modelContainer: container)
        guard let details = try? await manager.fetchTMDBMovieDetails(tmdbId: tmdbId) else { return }
        applyMovieDetails(details, to: movie, context: context)
        do {
            try context.save()
        } catch {
            Logger.database.error("enrichMovieIfNeeded save failed: \(error.localizedDescription)")
        }
        await enrichMovieRatingsIfNeeded(movie, context: context)
    }

    @MainActor
    static func enrichSeriesIfNeeded(_ series: Series, context: ModelContext) async {
        let container = context.container

        guard let tmdbId = await resolveSeriesTMDBId(series, context: context) else { return }

        if hasFreshTMDBDetails(enrichedAt: series.tmdbEnrichedAt, backdropPath: series.backdropPath, logoPath: series.logoPath, tagline: series.tagline, castCount: series.castMembers.count) {
            await enrichSeriesRatingsIfNeeded(series, context: context)
            return
        }

        let manager = ContentSyncManager(modelContainer: container)
        guard let details = try? await manager.fetchTMDBTVDetails(tmdbId: tmdbId) else { return }
        applySeriesDetails(details, to: series, context: context)
        do {
            try context.save()
        } catch {
            Logger.database.error("enrichSeriesIfNeeded save failed: \(error.localizedDescription)")
        }
        await enrichSeriesRatingsIfNeeded(series, context: context)
    }

    /// A recent stamp alone is not enough. Jellyfin sync used to set
    /// `tmdbEnrichedAt` when it stored the id, before any artwork or cast
    /// was fetched, and the detail screen then skipped TMDB entirely.
    private static func hasFreshTMDBDetails(
        enrichedAt: Date?,
        backdropPath: String?,
        logoPath: String?,
        tagline: String?,
        castCount: Int
    ) -> Bool {
        guard let enrichedAt, Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600 else { return false }
        let hasTagline = !(tagline ?? "").isEmpty
        return backdropPath != nil || logoPath != nil || hasTagline || castCount > 0
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