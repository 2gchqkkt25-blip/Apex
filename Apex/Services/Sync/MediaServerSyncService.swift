//
//  MediaServerSyncService.swift
//  Apex
//
//  Syncs Jellyfin / Emby / Plex libraries into the local catalog using
//  `{serverUUID}-movie-…` ids so IPTV tabs stay scoped to playlists only.
//

import Foundation
import OSLog
import Observation
import SwiftData

@MainActor
@Observable
final class MediaServerSyncService {
    static let shared = MediaServerSyncService()

    private(set) var isSyncing = false
    private(set) var syncingServerID: UUID?
    private(set) var progressDetail: String = ""
    private(set) var progressFraction: Double = 0

    func sync(server: MediaServer, container: ModelContainer) async throws {
        guard !isSyncing else { return }

        let snapshot = MediaServerSyncSnapshot(server: server)
        let serverID = server.id

        ContentIndexingService.shared.prepareForMediaSync()
        defer {
            ContentIndexingService.shared.mediaSyncFinished()
            isSyncing = false
            syncingServerID = nil
            progressDetail = ""
            progressFraction = 0
        }

        isSyncing = true
        syncingServerID = serverID
        progressDetail = "Connecting…"
        progressFraction = 0

        // Relax tvOS catalog limits during dedicated sync — the player isn't
        // loaded so memory headroom exists for larger pages and bigger batches.
        MediaServerCatalogLimits.syncActive = true
        defer { MediaServerCatalogLimits.syncActive = false }

        let outcome = try await Task.detached(priority: .utility) {
            try await MediaServerSyncRunner.run(
                snapshot: snapshot,
                container: container,
                reportProgress: { detail, fraction in
                    Task { @MainActor in
                        MediaServerSyncService.shared.progressDetail = detail
                        MediaServerSyncService.shared.progressFraction = fraction
                    }
                }
            )
        }.value

        let finishContext = ModelContext(container)
        finishContext.autosaveEnabled = false
        guard let local = try? finishContext.fetch(FetchDescriptor<MediaServer>(
            predicate: #Predicate { $0.id == serverID }
        )).first else { return }

        if let resolvedBaseURL = outcome.resolvedBaseURL {
            local.baseURL = resolvedBaseURL
        }
        if let resolvedIdentifier = outcome.resolvedPlexIdentifier {
            local.plexServerIdentifier = resolvedIdentifier
        }
        if let resolvedName = outcome.resolvedName, local.name.isEmpty || local.name == "Plex" {
            local.name = resolvedName
        }
        local.lastSyncDate = Date()
        local.syncStatus = .idle
        try finishContext.save()
        progressFraction = 1
        progressDetail = outcome.partialPass ? "Partial sync — tap Sync to continue" : "Done"
        Logger.database.info(
            "Media server sync \(outcome.partialPass ? "partial" : "complete", privacy: .public): \(local.name, privacy: .public) — \(outcome.importedMovies) movies, \(outcome.importedSeries) series"
        )
    }

    func deleteServer(_ server: MediaServer, container: ModelContainer) throws {
        let ctx = ModelContext(container)
        MediaServerDeletion.delete(server, in: ctx)
        try ctx.save()
        Logger.database.info("Deleted media server \(server.id.uuidString, privacy: .public)")
    }

