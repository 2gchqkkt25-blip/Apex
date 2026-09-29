//
//  MediaServerCatalogSearch.swift
//  Apex
//
//  Asks each configured Jellyfin, Emby, and Plex server for a title and saves
//  the hits into the local catalog. AIOStreams only lists a page of a catalog
//  during sync, so a movie can exist on the server without being on the device
//  until someone searches or presses play.
//

import Foundation
import SwiftData

@MainActor
enum MediaServerCatalogSearch {
    struct Imported {
        var movies: [Movie] = []
        var series: [Series] = []
    }

    /// Searches every configured server and upserts movie and series hits.
    /// Returns the rows on `context`, including ones that were already stored.
    static func importMatches(query: String, context: ModelContext, timeout: Duration = .seconds(8)) async -> Imported {
        let title = ContentIndexText.searchQuery(for: query).title
        guard title.count >= 2 else { return Imported() }
        let servers = serverQueries(in: context)
        guard !servers.isEmpty else { return Imported() }

        let found = await search(servers, query: title, timeout: timeout)
        var imported = Imported()
        for hit in found {
            switch kind(of: hit.item) {
            case .movie:
                if let movie = upsertMovie(hit, context: context) {
                    imported.movies.append(movie)
                }
            case .series:
                if let series = upsertSeries(hit, context: context) {
                    imported.series.append(series)
                }
            case nil:
                continue
            }
        }
        if !imported.movies.isEmpty || !imported.series.isEmpty {
            try? context.save()
        }
        return imported
    }

    private enum Kind { case movie, series }

    private static func kind(of item: MediaServerItem) -> Kind? {
        switch item.type.lowercased() {
        case "movie": return .movie
        case "series", "show": return .series
        default: return nil
        }
    }

    private struct ServerQuery: Sendable {
        let id: UUID
        let kind: MediaServerKind
        let baseURL: URL
        let token: String
        let userId: String
    }

    private struct Hit: Sendable {
        let serverID: UUID
        let kind: MediaServerKind
        let baseURL: URL
        let token: String
        let item: MediaServerItem
    }

    private static func serverQueries(in context: ModelContext) -> [ServerQuery] {
        let servers = (try? context.fetch(FetchDescriptor<MediaServer>())) ?? []
        return servers.compactMap { server in
            guard server.syncEnabled,
                  let baseURL = MediaServerURL.normalize(server.baseURL),
                  let token = server.authToken
            else { return nil }
            return ServerQuery(
                id: server.id,
                kind: server.kind,
                baseURL: baseURL,
                token: token,
                userId: server.userId ?? ""
            )
        }
    }

    private enum SearchBatch: Sendable {
        case hits([Hit])
        case timedOut
    }

    private static func search(_ servers: [ServerQuery], query: String, timeout: Duration) async -> [Hit] {
        await withTaskGroup(of: SearchBatch.self) { group in
            for server in servers {
                group.addTask {
                    let client = MediaServerClientFactory.client(for: server.kind)
                    let items = (try? await client.searchItems(
                        baseURL: server.baseURL,
                        userId: server.userId,
                        token: server.token,
                        query: query,
                        limit: 24
                    )) ?? []
                    let hits = items.map {
                        Hit(serverID: server.id, kind: server.kind, baseURL: server.baseURL, token: server.token, item: $0)
                    }
                    return .hits(hits)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            var hits: [Hit] = []
            var finishedServers = 0
            while let batch = await group.next() {
                switch batch {
                case .timedOut:
                    group.cancelAll()
                    return hits
                case let .hits(found):
                    hits.append(contentsOf: found)
                    finishedServers += 1
                    if finishedServers == servers.count {
                        group.cancelAll()
                        return hits
                    }
                }
            }
            return hits
        }
    }

    private static func upsertMovie(_ hit: Hit, context: ModelContext) -> Movie? {
        let catalogID = MediaServerIdentity.movieID(serverUUID: hit.serverID, remoteID: hit.item.id)
        let existing = fetchMovie(id: catalogID, context: context)
        let client = MediaServerClientFactory.client(for: hit.kind)
        let poster = client.imageURL(
            baseURL: hit.baseURL,
            itemId: hit.item.id,
            imageTag: hit.item.imageTag,
            token: hit.token,
            kind: "Primary"
        )?.absoluteString
        let movie: Movie
        if let existing {
            movie = existing
        } else {
            movie = Movie(
                id: catalogID,
                streamId: hit.item.id.hashValue,
                name: hit.item.name,
                streamIcon: poster,
                rating: 0,
                categoryId: MediaServerIdentity.libraryCategoryID(serverUUID: hit.serverID, libraryID: "search")
            )
            context.insert(movie)
            movie.directURL = "mediaserver:///\(hit.serverID.uuidString)/\(hit.item.id)/movie"
            movie.added = "search"
            movie.indexedAt = Date()
        }
        if movie.tmdbId == nil { movie.tmdbId = hit.item.providerTMDBId }
        if (movie.imdbId ?? "").isEmpty { movie.imdbId = hit.item.providerIMDBId }
        if (movie.plot ?? "").isEmpty { movie.plot = hit.item.overview }
        if (movie.genre ?? "").isEmpty, !hit.item.genres.isEmpty {
            movie.genre = hit.item.genres.joined(separator: ", ")
        }
        if (movie.releaseDate ?? "").isEmpty, let year = hit.item.productionYear {
            movie.releaseDate = String(year)
        }
        if movie.streamIcon == nil { movie.streamIcon = poster }
        return movie
    }

    private static func upsertSeries(_ hit: Hit, context: ModelContext) -> Series? {
        let catalogID = MediaServerIdentity.seriesID(serverUUID: hit.serverID, remoteID: hit.item.id)
        let existing = fetchSeries(id: catalogID, context: context)
        let client = MediaServerClientFactory.client(for: hit.kind)
        let poster = client.imageURL(
            baseURL: hit.baseURL,
            itemId: hit.item.id,
            imageTag: hit.item.imageTag,
            token: hit.token,
            kind: "Primary"
        )?.absoluteString
        let series: Series
        if let existing {
            series = existing
        } else {
            series = Series(
                id: catalogID,
                seriesId: hit.item.id.hashValue,
                name: hit.item.name,
                cover: poster,
                categoryId: MediaServerIdentity.libraryCategoryID(serverUUID: hit.serverID, libraryID: "search")
            )
            context.insert(series)
            series.lastModified = "search"
            series.indexedAt = Date()
        }
        if series.tmdbId == nil { series.tmdbId = hit.item.providerTMDBId }
        if (series.imdbId ?? "").isEmpty { series.imdbId = hit.item.providerIMDBId }
        if (series.plot ?? "").isEmpty { series.plot = hit.item.overview }
        if (series.genre ?? "").isEmpty, !hit.item.genres.isEmpty {
            series.genre = hit.item.genres.joined(separator: ", ")
        }
        if (series.releaseDate ?? "").isEmpty, let year = hit.item.productionYear {
            series.releaseDate = String(year)
        }
        if series.cover == nil { series.cover = poster }
        return series
    }

    private static func fetchMovie(id: String, context: ModelContext) -> Movie? {
        var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchSeries(id: String, context: ModelContext) -> Series? {
        var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
