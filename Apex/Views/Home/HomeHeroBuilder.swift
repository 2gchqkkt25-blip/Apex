//
//  HomeHeroBuilder.swift
//  Apex
//
//  Builds Home hero carousel items from TMDB trending, matching them to the
//  user's library by TMDB id or cleaned title, with a library-artwork fallback
//  when trending overlap is thin.
//

import Foundation
import SwiftData

enum HomeHeroBuilder {
    private static let heroCap = 8
    private static let minimumHeroCount = 3
    /// Max rows pulled when supplementing heroes or searching by title. Keeps
    /// post-sync Home loads from hydrating a 20k+ catalog on device.
    private static let libraryFetchLimit = 80
    private static let titleSearchFetchLimit = 100

    /// Interleaves trending movies and series the user owns into hero items.
    static func heroes(
        movies: [TrendingTitle],
        tvSeries: [TrendingTitle],
        movieLookup: (Int, String) -> Movie?,
        seriesLookup: (Int, String) -> Series?,
        backdropURL: (String?) -> URL?
    ) -> [HeroItem] {
        var heroes: [HeroItem] = []
        var usedIDs = Set<String>()
        let maxCount = max(movies.count, tvSeries.count)

        for index in 0 ..< maxCount {
            if index < movies.count {
                appendMovieHero(
                    trending: movies[index],
                    lookup: movieLookup,
                    backdropURL: backdropURL,
                    heroes: &heroes,
                    usedIDs: &usedIDs
                )
            }
            if index < tvSeries.count {
                appendSeriesHero(
                    trending: tvSeries[index],
                    lookup: seriesLookup,
                    backdropURL: backdropURL,
                    heroes: &heroes,
                    usedIDs: &usedIDs
                )
            }
        }
        return Array(heroes.prefix(heroCap))
    }

