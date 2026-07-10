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
    /// chunk so main-context merges stay infrequent. 50 balances throughput
    /// against memory (TMDB responses are held until save) — fewer, larger
    /// chunks mean fewer main-context merges on 20k+ catalogs.
    private let chunkSize = 50
    /// Pause between items — keeps TMDB traffic to a couple of requests per
    /// second at most.
    private let itemPause: Duration = .milliseconds(100)
    /// Pause after each chunk save — gives the UI a breathing window where no
    /// main-context merge will fire, preventing stutter during scrolling.
    private let chunkPause: Duration = .milliseconds(500)
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
                let idResolved = resolved.filter { $0.resolvedTMDBId != nil }.count
                let enriched = resolved.filter { $0.details != nil }.count
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

        var movieDescriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.indexedAt == nil })
        movieDescriptor.fetchLimit = chunkSize
        let movies = try context.fetch(movieDescriptor)
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
            let series = try context.fetch(seriesDescriptor)
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
    private func resolve(_ item: PendingItem) async throws -> IndexResult {
        guard tmdbClient.isConfigured else {
            return IndexResult(item: item, resolvedTMDBId: item.existingTMDBId, details: nil)
        }

        var tmdbId = item.existingTMDBId
        if tmdbId == nil {
            tmdbId = try await skippingPermanentFailures {
                switch item.kind {
                case .movie: try await self.searchMovieID(query: item.title, year: item.year)
                case .series: try await self.searchTVID(query: item.title, year: item.year)
                }
            }
            if tmdbId == nil {
                Logger.indexing.debug("[Search] No TMDB match for \(item.kind) '\(item.title)' (year \(item.year ?? -1))")
            }
        }

        // Background indexing resolves TMDB ids for search/matching only.
        // Full metadata (plot, cast, backdrops, OMDb ratings) loads on-demand
        // when the user opens a detail screen — fetching details for every title
        // in a 28K catalog hammers TMDB, saturates cellular, and each chunk save
        // re-runs every browse @Query via main-context merge.
        return IndexResult(item: item, resolvedTMDBId: tmdbId, details: nil)
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

    // MARK: - TMDB search with year fallback

    /// Provider year tags are often wrong, so a year-constrained search that
    /// finds nothing is retried without the year.
    private func searchMovieID(query: String, year: Int?) async throws -> Int? {
        if let id = try await tmdbClient.searchMovieID(query: query, year: year) {
            return id
        }
        guard year != nil else { return nil }
        return try await tmdbClient.searchMovieID(query: query, year: nil)
    }

    private func searchTVID(query: String, year: Int?) async throws -> Int? {
        if let id = try await tmdbClient.searchTVID(query: query, year: year) {
            return id
        }
        guard year != nil else { return nil }
        return try await tmdbClient.searchTVID(query: query, year: nil)
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
        return try context.fetchCount(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.syncStatusRaw == syncing })
        ) > 0
    }
}
