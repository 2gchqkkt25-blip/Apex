//
//  TopShelfDataWriter.swift
//  Apex
//
//  Writes Top Shelf content to the shared App Group so the tvOS extension
//  can display it. Called after playlist sync and periodically when the user's
//  watch state changes.
//

import Foundation
import SwiftData

#if os(tvOS)

enum TopShelfDataWriter {
    /// Updates the shared App Group with current Top Shelf data based on
    /// the user's chosen content mode. Call after sync completes or when
    /// favorites/watch progress changes.
    @MainActor
    static func update(container: ModelContainer) {
        guard let defaults = UserDefaults(suiteName: TopShelfSettings.appGroupID) else { return }
        let mode = TopShelfSettings.ContentMode(
            rawValue: defaults.string(forKey: TopShelfSettings.contentModeKey) ?? ""
        ) ?? .recentlyWatched

        let context = ModelContext(container)
        context.autosaveEnabled = false

        var items: [TopShelfItemData] = []

        switch mode {
        case .recentlyWatched:
            items = fetchRecentlyWatched(context: context, category: mode.rawValue)
        case .favorites:
            items = fetchFavorites(context: context, category: mode.rawValue)
        case .trending:
            items = fetchTrending(context: context, category: mode.rawValue)
        case .continueWatching:
            items = fetchContinueWatching(context: context, category: mode.rawValue)
        }

        // Persist to shared defaults as JSON
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: TopShelfSettings.itemsDataKey)
        }

        // Notify the extension to refresh
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private static func fetchRecentlyWatched(context: ModelContext, category: String) -> [TopShelfItemData] {
        var result: [TopShelfItemData] = []

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.lastWatchedDate != nil },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        movieDescriptor.fetchLimit = 15
        let movies = (try? context.fetch(movieDescriptor)) ?? []
        for movie in movies {
            guard let poster = movie.streamIcon, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: movie.id,
                title: movie.name,
                imageURL: poster,
                type: "movie",
                contentId: movie.tmdbId.map(String.init) ?? movie.id,
                category: category
            ))
        }

        var seriesDescriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.lastWatchedDate != nil },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        seriesDescriptor.fetchLimit = 10
        let series = (try? context.fetch(seriesDescriptor)) ?? []
        for show in series {
            guard let poster = show.cover, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: show.id,
                title: show.name,
                imageURL: poster,
                type: "series",
                contentId: show.tmdbId.map(String.init) ?? show.id,
                category: category
            ))
        }

        return Array(result.sorted { ($0.title) < ($1.title) }.prefix(20))
    }

    private static func fetchFavorites(context: ModelContext, category: String) -> [TopShelfItemData] {
        var result: [TopShelfItemData] = []

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.name)]
        )
        movieDescriptor.fetchLimit = 15
        let movies = (try? context.fetch(movieDescriptor)) ?? []
        for movie in movies {
            guard let poster = movie.streamIcon, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: movie.id,
                title: movie.name,
                imageURL: poster,
                type: "movie",
                contentId: movie.tmdbId.map(String.init) ?? movie.id,
                category: category
            ))
        }

        var seriesDescriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.name)]
        )
        seriesDescriptor.fetchLimit = 10
        let series = (try? context.fetch(seriesDescriptor)) ?? []
        for show in series {
            guard let poster = show.cover, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: show.id,
                title: show.name,
                imageURL: poster,
                type: "series",
                contentId: show.tmdbId.map(String.init) ?? show.id,
                category: category
            ))
        }

        return Array(result.prefix(20))
    }

    private static func fetchTrending(context: ModelContext, category: String) -> [TopShelfItemData] {
        // Use highest-rated content as a proxy for trending
        var result: [TopShelfItemData] = []

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.rating > 6.0 },
            sortBy: [SortDescriptor(\.rating, order: .reverse)]
        )
        movieDescriptor.fetchLimit = 20
        let movies = (try? context.fetch(movieDescriptor)) ?? []
        for movie in movies {
            guard let poster = movie.streamIcon, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: movie.id,
                title: movie.name,
                imageURL: poster,
                type: "movie",
                contentId: movie.tmdbId.map(String.init) ?? movie.id,
                category: category
            ))
        }

        return Array(result.prefix(20))
    }

    private static func fetchContinueWatching(context: ModelContext, category: String) -> [TopShelfItemData] {
        var result: [TopShelfItemData] = []

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.watchProgress > 0 && $0.watchProgress < 0.9 },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        movieDescriptor.fetchLimit = 15
        let movies = (try? context.fetch(movieDescriptor)) ?? []
        for movie in movies {
            guard let poster = movie.streamIcon, !poster.isEmpty else { continue }
            result.append(TopShelfItemData(
                id: movie.id,
                title: movie.name,
                imageURL: poster,
                type: "movie",
                contentId: movie.tmdbId.map(String.init) ?? movie.id,
                category: category
            ))
        }

        return Array(result.prefix(20))
    }
}

import TVServices

#endif
