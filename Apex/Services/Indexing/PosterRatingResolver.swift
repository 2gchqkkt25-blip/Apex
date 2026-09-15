//
//  PosterRatingResolver.swift
//  Apex
//
//  Prioritizes lightweight TMDB rating lookups for visible poster cards that
//  the catalog-wide post-sync pass has not reached yet.
//

import Foundation
import SwiftData

@MainActor
final class PosterRatingSaveCoordinator {
    static let shared = PosterRatingSaveCoordinator()

    private var pendingSave: Task<Void, Never>?

    private init() {}

    /// Coalesce visible-card updates into one save. Saving once per poster can
    /// repeatedly invalidate large SwiftData queries while the tvOS focus
    /// engine is animating between cards.
    func schedule(context: ModelContext) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? context.save()
            self?.pendingSave = nil
        }
    }
}

actor PosterRatingResolver {
    static let shared = PosterRatingResolver()

    struct Match: Sendable {
        let tmdbID: Int
        let score: Double
    }

    private let client = TMDBClient.shared
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var inFlight: [String: Task<Match?, Never>] = [:]

    #if os(tvOS)
        private let maxConcurrentRequests = 2
    #else
        private let maxConcurrentRequests = 4
    #endif

    private enum Kind: String, Sendable {
        case movie
        case series
    }

    func movieRating(
        catalogID: String,
        tmdbID: Int?,
        title: String,
        releaseDate: String?
    ) async -> Match? {
        await rating(
            kind: .movie,
            catalogID: catalogID,
            tmdbID: tmdbID,
            title: title,
            releaseDate: releaseDate
        )
    }

    func seriesRating(
        catalogID: String,
        tmdbID: Int?,
        title: String,
        releaseDate: String?
    ) async -> Match? {
        await rating(
            kind: .series,
            catalogID: catalogID,
            tmdbID: tmdbID,
            title: title,
            releaseDate: releaseDate
        )
    }

    private func rating(
        kind: Kind,
        catalogID: String,
        tmdbID: Int?,
        title: String,
        releaseDate: String?
    ) async -> Match? {
        let requestID = "\(kind.rawValue):\(catalogID)"
        if let task = inFlight[requestID] {
            return await task.value
        }

        let task = Task<Match?, Never> { [client] in
            await self.acquirePermit()
            if Task.isCancelled {
                self.releasePermit()
                return nil
            }
            let result = await Self.resolve(
                client: client,
                kind: kind,
                tmdbID: tmdbID,
                title: title,
                releaseDate: releaseDate
            )
            self.releasePermit()
            return result
        }
        inFlight[requestID] = task
        let result = await task.value
        inFlight[requestID] = nil
        return result
    }

    private func acquirePermit() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releasePermit() {
        if waiters.isEmpty {
            activeRequests = max(0, activeRequests - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }

    private nonisolated static func resolve(
        client: TMDBClient,
        kind: Kind,
        tmdbID: Int?,
        title: String,
        releaseDate: String?
    ) async -> Match? {
        let query = ContentIndexText.searchQuery(for: title)
        let year = ContentIndexText.year(fromReleaseDate: releaseDate) ?? query.year

        for attempt in 0 ..< 3 {
            do {
                if let tmdbID, tmdbID > 0 {
                    let score = switch kind {
                    case .movie: try await client.movieRating(tmdbID)
                    case .series: try await client.tvRating(tmdbID)
                    }
                    if let score, score > 0 {
                        return Match(tmdbID: tmdbID, score: score)
                    }
                }

                let match: (id: Int, voteAverage: Double?)? = switch kind {
                case .movie:
                    if let result = try await client.searchMovie(query: query.title, year: year) {
                        result
                    } else if year != nil,
                              let result = try await client.searchMovie(query: query.title, year: nil)
                    {
                        result
                    } else if query.title != title {
                        try await client.searchMovie(query: title, year: nil)
                    } else {
                        nil
                    }
                case .series:
                    if let result = try await client.searchTV(query: query.title, year: year) {
                        result
                    } else if year != nil,
                              let result = try await client.searchTV(query: query.title, year: nil)
                    {
                        result
                    } else if query.title != title {
                        try await client.searchTV(query: title, year: nil)
                    } else {
                        nil
                    }
                }

                guard let match else { return nil }
                if let score = match.voteAverage, score > 0 {
                    return Match(tmdbID: match.id, score: score)
                }
                let score = switch kind {
                case .movie: try await client.movieRating(match.id)
                case .series: try await client.tvRating(match.id)
                }
                if let score, score > 0 {
                    return Match(tmdbID: match.id, score: score)
                }
                return nil
            } catch TMDBError.serverError(429) where attempt < 2 {
                try? await Task.sleep(for: .seconds(attempt + 1))
            } catch {
                // A provider-supplied id can be stale or belong to a movie.
                // Retry once without it so title matching still gets a chance.
                if tmdbID != nil {
                    return await resolve(
                        client: client,
                        kind: kind,
                        tmdbID: nil,
                        title: title,
                        releaseDate: releaseDate
                    )
                }
                return nil
            }
        }
        return nil
    }
}
