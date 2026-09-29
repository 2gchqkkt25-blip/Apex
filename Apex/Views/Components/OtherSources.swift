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
    /// media server. Matches TMDB id, IMDb id, and — for Jellyfin, Emby, and
    /// Plex — the cleaned title and year. Media servers often have the file
    /// without a TMDB id, so title matching is what puts them in the picker.
    /// The current movie is included so the picker can show it alongside
    /// alternatives with its source label.
    static func resolveCrossSource(for movie: Movie, in context: ModelContext) -> [HomeMediaItem] {
        var chosen: [String: Movie] = [movie.id: movie]
        if let tmdbId = movie.tmdbId {
            let matches = (try? context.fetch(
                FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
            )) ?? []
            for match in matches { chosen[match.id] = match }
        }
        if let imdbId = canonicalIMDb(movie.imdbId) {
            let matches = (try? context.fetch(
                FetchDescriptor<Movie>(predicate: #Predicate { $0.imdbId == imdbId })
            )) ?? []
            for match in matches { chosen[match.id] = match }
        }
        let query = ContentIndexText.searchQuery(for: movie.name)
        let year = query.year ?? ContentIndexText.year(fromReleaseDate: movie.releaseDate)
        for candidate in catalogMovies(matching: movie.name, in: context)
            where sameTitle(candidate.name, as: query.title, year: year, releaseDate: candidate.releaseDate)
        {
            chosen[candidate.id] = candidate
        }
        return keepingEnabled(chosen.values.map { .movie($0) }, in: context)
    }

    /// Opens the source list only when there is a real choice: a media server
    /// is turned on, or the title is already on more than one enabled playlist.
    /// With no server on and a single Xtream, M3U, or Stalker playlist, Play
    /// starts that copy immediately.
    @MainActor
    static func playbackChoice(
        for movie: Movie,
        playlists: [Playlist],
        mediaServers: [MediaServer],
        in context: ModelContext
    ) -> CrossSourcePrompt? {
        guard offersSourceChoice(playlists: playlists, mediaServers: mediaServers) else { return nil }
        let local = resolveCrossSource(for: movie, in: context)
        let lookup = mediaServers.contains(where: \.syncEnabled) && serverIsMissing(from: local, in: context)
        guard lookup || distinctSourceCount(in: local) > 1 else { return nil }
        return CrossSourcePrompt(
            items: local,
            currentID: movie.id,
            playlists: playlists,
            mediaServers: mediaServers,
            lookupMovie: lookup ? movie : nil
        )
    }

    /// Every playlist copy, plus a live lookup on any configured media server
    /// that does not already have this title saved.
    @MainActor
    static func resolvedSources(for movie: Movie, in context: ModelContext) async -> [HomeMediaItem] {
        let local = resolveCrossSource(for: movie, in: context)
        var chosen = Dictionary(uniqueKeysWithValues: local.compactMap { item -> (String, HomeMediaItem)? in
            guard case let .movie(match) = item else { return nil }
            return (match.id, item)
        })
        let queries = serverQueries(for: movie.name)
        for query in queries where serverIsMissing(from: Array(chosen.values), in: context) {
            let imported = await MediaServerCatalogSearch.importMatches(
                query: query,
                context: context,
                timeout: .seconds(20)
            )
            mergeMovies(imported.movies, into: &chosen, matching: movie)
        }
        return Array(chosen.values)
    }

    /// All playable sources for a series across every configured playlist and
    /// media server. Same matching rules as the movie variant.
    static func resolveCrossSource(for series: Series, in context: ModelContext) -> [HomeMediaItem] {
        var chosen: [String: Series] = [series.id: series]
        if let tmdbId = series.tmdbId {
            let matches = (try? context.fetch(
                FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
            )) ?? []
            for match in matches { chosen[match.id] = match }
        }
        if let imdbId = canonicalIMDb(series.imdbId) {
            let matches = (try? context.fetch(
                FetchDescriptor<Series>(predicate: #Predicate { $0.imdbId == imdbId })
            )) ?? []
            for match in matches { chosen[match.id] = match }
        }
        let query = ContentIndexText.searchQuery(for: series.name)
        let year = query.year ?? ContentIndexText.year(fromReleaseDate: series.releaseDate)
        for candidate in catalogSeries(matching: series.name, in: context)
            where sameTitle(candidate.name, as: query.title, year: year, releaseDate: candidate.releaseDate)
        {
            chosen[candidate.id] = candidate
        }
        return keepingEnabled(chosen.values.map { .series($0) }, in: context)
    }

    /// Series counterpart of ``playbackChoice(for:playlists:mediaServers:in:)``.
    @MainActor
    static func playbackChoice(
        for series: Series,
        playlists: [Playlist],
        mediaServers: [MediaServer],
        in context: ModelContext
    ) -> CrossSourcePrompt? {
        guard offersSourceChoice(playlists: playlists, mediaServers: mediaServers) else { return nil }
        let local = resolveCrossSource(for: series, in: context)
        let lookup = mediaServers.contains(where: \.syncEnabled) && serverIsMissing(from: local, in: context)
        guard lookup || distinctSourceCount(in: local) > 1 else { return nil }
        return CrossSourcePrompt(
            items: local,
            currentID: series.id,
            playlists: playlists,
            mediaServers: mediaServers,
            lookupSeries: lookup ? series : nil
        )
    }

    /// Series counterpart of ``resolvedSources(for:in:)`` for movies.
    @MainActor
    static func resolvedSources(for series: Series, in context: ModelContext) async -> [HomeMediaItem] {
        let local = resolveCrossSource(for: series, in: context)
        var chosen = Dictionary(uniqueKeysWithValues: local.compactMap { item -> (String, HomeMediaItem)? in
            guard case let .series(match) = item else { return nil }
            return (match.id, item)
        })
        for query in serverQueries(for: series.name) where serverIsMissing(from: Array(chosen.values), in: context) {
            let imported = await MediaServerCatalogSearch.importMatches(
                query: query,
                context: context,
                timeout: .seconds(20)
            )
            mergeSeries(imported.series, into: &chosen, matching: series)
        }
        return Array(chosen.values)
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

    /// Drop copies from a media server or playlist the user has turned off.
    /// The login and library stay saved.
    private static func keepingEnabled(_ items: [HomeMediaItem], in context: ModelContext) -> [HomeMediaItem] {
        let enabledServers = Set(
            ((try? context.fetch(FetchDescriptor<MediaServer>())) ?? [])
                .filter(\.syncEnabled)
                .map(\.id)
        )
        let enabledPlaylists = Set(
            ((try? context.fetch(FetchDescriptor<Playlist>())) ?? [])
                .filter(\.syncEnabled)
                .map { $0.id.uuidString.lowercased() }
        )
        return items.filter { item in
            let catalogID: String
            let fromServer: Bool
            switch item {
            case let .movie(movie):
                fromServer = movie.isMediaServerCatalogItem
                catalogID = movie.id
            case let .series(series):
                fromServer = series.isMediaServerCatalogItem
                catalogID = series.id
            case .live:
                return true
            }
            if fromServer {
                guard let serverID = MediaServerIdentity.parseCatalogID(catalogID)?.serverUUID else { return true }
                return enabledServers.contains(serverID)
            }
            guard let owner = ownerPrefix(catalogID)?.lowercased() else { return true }
            return enabledPlaylists.contains(owner)
        }
    }

    /// A source list is worth showing when a media server is on, or when more
    /// than one Xtream, M3U, or Stalker playlist is turned on.
    private static func offersSourceChoice(playlists: [Playlist], mediaServers: [MediaServer]) -> Bool {
        if mediaServers.contains(where: \.syncEnabled) { return true }
        return playlists.filter(\.syncEnabled).count > 1
    }

    /// Playlist owners plus media servers represented in the list. Two copies
    /// from the same playlist count as one source.
    private static func distinctSourceCount(in items: [HomeMediaItem]) -> Int {
        playlistOwnerIDs(in: items).count + representedServerIDs(in: items).count
    }

    private static func playlistOwnerIDs(in items: [HomeMediaItem]) -> Set<String> {
        Set(items.compactMap { item -> String? in
            let catalogID: String
            let fromServer: Bool
            switch item {
            case let .movie(movie):
                fromServer = movie.isMediaServerCatalogItem
                catalogID = movie.id
            case let .series(series):
                fromServer = series.isMediaServerCatalogItem
                catalogID = series.id
            case .live:
                return nil
            }
            guard !fromServer else { return nil }
            return ownerPrefix(catalogID)?.lowercased()
        })
    }

    private static func ownerPrefix(_ id: String) -> String? {
        for marker in ["-movie-", "-series-", "-episode-"] {
            guard let range = id.range(of: marker) else { continue }
            let prefix = String(id[..<range.lowerBound])
            guard !prefix.isEmpty else { continue }
            return prefix
        }
        return nil
    }

    /// True when a configured Jellyfin, Emby, or Plex server is not already in the list.
    @MainActor
    private static func serverIsMissing(from items: [HomeMediaItem], in context: ModelContext) -> Bool {
        let servers = ((try? context.fetch(FetchDescriptor<MediaServer>())) ?? []).filter(\.syncEnabled)
        guard !servers.isEmpty else { return false }
        let covered = representedServerIDs(in: items)
        return servers.contains { !covered.contains($0.id) }
    }

    private static func representedServerIDs(in items: [HomeMediaItem]) -> Set<UUID> {
        Set(items.compactMap { item -> UUID? in
            let catalogID: String
            switch item {
            case let .movie(movie):
                guard movie.isMediaServerCatalogItem else { return nil }
                catalogID = movie.id
            case let .series(series):
                guard series.isMediaServerCatalogItem else { return nil }
                catalogID = series.id
            case .live:
                return nil
            }
            return MediaServerIdentity.parseCatalogID(catalogID)?.serverUUID
        })
    }

    /// Titles to ask a media server for. The article-free form is second, so
    /// "Matrix" is tried when "The Matrix" did not already cover every server.
    private static func serverQueries(for rawName: String) -> [String] {
        let title = ContentIndexText.searchQuery(for: rawName).title
        let stripped = ContentIndexText.stripLeadingArticle(title)
        if stripped.caseInsensitiveCompare(title) == .orderedSame { return [rawName] }
        return [rawName, stripped]
    }

    private static func catalogMovies(matching rawName: String, in context: ModelContext) -> [Movie] {
        var found: [String: Movie] = [:]
        for needle in ContentIndexText.sourceNeedles(for: rawName) {
            let nameQuery = needle
            let candidates = (try? context.fetch(
                FetchDescriptor<Movie>(predicate: #Predicate { $0.name.localizedStandardContains(nameQuery) })
            )) ?? []
            for candidate in candidates { found[candidate.id] = candidate }
        }
        return Array(found.values)
    }

    private static func catalogSeries(matching rawName: String, in context: ModelContext) -> [Series] {
        var found: [String: Series] = [:]
        for needle in ContentIndexText.sourceNeedles(for: rawName) {
            let nameQuery = needle
            let candidates = (try? context.fetch(
                FetchDescriptor<Series>(predicate: #Predicate { $0.name.localizedStandardContains(nameQuery) })
            )) ?? []
            for candidate in candidates { found[candidate.id] = candidate }
        }
        return Array(found.values)
    }

    private static func mergeMovies(
        _ imported: [Movie],
        into chosen: inout [String: HomeMediaItem],
        matching movie: Movie
    ) {
        let query = ContentIndexText.searchQuery(for: movie.name)
        let year = query.year ?? ContentIndexText.year(fromReleaseDate: movie.releaseDate)
        let imdb = canonicalIMDb(movie.imdbId)
        for match in imported {
            let sameName = sameTitle(match.name, as: query.title, year: year, releaseDate: match.releaseDate)
            let sameTMDB = movie.tmdbId != nil && match.tmdbId == movie.tmdbId
            let sameIMDb = imdb != nil && canonicalIMDb(match.imdbId) == imdb
            if sameName || sameTMDB || sameIMDb {
                chosen[match.id] = .movie(match)
            }
        }
    }

    private static func mergeSeries(
        _ imported: [Series],
        into chosen: inout [String: HomeMediaItem],
        matching series: Series
    ) {
        let query = ContentIndexText.searchQuery(for: series.name)
        let year = query.year ?? ContentIndexText.year(fromReleaseDate: series.releaseDate)
        let imdb = canonicalIMDb(series.imdbId)
        for match in imported {
            let sameName = sameTitle(match.name, as: query.title, year: year, releaseDate: match.releaseDate)
            let sameTMDB = series.tmdbId != nil && match.tmdbId == series.tmdbId
            let sameIMDb = imdb != nil && canonicalIMDb(match.imdbId) == imdb
            if sameName || sameTMDB || sameIMDb {
                chosen[match.id] = .series(match)
            }
        }
    }

    /// True when a row is the same title. Years must agree when both sides have one,
    /// so a remake is not offered as the original.
    private static func sameTitle(_ rawName: String, as cleanedTitle: String, year: Int?, releaseDate: String?) -> Bool {
        let left = ContentIndexText.comparableKey(for: cleanedTitle)
        let right = ContentIndexText.comparableKey(for: rawName)
        guard !left.isEmpty, left == right else { return false }
        let other = ContentIndexText.searchQuery(for: rawName)
        let otherYear = other.year ?? ContentIndexText.year(fromReleaseDate: releaseDate)
        if let year, let otherYear, abs(year - otherYear) > 1 { return false }
        return true
    }

    private static func canonicalIMDb(_ raw: String?) -> String? {
        guard var raw, !raw.isEmpty else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("tt") { raw = "tt\(raw)" }
        return raw
    }
}
