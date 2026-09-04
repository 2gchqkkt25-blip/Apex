//
//  ContentSyncManager.swift
//  Apex
//
//  Manages content synchronization from Xtream API to SwiftData
//

import Foundation
import OSLog
import SwiftData

// MARK: - ParsedEpisode

/// A provider episode parsed off the main actor, ready to be turned into an
/// `Episode` model by the caller on its own context. Value type so it can cross
/// the actor boundary safely.
struct ParsedEpisode {
    let id: String
    let episodeId: String
    let title: String
    let containerExtension: String
    let seasonNum: Int
    let episodeNum: Int
    let added: String?
    let directSource: String?
    let durationSecs: Int?
    let movieImage: String?
    let rating: Double?
    let airDate: String?
    let plot: String?
}

extension Series {
    /// Materializes fetched episodes on `context` and links them to this series,
    /// de-duping against any already present (Episode.id is unique). Mutating the
    /// `episodes` relationship directly updates any observing SwiftUI view, so the
    /// caller must run this on the same context the view renders from.
    ///
    /// Inserts are batched with a save + MainActor yield after each batch so the
    /// UI updates incrementally and the main thread never blocks long enough to
    /// trigger the tvOS watchdog. On tvOS batches are smaller (25) because the
    /// watchdog is stricter; on iOS/macOS 100-episode batches keep overhead low
    /// while still yielding regularly.
    @MainActor
    func insertEpisodes(_ parsed: [ParsedEpisode], into context: ModelContext) async {
        let parsedIds = parsed.map(\.id)
        var existingById: [String: Episode] = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
        if existingById.count < parsedIds.count {
            let stored = ((try? context.fetch(FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { parsedIds.contains($0.id) }
            ))) ?? [])
            for episode in stored {
                existingById[episode.id] = episode
            }
        }

        #if os(tvOS)
            let batchSize = 25
        #else
            let batchSize = 100
        #endif

        var index = parsed.startIndex
        while index < parsed.endIndex {
            let end = Swift.min(index + batchSize, parsed.endIndex)
            var didWrite = false
            for item in parsed[index ..< end] {
                if let existing = existingById[item.id] {
                    existing.title = item.title
                    existing.containerExtension = item.containerExtension
                    existing.seasonNum = item.seasonNum
                    existing.episodeNum = item.episodeNum
                    existing.added = item.added
                    existing.directSource = item.directSource
                    existing.durationSecs = item.durationSecs
                    existing.movieImage = item.movieImage
                    existing.rating = item.rating
                    existing.airDate = item.airDate
                    existing.plot = item.plot
                    existing.series = self
                    if !episodes.contains(where: { $0.id == existing.id }) {
                        episodes.append(existing)
                    }
                    didWrite = true
                    continue
                }

                let episode = Episode(
                    id: item.id,
                    episodeId: item.episodeId,
                    title: item.title,
                    containerExtension: item.containerExtension,
                    seasonNum: item.seasonNum,
                    episodeNum: item.episodeNum,
                    added: item.added,
                    directSource: item.directSource
                )
                episode.durationSecs = item.durationSecs
                episode.movieImage = item.movieImage
                episode.rating = item.rating
                episode.airDate = item.airDate
                episode.plot = item.plot
                episode.series = self
                context.insert(episode)
                episodes.append(episode)
                existingById[episode.id] = episode
                didWrite = true
            }
            if didWrite { try? context.save() }
            await Task.yield()
            index = end
        }
    }
}

// MARK: - ContentSyncManager

