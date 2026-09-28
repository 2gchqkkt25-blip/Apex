//
//  OtherSources.swift
//  Apex
//
//  Resolves other entries of the *same* title (matched by TMDB id) within the
//  same playlist — e.g. an alternate quality or language stream. Shared by the
//  movie and series detail screens (iOS, macOS and tvOS) so the "Other Sources"
//  row behaves identically everywhere.
//

import Foundation
import SwiftData

enum OtherSources {
    /// All playable sources for a movie across every configured playlist and
    /// media server, matched by TMDB id. Returns an empty array when the movie
    /// has no TMDB id or is the only copy. The current movie is included so the
    /// picker can show it alongside alternatives with its source label.
    static func resolveCrossSource(for movie: Movie, in context: ModelContext) -> [HomeMediaItem] {
        guard let tmdbId = movie.tmdbId else { return [] }
        let matches = (try? context.fetch(
            FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
        )) ?? []
        // Include the current movie so the picker always shows at least one
        // option with its source label; callers filter it out if they only
        // want *other* sources.
        return matches.map { .movie($0) }
    }

    /// All playable sources for a series across every configured playlist and
    /// media server, matched by TMDB id. Same semantics as the movie variant.
    static func resolveCrossSource(for series: Series, in context: ModelContext) -> [HomeMediaItem] {
        guard let tmdbId = series.tmdbId else { return [] }
        let matches = (try? context.fetch(
            FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
        )) ?? []
        return matches.map { .series($0) }
    }

    /// Legacy same-playlist-only resolution. Kept for backwards compatibility
    /// with existing "Other Sources" rows that intentionally scope to the
    /// current playlist (alternate quality/language within one provider).
    static func resolve(for movie: Movie, in context: ModelContext) -> [HomeMediaItem] {
        guard let tmdbId = movie.tmdbId else { return [] }
        let prefix = movie.id.components(separatedBy: "-movie-").first
        let matches = (try? context.fetch(
            FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
        )) ?? []
        return matches
            .filter { samePlaylist($0.id, as: prefix) && $0.id != movie.id }
            .map { .movie($0) }
    }

    static func resolve(for series: Series, in context: ModelContext) -> [HomeMediaItem] {
        guard let tmdbId = series.tmdbId else { return [] }
        let prefix = series.id.components(separatedBy: "-series-").first
        let matches = (try? context.fetch(
            FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
        )) ?? []
        return matches
            .filter { samePlaylist($0.id, as: prefix) && $0.id != series.id }
            .map { .series($0) }
    }

    /// Whether `id` belongs to the same playlist as `prefix` (the `<uuid>` part of
    /// a content id). A nil prefix means the owner couldn't be determined — in
    /// that case keep the match rather than hiding everything.
    private static func samePlaylist(_ id: String, as prefix: String?) -> Bool {
        guard let prefix else { return true }
        return id.hasPrefix(prefix)
    }
}
