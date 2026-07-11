//
//  EPGSyncManager.swift
//  Apex
//
//  Orchestrates a full "Sync Now" pass over every enabled EPG source. For
//  Xtream playlists the primary source is one `xmltv.php` download (seconds
//  for a current bulk dump); per-channel `get_short_epg` is only a fallback
//  when the dump is empty or stale, and for on-demand gap-fill of visible
//  channels.
//
//  For M3U / manual sources, downloads the XMLTV file and imports it via
//  `EPGInserter`.
//

import Foundation
import OSLog
import SwiftData

/// How aggressively to fetch external EPG during a playlist refresh vs a full
/// manual guide sync from Settings.
enum EPGSyncMode: Sendable {
    /// All 14 regional feeds; may take several minutes.
    case full
    /// US feeds only, stop once ~88% of channels are matched.
    case withPlaylist
    /// tvOS inline: only the 2-3 lightest/highest-yield feeds (~30MB total).
    /// Small enough to parse during the playlist sync sheet without jetsam risk,
    /// while populating the store for the majority of channels instantly.
    case tvOSQuick
}

actor EPGSyncManager {
    let modelContainer: ModelContainer
    private let m3uClient: M3UClient
    private let xtreamClient: XtreamClient
    private let bulkSyncClient: XtreamClient
    private let xtreamDownloadClient: XtreamClient

    init(
        modelContainer: ModelContainer,
        m3uClient: M3UClient = M3UClient(urlSession: M3UClient.makeEPGDownloadSession())
    ) {
        self.modelContainer = modelContainer
        self.m3uClient = m3uClient
        self.xtreamClient = XtreamClient(urlSession: XtreamClient.makeEPGImportSession())
        self.bulkSyncClient = XtreamClient(urlSession: XtreamClient.makeEPGBulkSyncSession())
        self.xtreamDownloadClient = XtreamClient(urlSession: XtreamClient.makeEPGImportSession())
    }

    typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int) -> Void
    typealias ExternalEPGProgressHandler = @Sendable (
        _ matchedChannels: Int,
        _ totalChannels: Int,
        _ feedIndex: Int,
        _ feedCount: Int,
        _ feedLabel: String
    ) -> Void

    // MARK: - Public entry point

    /// Refreshes the guide from every enabled source. Returns `true` when at
    /// least one source synced successfully.
    @discardableResult
    func syncAllSources(
        mode: EPGSyncMode = .full,
        onProgress: ProgressHandler? = nil
    ) async -> Bool {
        await EPGBackgroundPrefetch.shared.cancel()

        reconcileLinkedSources()

        let sources = enabledSources()
        guard !sources.isEmpty else {
            Logger.database.info("No enabled EPG sources, skipping EPG sync")
            return false
        }

        let catalog = channelCatalog()
        guard !catalog.identities.isEmpty else {
            Logger.database.info("No live streams with EPG channel IDs, skipping EPG sync")
            return false
        }

        var anySucceeded = false
        var completedChannels = 0
        let totalChannels = catalog.identities.count

        for source in sources {
            let identities = scopedChannelData(source: source, all: catalog)
            let currentOffset = completedChannels
            let succeeded = await sync(
                source: source,
                identities: identities,
                catalog: EPGChannelCatalog(identities: identities),
                mode: mode,
                onProgress: { completed, _ in
                    let overall = min(currentOffset + completed, totalChannels)
                    onProgress?(overall, totalChannels)
                }
            )
            completedChannels += identities.count
            anySucceeded = anySucceeded || succeeded
        }

        if anySucceeded {
            Self.pruneExpiredListings(in: modelContainer)
            Self.trimExcessListings(in: modelContainer)
        }

        return anySucceeded
    }

    // MARK: - Per-source dispatch

    private func sync(
        source: SourceInfo,
        identities: [ChannelRef],
        catalog: EPGChannelCatalog,
        mode: EPGSyncMode,
        onProgress: ProgressHandler?
    ) async -> Bool {
        markStatus(source.id, .syncing)

        guard !source.url.isEmpty else {
            markStatus(source.id, .error)
            return false
        }

        do {
            if let playlistID = source.playlistID,
               let playlist = playlist(for: playlistID) {
                if playlist.sourceType == .xtream {
                    let result = await syncXtreamAPI(
                        source: source,
                        playlist: playlist,
                        identities: identities,
                        mode: mode,
                        onProgress: onProgress
                    )
                    markSynced(source.id)
                    return result
                }
            }

            // M3U / manual XMLTV sources
            let outcome = await syncXMLTV(
                source: source,
                playlist: nil,
                scoped: identities,
                alignToNow: false
            )
            switch outcome {
            case .succeeded:
                markSynced(source.id)
                return true
            default:
                markStatus(source.id, .error)
                return false
            }
        }
    }

    // MARK: - Xtream API sync

    private func syncXtreamAPI(
        source: SourceInfo,
        playlist: PlaylistInfo,
        identities: [ChannelRef],
        mode: EPGSyncMode,
        onProgress: ProgressHandler?
    ) async -> Bool {
        // Try external EPG sources first (they have current data)
        let externalMatchedChannels = await syncExternalEPG(
            identities: identities,
            sourceID: source.id,
            mode: mode,
            onProgress: { matched, total, feedIndex, feedCount, feedLabel in
                onProgress?(matched, total)
                Task { @MainActor in
                    let pct = total > 0 ? Int((Double(matched) / Double(total) * 100).rounded()) : 0
                    EPGSyncService.shared.updateSyncProgress(
                        fraction: total > 0 ? Double(matched) / Double(total) : nil,
                        label: "\(pct)% · \(feedLabel) (\(feedIndex)/\(feedCount))"
                    )
                }
            }
        )
        if !externalMatchedChannels.isEmpty {
            onProgress?(identities.count, identities.count)
            Logger.database.warning("EPG external matched \(externalMatchedChannels.count) channels — \(identities.count - externalMatchedChannels.count) remaining load on-demand via live API")
            // Unmatched channels (like regional variants) get their data from
            // the live per-stream API when the user browses to them. That API
            // returns the correct current programme for each specific stream.
            markSynced(source.id)
            return true
        }

        let credentials = EPGPlaylistCredentials(
            id: playlist.id,
            sourceType: .xtream,
            serverURL: playlist.serverURL,
            username: playlist.username,
            password: playlist.password,
            serverTimezone: playlist.serverTimezone
        )

        // Determine the best EPG URL: prefer discovered/configured external URL
        let externalEPGURL: String? = {
            if let epg = playlist.epgURL, !epg.isEmpty { return epg }
            return nil
        }()

        // Try M3U header discovery if no external URL is configured
        let discoveredURL: String?
        if externalEPGURL == nil {
            discoveredURL = await xtreamClient.discoverM3UHeaderEPGURL(
                serverURL: playlist.serverURL,
                username: playlist.username,
                password: playlist.password
            )
            if let discoveredURL, !discoveredURL.isEmpty {
                persistDiscoveredEPGURL(discoveredURL, playlistID: playlist.id)
            }
        } else {
            discoveredURL = nil
        }

        let effectiveExternalURL = externalEPGURL ?? discoveredURL
        let xmltvPhpURL = buildXMLTVPhpURL(credentials: credentials)

        // If an external EPG URL exists and differs from xmltv.php, try it first
        if let externalURL = effectiveExternalURL,
           !externalURL.isEmpty,
           externalURL != xmltvPhpURL {
            Logger.database.warning("EPG trying external URL first: \(externalURL, privacy: .public)")
            let outcome = await syncXMLTV(
                source: source,
                playlist: playlist,
                scoped: identities,
                alignToNow: false,
                overrideURL: externalURL
            )
            switch outcome {
            case .succeeded:
                return true
            case .staleBulkFeed:
                Logger.database.warning("EPG external URL stale, trying xmltv.php")
            case .downloadFailed, .parsedNoUsableData:
                Logger.database.warning("EPG external URL failed, trying xmltv.php")
            }
        }

        // Download xmltv.php
        let skipXMLTV = EPGStaleXMLTVCache.shouldSkipXMLTVDownload(playlistID: playlist.id)
        if !skipXMLTV {
            let outcome = await syncXMLTV(
                source: source,
                playlist: playlist,
                scoped: identities,
                alignToNow: false
            )
            switch outcome {
            case .succeeded:
                EPGStaleXMLTVCache.clearXMLTVBulkStale(playlistID: playlist.id)
                return true
            case .staleBulkFeed:
                EPGStaleXMLTVCache.markXMLTVBulkStale(playlistID: playlist.id)
                Logger.database.warning("EPG xmltv.php is stale, falling back to API prime")
                let strategy = EPGProviderStrategy.apiOnDemand
                EPGStaleXMLTVCache.logStrategy(strategy, playlistName: source.name, playlistID: playlist.id)
                await syncAPIPrime(
                    strategy: strategy,
                    result: nil,
                    credentials: credentials,
                    identities: identities,
                    sourceID: source.id
                )
                return true
            case .downloadFailed, .parsedNoUsableData:
                Logger.database.warning("EPG xmltv.php failed/empty, falling back to API prime")
                let strategy = EPGProviderStrategy.apiFallback
                EPGStaleXMLTVCache.logStrategy(strategy, playlistName: source.name, playlistID: playlist.id)
                await syncAPIPrime(
                    strategy: strategy,
                    result: nil,
                    credentials: credentials,
                    identities: identities,
                    sourceID: source.id
                )
                return true
            }
        } else {
            // Skip XMLTV download (known stale), go straight to API prime
            let strategy = EPGProviderStrategy.apiOnDemand
            EPGStaleXMLTVCache.logStrategy(strategy, playlistName: source.name, playlistID: playlist.id)
            await syncAPIPrime(
                strategy: strategy,
                result: nil,
                credentials: credentials,
                identities: identities,
                sourceID: source.id
            )
            return true
        }
    }

    // MARK: - External EPG sources

    private static let externalCoverageSkipRatio = 0.82
    private static let bundledCoverageSkipRatio = 0.75
    private static let bundledCoverageStopRatio = 0.88

    private func syncExternalEPG(
        identities: [ChannelRef],
        sourceID: UUID,
        mode: EPGSyncMode,
        onProgress: ExternalEPGProgressHandler? = nil
    ) async -> Set<String> {
        let bundled: Bool
        switch mode {
        case .withPlaylist, .tvOSQuick: bundled = true
        case .full: bundled = false
        }
        let urls = ExternalEPGSources.urlsForPlaylist(
            channelNames: identities.map(\.name),
            bundled: bundled,
            mode: mode
        )
        guard !urls.isEmpty else { return [] }

        Logger.database.warning("EPG trying \(urls.count) external EPG source(s) (mode: \(String(describing: mode)))")

        let syncNow = Date()

        // The UI can transition into Live TV while the external guide is still
        // parsing — a routine playlist-refresh sync or the periodic background
        // refresh both run without blocking browse, on every platform. Clearing
        // `EPGListing` makes the guide blank, which then triggers extra
        // on-demand EPG fetching and looks like the app is "lagging" / "stuck"
        // (and it disappears again when returning).
        //
        // For bundled passes, preserve existing rows and only insert rows with
        // listing ids that don't already exist. This avoids SwiftData
        // unique-upsert conflicts without forcing a full store wipe. Only an
        // explicit full Settings -> Sync Now pass (`mode: .full`) does a hard
        // replace.
        let preserveExistingStore = bundled

        let existingListingIDs: Set<String>
        let existingCountByChannel: [String: Int]
        if preserveExistingStore {
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            let channelIds = Set(identities.map(\.primaryEPGChannelId))
            let pastCutoff = syncNow.addingTimeInterval(-EPGRetention.pastGrace)
            let futureCutoff = syncNow.addingTimeInterval(EPGRetention.futureHorizon)
            let existing = (try? context.fetch(
                FetchDescriptor<EPGListing>(
                    predicate: #Predicate<EPGListing> {
                        channelIds.contains($0.channelId) && $0.end > pastCutoff && $0.start < futureCutoff
                    }
                )
            )) ?? []
            existingListingIDs = Set(existing.map(\.id))
            existingCountByChannel = Dictionary(grouping: existing, by: \.channelId).mapValues(\.count)
        } else {
            // Preserve mode off — we will clear below and can start with an empty
            // "seen" set.
            existingListingIDs = []
            existingCountByChannel = [:]
        }

        if !preserveExistingStore {
            // Clear the store once at the start of the external pass so every
            // insert below is a fresh row.
            let clearContext = ModelContext(modelContainer)
            clearContext.autosaveEnabled = false
            try? clearContext.delete(model: EPGListing.self)
            try? clearContext.save()
        }

        var totalInserted = 0
        var matchedChannelIDs = Set<String>()
        // Accumulates every listing id inserted by *any* feed processed so far
        // in this pass. Each feed runs in its own `Task.detached` with its own
        // `ModelContext`, so without this a later feed has no way to know a
        // duplicate id (a channel/timeslot two feeds both cover) was already
        // committed by an earlier feed in the same pass — inserting it again
        // hits SwiftData's unique-attribute upsert path, which remaps the
        // persistent identifier and crashes ("fatal logic error in
        // DefaultStore"). Re-seeded into each feed's local `insertedIDs` below.
        var insertedIDsSoFar = existingListingIDs
        // Accumulates each channel's *total* row count — store + everything
        // inserted by earlier feeds this pass. `maxListingsPerChannel` only
        // means anything if it bounds a channel's total, but with
        // `preserveExistingStore` on, the store is never wiped between syncs;
        // a counter that reset to zero for every feed (and every sync) let a
        // channel covered by several feeds gain a fresh capful from each one,
        // every playlist refresh and every background sync, forever — bloating
        // the guide grid (which renders every row as a cell, unlike the list's
        // fixed now/next) until it rendered slowly or crashed outright.
        var listingCountSoFar = existingCountByChannel
        let totalChannels = identities.count

        // --- Parallel download phase ---
        // Other IPTV apps load EPG in seconds because they download all feeds
        // concurrently. The previous sequential download+parse loop spent most
        // of its 3-4 minutes waiting on network. Downloads now run in parallel
        // (up to 4 concurrent) while parsing stays sequential to preserve the
        // insertedIDsSoFar/listingCountSoFar threading guarantees.
        struct DownloadedFeed: Sendable {
            let index: Int
            let url: String
            let label: String
            let fileURL: URL
            let fileSize: Int64
        }

        // Determine which feeds to download (skip heavy ones early if possible)
        var feedsToDownload: [(index: Int, url: String, label: String)] = []
        for (feedIndex, url) in urls.enumerated() {
            let feedLabel = ExternalEPGSources.sources.first(where: { $0.url == url })?.name ?? "Feed \(feedIndex + 1)"
            // Skip obviously heavy sources up front (based on URL, not coverage —
            // coverage-based skipping still happens during the parse phase below)
            if ExternalEPGSources.isHeavyLowYieldSource(url: url), bundled {
                Logger.database.warning("EPG skipping heavy source (pre-download): \(feedLabel)")
                continue
            }
            feedsToDownload.append((feedIndex, url, feedLabel))
        }

        onProgress?(0, totalChannels, 1, feedsToDownload.count, "Downloading feeds…")

        // Download all feeds in parallel (capped at 4 concurrent to avoid
        // saturating the connection or tripping rate limits). Each download
        // writes to a temp file on disk so memory stays flat.
        // tvOS has tighter memory limits, so cap at 2 concurrent there.
        #if os(tvOS)
        let maxConcurrentDownloads = 2
        #else
        let maxConcurrentDownloads = 4
        #endif
        var downloadedFeeds: [DownloadedFeed] = []
        downloadedFeeds.reserveCapacity(feedsToDownload.count)

        await withTaskGroup(of: DownloadedFeed?.self) { group in
            var iterator = feedsToDownload.makeIterator()
            var inFlight = 0

            func scheduleNext() {
                while inFlight < maxConcurrentDownloads, let feed = iterator.next() {
                    inFlight += 1
                    group.addTask {
                        do {
                            let fileURL = try await self.downloadXMLTV(from: feed.url)
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                            Logger.database.warning("EPG feed downloaded — \(fileSize) bytes from \(feed.label)")
                            return DownloadedFeed(index: feed.index, url: feed.url, label: feed.label, fileURL: fileURL, fileSize: fileSize)
                        } catch {
                            Logger.database.warning("EPG feed download failed: \(feed.label) — \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
            }

            scheduleNext()
            for await result in group {
                inFlight -= 1
                if let feed = result {
                    downloadedFeeds.append(feed)
                }
                scheduleNext()
            }
        }

        // Sort by original feed order so higher-priority feeds (national) are
        // parsed first, giving the coverage-based early-stop logic the best data.
        downloadedFeeds.sort { $0.index < $1.index }

        Logger.database.warning("EPG parallel download complete: \(downloadedFeeds.count)/\(feedsToDownload.count) feeds ready")

        // --- Sequential parse phase ---
        // Parse must be sequential because each feed's dedup set and per-channel
        // counts build on the previous feed's results.
        for (parseIndex, downloaded) in downloadedFeeds.enumerated() {
            let feedIndex = downloaded.index
            let url = downloaded.url
            let feedLabel = downloaded.label
            let fileURL = downloaded.fileURL
            defer { try? FileManager.default.removeItem(at: fileURL) }

            if shouldSkipHeavyExternalSource(
                url: url,
                matchedCount: matchedChannelIDs.count,
                totalCount: totalChannels,
                bundled: bundled
            ) {
                Logger.database.warning(
                    "EPG skipping heavy external source — coverage \(matchedChannelIDs.count)/\(totalChannels)"
                )
                continue
            }

            onProgress?(matchedChannelIDs.count, totalChannels, parseIndex + 1, downloadedFeeds.count, feedLabel)

            do {
                Logger.database.warning("EPG external source parsing — \(downloaded.fileSize) bytes from \(feedLabel)")

                // File already downloaded in parallel phase above

                let container = modelContainer
                let channelIdentities = identities
                let baselineMatched = matchedChannelIDs.count
                let reportProgress = onProgress
                let seedIDs = insertedIDsSoFar
                let countSeed = listingCountSoFar

                struct FeedImportResult: Sendable {
                    let inserted: Int
                    let catalog: EPGChannelCatalog?
                    let westMappings: [String: [String]]
                    let shouldRefreshUI: Bool
                    let insertedIDs: Set<String>
                    let listingCounts: [String: Int]
                }

                let feedResult = await Task.detached(priority: .utility) {
                    var count = 0
                    // Distinct channels *this feed* has written to, for the
                    // progress estimate below only — not the cap (see
                    // `totalCountByChannel`).
                    var listingsPerChannel: [String: Int] = [:]
                    // Seeded with the store's existing per-channel counts plus
                    // every earlier feed's contribution this pass, so the cap
                    // below is a true ceiling on the channel's total row count.
                    var totalCountByChannel = countSeed
                    var didSignalMidFeedRefresh = false
                    // De-dupes deterministic listing ids within this feed AND
                    // against every earlier feed in this same pass (`seedIDs`)
                    // so the same `channelId-start-end` is never inserted twice
                    // (source duplicates / west-shift collisions / a later feed
                    // re-covering a channel an earlier feed already wrote),
                    // which would otherwise trigger a unique-constraint upsert +
                    // persistent-identifier remap on save.
                    var insertedIDs = seedIDs
                    let context = ModelContext(container)
                    context.autosaveEnabled = false
                    let now = syncNow
                    let pastCutoff = now.addingTimeInterval(-EPGRetention.pastGrace)
                    let futureCutoff = now.addingTimeInterval(EPGRetention.futureHorizon)
                    let westShift: TimeInterval = 3 * 3600
                    let maxPerChannel = EPGRetention.maxListingsPerChannel

                    func insertListing(
                        channelId: String,
                        title: String,
                        description: String,
                        start: Date,
                        end: Date
                    ) {
                        guard end > pastCutoff, start < futureCutoff else { return }
                        guard (totalCountByChannel[channelId] ?? 0) < maxPerChannel else { return }
                        let listingId = "\(channelId)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
                        guard insertedIDs.insert(listingId).inserted else { return }
                        context.insert(EPGListing(
                            id: listingId,
                            channelId: channelId,
                            title: title,
                            listingDescription: description,
                            start: start,
                            end: end
                        ))
                        listingsPerChannel[channelId] = (listingsPerChannel[channelId] ?? 0) + 1
                        totalCountByChannel[channelId] = (totalCountByChannel[channelId] ?? 0) + 1
                        count += 1
                    }

                    let stats = XMLTVParser.importExternalEPG(
                        fileURL: fileURL,
                        identities: channelIdentities,
                        batchSize: 2000
                    ) { catalog, westMappings, batch in
                        autoreleasepool {
                            for programme in batch {
                                let channelId = catalog.primaryID(for: programme.channelId)
                                insertListing(
                                    channelId: channelId,
                                    title: programme.title,
                                    description: programme.description,
                                    start: programme.start,
                                    end: programme.end
                                )

                                if let westIds = westMappings[channelId] {
                                    let shiftedStart = programme.start.addingTimeInterval(westShift)
                                    let shiftedEnd = programme.end.addingTimeInterval(westShift)
                                    for westId in westIds {
                                        insertListing(
                                            channelId: westId,
                                            title: programme.title,
                                            description: programme.description,
                                            start: shiftedStart,
                                            end: shiftedEnd
                                        )
                                    }
                                }
                            }
                            if count > 0, count % 8000 == 0, let reportProgress {
                                let interim = baselineMatched + listingsPerChannel.count
                                reportProgress(
                                    min(interim, totalChannels),
                                    totalChannels,
                                    parseIndex + 1,
                                    downloadedFeeds.count,
                                    feedLabel
                                )
                            }
                            // Flush + signal once mid-feed so the guide starts
                            // filling in without saving on every 2k batch (each
                            // save with a unique-constrained model is costly and
                            // risks identifier-remap churn).
                            if count > 0, !didSignalMidFeedRefresh {
                                try? context.save()
                                didSignalMidFeedRefresh = true
                                Task { @MainActor in
                                    EPGSyncService.shared.signalGuideRefreshDuringSync()
                                }
                            }
                        }
                    }

                    guard !stats.catalog.isEmpty else {
                        Logger.database.warning("EPG external source matched 0 channels by display name")
                        return FeedImportResult(inserted: 0, catalog: nil, westMappings: [:], shouldRefreshUI: false, insertedIDs: insertedIDs, listingCounts: totalCountByChannel)
                    }

                    Logger.database.warning(
                        "EPG external source matched \(stats.catalog.knownIDs.count) channel IDs, \(stats.westMappings.count) west/pacific offsets (single-pass, \(stats.matchedProgrammes)/\(stats.totalProgrammes) programmes)"
                    )
                    for (base, wests) in stats.westMappings.prefix(5) {
                        Logger.database.warning("EPG WEST MAP: \(base, privacy: .public) → \(wests.joined(separator: ", "), privacy: .public)")
                    }

                    if count > 0 {
                        try? context.save()
                    }
                    return FeedImportResult(
                        inserted: count,
                        catalog: stats.catalog,
                        westMappings: stats.westMappings,
                        shouldRefreshUI: count > 0 && !didSignalMidFeedRefresh,
                        insertedIDs: insertedIDs,
                        listingCounts: totalCountByChannel
                    )
                }.value

                insertedIDsSoFar = feedResult.insertedIDs
                listingCountSoFar = feedResult.listingCounts
                totalInserted += feedResult.inserted
                if let feedCatalog = feedResult.catalog {
                    let matched = Set(feedCatalog.normalize.values)
                    matchedChannelIDs.formUnion(matched)
                    for westIds in feedResult.westMappings.values {
                        matchedChannelIDs.formUnion(westIds)
                    }
                }
                Logger.database.warning("EPG external source inserted \(feedResult.inserted) listings")

                if feedResult.shouldRefreshUI {
                    await MainActor.run {
                        EPGSyncService.shared.signalGuideRefreshDuringSync()
                    }
                }

                onProgress?(matchedChannelIDs.count, totalChannels, parseIndex + 1, downloadedFeeds.count, feedLabel)

                if bundled, shouldStopBundledSync(matchedCount: matchedChannelIDs.count, totalCount: totalChannels) {
                    Logger.database.warning(
                        "EPG bundled sync complete early — \(matchedChannelIDs.count)/\(totalChannels) channels matched"
                    )
                    break
                }
            } catch {
                Logger.database.warning("EPG external source failed: \(error.localizedDescription)")
                continue
            }
        }

        if totalInserted > 0 {
            return matchedChannelIDs
        }
        return []
    }

    private func shouldSkipHeavyExternalSource(
        url: String,
        matchedCount: Int,
        totalCount: Int,
        bundled: Bool
    ) -> Bool {
        #if os(tvOS)
        // Apple TV has far less headroom. The two largest feeds — the ~500MB
        // locals dump and the ~73MB US2 national feed — are the biggest
        // memory/IO spikes and repeatedly drove memory warnings (worst when the
        // guide parse overlaps the user browsing Live TV: logos + on-demand
        // EPG). Never parse them on tvOS; the on-demand per-channel API fills
        // the visible channels and the remaining US feeds still populate the
        // store.
        if url.contains("US_LOCALS1") || url.contains("epg_ripper_US2.") {
            return true
        }
        #endif
        guard ExternalEPGSources.isHeavyLowYieldSource(url: url) else { return false }
        #if os(tvOS)
        return true
        #else
        guard totalCount > 0 else { return false }
        let ratio = bundled ? Self.bundledCoverageSkipRatio : Self.externalCoverageSkipRatio
        return Double(matchedCount) / Double(totalCount) >= ratio
        #endif
    }

    private func shouldStopBundledSync(matchedCount: Int, totalCount: Int) -> Bool {
        guard totalCount > 0 else { return false }
        return Double(matchedCount) / Double(totalCount) >= Self.bundledCoverageStopRatio
    }

    private static let apiPrimeChannelCount = 200

    /// Primes a slice of channels via the per-channel API when the bulk XMLTV
    /// dump is stale or empty. Background prefetch continues the rest after this
    /// returns.
    private func syncAPIPrime(
        strategy: EPGProviderStrategy,
        result: EPGInserter.Result?,
        credentials: EPGPlaylistCredentials,
        identities: [ChannelRef],
        sourceID: UUID
    ) async {
        let primeSlice = Array(identities.prefix(Self.apiPrimeChannelCount))
        guard !primeSlice.isEmpty else { return }

        Logger.database.warning(
            "EPG API prime [\(strategy.logLabel, privacy: .public)] — \(primeSlice.count) channels"
        )

        _ = await EPGAPISync.sync(
            credentials: credentials,
            identities: primeSlice,
            container: modelContainer,
            client: bulkSyncClient
        )

        // Schedule background prefetch for the remaining channels
        if identities.count > Self.apiPrimeChannelCount {
            await EPGBackgroundPrefetch.shared.schedule(
                credentials: credentials,
                identities: identities,
                startIndex: Self.apiPrimeChannelCount,
                container: modelContainer
            )
        }
    }

    // MARK: - XMLTV import

    private enum XMLTVImportOutcome {
        case succeeded
        case downloadFailed
        case parsedNoUsableData
        case staleBulkFeed
    }

    private func syncXMLTV(
        source: SourceInfo,
        playlist: PlaylistInfo?,
        scoped identities: [ChannelRef],
        alignToNow: Bool,
        overrideURL: String? = nil
    ) async -> XMLTVImportOutcome {
        let urlString = overrideURL ?? source.url
        guard !urlString.isEmpty else { return .downloadFailed }

        let fileURL: URL
        do {
            fileURL = try await downloadXMLTV(from: urlString)
        } catch {
            Logger.database.warning("EPG XMLTV download failed: \(error.localizedDescription, privacy: .public)")
            return .downloadFailed
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileSize: Int64 = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            return (attrs?[.size] as? Int64) ?? 0
        }()

        let catalog = EPGChannelCatalog(identities: identities)
        let timezone: TimeZone? = {
            if let tz = playlist?.serverTimezone { return TimeZone(identifier: tz) }
            return nil
        }()

        let result = EPGInserter.importFile(
            fileURL: fileURL,
            fileSize: fileSize,
            container: modelContainer,
            catalog: catalog,
            identities: identities,
            timezone: timezone,
            alignLatestToNow: alignToNow,
            xtreamStyleTimestamps: playlist?.sourceType == .xtream
        )

        Logger.database.warning(
            "EPG XMLTV result — inserted: \(result.inserted), matched: \(result.matchedProgrammes), total: \(result.totalProgrammes), stale: \(result.isStaleBulkFeed)"
        )

        if result.isStaleBulkFeed {
            return .staleBulkFeed
        }
        if result.inserted > 0 {
            return .succeeded
        }
        if result.matchedProgrammes == 0, result.totalProgrammes > 0 {
            return .parsedNoUsableData
        }
        if result.matchedProgrammes > 0, result.inserted == 0 {
            return .staleBulkFeed
        }
        if result.totalProgrammes == 0 {
            return .downloadFailed
        }
        return .parsedNoUsableData
    }

    private func downloadXMLTV(from urlString: String) async throws -> URL {
        let fileURL = try await m3uClient.downloadEPG(from: urlString)
        return fileURL
    }

    // MARK: - Timeout helper

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Helper types

    private struct SourceInfo {
        let id: UUID
        let name: String
        let url: String
        let playlistID: UUID?
    }

    private struct ChannelRef: EPGChannelIdentity {
        let streamId: Int
        let name: String
        let epgChannelId: String?
        let customSid: String?
    }

    private struct ChannelCatalogData {
        let identities: [ChannelRef]
    }

    private struct PlaylistInfo {
        let id: UUID
        let sourceType: PlaylistSourceType
        let serverURL: String
        let username: String
        let password: String
        let serverTimezone: String?
        let epgURL: String?
    }

    // MARK: - Data access helpers

    private func reconcileLinkedSources() {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        var changed = false
        for playlist in playlists {
            if EPGSourceReconciler.apply(playlist, in: context) {
                changed = true
            }
        }
        if changed {
            try? context.save()
        }
    }

    private func enabledSources() -> [SourceInfo] {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<EPGSource>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.addedAt)]
        )
        let sources = (try? context.fetch(descriptor)) ?? []
        return sources.map { SourceInfo(id: $0.id, name: $0.name, url: $0.url, playlistID: $0.playlistID) }
    }

    private func channelCatalog() -> ChannelCatalogData {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        // Fetch all LiveStreams — the extracting of lightweight ChannelRef values
        // ensures we don't hold on to heavy SwiftData objects beyond this scope.
        let streams = (try? context.fetch(FetchDescriptor<LiveStream>())) ?? []
        let identities = streams.map { ChannelRef(
            streamId: $0.streamId,
            name: $0.name,
            epgChannelId: $0.epgChannelId,
            customSid: $0.customSid
        ) }
        return ChannelCatalogData(identities: identities)
    }

    private func scopedChannelData(source: SourceInfo, all catalog: ChannelCatalogData) -> [ChannelRef] {
        guard let playlistID = source.playlistID else { return catalog.identities }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let prefix = "\(playlistID.uuidString)-live-"
        // Fetch only streams matching this playlist using a predicate to avoid
        // loading the entire catalog into memory for multi-playlist setups.
        let descriptor = FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.id.localizedStandardContains(prefix) }
        )
        let streams = (try? context.fetch(descriptor)) ?? []
        return streams.map { ChannelRef(
            streamId: $0.streamId,
            name: $0.name,
            epgChannelId: $0.epgChannelId,
            customSid: $0.customSid
        ) }
    }

    private func playlist(for playlistID: UUID) -> PlaylistInfo? {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.id == playlistID }
        )
        guard let playlist = (try? context.fetch(descriptor))?.first else { return nil }
        return PlaylistInfo(
            id: playlist.id,
            sourceType: playlist.sourceType,
            serverURL: playlist.serverURL,
            username: playlist.username,
            password: playlist.password,
            serverTimezone: playlist.serverTimezone,
            epgURL: playlist.epgURL
        )
    }

    // MARK: - Status bookkeeping

    private func markStatus(_ sourceID: UUID, _ status: SyncStatus) {
        updateSource(sourceID) { $0.syncStatus = status }
    }

    private func markSynced(_ sourceID: UUID) {
        updateSource(sourceID) {
            $0.syncStatus = .idle
            $0.lastSyncDate = Date()
        }
    }

    private func updateSource(_ sourceID: UUID, _ mutate: (EPGSource) -> Void) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let source = try? context.fetch(
            FetchDescriptor<EPGSource>(predicate: #Predicate { $0.id == sourceID })
        ).first else { return }
        mutate(source)
        try? context.save()
    }

    private func persistDiscoveredEPGURL(_ url: String, playlistID: UUID) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.id == playlistID }
        )
        guard let playlist = (try? context.fetch(descriptor))?.first else { return }
        guard playlist.epgURL != url else { return }
        playlist.epgURL = url
        try? context.save()
        // Also update the linked EPG source to use the discovered URL
        EPGSourceReconciler.reconcile(playlist, in: context)
    }

    private func clearDiscoveredEPGURL(playlistID: UUID) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.id == playlistID }
        )
        guard let playlist = (try? context.fetch(descriptor))?.first else { return }
        guard playlist.epgURL != nil else { return }
        playlist.epgURL = nil
        try? context.save()
        EPGSourceReconciler.reconcile(playlist, in: context)
    }

    // MARK: - URL helpers

    private func buildXMLTVPhpURL(credentials: EPGPlaylistCredentials) -> String? {
        let base = credentials.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard !base.isEmpty else { return nil }
        guard var components = URLComponents(string: base + "/xmltv.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password)
        ]
        return components.url?.absoluteString
    }

    // MARK: - Static utilities

    /// Resets any source left `.syncing` by a process that died mid-refresh.
    /// `.syncing` is runtime-only, so a value observed at launch is stale.
    static func recoverInterruptedSyncs(in context: ModelContext) {
        let syncingRaw = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<EPGSource>(
            predicate: #Predicate { $0.syncStatusRaw == syncingRaw }
        )
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for source in stuck {
            source.syncStatus = .idle
        }
        try? context.save()
    }

    /// Deletes expired listings (end < pastGrace cutoff) and those beyond the
    /// future horizon. Called after a successful sync to keep the store bounded.
    static func pruneExpiredListings(in container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let window = EPGRetention.importWindow()
        let cutoff = window.start
        let horizon = window.end
        let descriptor = FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { $0.end < cutoff || $0.start > horizon }
        )
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return }
        for listing in expired {
            context.delete(listing)
        }
        do {
            try context.save()
            Logger.database.info("EPG pruned \(expired.count) expired/out-of-range listings")
        } catch {
            Logger.database.error("EPG prune failed: \(error.localizedDescription)")
        }
    }

    /// Trims any channel's *non-expired* row count back down to
    /// `EPGRetention.maxListingsPerChannel`, keeping the earliest (soonest
    /// airing) rows. `syncExternalEPG`'s insert-time cap (Jul 10) now tracks a
    /// channel's running total across the whole pass, so this shouldn't be
    /// needed going forward — but it self-heals devices that already
    /// over-accumulated rows for well-covered channels across many syncs
    /// before that fix, without requiring a fresh install or a Sync Now.
    /// Called after every successful sync, same as `pruneExpiredListings`.
    static func trimExcessListings(in container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let window = EPGRetention.importWindow()
        let cutoff = window.start
        let horizon = window.end
        let descriptor = FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { $0.end > cutoff && $0.start < horizon },
            sortBy: [SortDescriptor(\.start)]
        )
        guard let listings = try? context.fetch(descriptor), !listings.isEmpty else { return }
        // `Dictionary(grouping:by:)` preserves each group's relative order from
        // the fetch, so every group here is still ascending by `start`.
        let grouped = Dictionary(grouping: listings, by: \.channelId)
        var trimmed = 0
        for (_, rows) in grouped where rows.count > EPGRetention.maxListingsPerChannel {
            for excess in rows.dropFirst(EPGRetention.maxListingsPerChannel) {
                context.delete(excess)
                trimmed += 1
            }
        }
        guard trimmed > 0 else { return }
        do {
            try context.save()
            Logger.database.info("EPG trimmed \(trimmed) excess listings over the per-channel cap")
        } catch {
            Logger.database.error("EPG trim failed: \(error.localizedDescription)")
        }
    }
}
