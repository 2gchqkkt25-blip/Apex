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
        let playlistStamp = activePlaylist?.lastSyncDate?.timeIntervalSince1970 ?? 0

        // Skip re-fetch when we already have a settled carousel for this playlist.
        if trendingState == .loaded, !heroItems.isEmpty, !trendingMovies.isEmpty, lastTrendingPlaylistStamp == playlistStamp {
            return
        }

        // Phase 1 — instant library heroes from the local catalog (no network, no
        // sync wait). Paint Home immediately so reopen doesn't freeze on the hero.
        if heroItems.isEmpty, let prefix = playlistPrefix, !prefix.isEmpty {
            let libraryMatch = await HomeHeroBuilder.libraryHeroMatch(
                container: modelContext.container,
                playlistPrefix: prefix,
                restriction: restriction
            )
            if !libraryMatch.heroSlots.isEmpty {
                applyTrendingMatch(libraryMatch)
                trendingState = .loaded
            }
        }

        guard client.isConfigured else {
            trendingState = .loaded
            return
        }
        guard !Task.isCancelled else { return }

        // Phase 2 — TMDB trending upgrades heroes in the background. Only block
        // the empty-state gate when phase 1 produced nothing to show.
        if heroItems.isEmpty {
            trendingState = .loading
        }
        await upgradeTrendingFromTMDB(client: client, playlistStamp: playlistStamp)
    }

    /// Fetches TMDB trending and merges into Home. Runs after playlist sync
    /// settles but does not block first paint when library heroes are already up.
    private func upgradeTrendingFromTMDB(client: TMDBClient, playlistStamp: Double) async {
        await waitUntilPlaylistSyncIdle()
        guard !Task.isCancelled else { return }

        let prefix = playlistPrefix ?? ""
        let restriction = restriction
        let container = modelContext.container

        do {
            async let movieTitles = client.trending(.movie)
            async let tvTitles = client.trending(.tvShow)
            let (movies, tvSeries) = try await (movieTitles, tvTitles)

            let match = await HomeHeroBuilder.matchTrending(
                container: container,
                movies: movies,
                tvSeries: tvSeries,
                playlistPrefix: prefix,
                restriction: restriction
            )

            applyTrendingMatch(match)
            trendingState = .loaded
            lastTrendingPlaylistStamp = playlistStamp

            Task(priority: .utility) {
                try? await Task.sleep(for: .seconds(3))
                guard NetworkMonitor.shared.shouldProceedWithHeavyNetworkWork() else { return }
                await enrichHeroLogos()
            }
        } catch {
            // Keep any library heroes from phase 1; mark settled so Home doesn't
            // stay in the empty-state gate forever.
            trendingState = heroItems.isEmpty ? .failed : .loaded
        }
    }

    /// Applies a trending match to view state — hero carousel + trending rows.
    private func applyTrendingMatch(_ match: TrendingCatalogMatch) {
        let movieLookup = fetchMoviesByCatalogID(Set(match.movieIDs + match.heroSlots.compactMap {
            $0.media == .movie ? $0.catalogID : nil
        }))
        let seriesLookup = fetchSeriesByCatalogID(Set(match.seriesIDs + match.heroSlots.compactMap {
            $0.media == .series ? $0.catalogID : nil
        }))

        if !match.movieIDs.isEmpty {
            trendingMovies = match.movieIDs.compactMap { movieLookup[$0].map(HomeMediaItem.movie) }
        }
        if !match.seriesIDs.isEmpty {
            trendingSeries = match.seriesIDs.compactMap { seriesLookup[$0].map(HomeMediaItem.series) }
        }

        let trendingHeroes = match.heroSlots.compactMap { slot -> HeroItem? in
            switch slot.media {
            case .movie:
                guard let movie = movieLookup[slot.catalogID] else { return nil }
                return .movie(
                    movie,
                    backdropURL: TMDBClient.backdropURL(slot.backdropPath),
                    overview: slot.overview
                )
            case .series:
                guard let series = seriesLookup[slot.catalogID] else { return nil }
                return .series(
                    series,
                    backdropURL: TMDBClient.backdropURL(slot.backdropPath),
                    overview: slot.overview
                )
            }
        }
        if !trendingHeroes.isEmpty {
            heroItems = trendingHeroes
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
        // Only enrich the first visible hero — the rest can load on demand.
        for hero in heroItems.prefix(2) {
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
        await waitUntilPlaylistSyncIdle()
        guard !Task.isCancelled else { return }

        let items = await trakt.fetchWatchlist()
        let movieTmdbIds = items.compactMap { $0.movie?.ids.tmdb }
        let seriesTmdbIds = items.compactMap { $0.show?.ids.tmdb }
        let prefix = playlistPrefix ?? ""
        let restriction = restriction
        let container = modelContext.container

        let matchedSlots = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let moviesByTmdbId = HomeHeroBuilder.fetchMoviesByTmdbId(
                tmdbIds: movieTmdbIds,
                playlistPrefix: prefix,
                restriction: restriction,
                in: context
            )
            let seriesByTmdbId = HomeHeroBuilder.fetchSeriesByTmdbId(
                tmdbIds: seriesTmdbIds,
                playlistPrefix: prefix,
                restriction: restriction,
                in: context
            )
            var slots: [(id: String, isMovie: Bool)] = []
            for item in items {
                switch item.type {
                case "movie":
                    if let tmdbID = item.movie?.ids.tmdb, let movie = moviesByTmdbId[tmdbID] {
                        slots.append((movie.id, true))
                    }
                case "show":
                    if let tmdbID = item.show?.ids.tmdb, let series = seriesByTmdbId[tmdbID] {
                        slots.append((series.id, false))
                    }
                default:
                    break
                }
            }
            return slots
        }.value

        let movieIDs = Set(matchedSlots.filter(\.isMovie).map(\.id))
        let seriesIDs = Set(matchedSlots.filter { !$0.isMovie }.map(\.id))
        let moviesByID = await fetchMoviesByCatalogIDBackground(movieIDs)
        let seriesByID = await fetchSeriesByCatalogIDBackground(seriesIDs)
        watchlist = matchedSlots.prefix(20).compactMap { slot -> HomeMediaItem? in
            if slot.isMovie {
                return moviesByID[slot.id].map(HomeMediaItem.movie)
            }
            return seriesByID[slot.id].map(HomeMediaItem.series)
        }
    }

    // MARK: - Catalog lookup (main context, batched)

    func fetchMoviesByCatalogID(_ ids: Set<String>) -> [String: Movie] {
        guard !ids.isEmpty else { return [:] }
        let idSet = ids
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { idSet.contains($0.id) })
        var byID: [String: Movie] = [:]
        for movie in (try? modelContext.fetch(descriptor)) ?? []
            where belongsToActivePlaylist(movie.id) && !restriction.hides(categoryID: movie.categoryId)
        {
            byID[movie.id] = movie
        }
        return byID
    }

    func fetchSeriesByCatalogID(_ ids: Set<String>) -> [String: Series] {
        guard !ids.isEmpty else { return [:] }
        let idSet = ids
        let descriptor = FetchDescriptor<Series>(predicate: #Predicate { idSet.contains($0.id) })
        var byID: [String: Series] = [:]
        for series in (try? modelContext.fetch(descriptor)) ?? []
            where belongsToActivePlaylist(series.id) && !restriction.hides(categoryID: series.categoryId)
        {
            byID[series.id] = series
        }
        return byID
    }

    /// Background-context versions of the catalog ID fetches — used by watchlist
    /// loading which previously blocked the main thread and triggered watchdog
    /// kills on large (28K) catalogs.
    func fetchMoviesByCatalogIDBackground(_ ids: Set<String>) async -> [String: Movie] {
        guard !ids.isEmpty else { return [:] }
        let container = modelContext.container
        let idSet = ids
        let prefix = playlistPrefix ?? ""
        let restriction = restriction
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { idSet.contains($0.id) })
            var byID: [String: Movie] = [:]
            for movie in (try? context.fetch(descriptor)) ?? []
                where movie.id.hasPrefix(prefix) && !restriction.hides(categoryID: movie.categoryId)
            {
                byID[movie.id] = movie
            }
            return byID
        }.value
    }

    func fetchSeriesByCatalogIDBackground(_ ids: Set<String>) async -> [String: Series] {
        guard !ids.isEmpty else { return [:] }
        let container = modelContext.container
        let idSet = ids
        let prefix = playlistPrefix ?? ""
        let restriction = restriction
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Series>(predicate: #Predicate { idSet.contains($0.id) })
            var byID: [String: Series] = [:]
            for series in (try? context.fetch(descriptor)) ?? []
                where series.id.hasPrefix(prefix) && !restriction.hides(categoryID: series.categoryId)
            {
                byID[series.id] = series
            }
            return byID
        }.value
    }

    /// Waits until playlist content sync finishes without blocking on CloudKit
    /// reconcile — the catalog is already local and usable during iCloud import.
    func waitUntilPlaylistSyncIdle() async {
        while isPlaylistSyncBusy {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
    }

    /// Waits until playlist sync / iCloud reconcile finish without blocking the
    /// main thread in a tight loop. Used by heavier rows (For You) that benefit
    /// from a settled store.
    func waitUntilSyncIdle() async {
        while isSyncBusy {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
    }

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
