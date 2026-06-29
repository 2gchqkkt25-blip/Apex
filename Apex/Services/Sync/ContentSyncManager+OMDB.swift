import Foundation
import OSLog
import SwiftData

// MARK: - OMDb Ratings Enrichment

extension ContentSyncManager {
    /// Fetches aggregator ratings (IMDb / Rotten Tomatoes / Metacritic) for an
    /// IMDb id without persisting. The caller applies the data directly to its
    /// own context to avoid cross-context merge timing issues. Returns an empty
    /// array when OMDb is unconfigured or the title is unknown.
    func fetchOMDBRatings(imdbId: String) async throws -> [ExternalRating] {
        let client = OMDBClient.shared
        guard client.isConfigured else { return [] }
        return try await client.ratings(imdbId: imdbId)
    }

    /// Fetches and persists OMDb ratings for a movie **off the main thread**, on
    /// the engine actor's own background context (the save auto-merges into the
    /// main context). Keeps the rating write off a detail view's hot path.
    func enrichMovieRatings(movieId: String, imdbId: String) async {
        let ratings: [ExternalRating]
        do {
            let result = try await fetchOMDBRatings(imdbId: imdbId)
            guard !result.isEmpty else {
                Logger.network.info("[OMDBEnrich] No OMDb ratings found for movie \(movieId) (imdbId \(imdbId))")
                return
            }
            ratings = result
        } catch {
            Logger.network.error("[OMDBEnrich] Failed to fetch OMDb ratings for movie \(movieId) (imdbId \(imdbId)): \(error.localizedDescription)")
            return
        }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == movieId })
        descriptor.fetchLimit = 1
        guard let movie = try? context.fetch(descriptor).first else {
            Logger.network.warning("[OMDBEnrich] Movie \(movieId) not found in store for rating enrichment")
            return
        }
        movie.externalRatings = ratings
        movie.ratingsEnrichedAt = Date()
        do {
            try context.save()
            Logger.network.info("[OMDBEnrich] Enriched ratings for movie \(movieId) — \(ratings.count) sources")
        } catch {
            Logger.network.error("[OMDBEnrich] Failed to save ratings for movie \(movieId): \(error.localizedDescription)")
        }
    }

    /// Series counterpart of ``enrichMovieRatings(movieId:imdbId:)``.
    func enrichSeriesRatings(seriesId: String, imdbId: String) async {
        let ratings: [ExternalRating]
        do {
            let result = try await fetchOMDBRatings(imdbId: imdbId)
            guard !result.isEmpty else {
                Logger.network.info("[OMDBEnrich] No OMDb ratings found for series \(seriesId) (imdbId \(imdbId))")
                return
            }
            ratings = result
        } catch {
            Logger.network.error("[OMDBEnrich] Failed to fetch OMDb ratings for series \(seriesId) (imdbId \(imdbId)): \(error.localizedDescription)")
            return
        }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesId })
        descriptor.fetchLimit = 1
        guard let series = try? context.fetch(descriptor).first else {
            Logger.network.warning("[OMDBEnrich] Series \(seriesId) not found in store for rating enrichment")
            return
        }
        series.externalRatings = ratings
        series.ratingsEnrichedAt = Date()
        do {
            try context.save()
            Logger.network.info("[OMDBEnrich] Enriched ratings for series \(seriesId) — \(ratings.count) sources")
        } catch {
            Logger.network.error("[OMDBEnrich] Failed to save ratings for series \(seriesId): \(error.localizedDescription)")
        }
    }
}

// MARK: - Detail-screen enrichment

/// 14 days — ratings rarely move, so revisits within the window skip the fetch.
private let ratingsCacheWindow: TimeInterval = 14 * 24 * 3600

/// Fetches OMDb ratings for a movie and persists them, once its IMDb id is
/// known (resolved by TMDB enrichment). No-ops when OMDb is unconfigured, the
/// IMDb id is missing, or the cache is still fresh. Call from a detail view's
/// `.task` after TMDB enrichment.
@MainActor
func enrichMovieRatingsIfNeeded(_ movie: Movie, context: ModelContext) async {
    guard let imdbId = movie.imdbId, !imdbId.isEmpty else {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for movie \(movie.id): no imdbId")
        return
    }
    guard OMDBClient.shared.isConfigured else {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for movie \(movie.id): OMDb not configured")
        return
    }
    if let enrichedAt = movie.ratingsEnrichedAt, Date().timeIntervalSince(enrichedAt) < ratingsCacheWindow {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for movie \(movie.id): cache fresh from \(enrichedAt)")
        return
    }
    // Fetch off-thread, then apply on the view's own context. Background-context
    // saves auto-merge on iOS but tvOS detail screens often miss the update until
    // navigating away — same class of bug as TMDB enrichment on tvOS.
    let manager = ContentSyncManager(modelContainer: context.container)
    let ratings: [ExternalRating]
    do {
        ratings = try await manager.fetchOMDBRatings(imdbId: imdbId)
        guard !ratings.isEmpty else {
            Logger.network.info("[OMDBEnrich] No OMDb ratings found for movie \(movie.id) (imdbId \(imdbId))")
            return
        }
    } catch {
        Logger.network.error("[OMDBEnrich] Failed to fetch OMDb ratings for movie \(movie.id) (imdbId \(imdbId)): \(error.localizedDescription)")
        return
    }
    movie.externalRatings = ratings
    movie.ratingsEnrichedAt = Date()
    try? context.save()
    Logger.network.info("[OMDBEnrich] Enriched ratings for movie \(movie.id) — \(ratings.count) sources")
}

/// Series counterpart of ``enrichMovieRatingsIfNeeded(_:context:)``.
@MainActor
func enrichSeriesRatingsIfNeeded(_ series: Series, context: ModelContext) async {
    guard let imdbId = series.imdbId, !imdbId.isEmpty else {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for series \(series.id): no imdbId")
        return
    }
    guard OMDBClient.shared.isConfigured else {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for series \(series.id): OMDb not configured")
        return
    }
    if let enrichedAt = series.ratingsEnrichedAt, Date().timeIntervalSince(enrichedAt) < ratingsCacheWindow {
        Logger.network.debug("[OMDBEnrich] Skipping ratings enrichment for series \(series.id): cache fresh from \(enrichedAt)")
        return
    }
    let manager = ContentSyncManager(modelContainer: context.container)
    let ratings: [ExternalRating]
    do {
        ratings = try await manager.fetchOMDBRatings(imdbId: imdbId)
        guard !ratings.isEmpty else {
            Logger.network.info("[OMDBEnrich] No OMDb ratings found for series \(series.id) (imdbId \(imdbId))")
            return
        }
    } catch {
        Logger.network.error("[OMDBEnrich] Failed to fetch OMDb ratings for series \(series.id) (imdbId \(imdbId)): \(error.localizedDescription)")
        return
    }
    series.externalRatings = ratings
    series.ratingsEnrichedAt = Date()
    try? context.save()
    Logger.network.info("[OMDBEnrich] Enriched ratings for series \(series.id) — \(ratings.count) sources")
}
