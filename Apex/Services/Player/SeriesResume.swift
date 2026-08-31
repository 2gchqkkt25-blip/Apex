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

        let ordered = episodes.sorted {
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