    /// Fills the carousel from the user's own library when trending overlap is
    /// sparse (common right after sync, before TMDB ids are assigned).
    static func supplementFromLibrary(
        context: ModelContext,
        playlistPrefix: String,
        restriction: ContentRestriction,
        existing: [HeroItem]
    ) -> [HeroItem] {
        guard existing.count < minimumHeroCount, !playlistPrefix.isEmpty else { return existing }

        var result = existing
        var usedIDs = Set(existing.map(\.id))

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.localizedStandardContains(playlistPrefix) },
            sortBy: [SortDescriptor(\.rating, order: .reverse)]
        )
        movieDescriptor.fetchLimit = libraryFetchLimit
        let movies = ((try? context.fetch(movieDescriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) }

        for movie in movies {
            guard result.count < heroCap else { break }
            let heroID = "movie-\(movie.id)"
            guard !usedIDs.contains(heroID) else { continue }
            guard movie.tmdbId != nil || movie.backdropPath != nil || movie.iconURL != nil else { continue }
            result.append(.movie(
                movie,
                backdropURL: TMDBClient.backdropURL(movie.backdropPath),
                overview: movie.plot ?? movie.tagline ?? ""
            ))
            usedIDs.insert(heroID)
        }

        var seriesDescriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.id.localizedStandardContains(playlistPrefix) }
        )
        seriesDescriptor.fetchLimit = libraryFetchLimit
        let seriesList = ((try? context.fetch(seriesDescriptor)) ?? [])
            .filter { !restriction.hides(categoryID: $0.categoryId) }
            .sorted { libraryScore($0) > libraryScore($1) }

        for show in seriesList {
            guard result.count < heroCap else { break }
            let heroID = "series-\(show.id)"
            guard !usedIDs.contains(heroID) else { continue }
            guard show.tmdbId != nil || show.backdropPath != nil || !(show.cover ?? "").isEmpty else { continue }
            result.append(.series(
                show,
                backdropURL: TMDBClient.backdropURL(show.backdropPath),
                overview: show.plot ?? show.tagline ?? ""
            ))
            usedIDs.insert(heroID)
        }

        return result
    }

    /// Matches a trending title to a library movie by TMDB id, then by cleaned title.
    static func matchMovie(
        tmdbId: Int,
        trendingTitle: String,
        playlistPrefix: String,
        in context: ModelContext
    ) -> Movie? {
        if let match = fetchMovie(tmdbId: tmdbId, playlistPrefix: playlistPrefix, in: context) { return match }
        return matchMovieByTitle(trendingTitle: trendingTitle, playlistPrefix: playlistPrefix, in: context)
    }

    /// Matches a trending title to a library series by TMDB id, then by cleaned title.
    static func matchSeries(
        tmdbId: Int,
        trendingTitle: String,
        playlistPrefix: String,
        in context: ModelContext
    ) -> Series? {
        if let match = fetchSeries(tmdbId: tmdbId, playlistPrefix: playlistPrefix, in: context) { return match }
        return matchSeriesByTitle(trendingTitle: trendingTitle, playlistPrefix: playlistPrefix, in: context)
    }

    // MARK: - Private

    private static func appendMovieHero(
        trending: TrendingTitle,
        lookup: (Int, String) -> Movie?,
        backdropURL: (String?) -> URL?,
        heroes: inout [HeroItem],
        usedIDs: inout Set<String>
    ) {
        guard let movie = lookup(trending.id, trending.title) else { return }
        let heroID = "movie-\(movie.id)"
        guard !usedIDs.contains(heroID) else { return }
        heroes.append(.movie(
            movie,
            backdropURL: backdropURL(trending.backdropPath),
            overview: trending.overview
        ))
        usedIDs.insert(heroID)
    }

    private static func appendSeriesHero(
        trending: TrendingTitle,
        lookup: (Int, String) -> Series?,
        backdropURL: (String?) -> URL?,
        heroes: inout [HeroItem],
        usedIDs: inout Set<String>
    ) {
        guard let series = lookup(trending.id, trending.title) else { return }
        let heroID = "series-\(series.id)"
        guard !usedIDs.contains(heroID) else { return }
        heroes.append(.series(
            series,
            backdropURL: backdropURL(trending.backdropPath),
            overview: trending.overview
        ))
        usedIDs.insert(heroID)
    }

    private static func fetchMovie(tmdbId: Int, playlistPrefix: String, in context: ModelContext) -> Movie? {
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.tmdbId == tmdbId && $0.id.localizedStandardContains(playlistPrefix) }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchSeries(tmdbId: Int, playlistPrefix: String, in context: ModelContext) -> Series? {
        var descriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.tmdbId == tmdbId && $0.id.localizedStandardContains(playlistPrefix) }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func matchMovieByTitle(
        trendingTitle: String,
        playlistPrefix: String,
        in context: ModelContext
    ) -> Movie? {
        let normalizedTrending = ContentIndexText.searchQuery(for: trendingTitle).title.lowercased()
        guard normalizedTrending.count >= 3, !playlistPrefix.isEmpty else { return nil }

        let fragment = String(normalizedTrending.prefix(24))
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { movie in
                movie.id.localizedStandardContains(playlistPrefix)
                    && movie.name.localizedStandardContains(fragment)
            }
        )
        descriptor.fetchLimit = titleSearchFetchLimit
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { movie in
            ContentIndexText.searchQuery(for: movie.name).title.lowercased() == normalizedTrending
        }
    }

    private static func matchSeriesByTitle(
        trendingTitle: String,
        playlistPrefix: String,
        in context: ModelContext
    ) -> Series? {
        let normalizedTrending = ContentIndexText.searchQuery(for: trendingTitle).title.lowercased()
        guard normalizedTrending.count >= 3, !playlistPrefix.isEmpty else { return nil }

        let fragment = String(normalizedTrending.prefix(24))
        var descriptor = FetchDescriptor<Series>(
            predicate: #Predicate { series in
                series.id.localizedStandardContains(playlistPrefix)
                    && series.name.localizedStandardContains(fragment)
            }
        )
        descriptor.fetchLimit = titleSearchFetchLimit
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { series in
            ContentIndexText.searchQuery(for: series.name).title.lowercased() == normalizedTrending
        }
    }

    private static func libraryScore(_ movie: Movie) -> Double {
        var score = movie.rating > 0 ? movie.rating : movie.rating5Based * 2
        if movie.backdropPath != nil { score += 5 }
        if movie.tmdbId != nil { score += 2 }
        if movie.tmdbEnrichedAt != nil { score += 1 }
        return score
    }

    private static func libraryScore(_ series: Series) -> Double {
        var score = Double(series.rating ?? "") ?? (Double(series.rating5Based ?? "") ?? 0) * 2
        if series.backdropPath != nil { score += 5 }
        if series.tmdbId != nil { score += 2 }
        if series.tmdbEnrichedAt != nil { score += 1 }
        return score
    }
}
