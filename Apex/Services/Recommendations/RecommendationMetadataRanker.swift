//
//  RecommendationMetadataRanker.swift
//  Apex
//
//  Genre- and TMDB-similarity fallback for the "For You" row when the on-device
//  embedding model is unavailable (tvOS, some simulators). Uses provider/TMDB
//  genre strings, ratings, and "similar titles" ids already on catalog models.
//

import Foundation
import SwiftData

nonisolated enum RecommendationMetadataRanker {
    struct TasteProfile {
        /// Normalized genre → accumulated taste weight.
        var genreWeights: [String: Float]
        /// Genres the user has rejected via thumbs-down.
        var dislikedGenreWeights: [String: Float]
        /// TMDB ids of titles the user liked (favorite, watch, upvote).
        var likedTMDBIds: Set<Int>
        /// TMDB "similar" ids harvested from liked titles' enrichment.
        var similarTMDBIds: Set<Int>
    }

    /// Parses a provider/TMDB genre field into normalized tokens.
    static func normalizedGenres(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty else { return [] }
        return Set(
            raw.split { $0 == "," || $0 == "|" || $0 == "/" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static func buildProfile(
        context: ModelContext,
        signalLimit: Int,
        favoriteWeight: Float,
        watchedWeight: Float,
        upvote: Int,
        downvote: Int
    ) -> TasteProfile? {
        var genreWeights: [String: Float] = [:]
        var dislikedGenreWeights: [String: Float] = [:]
        var likedTMDBIds = Set<Int>()
        var similarTMDBIds = Set<Int>()
        var hasSignal = false

        func absorb(genres: Set<String>, weight: Float, into bucket: inout [String: Float]) {
            guard weight > 0, !genres.isEmpty else { return }
            hasSignal = true
            for genre in genres {
                bucket[genre, default: 0] += weight
            }
        }

        var movies = FetchDescriptor<Movie>(
            predicate: #Predicate {
                $0.recommendationVoteRaw != downvote
                    && ($0.isFavorite || $0.isWatched || $0.lastWatchedDate != nil || $0.recommendationVoteRaw == upvote)
            },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        movies.fetchLimit = signalLimit
        for movie in (try? context.fetch(movies)) ?? [] {
            let weight = (movie.isFavorite || movie.recommendationVoteRaw == upvote) ? favoriteWeight : watchedWeight
            absorb(genres: normalizedGenres(movie.genre), weight: weight, into: &genreWeights)
            if let tmdbId = movie.tmdbId {
                likedTMDBIds.insert(tmdbId)
                similarTMDBIds.formUnion(movie.similarTMDBIds)
            }
            if movie.recommendationVoteRaw == downvote {
                absorb(genres: normalizedGenres(movie.genre), weight: 1, into: &dislikedGenreWeights)
            }
        }

        var series = FetchDescriptor<Series>(
            predicate: #Predicate {
                $0.recommendationVoteRaw != downvote
                    && ($0.isFavorite || $0.lastWatchedDate != nil || $0.recommendationVoteRaw == upvote)
            },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        series.fetchLimit = signalLimit
        for show in (try? context.fetch(series)) ?? [] {
            let weight = (show.isFavorite || show.recommendationVoteRaw == upvote) ? favoriteWeight : watchedWeight
            absorb(genres: normalizedGenres(show.genre), weight: weight, into: &genreWeights)
            if let tmdbId = show.tmdbId {
                likedTMDBIds.insert(tmdbId)
                similarTMDBIds.formUnion(show.similarTMDBIds)
            }
            if show.recommendationVoteRaw == downvote {
                absorb(genres: normalizedGenres(show.genre), weight: 1, into: &dislikedGenreWeights)
            }
        }

        // Downvotes on titles that weren't positive signals.
        let downMovies = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.recommendationVoteRaw == downvote }
        )
        for movie in (try? context.fetch(downMovies)) ?? [] {
            absorb(genres: normalizedGenres(movie.genre), weight: 1, into: &dislikedGenreWeights)
        }
        let downSeries = FetchDescriptor<Series>(
            predicate: #Predicate { $0.recommendationVoteRaw == downvote }
        )
        for show in (try? context.fetch(downSeries)) ?? [] {
            absorb(genres: normalizedGenres(show.genre), weight: 1, into: &dislikedGenreWeights)
        }

        guard hasSignal else { return nil }
        return TasteProfile(
            genreWeights: genreWeights,
            dislikedGenreWeights: dislikedGenreWeights,
            likedTMDBIds: likedTMDBIds,
            similarTMDBIds: similarTMDBIds
        )
    }

    static func scoreMovie(_ movie: Movie, profile: TasteProfile) -> Float {
        score(
            genres: normalizedGenres(movie.genre),
            tmdbId: movie.tmdbId,
            rating: movie.rating > 0 ? movie.rating : movie.rating5Based * 2,
            profile: profile
        )
    }

    static func scoreSeries(_ series: Series, profile: TasteProfile) -> Float {
        let rating = Double(series.rating ?? "") ?? (Double(series.rating5Based ?? "") ?? 0) * 2
        return score(
            genres: normalizedGenres(series.genre),
            tmdbId: series.tmdbId,
            rating: rating,
            profile: profile
        )
    }

    static func rankCandidates(
        limit: Int,
        context: ModelContext,
        profile: TasteProfile,
        pageSize: Int,
        downvote: Int
    ) -> [ScoredRecommendation] {
        var top: [(item: ScoredRecommendation, score: Float)] = []

        func consider(_ id: String, _ kind: RecommendedKind, _ score: Float) {
            guard top.count < limit || score > top.last!.score else { return }
            top.append((ScoredRecommendation(id: id, kind: kind), score))
            top.sort { $0.score > $1.score }
            if top.count > limit { top.removeLast() }
        }

        var movieOffset = 0
        while true {
            var descriptor = FetchDescriptor<Movie>(
                predicate: #Predicate {
                    !$0.isWatched && !$0.isFavorite && $0.lastWatchedDate == nil && $0.recommendationVoteRaw == 0
                },
                sortBy: [SortDescriptor(\.id)]
            )
            descriptor.fetchOffset = movieOffset
            descriptor.fetchLimit = pageSize
            let page = (try? context.fetch(descriptor)) ?? []
            for movie in page {
                consider(movie.id, .movie, scoreMovie(movie, profile: profile))
            }
            if page.count < pageSize { break }
            movieOffset += pageSize
        }

        var seriesOffset = 0
        while true {
            var descriptor = FetchDescriptor<Series>(
                predicate: #Predicate {
                    !$0.isFavorite && $0.lastWatchedDate == nil && $0.recommendationVoteRaw == 0
                },
                sortBy: [SortDescriptor(\.id)]
            )
            descriptor.fetchOffset = seriesOffset
            descriptor.fetchLimit = pageSize
            let page = (try? context.fetch(descriptor)) ?? []
            for show in page {
                consider(show.id, .series, scoreSeries(show, profile: profile))
            }
            if page.count < pageSize { break }
            seriesOffset += pageSize
        }

        return top.map(\.item)
    }

    private static func score(
        genres: Set<String>,
        tmdbId: Int?,
        rating: Double,
        profile: TasteProfile
    ) -> Float {
        var value: Float = 0
        for genre in genres {
            value += profile.genreWeights[genre, default: 0]
            value -= profile.dislikedGenreWeights[genre, default: 0] * 0.5
        }
        if let tmdbId, profile.similarTMDBIds.contains(tmdbId) {
            value += 3
        }
        if let tmdbId, profile.likedTMDBIds.contains(tmdbId) {
            value -= 10 // shouldn't happen — filtered — but guard anyway
        }
        if rating > 0 {
            value += Float(min(rating, 10)) * 0.05
        }
        return value
    }
}