    /// Lazy-load seasons/episodes for a series detail screen.
    func loadEpisodes(for series: Series, server: MediaServer, container: ModelContainer) async throws {
        guard let baseURL = MediaServerURL.normalize(server.baseURL),
              let token = server.authToken,
              let userId = server.userId
        else { return }

        guard let parsed = MediaServerIdentity.parseCatalogID(series.id) else { return }
        let remoteSeriesId = parsed.remoteID
        guard !remoteSeriesId.isEmpty else { return }

        let client = MediaServerClientFactory.client(for: server.kind)
        let seasons = try await client.seasons(baseURL: baseURL, userId: userId, token: token, seriesId: remoteSeriesId)
        let seriesID = series.id

        for season in seasons {
            let seasonRemoteId = season.id
            let episodes = try await client.episodes(
                baseURL: baseURL,
                userId: userId,
                token: token,
                seriesId: remoteSeriesId,
                seasonId: seasonRemoteId
            )
            guard !episodes.isEmpty else { continue }

            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            let existingEpisodes = try ctx.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.series?.id == seriesID }))
            var episodeCache = Dictionary(uniqueKeysWithValues: existingEpisodes.map { ($0.id, $0) })

            for ep in episodes {
                let catalogID = MediaServerIdentity.episodeID(serverUUID: server.id, remoteID: ep.id)
                let episode: Episode
                if let existing = episodeCache[catalogID] {
                    episode = existing
                } else {
                    episode = Episode(
                        id: catalogID,
                        episodeId: ep.id,
                        title: ep.name,
                        containerExtension: "mp4",
                        seasonNum: ep.parentIndexNumber ?? season.indexNumber ?? 1,
                        episodeNum: ep.indexNumber ?? 1,
                        series: series
                    )
                    episode.series = series
                    ctx.insert(episode)
                    episodeCache[catalogID] = episode
                }
                episode.title = ep.name
                if !MediaServerCatalogLimits.liteMetadataDuringSync {
                    episode.plot = ep.overview
                }
                episode.seasonNum = ep.parentIndexNumber ?? season.indexNumber ?? 1
                episode.episodeNum = ep.indexNumber ?? 1
                episode.durationSecs = ep.runTimeTicks.map { Int($0 / 10_000_000) }
                episode.directSource = "mediaserver:///\(server.id.uuidString)/\(ep.id)/episode"
                if let ud = ep.userData {
                    episode.isWatched = ud.played
                    episode.watchProgress = Double(ud.playbackPositionTicks) / 10_000_000
                    episode.lastWatchedDate = ud.lastPlayedDate
                }
            }
            try ctx.save()
            await Task.yield()
        }
    }
}

// MARK: - Background runner

private struct MediaServerSyncSnapshot: Sendable {
    let id: UUID
    let kind: MediaServerKind
    let name: String
    let baseURL: String
    let userId: String
    let authToken: String
    let plexToken: String?
    let plexServerIdentifier: String?

    init(server: MediaServer) {
        id = server.id
        kind = server.kind
        name = server.name
        baseURL = server.baseURL
        userId = server.userId ?? ""
        authToken = server.authToken ?? ""
        plexToken = server.plexToken
        plexServerIdentifier = server.plexServerIdentifier
    }
}

private struct MediaServerSyncOutcome: Sendable {
    var resolvedBaseURL: String?
    var resolvedPlexIdentifier: String?
    var resolvedName: String?
    var importedMovies = 0
    var importedSeries = 0
    var partialPass = false
}

