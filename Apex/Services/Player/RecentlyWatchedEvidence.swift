import Foundation
import SwiftData

/// Whether a catalog row belongs in Recently Watched. A non-nil `lastWatchedDate`
/// is not enough — CloudKit rematch, a tap-and-back, or a media-server `played`
/// flag can stamp the date on titles the user never actually played here.
enum RecentlyWatchedEvidence {
    nonisolated static let minimumProgress: Double = 5

    static func movieQualifies(_ movie: Movie) -> Bool {
        movie.lastWatchedDate != nil && (movie.isWatched || movie.watchProgress >= minimumProgress)
    }

    /// Does not walk `series.episodes` (that relationship can fault after prune).
    static func seriesQualifies(id seriesId: String, in context: ModelContext) -> Bool {
        guard !seriesId.isEmpty else { return false }
        let idPrefix = seriesId + "-episode-"
        let minProgress = minimumProgress
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.id.starts(with: idPrefix)
                    && (episode.isWatched || episode.watchProgress >= minProgress)
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first != nil
    }
}
