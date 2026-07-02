import Foundation
import OSLog
import SwiftData

/// Resolves the IntroDB lookup key — the *series'* IMDb id plus the season and
/// episode numbers — for the content currently playing.
///
/// IntroDB only indexes episodic TV (its segments endpoint requires a season
/// and episode), so movies and live streams resolve to `nil` and simply get no
/// skip affordance. Cross-platform: the host (`FullScreenPlayerView`) owns the
/// lookup and the async fetch, handing the result down to whichever engine is
/// active — mirroring `NextEpisodeResolver`.
///
/// When the series has a `tmdbId` but no cached `imdbId` (the common case for
/// episodes played directly from a category without first opening the series
/// detail screen), the resolver fetches the IMDb ID from TMDB's lightweight
/// external-ids endpoint and persists it so the next playback already has it.
enum IntroSkipResolver {
    struct Lookup: Equatable {
        let imdbId: String
        let season: Int
        let episode: Int
    }

    /// The IntroDB lookup key for `ref`, or `nil` when it is not an episode, the
    /// episode / series can't be resolved, or no IMDb id can be found (even after
    /// attempting a TMDB external-ids fetch).
    ///
    /// SwiftData access runs on the calling actor (must be the main actor).
    /// The TMDB fallback fetch runs on a background task and is skipped entirely
    /// when the series already has a cached `imdbId`.
    static func lookup(for ref: PlayableMedia.ContentRef, in context: ModelContext) async -> Lookup? {
        guard case let .episode(id) = ref else { return nil }

        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let episode = try? context.fetch(descriptor).first else {
            Logger.player.info("[SkipIntro] Episode not found in store")
            return nil
        }

        let season = episode.seasonNum
        let episodeNum = effectiveEpisodeNumber(for: episode)
        guard episodeNum > 0 else {
            Logger.player.info("[SkipIntro] Invalid episode number for \(id, privacy: .public)")
            return nil
        }

        guard let series = EpisodeSeriesResolver.series(for: episode, in: context) else {
            Logger.player.info("[SkipIntro] Could not resolve series for episode \(id, privacy: .public)")
            return nil
        }

        // Fast path: the series already has a cached IMDb ID from a prior
        // enrichment or a previous lookup.
        if let cached = series.imdbId?.trimmingCharacters(in: .whitespaces), !cached.isEmpty {
            let imdbId = IntroDBClient.normalizedIMDbID(cached)
            guard !imdbId.isEmpty else { return nil }
            return Lookup(imdbId: imdbId, season: season, episode: episodeNum)
        }

        guard TMDBClient.shared.isConfigured else {
            Logger.player.info("[SkipIntro] TMDB not configured — cannot resolve IMDb ID")
            return nil
        }

        // Resolve TMDB id when missing (common before the background indexer runs).
        var tmdbId = series.tmdbId
        if tmdbId == nil {
            tmdbId = await resolveTMDBId(for: series, in: context)
        }

        guard let tmdbId else {
            Logger.player.info("[SkipIntro] No TMDB match for series '\(series.name, privacy: .public)'")
            return nil
        }

        guard let resolved = await resolveAndPersistIMDbID(tmdbId: tmdbId, seriesID: series.id, in: context) else {
            return nil
        }
        return Lookup(imdbId: resolved, season: season, episode: episodeNum)
    }

    /// Providers sometimes leave `episodeNum` at 0; fall back to the stream id.
    private static func effectiveEpisodeNumber(for episode: Episode) -> Int {
        if episode.episodeNum > 0 { return episode.episodeNum }
        if let parsed = Int(episode.episodeId.filter(\.isNumber)), parsed > 0 { return parsed }
        return episode.episodeNum
    }

    /// Searches TMDB by cleaned series title when the provider did not supply a
    /// TMDB id and the background indexer has not run yet.
    private static func resolveTMDBId(for series: Series, in context: ModelContext) async -> Int? {
        let query = ContentIndexText.searchQuery(for: series.name)
        let year = ContentIndexText.year(fromReleaseDate: series.releaseDate) ?? query.year
        let client = TMDBClient.shared
        do {
            if let id = try await client.searchTVID(query: query.title, year: year) {
                series.tmdbId = id
                try? context.save()
                Logger.player.info("[SkipIntro] TMDB search matched '\(series.name, privacy: .public)' → \(id)")
                return id
            }
            if year != nil, let id = try await client.searchTVID(query: query.title, year: nil) {
                series.tmdbId = id
                try? context.save()
                Logger.player.info("[SkipIntro] TMDB search matched '\(series.name, privacy: .public)' → \(id) (year dropped)")
                return id
            }
        } catch {
            Logger.player.warning("[SkipIntro] TMDB search failed for '\(series.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    // MARK: - TMDB fallback

    /// Fetches the IMDb ID for `tmdbId` from TMDB's `/tv/{id}/external_ids`,
    /// persists it on `Series.imdbId`, and returns it.  Logs a warning when the
    /// fetch fails so the skip-intro feature fails loudly enough to debug.
    private static func resolveAndPersistIMDbID(
        tmdbId: Int, seriesID: String, in context: ModelContext
    ) async -> String? {
        do {
            guard let imdbId = try await TMDBClient.shared.tvExternalIMDbID(tmdbId) else {
                Logger.player.info("[SkipIntro] TMDB has no IMDb ID for tmdb=\(tmdbId)")
                return nil
            }
            // Persist on the calling context so the next episode from the same
            // series hits the fast path.
            var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesID })
            descriptor.fetchLimit = 1
            if let series = try? context.fetch(descriptor).first {
                series.imdbId = imdbId
                try? context.save()
            }
            Logger.player.info("[SkipIntro] Resolved IMDb ID \(imdbId) from TMDB for tmdb=\(tmdbId)")
            return IntroDBClient.normalizedIMDbID(imdbId)
        } catch {
            Logger.player.warning("[SkipIntro] TMDB external-ids fetch failed for tmdb=\(tmdbId): \(error.localizedDescription)")
            return nil
        }
    }
}