private enum MediaServerSyncRunner {
    static func run(
        snapshot: MediaServerSyncSnapshot,
        container: ModelContainer,
        reportProgress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> MediaServerSyncOutcome {
        guard !snapshot.authToken.isEmpty, !snapshot.userId.isEmpty else {
            throw MediaServerError.invalidURL
        }

        var outcome = MediaServerSyncOutcome()
        var baseURLString = snapshot.baseURL
        guard var baseURL = MediaServerURL.normalize(baseURLString) else {
            throw MediaServerError.invalidURL
        }

        if snapshot.kind == .plex, let plexToken = snapshot.plexToken {
            reportProgress("Finding server…", 0)
            let plex = PlexClient()
            let resolved = try await plex.resolveReachableConnection(
                token: plexToken,
                preferredIdentifier: snapshot.plexServerIdentifier,
                manualURL: snapshot.baseURL.contains(".plex.direct") ? nil : snapshot.baseURL,
                currentURL: snapshot.baseURL
            )
            baseURL = resolved.url
            baseURLString = resolved.url.absoluteString
            outcome.resolvedBaseURL = baseURLString
            outcome.resolvedPlexIdentifier = resolved.identifier
            outcome.resolvedName = resolved.name
        }

        let client = MediaServerClientFactory.client(for: snapshot.kind)
        let libraries = try await client.listLibraries(
            baseURL: baseURL,
            userId: snapshot.userId,
            token: snapshot.authToken
        )

        let syncStamp = UUID().uuidString
        let pageSize = MediaServerCatalogLimits.syncPageSize
        let itemCap = MediaServerCatalogLimits.maxItemsPerSyncPass
        var importedTotal = 0

        reportProgress("Loading catalog…", 0.05)

        let totalLibraries = max(libraries.count, 1)
        for (index, library) in libraries.enumerated() {
            guard !Task.isCancelled else { break }
            if let itemCap, importedTotal >= itemCap {
                outcome.partialPass = true
                break
            }

            let libraryBaseFraction = 0.05 + (Double(index) / Double(totalLibraries)) * 0.85
            let librarySpan = 0.85 / Double(totalLibraries)
            let collectionType = library.collectionType?.lowercased() ?? ""

            if collectionType.contains("movie") || collectionType == "movies" {
                let added = try await importMovies(
                    client: client,
                    baseURL: baseURL,
                    userId: snapshot.userId,
                    token: snapshot.authToken,
                    library: library,
                    serverUUID: snapshot.id,
                    syncStamp: syncStamp,
                    container: container,
                    pageSize: pageSize,
                    importedTotal: &importedTotal,
                    itemCap: itemCap,
                    baseFraction: libraryBaseFraction,
                    spanFraction: librarySpan,
                    reportProgress: reportProgress
                )
                outcome.importedMovies += added
            } else if collectionType.contains("tv") || collectionType.contains("show") || collectionType == "series" {
                let added = try await importSeries(
                    client: client,
                    baseURL: baseURL,
                    userId: snapshot.userId,
                    token: snapshot.authToken,
                    library: library,
                    serverUUID: snapshot.id,
                    syncStamp: syncStamp,
                    container: container,
                    pageSize: pageSize,
                    importedTotal: &importedTotal,
                    itemCap: itemCap,
                    baseFraction: libraryBaseFraction,
                    spanFraction: librarySpan,
                    reportProgress: reportProgress
                )
                outcome.importedSeries += added
            } else {
                let movieAdded = try await importMovies(
                    client: client,
                    baseURL: baseURL,
                    userId: snapshot.userId,
                    token: snapshot.authToken,
                    library: library,
                    serverUUID: snapshot.id,
                    syncStamp: syncStamp,
                    container: container,
                    pageSize: pageSize,
                    importedTotal: &importedTotal,
                    itemCap: itemCap,
                    types: ["Movie"],
                    baseFraction: libraryBaseFraction,
                    spanFraction: librarySpan * 0.5,
                    reportProgress: reportProgress
                )
                outcome.importedMovies += movieAdded
                if itemCap == nil || importedTotal < itemCap! {
                    let seriesAdded = try await importSeries(
                        client: client,
                        baseURL: baseURL,
                        userId: snapshot.userId,
                        token: snapshot.authToken,
                        library: library,
                        serverUUID: snapshot.id,
                        syncStamp: syncStamp,
                        container: container,
                        pageSize: pageSize,
                        importedTotal: &importedTotal,
                        itemCap: itemCap,
                        types: ["Series"],
                        baseFraction: libraryBaseFraction + librarySpan * 0.5,
                        spanFraction: librarySpan * 0.5,
                        reportProgress: reportProgress
                    )
                    outcome.importedSeries += seriesAdded
                }
            }

            if let itemCap, importedTotal >= itemCap {
                outcome.partialPass = true
                break
            }
        }

        if !outcome.partialPass {
            reportProgress("Cleaning up…", 0.92)
            try purgeStale(serverUUID: snapshot.id, syncStamp: syncStamp, container: container)
        }

        return outcome
    }

    private static func importMovies(
        client: any MediaServerClient,
        baseURL: URL,
        userId: String,
        token: String,
        library: MediaServerLibrary,
        serverUUID: UUID,
        syncStamp: String,
        container: ModelContainer,
        pageSize: Int,
        importedTotal: inout Int,
        itemCap: Int?,
        types: [String] = ["Movie"],
        baseFraction: Double,
        spanFraction: Double,
        reportProgress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> Int {
        var start = 0
        var imported = 0
        var totalCount: Int?
        let categoryId = MediaServerIdentity.libraryCategoryID(serverUUID: serverUUID, libraryID: library.id)
        var batchContext: ModelContext?
        var batchCache: [String: Movie] = [:]
        var pagesSinceSave = 0

        defer {
            batchContext = nil
            batchCache.removeAll()
        }

        func flushBatch(force: Bool = false) async throws {
            guard let batchContext, pagesSinceSave > 0 || force else { return }
            try batchContext.save()
            batchCache.removeAll(keepingCapacity: false)
            pagesSinceSave = 0
            await Task.yield()
            let pause = MediaServerCatalogLimits.syncBatchPause
            if pause > .zero {
                try? await Task.sleep(for: pause)
            }
        }

        while true {
            guard !Task.isCancelled else { break }
            if let itemCap, importedTotal >= itemCap { break }

            let page = try await client.listItems(
                baseURL: baseURL,
                userId: userId,
                token: token,
                parentId: library.id,
                includeTypes: types,
                startIndex: start,
                limit: pageSize
            )
            if totalCount == nil { totalCount = page.totalCount }
            if page.items.isEmpty { break }

            let movieItems = page.items.filter { $0.type == "Movie" }
            if !movieItems.isEmpty {
                try autoreleasepool {
                    if batchContext == nil {
                        let ctx = ModelContext(container)
                        ctx.autosaveEnabled = false
                        batchContext = ctx
                    }
                    guard let batchContext else { return }

                    let catalogIDs = movieItems.map { MediaServerIdentity.movieID(serverUUID: serverUUID, remoteID: $0.id) }
                    let missingIDs = catalogIDs.filter { batchCache[$0] == nil }
                    if !missingIDs.isEmpty {
                        let fetched = try fetchExistingMovies(ids: missingIDs, context: batchContext)
                        batchCache.merge(fetched) { _, new in new }
                    }

                    for item in movieItems {
                        if let itemCap, importedTotal >= itemCap { break }
                        let catalogID = MediaServerIdentity.movieID(serverUUID: serverUUID, remoteID: item.id)
                        upsertMovie(
                            item: item,
                            catalogID: catalogID,
                            categoryId: categoryId,
                            syncStamp: syncStamp,
                            server: serverUUID,
                            baseURL: baseURL,
                            token: token,
                            client: client,
                            context: batchContext,
                            cache: &batchCache
                        )
                        imported += 1
                        importedTotal += 1
                    }
                }

                pagesSinceSave += 1
                if pagesSinceSave >= MediaServerCatalogLimits.syncPagesPerSave {
                    try await flushBatch()
                    batchContext = nil
                }
            }

            updateProgress(
                label: library.name,
                imported: imported,
                total: totalCount,
                baseFraction: baseFraction,
                spanFraction: spanFraction,
                reportProgress: reportProgress
            )
            await Task.yield()

            if let itemCap, importedTotal >= itemCap { break }
            if page.items.count < pageSize { break }
            start += pageSize
        }

        try await flushBatch(force: true)
        return imported
    }

    private static func importSeries(
        client: any MediaServerClient,
        baseURL: URL,
        userId: String,
        token: String,
        library: MediaServerLibrary,
        serverUUID: UUID,
        syncStamp: String,
        container: ModelContainer,
        pageSize: Int,
        importedTotal: inout Int,
        itemCap: Int?,
        types: [String] = ["Series"],
        baseFraction: Double,
        spanFraction: Double,
        reportProgress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> Int {
        var start = 0
        var imported = 0
        var totalCount: Int?
        let categoryId = MediaServerIdentity.libraryCategoryID(serverUUID: serverUUID, libraryID: library.id)
        var batchContext: ModelContext?
        var batchCache: [String: Series] = [:]
        var pagesSinceSave = 0

        defer {
            batchContext = nil
            batchCache.removeAll()
        }

        func flushBatch(force: Bool = false) async throws {
            guard let batchContext, pagesSinceSave > 0 || force else { return }
            try batchContext.save()
            batchCache.removeAll(keepingCapacity: false)
            pagesSinceSave = 0
            await Task.yield()
            let pause = MediaServerCatalogLimits.syncBatchPause
            if pause > .zero {
                try? await Task.sleep(for: pause)
            }
        }

        while true {
            guard !Task.isCancelled else { break }
            if let itemCap, importedTotal >= itemCap { break }

            let page = try await client.listItems(
                baseURL: baseURL,
                userId: userId,
                token: token,
                parentId: library.id,
                includeTypes: types,
                startIndex: start,
                limit: pageSize
            )
            if totalCount == nil { totalCount = page.totalCount }
            if page.items.isEmpty { break }

            let seriesItems = page.items.filter { $0.type == "Series" }
            if !seriesItems.isEmpty {
                try autoreleasepool {
                    if batchContext == nil {
                        let ctx = ModelContext(container)
                        ctx.autosaveEnabled = false
                        batchContext = ctx
                    }
                    guard let batchContext else { return }

                    let catalogIDs = seriesItems.map { MediaServerIdentity.seriesID(serverUUID: serverUUID, remoteID: $0.id) }
                    let missingIDs = catalogIDs.filter { batchCache[$0] == nil }
                    if !missingIDs.isEmpty {
                        let fetched = try fetchExistingSeries(ids: missingIDs, context: batchContext)
                        batchCache.merge(fetched) { _, new in new }
                    }

                    for item in seriesItems {
                        if let itemCap, importedTotal >= itemCap { break }
                        let catalogID = MediaServerIdentity.seriesID(serverUUID: serverUUID, remoteID: item.id)
                        upsertSeries(
                            item: item,
                            catalogID: catalogID,
                            categoryId: categoryId,
                            syncStamp: syncStamp,
                            server: serverUUID,
                            baseURL: baseURL,
                            token: token,
                            client: client,
                            context: batchContext,
                            cache: &batchCache
                        )
                        imported += 1
                        importedTotal += 1
                    }
                }

                pagesSinceSave += 1
                if pagesSinceSave >= MediaServerCatalogLimits.syncPagesPerSave {
                    try await flushBatch()
                    batchContext = nil
                }
            }

            updateProgress(
                label: library.name,
                imported: imported,
                total: totalCount,
                baseFraction: baseFraction,
                spanFraction: spanFraction,
                reportProgress: reportProgress
            )
            await Task.yield()

            if let itemCap, importedTotal >= itemCap { break }
            if page.items.count < pageSize { break }
            start += pageSize
        }

        try await flushBatch(force: true)
        return imported
    }

    private static func fetchExistingMovies(ids: [String], context: ModelContext) throws -> [String: Movie] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: Movie] = [:]
        result.reserveCapacity(ids.count)
        for chunk in ids.chunked(into: MediaServerCatalogLimits.lookupChunkSize) {
            let batch = chunk
            let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { batch.contains($0.id) })
            for movie in try context.fetch(descriptor) {
                result[movie.id] = movie
            }
        }
        return result
    }

