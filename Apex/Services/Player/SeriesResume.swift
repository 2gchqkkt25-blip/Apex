import Foundation
import SwiftData

/// Picks the episode Play / Resume / Top Shelf should start.
///
/// Prefer the episode the user actually left (latest `lastWatchedDate`). Falling
/// back to "highest season/episode number" skips a rewatch and, when progress
/// was wiped, lands on S1E1.
enum SeriesResume {
    static func episode(in series: Series) -> Episode? {
        episode(in: series.episodes)
    }

    static func episode(in episodes: [Episode]) -> Episode? {
        guard !episodes.isEmpty else { return nil }

        let ordered = episodes
            .filter(\.isProviderEpisode)
            .sorted {
                ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum)
            }

        if let recent = ordered
            .filter({ $0.lastWatchedDate != nil && ($0.watchProgress > 1 || $0.isWatched) })
            .max(by: { ($0.lastWatchedDate ?? .distantPast) < ($1.lastWatchedDate ?? .distantPast) })
        {
            if !recent.isWatched, recent.watchProgress > 1 { return recent }
            if let index = ordered.firstIndex(where: { $0.id == recent.id }),
               index + 1 < ordered.count
            {
                return ordered[index + 1]
            }
            return recent
        }

        if let inProgress = ordered
            .filter({ $0.watchProgress > 1 && !$0.isWatched })
            .max(by: { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) })
        {
            return inProgress
        }

        if let watched = ordered.filter(\.isWatched)
            .max(by: { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) }),
           let index = ordered.firstIndex(where: { $0.id == watched.id })
        {
            return index + 1 < ordered.count ? ordered[index + 1] : ordered.first
        }

        return ordered.first
    }

    /// Relinks episodes that exist in the store but are missing from the
    /// relationship (empty `series.episodes` after a sync/fault). Returns true
    /// when at least one row was attached.
    @discardableResult
    static func attachStoredEpisodes(to series: Series, in context: ModelContext) -> Bool {
        guard series.episodes.isEmpty else { return false }
        let seriesId = series.id
        let found = ((try? context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate<Episode> { $0.id.localizedStandardContains(seriesId) }
        ))) ?? []).filter { $0.id.hasPrefix(seriesId) }
        guard !found.isEmpty else { return false }
        for episode in found where episode.series?.id != series.id {
            episode.series = series
        }
        series.episodes.append(contentsOf: found.filter { ep in
            !series.episodes.contains(where: { $0.id == ep.id })
        })
        try? context.save()
        return true
    }
}

/// Fills in episodes the provider has not streamed yet, using TMDB's season
/// list. Those rows stay in the season so upcoming episodes are visible, and
/// `Episode.isProviderEpisode` keeps them from being played.
enum SeriesEpisodeCatalog {
    @MainActor
    static func mergeGuideEpisodes(into series: Series, context: ModelContext) async {
        guard TMDBClient.shared.isConfigured else { return }
        let tmdbId = series.tmdbId ?? Int(series.tmdb ?? "")
        guard let tmdbId else { return }

        let seasons = (try? await TMDBClient.shared.tvSeasonNumbers(tmdbId)) ?? []
        guard !seasons.isEmpty else { return }

        let known = Set(series.episodes.map { "\($0.seasonNum)-\($0.episodeNum)" })
        var missing: [TMDBSeasonEpisode] = []
        await withTaskGroup(of: [TMDBSeasonEpisode].self) { group in
            for season in seasons {
                group.addTask {
                    (try? await TMDBClient.shared.tvSeasonEpisodes(tmdbId, season: season)) ?? []
                }
            }
            for await episodes in group {
                for episode in episodes where episode.episodeNumber > 0 && !known.contains("\(episode.seasonNumber)-\(episode.episodeNumber)") {
                    missing.append(episode)
                }
            }
        }
        let fallbackArtwork = seriesArtwork(series)
        for episode in missing {
            let rowID = "\(series.id)-tmdb-\(episode.seasonNumber)-\(episode.episodeNumber)"
            guard !series.episodes.contains(where: { $0.id == rowID }) else { continue }
            let row = Episode(
                id: rowID,
                episodeId: "tmdb-\(episode.seasonNumber)-\(episode.episodeNumber)",
                title: episode.name,
                containerExtension: "",
                seasonNum: episode.seasonNumber,
                episodeNum: episode.episodeNumber,
                series: series
            )
            row.plot = episode.overview
            row.airDate = episode.airDate
            row.durationSecs = episode.runtimeMinutes.map { $0 * 60 }
            row.movieImage = episode.stillURL ?? fallbackArtwork
            row.rating = episode.rating
            context.insert(row)
            series.episodes.append(row)
        }
        // Episodes already saved before artwork fallback have a blank still.
        // TMDB often has no episode image until it airs; the series backdrop
        // or poster fills that box.
        if let fallbackArtwork {
            for episode in series.episodes where !episode.isProviderEpisode && (episode.movieImage?.isEmpty != false) {
                episode.movieImage = fallbackArtwork
            }
        }
        try? context.save()
    }

    private static func seriesArtwork(_ series: Series) -> String? {
        if let backdrop = TMDBClient.backdropURL(series.backdropPath, size: "w780")?.absoluteString {
            return backdrop
        }
        if let cover = series.cover, !cover.isEmpty {
            return cover
        }
        return nil
    }
}
