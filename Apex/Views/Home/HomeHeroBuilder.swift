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

// MARK: - Background trending match (catalog ids only)

/// Lightweight trending match result — catalog ids only so SwiftData work can
/// run off the main thread and models are re-fetched on the view context.
struct TrendingCatalogMatch: Sendable {
    struct HeroSlot: Sendable {
        enum Media: Sendable { case movie, series }
        let media: Media
        let catalogID: String
        let backdropPath: String?
        let overview: String
    }

    let movieIDs: [String]
    let seriesIDs: [String]
    let heroSlots: [HeroSlot]
}

extension HomeHeroBuilder {
    /// Builds hero slots from the user's own library only — no TMDB network call.
    /// Used as a fast first paint on Home launch while trending is still fetching.
    nonisolated static func libraryHeroMatch(
        container: ModelContainer,
        playlistPrefix: String,
        restriction: ContentRestriction
    ) async -> TrendingCatalogMatch {
        guard !playlistPrefix.isEmpty else {
            return TrendingCatalogMatch(movieIDs: [], seriesIDs: [], heroSlots: [])
        }
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let slots = supplementHeroSlots(
                context: context,
                playlistPrefix: playlistPrefix,
                restriction: restriction,
                existing: []
            )
            return TrendingCatalogMatch(movieIDs: [], seriesIDs: [], heroSlots: slots)
        }.value
    }

    /// Matches TMDB trending titles to the local catalog on a background context.
    nonisolated static func matchTrending(
        container: ModelContainer,
        movies: [TrendingTitle],
        tvSeries: [TrendingTitle],
        playlistPrefix: String,
        restriction: ContentRestriction
    ) async -> TrendingCatalogMatch {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let prefix = playlistPrefix

            let moviesByTmdbId = fetchMoviesByTmdbId(
                tmdbIds: movies.map(\.id),
                playlistPrefix: prefix,
                restriction: restriction,
                in: context
            )
            let seriesByTmdbId = fetchSeriesByTmdbId(
                tmdbIds: tvSeries.map(\.id),
                playlistPrefix: prefix,
                restriction: restriction,
                in: context
            )

            func resolveMovieID(tmdbId: Int, trendingTitle: String) -> String? {
                if let movie = moviesByTmdbId[tmdbId] { return movie.id }
                return matchMovie(
                    tmdbId: tmdbId,
                    trendingTitle: trendingTitle,
                    playlistPrefix: prefix,
                    in: context
                )?.id
            }

            func resolveSeriesID(tmdbId: Int, trendingTitle: String) -> String? {
                if let series = seriesByTmdbId[tmdbId] { return series.id }
                return matchSeries(
                    tmdbId: tmdbId,
                    trendingTitle: trendingTitle,
                    playlistPrefix: prefix,
                    in: context
                )?.id
            }

            var movieIDs: [String] = []
            var seriesIDs: [String] = []
            var seenMovieIDs = Set<String>()
            var seenSeriesIDs = Set<String>()

            for title in movies {
                guard let id = resolveMovieID(tmdbId: title.id, trendingTitle: title.title),
                      seenMovieIDs.insert(id).inserted
                else { continue }
                movieIDs.append(id)
            }
            for title in tvSeries {
                guard let id = resolveSeriesID(tmdbId: title.id, trendingTitle: title.title),
                      seenSeriesIDs.insert(id).inserted
                else { continue }
                seriesIDs.append(id)
            }

            var heroSlots = heroSlots(
                movies: movies,
                tvSeries: tvSeries,
                movieLookup: resolveMovieID,
                seriesLookup: resolveSeriesID
            )
            heroSlots = supplementHeroSlots(
                context: context,
                playlistPrefix: prefix,
                restriction: restriction,
                existing: heroSlots
            )

            return TrendingCatalogMatch(
                movieIDs: Array(movieIDs.prefix(20)),
                seriesIDs: Array(seriesIDs.prefix(20)),
                heroSlots: heroSlots
            )
        }.value
    }

    nonisolated static func fetchMoviesByTmdbId(
        tmdbIds: [Int],
        playlistPrefix: String,
        restriction: ContentRestriction,
        in context: ModelContext
    ) -> [Int: Movie] {
        let ids = Set(tmdbIds)
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Movie>(predicate: movieTmdbIdPredicate(ids: ids))
        var byId: [Int: Movie] = [:]
        for movie in (try? context.fetch(descriptor)) ?? [] {
            guard playlistPrefix.isEmpty || movie.id.hasPrefix(playlistPrefix),
                  !restriction.hides(categoryID: movie.categoryId),
                  let tmdbId = movie.tmdbId, byId[tmdbId] == nil
            else { continue }
            byId[tmdbId] = movie
        }
        return byId
    }

    nonisolated static func fetchSeriesByTmdbId(
        tmdbIds: [Int],
        playlistPrefix: String,
        restriction: ContentRestriction,
        in context: ModelContext
    ) -> [Int: Series] {
        let ids = Set(tmdbIds)
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Series>(predicate: seriesTmdbIdPredicate(ids: ids))
        var byId: [Int: Series] = [:]
        for series in (try? context.fetch(descriptor)) ?? [] {
            guard playlistPrefix.isEmpty || series.id.hasPrefix(playlistPrefix),
                  !restriction.hides(categoryID: series.categoryId),
                  let tmdbId = series.tmdbId, byId[tmdbId] == nil
            else { continue }
            byId[tmdbId] = series
        }
        return byId
    }

    private static func heroSlots(
        movies: [TrendingTitle],
        tvSeries: [TrendingTitle],
        movieLookup: (Int, String) -> String?,
        seriesLookup: (Int, String) -> String?
    ) -> [TrendingCatalogMatch.HeroSlot] {
        var slots: [TrendingCatalogMatch.HeroSlot] = []
        var usedIDs = Set<String>()
        let maxCount = max(movies.count, tvSeries.count)

        for index in 0 ..< maxCount {
            if index < movies.count {
                let trending = movies[index]
                if let catalogID = movieLookup(trending.id, trending.title) {
                    let heroID = "movie-\(catalogID)"
                    if usedIDs.insert(heroID).inserted {
                        slots.append(.init(
                            media: .movie,
                            catalogID: catalogID,
                            backdropPath: trending.backdropPath,
                            overview: trending.overview
                        ))
                    }
                }
            }
            if index < tvSeries.count {
                let trending = tvSeries[index]
                if let catalogID = seriesLookup(trending.id, trending.title) {
                    let heroID = "series-\(catalogID)"
                    if usedIDs.insert(heroID).inserted {
                        slots.append(.init(
                            media: .series,
                            catalogID: catalogID,
                            backdropPath: trending.backdropPath,
                            overview: trending.overview
                        ))
                    }
                }
            }
        }
        return Array(slots.prefix(heroCap))
    }

    private static func supplementHeroSlots(
        context: ModelContext,
        playlistPrefix: String,
        restriction: ContentRestriction,
        existing: [TrendingCatalogMatch.HeroSlot]
    ) -> [TrendingCatalogMatch.HeroSlot] {
        guard existing.count < minimumHeroCount, !playlistPrefix.isEmpty else { return existing }

        var result = existing
        var usedIDs = Set(existing.map { slot in
            switch slot.media {
            case .movie: "movie-\(slot.catalogID)"
            case .series: "series-\(slot.catalogID)"
            }
        })

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
            result.append(.init(
                media: .movie,
                catalogID: movie.id,
                backdropPath: movie.backdropPath,
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
            result.append(.init(
                media: .series,
                catalogID: show.id,
                backdropPath: show.backdropPath,
                overview: show.plot ?? show.tagline ?? ""
            ))
            usedIDs.insert(heroID)
        }

        return result
    }
}
