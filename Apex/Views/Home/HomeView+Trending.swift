//
//  HomeView+Trending.swift
//  Apex
//
//  Home's TMDB trending and Trakt watchlist loading, split from `HomeView` to
//  keep the view file within size limits. Trending/watchlist titles are matched
//  against the local catalog in batched queries keyed by `tmdbId`, with title
//  fallback and library hero supplementation via `HomeHeroBuilder`.
//

import SwiftData
import SwiftUI

extension HomeView {
    // MARK: - Trending

    func loadTrending() async {
        let client = TMDBClient.shared
        guard client.isConfigured else {
            trendingState = .loaded
            return
        }
        guard !isSyncBusy else { return }
        trendingState = .loading
        do {
            async let movieTitles = client.trending(.movie)
            async let tvTitles = client.trending(.tvShow)
            let (movies, tvSeries) = try await (movieTitles, tvTitles)

            // Fast path: two batched queries for TMDB id matches.
            let moviesByTmdbId = fetchMovies(tmdbIds: movies.map(\.id))
            let seriesByTmdbId = fetchSeries(tmdbIds: tvSeries.map(\.id))
            let prefix = playlistPrefix ?? ""

            func resolveMovie(tmdbId: Int, trendingTitle: String) -> Movie? {
                if let movie = moviesByTmdbId[tmdbId] { return movie }
                guard let movie = HomeHeroBuilder.matchMovie(
                    tmdbId: tmdbId,
                    trendingTitle: trendingTitle,
                    playlistPrefix: prefix,
                    in: modelContext
                ) else { return nil }
                return restriction.hides(categoryID: movie.categoryId) ? nil : movie
            }

            func resolveSeries(tmdbId: Int, trendingTitle: String) -> Series? {
                if let series = seriesByTmdbId[tmdbId] { return series }
                guard let series = HomeHeroBuilder.matchSeries(
                    tmdbId: tmdbId,
                    trendingTitle: trendingTitle,
                    playlistPrefix: prefix,
                    in: modelContext
                ) else { return nil }
                return restriction.hides(categoryID: series.categoryId) ? nil : series
            }

            var movieItems: [HomeMediaItem] = []
            var seriesItems: [HomeMediaItem] = []
            for title in movies {
                if let movie = resolveMovie(tmdbId: title.id, trendingTitle: title.title) {
                    movieItems.append(.movie(movie))
                }
            }
            for title in tvSeries {
                if let series = resolveSeries(tmdbId: title.id, trendingTitle: title.title) {
                    seriesItems.append(.series(series))
                }
            }
            movieItems = dedupedMediaItems(movieItems)
            seriesItems = dedupedMediaItems(seriesItems)
            trendingMovies = Array(movieItems.prefix(20))
            trendingSeries = Array(seriesItems.prefix(20))

            let heroes = HomeHeroBuilder.heroes(
                movies: movies,
                tvSeries: tvSeries,
                movieLookup: resolveMovie,
                seriesLookup: resolveSeries,
                backdropURL: { TMDBClient.backdropURL($0) }
            )
            heroItems = HomeHeroBuilder.supplementFromLibrary(
                context: modelContext,
                playlistPrefix: prefix,
                restriction: restriction,
                existing: heroes
            )
            trendingState = .loaded
            #if os(tvOS)
            Task(priority: .utility) {
                try? await Task.sleep(for: .seconds(8))
                await enrichHeroLogos()
            }
            #else
            await enrichHeroLogos()
            #endif
        } catch {
            trendingState = .failed
        }
    }

