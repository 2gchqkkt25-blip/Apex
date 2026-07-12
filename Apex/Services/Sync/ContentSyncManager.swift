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
        let existingIds = Set(episodes.map(\.id))
        let newEpisodes = parsed.filter { !existingIds.contains($0.id) }
        guard !newEpisodes.isEmpty else { return }

        #if os(tvOS)
        let batchSize = 25
        #else
        let batchSize = 100
        #endif

        var index = newEpisodes.startIndex
        while index < newEpisodes.endIndex {
            let end = Swift.min(index + batchSize, newEpisodes.endIndex)
            for parsed in newEpisodes[index ..< end] {
                let episode = Episode(
                    id: parsed.id,
                    episodeId: parsed.episodeId,
                    title: parsed.title,
                    containerExtension: parsed.containerExtension,
                    seasonNum: parsed.seasonNum,
                    episodeNum: parsed.episodeNum,
                    added: parsed.added,
                    directSource: parsed.directSource
                )
                episode.durationSecs = parsed.durationSecs
                episode.movieImage = parsed.movieImage
                episode.rating = parsed.rating
                episode.airDate = parsed.airDate
                episode.plot = parsed.plot
                episode.series = self
                context.insert(episode)
                episodes.append(episode)
            }
            try? context.save()
            // Yield the main actor so SwiftUI can process the new batch and the
            // OS watchdog sees the main thread is still responsive.
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

        do {
            // Run directly in the caller's task — no wrapping unstructured Task —
            // so cancelling the caller (e.g. the user aborting from the progress
            // sheet) propagates here and tears the sync down.
            try await performSync(playlistId: playlistId, progress: progress, full: full)
        } catch {
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
        NotificationCenter.default.post(name: .lumeContentSyncDidComplete, object: nil)
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

        try await syncMovies(for: playlist, playlistId: playlistId, progress: progress)
        try await Task.sleep(for: .seconds(2))
        try await syncSeries(for: playlist, playlistId: playlistId, progress: progress)
        try await Task.sleep(for: .seconds(2))
        try await syncLiveStreams(for: playlist, playlistId: playlistId, progress: progress)
    }

    func syncAllCategories(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil, full _: Bool = false) async throws {
        Logger.database.info("Starting VOD category sync")
        await progress?.start(.movieCategories)
        try await syncVODCategories(for: playlist, playlistId: playlistId, progress: progress)
        await progress?.complete(.movieCategories)

        Logger.database.info("Starting Series category sync")
        await progress?.start(.seriesCategories)
        try await syncSeriesCategories(for: playlist, playlistId: playlistId, progress: progress)
        await progress?.complete(.seriesCategories)

        Logger.database.info("Starting Live TV category sync")
        await progress?.start(.liveCategories)
        try await syncLiveCategories(for: playlist, playlistId: playlistId, progress: progress)
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
    /// trigger). Falls back to a single full fetch when no categories exist yet.
    func syncMovies(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        await progress?.start(.movies)
        let categories = localCategories(playlistId: playlistId, type: .vod)
        let playlistPrefix = "\(playlistId.uuidString)-\(CategoryType.vod.rawValue)-"
        var seenIds = Set<String>()
        var syncedTotal = 0

        if categories.isEmpty {
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
        }

        if !seenIds.isEmpty {
            pruneStaleMovies(playlistId: playlistId, seenIds: seenIds)
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
                await progress?.update(
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await progress?.update(
                    detail: "\(runningTotal) movies · category \(categoryProgress.current)/\(categoryProgress.total)",
                    fraction: Double(categoryProgress.current) / Double(categoryProgress.total)
                )
            }
        }
        return runningTotal
    }

    /// Syncs series in memory-bounded batches, one provider category at a time.
    func syncSeries(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        await progress?.start(.series)
        let categories = localCategories(playlistId: playlistId, type: .series)
        let playlistPrefix = "\(playlistId.uuidString)-\(CategoryType.series.rawValue)-"
        var seenIds = Set<String>()
        var syncedTotal = 0

        if categories.isEmpty {
            let seriesDTOs = try await xtreamClient.getSeries(playlist: playlist)
            syncedTotal = try await upsertSeriesBatch(
                seriesDTOs,
                playlist: playlist,
                playlistId: playlistId,
                playlistPrefix: playlistPrefix,
                seenIds: &seenIds,
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
                    progress: progress,
                    totalCount: nil,
                    syncedSoFar: syncedTotal,
                    categoryProgress: (index + 1, categories.count)
                )
            }
        }

        if !seenIds.isEmpty {
            pruneStaleSeries(playlistId: playlistId, seenIds: seenIds)
        }

        Logger.database.info("Completed syncing \(syncedTotal) series")
        await progress?.complete(.series)
    }

    private func upsertSeriesBatch(
        _ seriesDTOs: [XtreamSeries],
        playlist: Playlist,
        playlistId: UUID,
        playlistPrefix: String,
        seenIds: inout Set<String>,
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
                    applySeriesFields(from: seriesDTO, to: series, playlistPrefix: playlistPrefix, serverURL: playlist.serverURL)
                }

                try context.save()
                runningTotal += batch.count
                Logger.database.info("Synced series \(runningTotal) total (\(batchStart + 1)–\(batchEnd) in category batch)")
            }

            if let totalCount {
                await progress?.update(
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await progress?.update(
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

    private func fetchXtreamEpisodes(seriesId: Int, seriesElementId: String, playlist: Playlist) async throws -> [ParsedEpisode] {
        let seriesInfo = try await xtreamClient.getSeriesInfo(playlist: playlist, seriesId: seriesId)
        guard let episodesDict = seriesInfo.episodes else { return [] }

        var result: [ParsedEpisode] = []
        for (seasonKey, episodes) in episodesDict {
            guard let seasonNum = Int(seasonKey) else { continue }
            for episodeDTO in episodes {
                guard let episodeIdString = episodeDTO.id else { continue }
                let plot = episodeDTO.info?.plot
                result.append(ParsedEpisode(
                    id: "\(seriesElementId)-episode-\(episodeIdString)",
                    episodeId: episodeIdString,
                    title: Self.cleanEpisodeTitle(episodeDTO.title),
                    containerExtension: episodeDTO.containerExtension ?? "mkv",
                    seasonNum: seasonNum,
                    episodeNum: episodeDTO.episodeNum ?? 0,
                    added: episodeDTO.added,
                    directSource: episodeDTO.directSource,
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
    func syncLiveStreams(for playlist: Playlist, playlistId: UUID, progress: SyncProgress? = nil) async throws {
        await progress?.start(.liveStreams)
        let categories = localCategories(playlistId: playlistId, type: .live)
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
        }

        if !seenIds.isEmpty {
            pruneStaleLiveStreams(playlistId: playlistId, seenIds: seenIds)
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
                await progress?.update(
                    detail: "\(min(runningTotal, totalCount)) of \(totalCount)",
                    fraction: totalCount == 0 ? 1 : Double(min(runningTotal, totalCount)) / Double(totalCount)
                )
            } else if let categoryProgress {
                await progress?.update(
                    detail: "\(runningTotal) channels · category \(categoryProgress.current)/\(categoryProgress.total)",
                    fraction: Double(categoryProgress.current) / Double(categoryProgress.total)
                )
            }
        }
        return runningTotal
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
