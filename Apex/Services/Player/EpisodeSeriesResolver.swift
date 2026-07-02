import Foundation
import SwiftData

/// Resolves the `Series` that owns an `Episode`, repairing a missing inverse
/// link when episodes were inserted through `Series.insertEpisodes` without
/// setting `episode.series` (Xtream / Stalker lazy load). M3U import sets the
/// link in the `Episode` initializer, so this is mainly a backfill path.
enum EpisodeSeriesResolver {
    /// The series for `episode`, using the cached relationship when present or
    /// recovering it from the episode id (`{seriesId}-episode-{episodeKey}`).
    static func series(for episode: Episode, in context: ModelContext) -> Series? {
        if let linked = episode.series { return linked }
        guard let seriesID = seriesID(fromEpisodeID: episode.id) else { return nil }

        var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesID })
        descriptor.fetchLimit = 1
        guard let found = try? context.fetch(descriptor).first else { return nil }

        episode.series = found
        try? context.save()
        return found
    }

    /// Parses `{seriesElementId}-episode-{providerEpisodeKey}` → series element id.
    static func seriesID(fromEpisodeID id: String) -> String? {
        let marker = "-episode-"
        guard let range = id.range(of: marker) else { return nil }
        let seriesID = String(id[..<range.lowerBound])
        return seriesID.isEmpty ? nil : seriesID
    }
}