    private static func fetchExistingSeries(ids: [String], context: ModelContext) throws -> [String: Series] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: Series] = [:]
        result.reserveCapacity(ids.count)
        for chunk in ids.chunked(into: MediaServerCatalogLimits.lookupChunkSize) {
            let batch = chunk
            let descriptor = FetchDescriptor<Series>(predicate: #Predicate { batch.contains($0.id) })
            for series in try context.fetch(descriptor) {
                result[series.id] = series
            }
        }
        return result
    }

    private static func updateProgress(
        label: String,
        imported: Int,
        total: Int?,
        baseFraction: Double,
        spanFraction: Double,
        reportProgress: @escaping @Sendable (String, Double) -> Void
    ) {
        if let total, total > 0 {
            reportProgress(
                "\(label) — \(imported)/\(total)",
                baseFraction + spanFraction * min(Double(imported) / Double(total), 1)
            )
        } else {
            reportProgress("\(label) — \(imported)", baseFraction + spanFraction * 0.5)
        }
    }

    private static func upsertMovie(
        item: MediaServerItem,
        catalogID: String,
        categoryId: String,
        syncStamp: String,
        server: UUID,
        baseURL: URL,
        token: String,
        client: any MediaServerClient,
        context: ModelContext,
        cache: inout [String: Movie]
    ) {
        let minimal = MediaServerCatalogLimits.minimalCatalogDuringSync
        let poster = client.imageURL(baseURL: baseURL, itemId: item.id, imageTag: item.imageTag, token: token, kind: "Primary")?.absoluteString
        let movie: Movie
        if let existing = cache[catalogID] {
            movie = existing
        } else {
            movie = Movie(
                id: catalogID,
                streamId: item.id.hashValue,
                name: item.name,
                streamIcon: poster,
                rating: 0,
                categoryId: categoryId
            )
            context.insert(movie)
            cache[catalogID] = movie
        }
        movie.name = item.name
        if let poster { movie.streamIcon = poster }
        if MediaServerCatalogLimits.liteMetadataDuringSync {
            movie.plot = nil
            movie.genre = nil
        } else if !minimal {
            movie.plot = item.overview
            movie.genre = item.genres.joined(separator: ", ")
        }
        if !minimal {
            movie.releaseDate = item.productionYear.map(String.init)
            movie.durationSecs = item.runTimeTicks.map { Int($0 / 10_000_000) }
            if let tmdbId = item.providerTMDBId {
                movie.tmdbId = tmdbId
                movie.tmdbEnrichedAt = Date()
            }
            if let imdb = item.providerIMDBId { movie.imdbId = imdb }
        }
        movie.directURL = "mediaserver:///\(server.uuidString)/\(item.id)/movie"
        movie.categoryId = categoryId
        movie.added = syncStamp
        movie.indexedAt = Date()
        if let ud = item.userData {
            movie.isWatched = ud.played
            movie.watchProgress = Double(ud.playbackPositionTicks) / 10_000_000
            movie.lastWatchedDate = ud.lastPlayedDate
        }
    }

    private static func upsertSeries(
        item: MediaServerItem,
        catalogID: String,
        categoryId: String,
        syncStamp: String,
        server: UUID,
        baseURL: URL,
        token: String,
        client: any MediaServerClient,
        context: ModelContext,
        cache: inout [String: Series]
    ) {
        let minimal = MediaServerCatalogLimits.minimalCatalogDuringSync
        let poster = client.imageURL(baseURL: baseURL, itemId: item.id, imageTag: item.imageTag, token: token, kind: "Primary")?.absoluteString
        let series: Series
        if let existing = cache[catalogID] {
            series = existing
        } else {
            series = Series(
                id: catalogID,
                seriesId: item.id.hashValue,
                name: item.name,
                cover: poster,
                categoryId: categoryId
            )
            context.insert(series)
            cache[catalogID] = series
        }
        series.name = item.name
        if let poster { series.cover = poster }
        if MediaServerCatalogLimits.liteMetadataDuringSync {
            series.plot = nil
            series.genre = nil
        } else if !minimal {
            series.plot = item.overview
            series.genre = item.genres.joined(separator: ", ")
        }
        if !minimal {
            series.releaseDate = item.productionYear.map(String.init)
            if let tmdbId = item.providerTMDBId {
                series.tmdbId = tmdbId
                series.tmdbEnrichedAt = Date()
            }
            if let imdb = item.providerIMDBId { series.imdbId = imdb }
        }
        series.categoryId = categoryId
        series.lastModified = syncStamp
        series.indexedAt = Date()
        if let ud = item.userData, ud.played {
            series.lastWatchedDate = ud.lastPlayedDate
        }
    }

    /// Removes rows that were not touched during this sync pass (stamp mismatch).
    private static func purgeStale(serverUUID: UUID, syncStamp: String, container: ModelContainer) throws {
        let moviePrefix = "\(serverUUID.uuidString)-movie-"
        let seriesPrefix = "\(serverUUID.uuidString)-series-"
        try purgeStaleMovies(prefix: moviePrefix, syncStamp: syncStamp, container: container)
        try purgeStaleSeries(prefix: seriesPrefix, syncStamp: syncStamp, container: container)
    }

    private static func purgeStaleMovies(prefix: String, syncStamp: String, container: ModelContainer) throws {
        let batchSize = MediaServerCatalogLimits.catalogBatchSize
        let stamp = syncStamp
        while true {
            let ctx = ModelContext(container)
            var descriptor = FetchDescriptor<Movie>(
                predicate: #Predicate { movie in
                    movie.id.starts(with: prefix) && movie.added != stamp
                },
                sortBy: [SortDescriptor(\.id)]
            )
            descriptor.fetchLimit = batchSize
            let batch = try ctx.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for movie in batch {
                ctx.delete(movie)
            }
            try ctx.save()

            if batch.count < batchSize { break }
        }
    }

    private static func purgeStaleSeries(prefix: String, syncStamp: String, container: ModelContainer) throws {
        let batchSize = MediaServerCatalogLimits.catalogBatchSize
        let stamp = syncStamp
        while true {
            let ctx = ModelContext(container)
            var descriptor = FetchDescriptor<Series>(
                predicate: #Predicate { series in
                    series.id.starts(with: prefix) && series.lastModified != stamp
                },
                sortBy: [SortDescriptor(\.id)]
            )
            descriptor.fetchLimit = batchSize
            let batch = try ctx.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for series in batch {
                ctx.delete(series)
            }
            try ctx.save()

            if batch.count < batchSize { break }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index ..< end]))
            index = end
        }
        return chunks
    }
}
