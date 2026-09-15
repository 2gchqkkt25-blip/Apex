//
//  ContentIndexer.swift
//  Apex
//
//  Builds the local content index: resolves each movie and series against
//  TMDB (searching by cleaned title when the provider supplies no id), applies
//  the same enrichment the detail screens use, and stores an on-device
//  embedding vector for future semantic search.
//
//  Designed to run slowly in the background: items are processed in small
//  chunks on a dedicated ModelContext with pauses in between, so neither TMDB
//  nor the main thread is hammered. The loop waits while a playlist sync is
//  running and while the player is up — even a background-context save forces
//  the main context to merge and re-run every @Query, which hitches KSPlayer.
//

import Foundation
import OSLog
import SwiftData

actor ContentIndexer {
    private let modelContainer: ModelContainer
    private let tmdbClient: TMDBClient

    /// Items per chunk; the context is saved and progress published once per
    /// chunk so main-context merges stay infrequent.
    private var chunkSize: Int {
        #if os(tvOS)
            10
        #else
            50
        #endif
    }

    /// Pause after each chunk save — gives the UI a breathing window where no
    /// main-context merge will fire, preventing stutter during scrolling.
    private var chunkPause: Duration {
        #if os(tvOS)
            .seconds(2)
        #else
            .milliseconds(500)
        #endif
    }

    private let itemPause: Duration = .milliseconds(100)
    /// Pause before re-checking when a sync or playback blocks indexing.
    private let busyPause: Duration = .seconds(20)
    /// First wait before retrying a failed embedding-asset download; doubles
    /// each attempt up to `assetRetryMaxPause`. The OTA asset request times out
    /// on slow connections, so we back off and retry in-pass instead of ending
    /// the run (which would stall indexing until the next launch or sync).
    private let assetRetryPause: Duration = .seconds(15)
    private let assetRetryMaxPause: Duration = .seconds(300)

    init(modelContainer: ModelContainer, tmdbClient: TMDBClient = .shared) {
        self.modelContainer = modelContainer
        self.tmdbClient = tmdbClient
    }

    // MARK: - Run loop

    /// Indexes every unindexed title, publishing progress to `status`.
    /// Returns when the library is fully indexed; throws on cancellation, on
    /// an unavailable embedding model, or on a transient network failure (the
    /// next kick retries — already-indexed items are never reprocessed).
    func run(status: ContentIndexingService) async throws {
        var counts = try currentCounts()
        await status.update(indexed: counts.indexed, total: counts.total)
        guard counts.indexed < counts.total else {
            // Even when fully indexed, run the rating backfill — titles
            // indexed before vote-average capture was added still need it.
            await backfillMissingRatings()
            await status.finish(indexed: counts.indexed, total: counts.total)
            return
        }

        let embedder: TextEmbedder?
        let embeddingReady: Bool
        #if os(tvOS)
            // NLContextualEmbedding is unavailable on tvOS — skip the model download
            // and retry loop (15s+ wasted at every indexing pass).
            embedder = nil
            embeddingReady = false
            Logger.indexing.info("Skipping TextEmbedder on tvOS — proceeding with TMDB id indexing only")
        #else
            await status.setPreparing()
            do {
                let model = try TextEmbedder()
                embedder = model
                defer { model.unload() }
                do {
                    try await prepareEmbedder(model, status: status)
                    embeddingReady = true
                } catch {
                    // Embedding model unavailable (common in Simulator). Proceed without
                    // semantic-search vectors — TMDB enrichment still runs.
                    Logger.indexing.warning("Embedding model unavailable; proceeding with TMDB enrichment only: \(error)")
                    embeddingReady = false
                }
            } catch {
                // TextEmbedder() itself failed (model not available on this device).
                // Proceed with TMDB enrichment only — no semantic-search vectors.
                Logger.indexing.warning("TextEmbedder unavailable; proceeding with TMDB enrichment only: \(error)")
                embedder = nil
                embeddingReady = false
            }
        #endif

        Logger.indexing.info("Content index pass starting: \(counts.total - counts.indexed) of \(counts.total) titles remaining")
        var chunksSinceTotalRefresh = 0
        while !Task.isCancelled {
            if try await hasActiveSync()
                || status.isPlaybackActive
                || status.isCloudSyncActive
                || status.isBrowsePaused
                || EPGSyncGate.isActive
                || MediaSyncGate.isActive
                || MediaConnectGate.isActive
            {
                Logger.indexing.debug("Indexer pausing: blocked by active sync, playback, cloud sync, browse, or EPG import")
                await status.setWaiting()
                try await Task.sleep(for: busyPause)
                continue
            }

            let processed = try await indexNextChunk(embedder: embeddingReady ? embedder : nil)
            if processed == 0 { break }
            counts.indexed += processed
            chunksSinceTotalRefresh += 1
            // Re-count the catalog total occasionally (sync may add rows mid-pass);
            // indexed count is incremented locally so we skip four fetchCounts per chunk.
            if chunksSinceTotalRefresh >= 10 {
                counts.total = try currentCounts().total
                chunksSinceTotalRefresh = 0
            }
            await status.update(indexed: counts.indexed, total: counts.total)
            try await Task.sleep(for: chunkPause)
        }

        try Task.checkCancellation()
        counts = try currentCounts()
        await status.finish(indexed: counts.indexed, total: counts.total)
        Logger.indexing.info("Content index complete: \(counts.indexed) of \(counts.total) titles")

        // Backfill ratings for already-indexed titles that have a TMDB id
        // but no rating yet (indexed before vote-average capture was added).
        // Uses the lightweight search endpoint — no detail fetch needed.
        await backfillMissingRatings()
    }

    /// Fills missing poster scores after a playlist sync. Known TMDB ids use a
    /// lightweight score endpoint; titles without ids use TMDB search, whose
    /// result already includes `vote_average`. SwiftData objects never cross a
    /// network suspension point.
    func backfillMissingRatings(playlistID: UUID? = nil, maxCandidates: Int? = nil) async {
        guard tmdbClient.isConfigured else {
            Logger.indexing.warning("[Backfill] TMDB client not configured — skipping")
            return
        }
        var candidates = fetchRatingCandidates(playlistID: playlistID)
        if let maxCandidates, candidates.count > maxCandidates {
            candidates = Array(candidates.prefix(maxCandidates))
        }
        guard !candidates.isEmpty else { return }
        Logger.indexing.info("[Backfill] Resolving scores for \(candidates.count) titles")

        var updated = 0
        for start in stride(from: 0, to: candidates.count, by: 25) {
            guard await waitForRatingWork() else { return }
            let end = min(start + 25, candidates.count)
            let batch = Array(candidates[start ..< end])
            let results = await resolveRatings(batch)
            updated += writeRatings(results)
            // Keep the sustained request rate below TMDB's burst threshold for
            // large catalogs. Without this, later batches can all receive 429s
            // before the posters the user is viewing are reached.
            if end < candidates.count {
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        Logger.indexing.info("[Backfill] Saved TMDB scores for \(updated)/\(candidates.count) titles")
    }

    private enum RatingKind: Sendable { case movie, series }

    private struct RatingCandidate: Sendable {
        let kind: RatingKind
        let id: String
        let title: String
        let originalTitle: String
        let year: Int?
        let tmdbID: Int?
    }

    private struct RatingResult: Sendable {
        let candidate: RatingCandidate
        let tmdbID: Int?
        let score: Double
    }

    private func fetchRatingCandidates(playlistID: UUID?) -> [RatingCandidate] {
        let context = ModelContext(modelContainer)
        let prefix = playlistID?.uuidString ?? ""
        let movieDescriptor = playlistID == nil
            ? FetchDescriptor<Movie>()
            : FetchDescriptor<Movie>(predicate: #Predicate { $0.id.starts(with: prefix) })
        let seriesDescriptor = playlistID == nil
            ? FetchDescriptor<Series>()
            : FetchDescriptor<Series>(predicate: #Predicate { $0.id.starts(with: prefix) })

        let movies = ((try? context.fetch(movieDescriptor)) ?? []).compactMap { movie -> RatingCandidate? in
            guard movie.rating <= 0 else { return nil }
            let query = ContentIndexText.searchQuery(for: movie.name)
            return RatingCandidate(
                kind: .movie,
                id: movie.id,
                title: query.title,
                originalTitle: movie.name,
                year: ContentIndexText.year(fromReleaseDate: movie.releaseDate) ?? query.year,
                tmdbID: movie.tmdbId
            )
        }
        let series = ((try? context.fetch(seriesDescriptor)) ?? []).compactMap { item -> RatingCandidate? in
            guard (Double(item.rating ?? "") ?? 0) <= 0 else { return nil }
            let query = ContentIndexText.searchQuery(for: item.name)
            return RatingCandidate(
                kind: .series,
                id: item.id,
                title: query.title,
                originalTitle: item.name,
                year: ContentIndexText.year(fromReleaseDate: item.releaseDate) ?? query.year,
                tmdbID: item.tmdbId
            )
        }

        // Alternate media types instead of appending every series after every
        // movie. Large IPTV catalogs commonly contain thousands of movies;
        // concatenation meant users could see movie scores for hours before
        // the first series score was even requested.
        var candidates: [RatingCandidate] = []
        candidates.reserveCapacity(movies.count + series.count)
        let count = max(movies.count, series.count)
        for index in 0 ..< count {
            if index < movies.count { candidates.append(movies[index]) }
            if index < series.count { candidates.append(series[index]) }
        }
        return candidates
    }

    private func resolveRatings(_ candidates: [RatingCandidate]) async -> [RatingResult] {
        await withTaskGroup(of: RatingResult?.self, returning: [RatingResult].self) { group in
            var iterator = candidates.makeIterator()
            var running = 0
            var results: [RatingResult] = []

            func schedule() {
                while running < 4, let candidate = iterator.next() {
                    running += 1
                    group.addTask { [tmdbClient] in
                        func searchByTitle() async throws -> (id: Int, voteAverage: Double?)? {
                            switch candidate.kind {
                            case .movie:
                                if let result = try await tmdbClient.searchMovie(query: candidate.title, year: candidate.year) {
                                    result
                                } else if candidate.year != nil,
                                          let result = try await tmdbClient.searchMovie(query: candidate.title, year: nil)
                                {
                                    result
                                } else if candidate.originalTitle != candidate.title {
                                    try await tmdbClient.searchMovie(query: candidate.originalTitle, year: nil)
                                } else {
                                    nil
                                }
                            case .series:
                                if let result = try await tmdbClient.searchTV(query: candidate.title, year: candidate.year) {
                                    result
                                } else if candidate.year != nil,
                                          let result = try await tmdbClient.searchTV(query: candidate.title, year: nil)
                                {
                                    result
                                } else if candidate.originalTitle != candidate.title {
                                    try await tmdbClient.searchTV(query: candidate.originalTitle, year: nil)
                                } else {
                                    nil
                                }
                            }
                        }

                        for attempt in 0 ..< 3 {
                            do {
                                let match: (id: Int, voteAverage: Double?)?
                                if let tmdbID = candidate.tmdbID, tmdbID > 0 {
                                    do {
                                        let score = switch candidate.kind {
                                        case .movie: try await tmdbClient.movieRating(tmdbID)
                                        case .series: try await tmdbClient.tvRating(tmdbID)
                                        }
                                        match = if let score, score > 0 {
                                            (tmdbID, score)
                                        } else {
                                            try await searchByTitle()
                                        }
                                    } catch TMDBError.serverError(404) {
                                        match = try await searchByTitle()
                                    }
                                } else {
                                    match = try await searchByTitle()
                                }
                                guard let match, let score = match.voteAverage, score > 0 else { return nil }
                                return RatingResult(candidate: candidate, tmdbID: match.id, score: score)
                            } catch TMDBError.serverError(429) where attempt < 2 {
                                try? await Task.sleep(for: .seconds(attempt + 1))
                            } catch {
                                Logger.indexing.debug("[Backfill] TMDB score failed for \(candidate.id): \(error.localizedDescription)")
                                return nil
                            }
                        }
                        return nil
                    }
                }
            }

            schedule()
            for await result in group {
                running -= 1
                if let result { results.append(result) }
                schedule()
            }
            return results
        }
    }

    private func writeRatings(_ results: [RatingResult]) -> Int {
        guard !results.isEmpty else { return 0 }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var updated = 0
        for result in results {
            let id = result.candidate.id
            switch result.candidate.kind {
            case .movie:
                var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let movie = try? context.fetch(descriptor).first, movie.rating <= 0 else { continue }
                if let resolvedID = result.tmdbID, resolvedID > 0, movie.tmdbId != resolvedID {
                    movie.tmdbId = resolvedID
                }
                movie.rating = result.score
            case .series:
                var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let series = try? context.fetch(descriptor).first,
                      (Double(series.rating ?? "") ?? 0) <= 0 else { continue }
                if let resolvedID = result.tmdbID, resolvedID > 0, series.tmdbId != resolvedID {
                    series.tmdbId = resolvedID
                }
                series.rating = String(format: "%.1f", result.score)
            }
            updated += 1
        }
        guard updated > 0 else { return 0 }
        do {
            try context.save()
            return updated
        } catch {
            Logger.indexing.error("[Backfill] Rating batch save failed: \(error.localizedDescription)")
            return 0
        }
    }

    private func waitForRatingWork() async -> Bool {
        while !Task.isCancelled {
            let busy = await MainActor.run {
                let service = ContentIndexingService.shared
                return service.isPlaybackActive || service.isCloudSyncActive || service.isBrowsePaused
            }
            // Poster scores are intentionally independent of EPG refresh. The
            // guide can run for minutes after a playlist refresh; making rating
            // work wait for it left every poster blank during normal use.
            if !busy, !MediaSyncGate.isActive, !MediaConnectGate.isActive {
                return true
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return false
    }

    /// Loads the embedding model, waiting and retrying when its assets fail to
    /// download. The on-device asset request times out on slow connections;
    /// rather than abandoning the pass (which leaves indexing stalled until the
    /// next launch or sync) we back off and try again — the download usually
    /// succeeds on a later attempt. A model that genuinely has no assets for
    /// this device throws `EmbedderError`, which ends the run for good.
    /// After `maxAssetRetries` transient failures, gives up so TMDB enrichment
    /// can still proceed without semantic-search vectors.
    private func prepareEmbedder(_ embedder: TextEmbedder, status: ContentIndexingService) async throws {
        var pause = assetRetryPause
        var attempts = 0
        let maxAssetRetries = 4
        while attempts < maxAssetRetries {
            try Task.checkCancellation()
            do {
                try await embedder.prepare()
                return
            } catch let error as TextEmbedder.EmbedderError {
                throw error
            } catch {
                attempts += 1
                guard attempts < maxAssetRetries else { throw error }
                let seconds = pause.components.seconds
                Logger.indexing.warning("Embedding asset download failed, retrying in \(seconds)s (attempt \(attempts)/\(maxAssetRetries)): \(error)")
                await status.setWaiting()
                try await Task.sleep(for: pause)
                pause = min(pause * 2, assetRetryMaxPause)
                await status.setPreparing()
            }
        }
    }

    // MARK: - Chunk processing

    /// What a title is, and the few fields the TMDB lookup needs — copied out of
    /// SwiftData as plain values so the network phase never touches a managed
    /// object. `title`/`year` are the cleaned search query; they also seed the
    /// embedding document.
    private enum ItemKind: CustomStringConvertible { case movie, series
        var description: String {
            switch self { case .movie: "movie"; case .series: "series" }
        }
    }

    private struct PendingItem {
        let kind: ItemKind
        let id: String
        let title: String
        let year: Int?
        let existingTMDBId: Int?
        let needsEnrichment: Bool
    }

    /// The TMDB data resolved for a pending item, ready to write back.
    private struct IndexResult {
        let item: PendingItem
        let resolvedTMDBId: Int?
        /// Vote average captured from the TMDB search response — persisted
        /// during indexing so poster cards show ratings immediately without
        /// waiting for detail-view enrichment.
        let resolvedVoteAverage: Double?
        let details: TMDBTitleDetails?
    }

    /// Indexes up to `chunkSize` pending titles (movies first, then series).
    /// Returns the number processed; 0 means the index is complete.
    ///
    /// Split into two phases so a managed object is never accessed across an
    /// `await`. The original loop held the fetched `Movie`/`Series` objects on a
    /// single context while awaiting TMDB over the network; resuming and then
    /// touching a property re-faulted it from the store — and if CloudKit had
    /// torn down and re-added stores on the shared coordinator in the meantime
    /// (the multi-store container shares one coordinator), the fault threw an
    /// uncatchable `no such table` `NSException` that terminated the app. Here
    /// the only phase that suspends works purely on value snapshots; the
    /// objects are re-fetched and mutated synchronously while the store is open.
    private func indexNextChunk(embedder: TextEmbedder?) async throws -> Int {
        let pending = try fetchPending()
        guard !pending.isEmpty else { return 0 }

        Logger.indexing.debug("Indexing chunk of \(pending.count) items")

        // Phase 1 — network only. Touches no SwiftData object, so nothing can
        // fault against the store across a suspension point.
        var resolved: [IndexResult] = []
        var failure: Error?
        for item in pending {
            do {
                try Task.checkCancellation()
                try await resolved.append(resolve(item))
                try await Task.sleep(for: itemPause)
            } catch {
                // Transient failure or cancellation: stop fetching, but still
                // write the items already resolved so progress isn't lost.
                failure = error
                break
            }
        }

        // Phase 2 — write back fully synchronously (re-fetch → apply → embed →
        // stamp), then save once. No `await` here means the objects are
        // realised while the store is open, and one save per chunk keeps
        // main-context merges (which re-run every @Query) infrequent.
        if !resolved.isEmpty {
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            for result in resolved {
                write(result, context: context, embedder: embedder)
            }
            do {
                try context.save()
                let idResolved = resolved.count(where: { $0.resolvedTMDBId != nil })
                let enriched = resolved.count(where: { $0.details != nil })
                Logger.indexing.info("Indexed chunk: \(resolved.count) titles (TMDB: \(enriched) enriched, \(idResolved) id-resolved)")
            } catch {
                failure = failure ?? error
            }
        }

        if let failure { throw failure }
        return resolved.count
    }

    /// Snapshots the next chunk of unindexed titles into plain values.
    private func fetchPending() throws -> [PendingItem] {
        let context = ModelContext(modelContainer)
        let mediaServerIDs = try Set(context.fetch(FetchDescriptor<MediaServer>()).map(\.id.uuidString))

        func isMediaServerCatalog(_ id: String) -> Bool {
            MediaServerIdentity.belongsToKnownMediaServer(id, serverIDs: mediaServerIDs)
        }

        var movieDescriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.indexedAt == nil })
        movieDescriptor.fetchLimit = chunkSize
        let movies = try context.fetch(movieDescriptor).filter { !isMediaServerCatalog($0.id) }
        var items: [PendingItem] = movies.map { movie in
            let query = ContentIndexText.searchQuery(for: movie.name)
            return PendingItem(
                kind: .movie,
                id: movie.id,
                title: query.title,
                year: ContentIndexText.year(fromReleaseDate: movie.releaseDate) ?? query.year,
                existingTMDBId: movie.tmdbId,
                needsEnrichment: movie.tmdbEnrichedAt == nil
            )
        }

        if movies.count < chunkSize {
            var seriesDescriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.indexedAt == nil })
            seriesDescriptor.fetchLimit = chunkSize - movies.count
            let series = try context.fetch(seriesDescriptor).filter { !isMediaServerCatalog($0.id) }
            items += series.map { item in
                let query = ContentIndexText.searchQuery(for: item.name)
                return PendingItem(
                    kind: .series,
                    id: item.id,
                    title: query.title,
                    year: ContentIndexText.year(fromReleaseDate: item.releaseDate) ?? query.year,
                    existingTMDBId: item.tmdbId,
                    needsEnrichment: item.tmdbEnrichedAt == nil
                )
            }
        }

        return items
    }

    /// Resolves an item's TMDB id (searching when absent) and detail payload
    /// (when not yet enriched) over the network, working only on values.
    /// Also captures the vote average from the search response so poster
    /// cards can show ratings immediately without waiting for detail enrichment.
    private func resolve(_ item: PendingItem) async throws -> IndexResult {
        guard tmdbClient.isConfigured else {
            return IndexResult(item: item, resolvedTMDBId: item.existingTMDBId, resolvedVoteAverage: nil, details: nil)
        }

        var tmdbId = item.existingTMDBId
        var voteAverage: Double?
        if tmdbId == nil {
            // Provider year tags are often wrong, so a year-constrained search
            // that finds nothing is retried without the year — same fallback
            // the old searchMovieID/searchTVID helpers provided.
            let match = try await skippingPermanentFailures {
                switch item.kind {
                case .movie:
                    if let m = try await self.tmdbClient.searchMovie(query: item.title, year: item.year) {
                        return m
                    }
                    guard item.year != nil else { return nil }
                    return try await self.tmdbClient.searchMovie(query: item.title, year: nil)
                case .series:
                    if let m = try await self.tmdbClient.searchTV(query: item.title, year: item.year) {
                        return m
                    }
                    guard item.year != nil else { return nil }
                    return try await self.tmdbClient.searchTV(query: item.title, year: nil)
                }
            }
            tmdbId = match?.id
            voteAverage = match?.voteAverage
            if tmdbId == nil {
                Logger.indexing.debug("[Search] No TMDB match for \(item.kind) '\(item.title)' (year \(item.year ?? -1))")
            }
        }

        // Background indexing resolves TMDB ids for search/matching only.
        // Full metadata (plot, cast, backdrops, OMDb ratings) loads on-demand
        // when the user opens a detail screen — fetching details for every title
        // in a 28K catalog hammers TMDB, saturates cellular, and each chunk save
        // re-runs every browse @Query via main-context merge.
        return IndexResult(item: item, resolvedTMDBId: tmdbId, resolvedVoteAverage: voteAverage, details: nil)
    }

    /// Re-fetches the title on the write context and applies the resolved TMDB
    /// data, embedding and index stamp. Synchronous: the object is realised and
    /// mutated while the store is open, never across an `await`. A title that
    /// vanished since Phase 1 (deleted by a sync) is silently skipped.
    private func write(_ result: IndexResult, context: ModelContext, embedder: TextEmbedder?) {
        switch result.item.kind {
        case .movie:
            let id = result.item.id
            var descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let movie = try? context.fetch(descriptor).first else {
                Logger.indexing.warning("Movie \(result.item.id) vanished before write phase — skipped by sync")
                return
            }

            if movie.tmdbId == nil, let tmdbId = result.resolvedTMDBId {
                movie.tmdbId = tmdbId
            }
            // Persist the vote average from the search response so poster
            // cards show ratings immediately — no extra API call needed.
            // Only write when the field is still zero (provider default) to
            // avoid overwriting a value already set by detail enrichment.
            if movie.rating == 0, let vote = result.resolvedVoteAverage, vote > 0 {
                movie.rating = vote
            }
            if let details = result.details {
                // Background context: skip the cast relationship — see
                // applyMovieDetails. The embedding uses `movie.actors`, and the
                // detail view fully enriches (incl. cast) on first open.
                applyMovieDetails(details, to: movie, context: context, includeCast: false)
            }
            if let embedder {
                let document = ContentIndexText.document(for: .init(
                    name: result.item.title,
                    year: result.item.year,
                    genre: movie.genre,
                    tagline: movie.tagline,
                    plot: movie.plot,
                    cast: movie.actors
                ))
                if let vector = try? embedder.vector(for: document) {
                    movie.embeddingData = TextEmbedder.encode(vector)
                }
            }
            movie.indexedAt = Date()

        case .series:
            let id = result.item.id
            var descriptor = FetchDescriptor<Series>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let series = try? context.fetch(descriptor).first else {
                Logger.indexing.warning("Series \(result.item.id) vanished before write phase — skipped by sync")
                return
            }

            if series.tmdbId == nil, let tmdbId = result.resolvedTMDBId {
                series.tmdbId = tmdbId
            }
            // Persist the vote average from the search response so poster
            // cards show ratings immediately — no extra API call needed.
            // Only write when the field is still empty/zero to avoid
            // overwriting a value already set by detail enrichment.
            let currentSeriesRating = Double(series.rating ?? "") ?? 0
            if currentSeriesRating == 0, let vote = result.resolvedVoteAverage, vote > 0 {
                series.rating = String(format: "%.1f", vote)
            }
            if let details = result.details {
                // Background context: skip the cast relationship — see
                // applySeriesDetails. The embedding uses the `series.cast`
                // string; the detail view fully enriches (incl. cast) later.
                applySeriesDetails(details, to: series, context: context, includeCast: false)
            }
            if let embedder {
                let document = ContentIndexText.document(for: .init(
                    name: result.item.title,
                    year: result.item.year,
                    genre: series.genre,
                    tagline: series.tagline,
                    plot: series.plot,
                    cast: series.cast
                ))
                if let vector = try? embedder.vector(for: document) {
                    series.embeddingData = TextEmbedder.encode(vector)
                }
            }
            series.indexedAt = Date()
        }
    }

    /// Runs a TMDB request, converting *permanent* failures (no match, bad
    /// payload) into nil so the item proceeds without TMDB data. Transient
    /// failures (offline, 5xx, rate limit) rethrow and end the run — the next
    /// kick retries those items.
    private func skippingPermanentFailures<T>(_ request: () async throws -> T?) async throws -> T? {
        do {
            return try await request()
        } catch let error as TMDBError {
            switch error {
            case let .serverError(code) where code == 404:
                return nil
            case .decodingError, .invalidURL, .missingToken:
                return nil
            case .serverError, .invalidResponse:
                throw error
            }
        }
    }

    // MARK: - Store queries

    private func currentCounts() throws -> (indexed: Int, total: Int) {
        let context = ModelContext(modelContainer)
        let totalMovies = try context.fetchCount(FetchDescriptor<Movie>())
        let totalSeries = try context.fetchCount(FetchDescriptor<Series>())
        let indexedMovies = try context.fetchCount(
            FetchDescriptor<Movie>(predicate: #Predicate { $0.indexedAt != nil })
        )
        let indexedSeries = try context.fetchCount(
            FetchDescriptor<Series>(predicate: #Predicate { $0.indexedAt != nil })
        )
        return (indexedMovies + indexedSeries, totalMovies + totalSeries)
    }

    private func hasActiveSync() throws -> Bool {
        let context = ModelContext(modelContainer)
        let syncing = SyncStatus.syncing.rawValue
        let playlistSyncing = try context.fetchCount(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.syncStatusRaw == syncing })
        ) > 0
        let mediaSyncing = try context.fetchCount(
            FetchDescriptor<MediaServer>(predicate: #Predicate { $0.syncStatusRaw == syncing })
        ) > 0
        return playlistSyncing || mediaSyncing
    }
}