    /// The TMDB trending feed carries no logo artwork, so a hero title shows
    /// only its backdrop until its full details are fetched. That fetch used to
    /// happen only on the detail screen, so logos "popped in" after visiting
    /// Details and coming back. Enrich the visible hero titles up front via the
    /// same TMDB detail path. Runs after the carousel is shown so backdrops
    /// aren't blocked.
    private func enrichHeroLogos() async {
        let manager = ContentSyncManager(modelContainer: modelContext.container)
        for hero in heroItems {
            switch hero {
            case let .movie(movie, _, _):
                guard heroNeedsLogo(logoPath: movie.logoPath, enrichedAt: movie.tmdbEnrichedAt),
                      let tmdbId = movie.tmdbId
                else { continue }
                await manager.enrichMovie(id: movie.id, tmdbId: tmdbId)
            case let .series(series, _, _):
                guard heroNeedsLogo(logoPath: series.logoPath, enrichedAt: series.tmdbEnrichedAt),
                      let tmdbId = series.tmdbId
                else { continue }
                await manager.enrichSeries(id: series.id, tmdbId: tmdbId)
            }
        }
    }

    private func heroNeedsLogo(logoPath: String?, enrichedAt: Date?) -> Bool {
        guard (logoPath ?? "").isEmpty else { return false }
        guard let enrichedAt else { return true }
        return Date().timeIntervalSince(enrichedAt) >= 14 * 24 * 3600
    }

    private func dedupedMediaItems(_ items: [HomeMediaItem]) -> [HomeMediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Watchlist

    func loadWatchlist() async {
        guard trakt.isConnected else {
            watchlist = []
            return
        }
        guard !isSyncBusy else { return }
        let items = await trakt.fetchWatchlist()
        let moviesByTmdbId = fetchMovies(tmdbIds: items.compactMap { $0.movie?.ids.tmdb })
        let seriesByTmdbId = fetchSeries(tmdbIds: items.compactMap { $0.show?.ids.tmdb })
        var matched: [HomeMediaItem] = []
        for item in items {
            switch item.type {
            case "movie":
                if let tmdbID = item.movie?.ids.tmdb, let movie = moviesByTmdbId[tmdbID] {
                    matched.append(.movie(movie))
                }
            case "show":
                if let tmdbID = item.show?.ids.tmdb, let series = seriesByTmdbId[tmdbID] {
                    matched.append(.series(series))
                }
            default:
                break
            }
        }
        watchlist = Array(matched.prefix(20))
    }

    // MARK: - Batched catalog lookup

    private func fetchMovies(tmdbIds: [Int]) -> [Int: Movie] {
        let ids = Set(tmdbIds)
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Movie>(predicate: movieTmdbIdPredicate(ids: ids))
        var byId: [Int: Movie] = [:]
        for movie in (try? modelContext.fetch(descriptor)) ?? []
            where belongsToActivePlaylist(movie.id) && !restriction.hides(categoryID: movie.categoryId)
        {
            guard let tmdbId = movie.tmdbId, byId[tmdbId] == nil else { continue }
            byId[tmdbId] = movie
        }
        return byId
    }

    private func fetchSeries(tmdbIds: [Int]) -> [Int: Series] {
        let ids = Set(tmdbIds)
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Series>(predicate: seriesTmdbIdPredicate(ids: ids))
        var byId: [Int: Series] = [:]
        for series in (try? modelContext.fetch(descriptor)) ?? []
            where belongsToActivePlaylist(series.id) && !restriction.hides(categoryID: series.categoryId)
        {
            guard let tmdbId = series.tmdbId, byId[tmdbId] == nil else { continue }
            byId[tmdbId] = series
        }
        return byId
    }
}

/// `tmdbId` is optional, and neither `?? -1` (TERNARY) nor a nil-check +
/// force-unwrap (ForcedUnwrap) survives SwiftData's SQL generation — both throw
/// at fetch time on a real store (in-memory stores skip SQL and don't
/// reproduce it). Comparing against a `Set<Int?>` builds a plain `IN` clause.
nonisolated func movieTmdbIdPredicate(ids: Set<Int>) -> Predicate<Movie> {
    let optionalIds = Set(ids.map(Int?.some))
    return #Predicate { optionalIds.contains($0.tmdbId) }
}

nonisolated func seriesTmdbIdPredicate(ids: Set<Int>) -> Predicate<Series> {
    let optionalIds = Set(ids.map(Int?.some))
    return #Predicate { optionalIds.contains($0.tmdbId) }
}