actor ContentSyncManager {
    // MARK: - Properties

    let modelContainer: ModelContainer
    let xtreamClient: XtreamClient
    private var activeSyncPlaylistIDs: Set<UUID> = []

    /// Kept at 2000 (matching upstream Lume) so a 20k+ library triggers far fewer
    /// main-context save notifications than smaller batches — each save was freezing
    /// the sync UI on device.
    private let batchSize = 2000

    /// Throttles progress updates to at most once per 100 ms so large syncs don't
    /// flood the MainActor with hops that stall the UI.
    private var lastProgressUpdate = Date.distantPast

    private func throttledProgress(_ progress: SyncProgress?, detail: String, fraction: Double) async {
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) > 0.1 else { return }
        lastProgressUpdate = now
        await progress?.update(detail: detail, fraction: fraction)
    }

    // MARK: - Initialization

    init(modelContainer: ModelContainer, xtreamClient: XtreamClient = XtreamClient()) {
        self.modelContainer = modelContainer
        self.xtreamClient = xtreamClient
    }

    // MARK: - Playlist Sync

    /// Performs a full sync of a playlist (categories and content)
    func syncPlaylist(_ playlist: Playlist, progress: SyncProgress? = nil, full: Bool = false) async throws {
        let playlistId = playlist.id

        guard !activeSyncPlaylistIDs.contains(playlistId) else {
            throw SyncError.syncInProgress
        }

        activeSyncPlaylistIDs.insert(playlistId)
        defer { activeSyncPlaylistIDs.remove(playlistId) }

        NotificationCenter.default.post(name: .apexPlaylistCatalogSyncWillStart, object: playlistId)

        do {
            // Run directly in the caller's task — no wrapping unstructured Task —
            // so cancelling the caller (e.g. the user aborting from the progress
            // sheet) propagates here and tears the sync down.
            try await performSync(playlistId: playlistId, progress: progress, full: full)
        } catch {
            NotificationCenter.default.post(name: .apexPlaylistCatalogSyncDidAbort, object: playlistId)
            // An aborted sync isn't a failure: restore the playlist to idle so it
            // can be retried cleanly, rather than wedging it in the error state.
            if Task.isCancelled {
                markPlaylistIdle(playlistId: playlistId)
            } else {
                markPlaylistError(playlistId: playlistId)
            }
            throw error
        }

        Logger.database.info("Completed sync for playlist \(playlistId)")

        // Nudge iCloud sync: a freshly fetched catalog may now be able to apply
        // cloud user state (favorites / progress) that was waiting for it.
        NotificationCenter.default.post(name: .lumeContentSyncDidComplete, object: playlistId)
    }

    private func performSync(playlistId: UUID, progress: SyncProgress?, full: Bool) async throws {
        let statusContext = ModelContext(modelContainer)
        statusContext.autosaveEnabled = false
        guard let playlist = try statusContext.fetch(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistId })
        ).first else {
            Logger.database.error("Sync aborted: playlist \(playlistId) not found in store")
            throw SyncError.playlistNotFound
        }

        playlist.syncStatus = .syncing
        try statusContext.save()

        switch playlist.sourceType {
        case .xtream:
            try await performXtreamSync(playlist: playlist, playlistId: playlistId, progress: progress, full: full)
        case .m3u:
            try await performM3USync(playlist: playlist, playlistId: playlistId, progress: progress)
        case .stalker:
            try await performStalkerSync(playlist: playlist, playlistId: playlistId, progress: progress, full: full)
        case .stremio:
            try await performStremioSync(playlist: playlist, playlistId: playlistId, progress: progress)
        }

        let doneContext = ModelContext(modelContainer)
        doneContext.autosaveEnabled = false
        if let dpl = try doneContext.fetch(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistId })
        ).first {
            dpl.syncStatus = .idle
            dpl.lastSyncDate = Date()
            // Ensure the linked EPG source exists before post-sync guide refresh.
            // Xtream/Stalker sync paths never called reconcile — without this the
            // guide stays empty even though channels carry epgChannelId values.
            EPGSourceReconciler.reconcile(dpl, in: doneContext)
            try doneContext.save()
        }
    }

    /// The Xtream pipeline: authenticate, then pull categories and content
    /// through the provider's JSON API.
    private func performXtreamSync(playlist: Playlist, playlistId: UUID, progress: SyncProgress?, full: Bool) async throws {
        await progress?.start(.authenticating)
        let authResponse = try await xtreamClient.getInfo(playlist: playlist)
        updatePlaylistInfo(playlistId, with: authResponse)
        await progress?.complete(.authenticating)

        try await syncAllCategories(for: playlist, playlistId: playlistId, progress: progress, full: full)

        // Movies and live streams are independent — fetch and upsert them
        // concurrently. Series must finish before episode refresh (episodes
        // depend on series IDs existing in the store).
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.syncMovies(for: playlist, playlistId: playlistId, progress: progress, full: full) }
            group.addTask { try await self.syncLiveStreams(for: playlist, playlistId: playlistId, progress: progress, full: full) }
            try await group.waitForAll()
        }

        let lastModifiedChangedIds = try await syncSeries(for: playlist, playlistId: playlistId, progress: progress, full: full)
        enqueueEpisodeRefresh(playlistId: playlistId, lastModifiedChangedIds: lastModifiedChangedIds)
    }

    func syncAllCategories(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil, full _: Bool = false) async throws {
        // All three category types are independent API calls — fetch them
        // concurrently so total wall time equals the slowest call instead of
        // the sum. Each sync*Categories creates its own ModelContext, so there
        // is no shared-state conflict.
        Logger.database.info("Starting concurrent category sync (VOD + Series + Live)")
        await progress?.start(.movieCategories)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.syncVODCategories(for: playlist, playlistId: playlistId, progress: progress) }
            group.addTask { try await self.syncSeriesCategories(for: playlist, playlistId: playlistId, progress: progress) }
            group.addTask { try await self.syncLiveCategories(for: playlist, playlistId: playlistId, progress: progress) }
            try await group.waitForAll()
        }
        await progress?.complete(.movieCategories)
        await progress?.complete(.seriesCategories)
        await progress?.complete(.liveCategories)
    }

    // MARK: - Category Sync

    private func syncVODCategories(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        let categories = try await xtreamClient.getVODCategories(playlist: playlist)
        Logger.database.info("Fetched \(categories.count) VOD categories")
        await progress?.update(detail: "\(categories.count) categories")
        try syncCategories(categories, type: .vod, playlistId: playlistId)
    }

    private func syncSeriesCategories(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        let categories = try await xtreamClient.getSeriesCategories(playlist: playlist)
        Logger.database.info("Fetched \(categories.count) Series categories")
        await progress?.update(detail: "\(categories.count) categories")
        try syncCategories(categories, type: .series, playlistId: playlistId)
    }

    private func syncLiveCategories(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        let categories = try await xtreamClient.getLiveCategories(playlist: playlist)
        Logger.database.info("Fetched \(categories.count) Live categories")
        await progress?.update(detail: "\(categories.count) categories")
        try syncCategories(categories, type: .live, playlistId: playlistId)
    }

    private func syncCategories(_ dtos: [XtreamCategory], type: CategoryType, playlistId: UUID) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        let categoryLookup = buildExistingCategoryLookup(context: context, playlistId: playlistId, type: type)

        guard let playlist = try context.fetch(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistId })
        ).first else { return }

        for (index, categoryDTO) in dtos.enumerated() {
            if let existingCat = categoryLookup[categoryDTO.categoryId] {
                existingCat.name = categoryDTO.categoryName
                existingCat.parentId = categoryDTO.parentId ?? 0
                existingCat.sortOrder = index
                existingCat.lastRefreshed = Date()
            } else {
                let category = Category(
                    apiId: categoryDTO.categoryId,
                    name: categoryDTO.categoryName,
                    parentId: categoryDTO.parentId ?? 0,
                    type: type,
                    playlist: playlist
                )
                category.sortOrder = index
                category.lastRefreshed = Date()
                context.insert(category)
            }
        }

        try context.save()

        // Remove categories of this type the provider has dropped. Gated on a
        // non-empty fetch: an empty category list is the transient-failure
        // signature, and sweeping then would drop every category for the type.
        if !dtos.isEmpty {
            let seenApiIds = Set(dtos.map(\.categoryId))
            pruneStaleCategories(playlistId: playlistId, type: type, seenApiIds: seenApiIds)
        }
    }

    // MARK: - Content Sync (Batched)

    /// Syncs movies in memory-bounded batches.
    ///
    /// Fetches one VOD category at a time from the provider so a 20k+ library
    /// never lands in memory as a single decoded JSON array (the main device OOM
    /// trigger). Falls back to a single full fetch when no categories exist yet,
    /// when a category-scoped pass yields nothing (stale category ids), or when
    /// `full` is set (manual Sync Now — the same path as delete-and-re-add).
    func syncMovies(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil, full: Bool = false) async throws {
        await progress?.start(.movies)
        let categories = full ? [] : localCategories(playlistId: playlistId, type: .vod)
        let playlistPrefix = "\(playlistId.uuidString)-\(CategoryType.vod.rawValue)-"
        var seenIds = Set<String>()
        var syncedTotal = 0

        if categories.isEmpty {
            if full {
                Logger.database.info("Full movie sync — unfiltered VOD list")
            }
            let movieDTOs = try await xtreamClient.getVODStreams(playlist: playlist)
            syncedTotal = try await upsertMovieBatch(
                movieDTOs,
                playlist: playlist,
                playlistId: playlistId,
                playlistPrefix: playlistPrefix,
                seenIds: &seenIds,
                progress: progress,
                totalCount: movieDTOs.count,
                syncedSoFar: 0
            )
        } else {
            Logger.database.info("Syncing movies across \(categories.count) categories")
            for (index, category) in categories.enumerated() {
                try Task.checkCancellation()
                let movieDTOs = try await xtreamClient.getVODStreams(playlist: playlist, categoryId: category.apiId)
                syncedTotal = try await upsertMovieBatch(
                    movieDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    progress: progress,
                    totalCount: nil,
                    syncedSoFar: syncedTotal,
                    categoryProgress: (index + 1, categories.count)
                )
            }
            let existingCount = countMovies(playlistId: playlistId)
            if seenIds.isEmpty || catalogFetchLooksIncomplete(seenCount: seenIds.count, existingCount: existingCount) {
                Logger.database.warning("Per-category movie fetch looked incomplete (\(seenIds.count) vs \(existingCount) stored) — falling back to unfiltered VOD list")
                let movieDTOs = try await xtreamClient.getVODStreams(playlist: playlist)
                syncedTotal = try await upsertMovieBatch(
                    movieDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    progress: progress,
                    totalCount: movieDTOs.count,
                    syncedSoFar: 0
                )
            }
        }

        let existingCount = countMovies(playlistId: playlistId)
        if shouldPruneStaleCatalog(seenCount: seenIds.count, existingCount: existingCount) {
            pruneStaleMovies(playlistId: playlistId, seenIds: seenIds)
        } else if !seenIds.isEmpty {
            Logger.database.warning("Skipping movie prune — fetch returned \(seenIds.count) ids against \(existingCount) stored")
        }

        Logger.database.info("Completed syncing \(syncedTotal) movies")
        await progress?.complete(.movies)
    }

    private func upsertMovieBatch(
        _ movieDTOs: [XtreamVODStream],
        playlist: Playlist,
        playlistId: UUID,
        playlistPrefix: String,
        seenIds: inout Set<String>,
        progress: SyncProgress?,
        totalCount: Int?,
        syncedSoFar: Int,
        categoryProgress: (current: Int, total: Int)? = nil
    ) async throws -> Int {
        let count = movieDTOs.count
        guard count > 0 else { return syncedSoFar }

        var runningTotal = syncedSoFar
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            try Task.checkCancellation()
            try autoreleasepool {
                let batchEnd = min(batchStart + batchSize, count)
                let batch = movieDTOs[batchStart ..< batchEnd]

                let context = ModelContext(modelContainer)
                context.autosaveEnabled = false
                let existing = existingMovies(in: batch, playlistId: playlistId, context: context)

                for movieDTO in batch {
                    guard let streamId = movieDTO.streamId else { continue }
                    let movieId = "\(playlistId.uuidString)-movie-\(streamId)"
                    seenIds.insert(movieId)

                    let movie: Movie
                    if let found = existing[movieId] {
                        movie = found
                    } else {
                        movie = Movie(id: movieId, streamId: streamId, name: "")
                        context.insert(movie)
                    }
                    applyMovieFields(from: movieDTO, to: movie, playlistPrefix: playlistPrefix, serverURL: playlist.serverURL)
                }

                try context.save()
                runningTotal += batch.count
                Logger.database.info("Synced movies \(runningTotal) total (\(batchStart + 1)–\(batchEnd) in category batch)")
            }

            if let totalCount {
                await throttledProgress(
                    progress,
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await throttledProgress(
                    progress,
                    detail: "\(runningTotal) movies · category \(categoryProgress.current)/\(categoryProgress.total)",
                    fraction: Double(categoryProgress.current) / Double(categoryProgress.total)
                )
            }
        }
        return runningTotal
    }

    /// Syncs series in memory-bounded batches, one provider category at a time.
    func syncSeries(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil, full: Bool = false) async throws -> Set<String> {
        await progress?.start(.series)
        let categories = full ? [] : localCategories(playlistId: playlistId, type: .series)
        let playlistPrefix = "\(playlistId.uuidString)-\(CategoryType.series.rawValue)-"
        var seenIds = Set<String>()
        var lastModifiedChangedIds = Set<String>()
        var syncedTotal = 0

        if categories.isEmpty {
            let seriesDTOs = try await xtreamClient.getSeries(playlist: playlist)
            syncedTotal = try await upsertSeriesBatch(
                seriesDTOs,
                playlist: playlist,
                playlistId: playlistId,
                playlistPrefix: playlistPrefix,
                seenIds: &seenIds,
                lastModifiedChangedIds: &lastModifiedChangedIds,
                progress: progress,
                totalCount: seriesDTOs.count,
                syncedSoFar: 0
            )
        } else {
            Logger.database.info("Syncing series across \(categories.count) categories")
            for (index, category) in categories.enumerated() {
                try Task.checkCancellation()
                let seriesDTOs = try await xtreamClient.getSeries(playlist: playlist, categoryId: category.apiId)
                syncedTotal = try await upsertSeriesBatch(
                    seriesDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    lastModifiedChangedIds: &lastModifiedChangedIds,
                    progress: progress,
                    totalCount: nil,
                    syncedSoFar: syncedTotal,
                    categoryProgress: (index + 1, categories.count)
                )
            }
            let existingCount = countSeries(playlistId: playlistId)
            if seenIds.isEmpty || catalogFetchLooksIncomplete(seenCount: seenIds.count, existingCount: existingCount) {
                Logger.database.warning("Per-category series fetch looked incomplete (\(seenIds.count) vs \(existingCount) stored) — falling back to unfiltered series list")
                let seriesDTOs = try await xtreamClient.getSeries(playlist: playlist)
                syncedTotal = try await upsertSeriesBatch(
                    seriesDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    lastModifiedChangedIds: &lastModifiedChangedIds,
                    progress: progress,
                    totalCount: seriesDTOs.count,
                    syncedSoFar: 0
                )
            }
        }

        let existingCount = countSeries(playlistId: playlistId)
        if shouldPruneStaleCatalog(seenCount: seenIds.count, existingCount: existingCount) {
            pruneStaleSeries(playlistId: playlistId, seenIds: seenIds)
        } else if !seenIds.isEmpty {
            Logger.database.warning("Skipping series prune — fetch returned \(seenIds.count) ids against \(existingCount) stored")
        }

        Logger.database.info("Completed syncing \(syncedTotal) series (\(lastModifiedChangedIds.count) last_modified changes)")
        await progress?.complete(.series)
        return lastModifiedChangedIds
    }

    private func upsertSeriesBatch(
        _ seriesDTOs: [XtreamSeries],
        playlist: Playlist,
        playlistId: UUID,
        playlistPrefix: String,
        seenIds: inout Set<String>,
        lastModifiedChangedIds: inout Set<String>,
        progress: SyncProgress?,
        totalCount: Int?,
        syncedSoFar: Int,
        categoryProgress: (current: Int, total: Int)? = nil
    ) async throws -> Int {
        let count = seriesDTOs.count
        guard count > 0 else { return syncedSoFar }

        var runningTotal = syncedSoFar
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            try Task.checkCancellation()
            var batchChanged = Set<String>()
            try autoreleasepool {
                let batchEnd = min(batchStart + batchSize, count)
                let batch = seriesDTOs[batchStart ..< batchEnd]

                let context = ModelContext(modelContainer)
                context.autosaveEnabled = false
                let existing = existingSeries(in: batch, playlistId: playlistId, context: context)

                for seriesDTO in batch {
                    guard let seriesId = seriesDTO.seriesId else { continue }
                    let id = "\(playlistId.uuidString)-series-\(seriesId)"
                    seenIds.insert(id)

                    let series: Series
                    if let found = existing[id] {
                        series = found
                    } else {
                        series = Series(id: id, seriesId: seriesId, name: "")
                        context.insert(series)
                    }
                    let previousModified = series.lastModified
                    applySeriesFields(from: seriesDTO, to: series, playlistPrefix: playlistPrefix, serverURL: playlist.serverURL)
                    if existing[id] != nil, previousModified != series.lastModified {
                        batchChanged.insert(id)
                    }
                }

                try context.save()
                runningTotal += batch.count
                Logger.database.info("Synced series \(runningTotal) total (\(batchStart + 1)–\(batchEnd) in category batch)")
            }
            lastModifiedChangedIds.formUnion(batchChanged)

            if let totalCount {
                await throttledProgress(
                    progress,
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await throttledProgress(
                    progress,
                    detail: "\(runningTotal) series · category \(categoryProgress.current)/\(categoryProgress.total)",
                    fraction: Double(categoryProgress.current) / Double(categoryProgress.total)
                )
            }
        }
        return runningTotal
    }

    /// Syncs episodes for a series
    /// Fetches and parses a series' episodes from the provider **without**
    /// touching the database.
    ///
    /// The caller inserts the returned episodes through its own (view) context,
    /// attaching them to the `Series` instance it already holds. Writing through
    /// a separate background context instead leaves the view-context series'
    /// `episodes` relationship stale until a later cross-context merge — which
    /// races the UI refresh and, on tvOS, loses (episodes only appear after
    /// navigating away and back). Returning value types sidesteps that entirely.
    func fetchEpisodes(seriesId: Int, seriesElementId: String, playlist: Playlist) async throws -> [ParsedEpisode] {
        switch playlist.sourceType {
        case .xtream:
            try await fetchXtreamEpisodes(seriesId: seriesId, seriesElementId: seriesElementId, playlist: playlist)
        case .stalker:
            try await fetchStalkerEpisodes(seriesId: seriesId, seriesElementId: seriesElementId, playlist: playlist)
        case .m3u:
            // M3U content is imported during sync; no lazy episode fetch.
            []
        case .stremio:
            try await fetchStremioEpisodes(seriesElementId: seriesElementId, playlist: playlist)
        }
    }

    /// Re-fetches episode lists after a catalog sync so new airings land without
    /// opening each show. Playlist sync only upserts the series row; episodes
    /// are otherwise lazy and would stay frozen at the first fetch.
    ///
    /// Xtream `last_modified` changes on **existing** rows are refreshed first
    /// (new inserts skip this — they have no cached episode list yet). Recently
    /// watched shows are always included. Total `get_series_info` calls are
    /// capped so a panel-wide timestamp bump cannot hammer the provider.
    ///
    /// Runs after the sync sheet can dismiss — waiting on up to 80 episode
    /// fetches made playlist refresh feel minutes slower than other IPTV apps.
    func enqueueEpisodeRefresh(playlistId: UUID, lastModifiedChangedIds: Set<String> = []) {
        Task {
            await self.runDeferredEpisodeRefresh(
                playlistId: playlistId,
                lastModifiedChangedIds: lastModifiedChangedIds
            )
        }
    }

    private func runDeferredEpisodeRefresh(playlistId: UUID, lastModifiedChangedIds: Set<String>) async {
        let lookup = ModelContext(modelContainer)
        lookup.autosaveEnabled = false
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistId })
        descriptor.fetchLimit = 1
        guard let playlist = try? lookup.fetch(descriptor).first else { return }
        try? await refreshRecentlyWatchedEpisodes(
            playlist: playlist,
            playlistId: playlistId,
            lastModifiedChangedIds: lastModifiedChangedIds
        )
    }

    func refreshRecentlyWatchedEpisodes(
        playlist: Playlist,
        playlistId: UUID,
        lastModifiedChangedIds: Set<String> = []
    ) async throws {
        switch playlist.sourceType {
        case .m3u:
            return
        case .xtream, .stalker, .stremio:
            break
        }

        let prefix = playlistId.uuidString
        let lookup = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.lastWatchedDate != nil },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        let candidates: [Series]
        do {
            candidates = try lookup.fetch(descriptor)
        } catch {
            candidates = []
        }
        let watchedIds = candidates
            .filter { $0.id.hasPrefix(prefix) }
            .prefix(EpisodeRefreshPlanner.recentlyWatchedLimit)
            .map(\.id)

        let refreshIds = EpisodeRefreshPlanner.orderedIds(
            lastModifiedChanged: lastModifiedChangedIds.sorted(),
            recentlyWatched: Array(watchedIds)
        )
        guard !refreshIds.isEmpty else { return }

        let ids = refreshIds
        let rows: [Series]
        do {
            rows = try lookup.fetch(FetchDescriptor<Series>(
                predicate: #Predicate { ids.contains($0.id) }
            ))
        } catch {
            rows = []
        }
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var targets: [(seriesId: Int, elementId: String, name: String)] = []
        targets.reserveCapacity(refreshIds.count)
        for id in refreshIds {
            guard let series = byId[id] else { continue }
            targets.append((series.seriesId, series.id, series.name))
        }
        guard !targets.isEmpty else { return }

        Logger.database.info(
            "Refreshing episodes for \(targets.count) series (\(lastModifiedChangedIds.count) last_modified candidates)"
        )

        // Fetch episodes concurrently with a cap to avoid hammering the
        // provider. Each persistParsedEpisodes creates its own background
        // context so concurrent writes are safe.
        let maxConcurrent = 6
        try await withThrowingTaskGroup(of: Void.self) { group in
            var running = 0
            for target in targets {
                try Task.checkCancellation()
                if running >= maxConcurrent {
                    try await group.next()
                    running -= 1
                }
                let seriesId = target.seriesId
                let elementId = target.elementId
                let name = target.name
                group.addTask { [playlist] in
                    do {
                        let parsed = try await self.fetchEpisodes(
                            seriesId: seriesId,
                            seriesElementId: elementId,
                            playlist: playlist
                        )
                        await self.persistParsedEpisodes(parsed, seriesElementId: elementId)
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        Logger.database.warning(
                            "Episode refresh failed for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                running += 1
            }
            try await group.waitForAll()
        }
    }

    /// Upserts provider episodes onto the series in a background context.
    /// Does not prune missing ids — an incomplete `get_series_info` must not
    /// wipe a show the user already has.
    private func persistParsedEpisodes(_ parsed: [ParsedEpisode], seriesElementId: String) {
        guard !parsed.isEmpty else { return }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let seriesId = seriesElementId
        var seriesDescriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesId })
        seriesDescriptor.fetchLimit = 1
        guard let series = try? context.fetch(seriesDescriptor).first else { return }

        let parsedIds = parsed.map(\.id)
        let stored: [Episode]
        do {
            stored = try context.fetch(FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { parsedIds.contains($0.id) }
            ))
        } catch {
            stored = []
        }
        var existingById = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

        for item in parsed {
            if let existing = existingById[item.id] {
                existing.title = item.title
                existing.containerExtension = item.containerExtension
                existing.seasonNum = item.seasonNum
                existing.episodeNum = item.episodeNum
                existing.added = item.added
                existing.directSource = item.directSource
                existing.durationSecs = item.durationSecs
                existing.movieImage = item.movieImage
                existing.rating = item.rating
                existing.airDate = item.airDate
                existing.plot = item.plot
                existing.series = series
                if !series.episodes.contains(where: { $0.id == existing.id }) {
                    series.episodes.append(existing)
                }
                continue
            }

            let episode = Episode(
                id: item.id,
                episodeId: item.episodeId,
                title: item.title,
                containerExtension: item.containerExtension,
                seasonNum: item.seasonNum,
                episodeNum: item.episodeNum,
                added: item.added,
                directSource: item.directSource
            )
            episode.durationSecs = item.durationSecs
            episode.movieImage = item.movieImage
            episode.rating = item.rating
            episode.airDate = item.airDate
            episode.plot = item.plot
            episode.series = series
            context.insert(episode)
            series.episodes.append(episode)
            existingById[item.id] = episode
        }
        try? context.save()
    }

    private func fetchXtreamEpisodes(seriesId: Int, seriesElementId: String, playlist: Playlist) async throws -> [ParsedEpisode] {
        Logger.database.warning("fetchXtreamEpisodes — seriesId=\(seriesId) playlist=\(playlist.serverURL, privacy: .public)")
        let seriesInfo = try await xtreamClient.getSeriesInfo(playlist: playlist, seriesId: seriesId)
        var episodesDict = seriesInfo.episodes ?? [:]

        // Reseller panels often have duplicate series entries across categories
        // (e.g. "Silo" in Sci-Fi with episodes, "Silo (2023)" in Apple TV+ empty).
        // When the primary entry has no episodes, search for an alternate entry
        // with the same name that does have episodes.
        if episodesDict.isEmpty {
            Logger.database.warning("fetchXtreamEpisodes — 0 episodes, searching for alternate entry")
            if let altDict = await findAlternateEpisodes(seriesId: seriesId, seriesElementId: seriesElementId, playlist: playlist) {
                episodesDict = altDict
            }
        }

        guard !episodesDict.isEmpty else {
            Logger.database.warning("fetchXtreamEpisodes — no episodes found (primary or alternate)")
            return []
        }
        Logger.database.warning("fetchXtreamEpisodes — got \(episodesDict.count) seasons")

        // Reseller panels: the API panel URL differs from the actual stream server.
        // Detect this by checking if any synced movie has a directURL pointing to
        // a different host. If so, derive the episode stream URL from that server.
        let streamServer = resolveStreamServer(for: playlist)

        var result: [ParsedEpisode] = []
        for (seasonKey, episodes) in episodesDict {
            guard let seasonNum = Int(seasonKey) else { continue }
            for episodeDTO in episodes {
                guard let episodeIdString = episodeDTO.id else { continue }

                // Build the stream URL. If we found a real stream server (reseller panel),
                // construct the URL using that server instead of the API panel.
                let directSource: String?
                if let server = streamServer {
                    // Use m3u8 (HLS) as the streaming format. Reseller panels
                    // often report mkv/mp4 as container_extension (source format)
                    // but only serve via m3u8 or ts (the allowed_output_formats).
                    // HTTP 403 is returned for raw file extensions like .mkv.
                    let ext = "m3u8"
                    directSource = "\(server.base)/series/\(server.username)/\(server.password)/\(episodeIdString).\(ext)"
                } else {
                    directSource = episodeDTO.directSource
                }

                let plot = episodeDTO.info?.plot
                result.append(ParsedEpisode(
                    id: "\(seriesElementId)-episode-\(episodeIdString)",
                    episodeId: episodeIdString,
                    title: Self.cleanEpisodeTitle(episodeDTO.title),
                    containerExtension: episodeDTO.containerExtension ?? "mkv",
                    seasonNum: seasonNum,
                    episodeNum: episodeDTO.episodeNum ?? 0,
                    added: episodeDTO.added,
                    directSource: directSource,
                    durationSecs: episodeDTO.info?.durationSecs,
                    movieImage: episodeDTO.info?.movieImage,
                    rating: episodeDTO.info?.rating,
                    airDate: episodeDTO.info?.airDate,
                    plot: (plot?.isEmpty == false) ? plot : nil
                ))
            }
        }
        return result
    }

    /// Detects reseller panels where the API endpoint differs from the stream server.
    /// Checks if any movie in this playlist has a `directURL` pointing to a different
    /// host than `playlist.serverURL`. Returns the stream server base + credentials
    /// for building series episode URLs.
    private struct StreamServerInfo {
        let base: String // e.g. "http://proxpanel.me:8080"
        let username: String // credentials from the stream URL (may differ from panel)
        let password: String
    }

    private func resolveStreamServer(for playlist: Playlist) -> StreamServerInfo? {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let playlistPrefix = playlist.id.uuidString
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.directURL != nil && $0.id.localizedStandardContains(playlistPrefix) }
        )
        descriptor.fetchLimit = 1
        guard let movie = (try? context.fetch(descriptor))?.first,
              let directURL = movie.directURL,
              !directURL.isEmpty,
              let movieURL = URL(string: directURL)
        else {
            Logger.database.warning("resolveStreamServer — no movie with directURL found for playlist \(playlistPrefix, privacy: .public)")
            return nil
        }

        // Extract the base: scheme + host + port
        guard let host = movieURL.host else { return nil }
        let playlistHost = URL(string: playlist.serverURL)?.host ?? ""
        guard host != playlistHost else {
            Logger.database.info("resolveStreamServer — same host (\(host, privacy: .public)), using standard path")
            return nil
        }

        var base = "\(movieURL.scheme ?? "http")://\(host)"
        if let port = movieURL.port, port != 80, port != 443 {
            base += ":\(port)"
        }

        // Extract credentials from the stream URL path: /movie/{username}/{password}/{id}.{ext}
        // or /series/{username}/{password}/{id}.{ext}
        let pathComponents = movieURL.pathComponents.filter { $0 != "/" }
        // Expected: ["movie", "username", "password", "id.ext"]
        let username: String
        let password: String
        if pathComponents.count >= 4 {
            username = pathComponents[1]
            password = pathComponents[2]
        } else {
            // Can't extract credentials — fall back to panel credentials
            username = playlist.username
            password = playlist.password
        }

        Logger.database.warning("resolveStreamServer — detected reseller panel. Server: \(base, privacy: .public) user: \(username, privacy: .public)")
        return StreamServerInfo(base: base, username: username, password: password)
    }

    /// Searches for an alternate series entry with the same name that has episodes.
    /// Common with reseller panels that duplicate series across categories (one with
    /// data, one empty).
    private func findAlternateEpisodes(seriesId: Int, seriesElementId: String, playlist: Playlist) async -> [String: [XtreamEpisode]]? {
        // Find the series name from our local store
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let series = try? context.fetch(
            FetchDescriptor<Series>(predicate: #Predicate { $0.id == seriesElementId })
        ).first else { return nil }

        // Clean the name for comparison: strip year suffixes like "(2023)"
        let baseName = series.name
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !baseName.isEmpty else { return nil }

        // Find other series in the same playlist with a matching base name
        let playlistPrefix = playlist.id.uuidString
        let allSeries = (try? context.fetch(
            FetchDescriptor<Series>(predicate: #Predicate { $0.id.localizedStandardContains(playlistPrefix) })
        )) ?? []

        let candidates = allSeries.filter { candidate in
            guard candidate.seriesId != seriesId else { return false }
            let candidateName = candidate.name
                .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return candidateName == baseName
        }

        // Try each candidate's series info until we find one with episodes
        for candidate in candidates {
            if let info = try? await xtreamClient.getSeriesInfo(playlist: playlist, seriesId: candidate.seriesId),
               let eps = info.episodes, !eps.isEmpty
            {
                Logger.database.warning("fetchXtreamEpisodes — found alternate entry (id=\(candidate.seriesId)) with \(eps.values.flatMap(\.self).count) episodes")
                return eps
            }
        }
        return nil
    }

    /// Reduces a raw Xtream episode title to just the episode name.
    ///
    /// Providers commonly prefix the series and a season/episode token, e.g.
    /// "Breaking Bad - S05E16 - Felina" or "Breaking Bad S05E16 Felina". We locate
    /// the first `SxxExx` / `NxM` token and keep whatever follows it ("Felina").
    /// Titles with no such token are returned untouched; a token with nothing after
    /// it (e.g. "Breaking Bad - S05E16") yields "" so the UI can fall back to "E16".
    static func cleanEpisodeTitle(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }

        let token = #"(?i)\bS\d{1,3}\s*E\d{1,4}\b|\b\d{1,3}x\d{1,4}\b"#
        guard let match = raw.range(of: token, options: .regularExpression) else {
            return raw
        }

        let separators = CharacterSet(charactersIn: " -–—·:|.").union(.whitespacesAndNewlines)
        return raw[match.upperBound...].trimmingCharacters(in: separators)
    }

    /// Syncs live streams in memory-bounded batches, one provider category at a time.
    func syncLiveStreams(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil, full: Bool = false) async throws {
        await progress?.start(.liveStreams)
        let categories = full ? [] : localCategories(playlistId: playlistId, type: .live)
        let playlistPrefix = "\(playlistId.uuidString)-\(CategoryType.live.rawValue)-"
        var seenIds = Set<String>()
        var syncedTotal = 0

        if categories.isEmpty {
            let streamDTOs = try await xtreamClient.getLiveStreams(playlist: playlist)
            syncedTotal = try await upsertLiveStreamBatch(
                streamDTOs,
                playlist: playlist,
                playlistId: playlistId,
                playlistPrefix: playlistPrefix,
                seenIds: &seenIds,
                progress: progress,
                totalCount: streamDTOs.count,
                syncedSoFar: 0
            )
        } else {
            Logger.database.info("Syncing live streams across \(categories.count) categories")
            for (index, category) in categories.enumerated() {
                try Task.checkCancellation()
                let streamDTOs = try await xtreamClient.getLiveStreams(playlist: playlist, categoryId: category.apiId)
                syncedTotal = try await upsertLiveStreamBatch(
                    streamDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    progress: progress,
                    totalCount: nil,
                    syncedSoFar: syncedTotal,
                    categoryProgress: (index + 1, categories.count)
                )
            }
            let existingCount = countLiveStreams(playlistId: playlistId)
            if seenIds.isEmpty || catalogFetchLooksIncomplete(seenCount: seenIds.count, existingCount: existingCount) {
                Logger.database.warning("Per-category live fetch looked incomplete (\(seenIds.count) vs \(existingCount) stored) — falling back to unfiltered live list")
                let streamDTOs = try await xtreamClient.getLiveStreams(playlist: playlist)
                syncedTotal = try await upsertLiveStreamBatch(
                    streamDTOs,
                    playlist: playlist,
                    playlistId: playlistId,
                    playlistPrefix: playlistPrefix,
                    seenIds: &seenIds,
                    progress: progress,
                    totalCount: streamDTOs.count,
                    syncedSoFar: 0
                )
            }
        }

        let existingCount = countLiveStreams(playlistId: playlistId)
        if shouldPruneStaleCatalog(seenCount: seenIds.count, existingCount: existingCount) {
            pruneStaleLiveStreams(playlistId: playlistId, seenIds: seenIds)
        } else if !seenIds.isEmpty {
            Logger.database.warning("Skipping live prune — fetch returned \(seenIds.count) ids against \(existingCount) stored")
        }

        Logger.database.info("Completed syncing \(syncedTotal) live streams")
        await progress?.complete(.liveStreams)
    }

    private func upsertLiveStreamBatch(
        _ streamDTOs: [XtreamLiveStream],
        playlist: Playlist,
        playlistId: UUID,
        playlistPrefix: String,
        seenIds: inout Set<String>,
        progress: SyncProgress?,
        totalCount: Int?,
        syncedSoFar: Int,
        categoryProgress: (current: Int, total: Int)? = nil
    ) async throws -> Int {
        let count = streamDTOs.count
        guard count > 0 else { return syncedSoFar }

        var runningTotal = syncedSoFar
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            try Task.checkCancellation()
            try autoreleasepool {
                let batchEnd = min(batchStart + batchSize, count)
                let batch = streamDTOs[batchStart ..< batchEnd]

                let context = ModelContext(modelContainer)
                context.autosaveEnabled = false
                let existing = existingLiveStreams(in: batch, playlistId: playlistId, context: context)

                var iconSampleCount = 0
                for streamDTO in batch {
                    guard let streamId = streamDTO.streamId else { continue }
                    if iconSampleCount < 3, let icon = streamDTO.streamIcon, !icon.isEmpty {
                        let resolved = absoluteIconURL(from: icon, serverURL: playlist.serverURL)
                        Logger.database.info("[IconDebug] raw: \(icon) → resolved: \(resolved ?? "nil"), server: \(playlist.serverURL)")
                        iconSampleCount += 1
                    }
                    let id = "\(playlistId.uuidString)-live-\(streamId)"
                    seenIds.insert(id)

                    let liveStream: LiveStream
                    if let found = existing[id] {
                        liveStream = found
                    } else {
                        liveStream = LiveStream(id: id, streamId: streamId, name: "")
                        context.insert(liveStream)
                    }
                    liveStream.name = streamDTO.name ?? ""
                    liveStream.streamIcon = absoluteIconURL(from: streamDTO.streamIcon, serverURL: playlist.serverURL)
                    liveStream.epgChannelId = streamDTO.epgChannelId
                    liveStream.added = streamDTO.added
                    liveStream.customSid = streamDTO.customSid
                    liveStream.tvArchive = streamDTO.tvArchive ?? 0
                    liveStream.tvArchiveDuration = streamDTO.tvArchiveDuration ?? 0
                    liveStream.isAdult = streamDTO.isAdult ?? 0
                    liveStream.num = streamDTO.num ?? 0

                    if let catIdStr = streamDTO.categoryId {
                        liveStream.categoryId = playlistPrefix + catIdStr
                    }
                }

                try context.save()
                runningTotal += batch.count
                Logger.database.info("Synced streams \(runningTotal) total (\(batchStart + 1)–\(batchEnd) in category batch)")
            }

            if let totalCount {
                await throttledProgress(
                    progress,
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await throttledProgress(
                    progress,
                    detail: "\(runningTotal) channels · category \(categoryProgress.current)/\(categoryProgress.total)",
                    fraction: Double(categoryProgress.current) / Double(categoryProgress.total)
                )
            }
        }
        return runningTotal
    }
}

