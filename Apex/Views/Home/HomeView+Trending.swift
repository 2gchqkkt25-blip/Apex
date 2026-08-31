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
        let playlistChanged = lastTrendingPlaylistStamp != playlistStamp

        if playlistChanged {
            if heroItems.isEmpty {
                trendingState = .loading
            }
            trendingMovies = []
            trendingSeries = []
        }

        if trendingState == .loaded,
           lastTrendingPlaylistStamp == playlistStamp,
           (!heroItems.isEmpty || !trendingMovies.isEmpty || !trendingSeries.isEmpty)
        {
            return
        }

        // Phase 1 — instant library / Plex heroes (no network).
        if heroItems.isEmpty {
            let libraryMatch = await HomeHeroBuilder.libraryHeroMatch(
                container: modelContext.container,
                playlistPrefix: playlistPrefix ?? "",
                restriction: restriction
            )
            if !libraryMatch.heroSlots.isEmpty {
                applyTrendingMatch(libraryMatch)
                trendingState = .loaded
            }
        }

        guard client.isConfigured else {
            await loadLibraryTrendingFallback(playlistStamp: playlistStamp)
            return
        }
        guard !Task.isCancelled else { return }

        // Phase 2 — TMDB trending rows + hero upgrade when phase 1 was empty.
        if heroItems.isEmpty {
            trendingState = .loading
        }
        await upgradeTrendingFromTMDB(client: client, playlistStamp: playlistStamp)
    }

    private func loadLibraryTrendingFallback(playlistStamp: Double) async {
        if trendingMovies.isEmpty, trendingSeries.isEmpty {
            let libraryTrending = await HomeHeroBuilder.libraryTrendingMatch(
                container: modelContext.container,
                playlistPrefix: playlistPrefix ?? "",
                restriction: restriction
            )
            if !libraryTrending.movieIDs.isEmpty || !libraryTrending.seriesIDs.isEmpty {
                applyTrendingMatch(libraryTrending)
            }
        }
        trendingState = .loaded
        lastTrendingPlaylistStamp = playlistStamp
    }

    private func upgradeTrendingFromTMDB(client: TMDBClient, playlistStamp: Double) async {
        #if os(tvOS)
        if !DeviceMemoryTier.current.isConstrained {
            await waitUntilPlaylistSyncIdle()
        }
        #else
        await waitUntilPlaylistSyncIdle()
        #endif
        guard !Task.isCancelled else { return }

        let prefix = playlistPrefix ?? ""
        let restriction = restriction
        let container = modelContext.container
        let hadHeroes = !heroItems.isEmpty

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

            applyTrendingMatch(match, preserveExistingHeroes: hadHeroes)
            trendingState = .loaded
            lastTrendingPlaylistStamp = playlistStamp

            #if os(tvOS)
            guard !DeviceMemoryTier.current.isConstrained else { return }
            #endif
            Task(priority: .utility) {
                try? await Task.sleep(for: .seconds(3))
                guard NetworkMonitor.shared.shouldProceedWithHeavyNetworkWork() else { return }
                await enrichHeroLogos()
            }
        } catch {
            if trendingMovies.isEmpty, trendingSeries.isEmpty {
                await loadLibraryTrendingFallback(playlistStamp: playlistStamp)
            } else {
                trendingState = heroItems.isEmpty ? .failed : .loaded
                lastTrendingPlaylistStamp = playlistStamp
            }
        }
    }

    private func applyTrendingMatch(_ match: TrendingCatalogMatch, preserveExistingHeroes: Bool = false) {
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
        #if os(tvOS)
        if DeviceMemoryTier.current.isConstrained {
            trendingMovies = Array(trendingMovies.prefix(6))
            trendingSeries = Array(trendingSeries.prefix(6))
        }
        #endif

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
        if !trendingHeroes.isEmpty, !preserveExistingHeroes || heroItems.isEmpty {
            heroItems = trendingHeroes
            prefetchFirstHeroBackdrop()
        }
    }

    private func prefetchFirstHeroBackdrop() {
        guard let url = heroItems.first?.imageURL else { return }
        #if os(tvOS)
        guard !DeviceMemoryTier.current.isConstrained else { return }
        #endif
        Task {
            await ImagePipeline.shared.prefetch(
                [url],
                maxPixelSize: HeroBackdropMetrics.prefetchMaxPixelSize
            )
        }
    }

    private func enrichHeroLogos() async {
        #if os(tvOS)
        guard !DeviceMemoryTier.current.isConstrained else { return }
        #endif
        let manager = ContentSyncManager(modelContainer: modelContext.container)
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

    func fetchMoviesByCatalogIDBackground(_ ids: Set<String>) async -> [String: Movie] {
        guard !ids.isEmpty else { return [:] }
        let container = modelContext.container
        let idSet = ids
        let prefix = playlistPrefix
        let restriction = restriction
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { idSet.contains($0.id) })
            var byID: [String: Movie] = [:]
            for movie in (try? context.fetch(descriptor)) ?? []
                where HomeCatalogScope.includes(movie.id, playlistPrefix: prefix)
                    && !restriction.hides(categoryID: movie.categoryId)
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
        let prefix = playlistPrefix
        let restriction = restriction
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Series>(predicate: #Predicate { idSet.contains($0.id) })
            var byID: [String: Series] = [:]
            for series in (try? context.fetch(descriptor)) ?? []
                where HomeCatalogScope.includes(series.id, playlistPrefix: prefix)
                    && !restriction.hides(categoryID: series.categoryId)
            {
                byID[series.id] = series
            }
            return byID
        }.value
    }

    func waitUntilPlaylistSyncIdle() async {
        while isPlaylistSyncBusy {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
    }

    func waitUntilSyncIdle() async {
        while isSyncBusy {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
    }
}

nonisolated func movieTmdbIdPredicate(ids: Set<Int>) -> Predicate<Movie> {
    let optionalIds = Set(ids.map(Int?.some))
    return #Predicate { optionalIds.contains($0.tmdbId) }
}

nonisolated func seriesTmdbIdPredicate(ids: Set<Int>) -> Predicate<Series> {
    let optionalIds = Set(ids.map(Int?.some))
    return #Predicate { optionalIds.contains($0.tmdbId) }
}
