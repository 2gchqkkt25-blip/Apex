//
//  HomeMediaItem.swift
//  Apex
//
//  A type-erased wrapper over the three playable content kinds so a single
//  horizontal row (see HomeRows) can present movies, series and live channels
//  together.
//

import Foundation
import SwiftData

enum HomeMediaItem: Identifiable, Hashable {
    case movie(Movie)
    case series(Series)
    case live(LiveStream)

    var id: String {
        switch self {
        case let .movie(movie): "movie-\(movie.id)"
        case let .series(series): "series-\(series.id)"
        case let .live(stream): "live-\(stream.id)"
        }
    }

    var title: String {
        switch self {
        case let .movie(movie): movie.name
        case let .series(series): series.name
        case let .live(stream): stream.name
        }
    }

    var imageURL: URL? {
        switch self {
        case let .movie(movie): movie.iconURL
        case let .series(series): URL(string: series.cover ?? "")
        case let .live(stream): stream.iconURL
        }
    }

    var lastWatchedDate: Date? {
        switch self {
        case let .movie(movie): movie.lastWatchedDate
        case let .series(series): series.lastWatchedDate
        case let .live(stream): stream.lastWatchedDate
        }
    }

    var categoryId: String? {
        switch self {
        case let .movie(movie): movie.categoryId
        case let .series(series): series.categoryId
        case let .live(stream): stream.categoryId
        }
    }

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    /// Best available score for the poster overlay; nil for live channels.
    var posterRating: PosterRatingDisplay? {
        switch self {
        case let .movie(movie): PosterRatingDisplay.forMovie(movie)
        case let .series(series): PosterRatingDisplay.forSeries(series)
        case .live: nil
        }
    }

    /// Resume fraction for partially-watched movies or series (0...1), otherwise nil.
    ///
    /// Series progress is loaded from the store by episode id — never via
    /// `series.episodes`. Walking that relationship during SwiftUI prefetch
    /// traps on `_InvalidFutureBackingData` after prune / CloudKit merge.
    func resumeProgress(in context: ModelContext) -> Double? {
        switch self {
        case let .movie(movie):
            Self.movieResumeFraction(movie)
        case let .series(series):
            Self.seriesResumeFraction(seriesId: series.id, in: context)
        case .live:
            nil
        }
    }

    static func movieResumeFraction(_ movie: Movie) -> Double? {
        guard let duration = movie.durationSecs, duration > 0,
              movie.watchProgress > 0, !movie.isWatched else { return nil }
        return min(movie.watchProgress / Double(duration), 1)
    }

    /// In-progress episode for `seriesId`, using the `{seriesId}-episode-…` id
    /// convention (Xtream / Stalker / M3U). Does not materialize `Series.episodes`.
    static func seriesResumeFraction(seriesId: String, in context: ModelContext) -> Double? {
        guard !seriesId.isEmpty else { return nil }
        let idPrefix = seriesId + "-episode-"
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.id.starts(with: idPrefix)
                    && episode.watchProgress > 0
                    && episode.isWatched == false
            },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let episode = (try? context.fetch(descriptor))?.first,
              let duration = episode.durationSecs, duration > 0
        else { return nil }
        return min(episode.watchProgress / Double(duration), 1)
    }
}