// MARK: - Episode refresh selection

/// Picks which series get a `get_series_info` pass after catalog sync.
/// `nonisolated` so unit tests can call it without hopping to the main actor.
nonisolated enum EpisodeRefreshPlanner {
    static let recentlyWatchedLimit = 20
    static let lastModifiedLimit = 60
    static let totalCap = 80

    /// Existing rows whose Xtream `last_modified` changed, then recently watched.
    /// Unique; last-modified is capped so a catalog-wide stamp cannot queue
    /// thousands of episode fetches. Watched titles still get a slot afterward.
    nonisolated static func orderedIds(
        lastModifiedChanged: [String],
        recentlyWatched: [String]
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for id in lastModifiedChanged.prefix(lastModifiedLimit) {
            guard seen.insert(id).inserted else { continue }
            ordered.append(id)
        }
        for id in recentlyWatched.prefix(recentlyWatchedLimit) {
            guard seen.insert(id).inserted else { continue }
            ordered.append(id)
            if ordered.count >= totalCap { break }
        }
        return ordered
    }
}

// MARK: - Sync Error

enum SyncError: LocalizedError {
    case syncInProgress
    case playlistNotFound
    case invalidCredentials
    case networkError(Error)
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .syncInProgress:
            "A sync is already in progress for this playlist"
        case .playlistNotFound:
            "The playlist could not be found"
        case .invalidCredentials:
            "Invalid username or password"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .databaseError(error):
            "Database error: \(error.localizedDescription)"
        }
    }
}
