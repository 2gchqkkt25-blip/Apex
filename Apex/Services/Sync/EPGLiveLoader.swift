//
//  EPGLiveLoader.swift
//  Apex
//
//  On-demand EPG for Xtream playlists. Fetches per-channel guide data for
//  visible channels, caches in memory, and persists into SwiftData via
//  `EPGBrowseLoader` / `EPGAPISync.persist` so all platforms share one store.
//
//  See `EPG.md` for architecture and the stale-timestamp alignment rule.
//

import Foundation
import OSLog
import SwiftData

/// A single programme slot — grid + cards share this instead of SwiftData models.
nonisolated struct EPGProgram: Sendable, Equatable, Identifiable {
    var id: String { "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))" }
    let title: String
    let description: String
    let start: Date
    let end: Date
}

/// Sendable snapshot of playlist credentials — never pass SwiftData `Playlist`
/// into background EPG work.
nonisolated struct EPGPlaylistCredentials: Sendable {
    let id: UUID
    let sourceType: PlaylistSourceType
    let serverURL: String
    let username: String
    let password: String
    let serverTimezone: String?

    init(
        id: UUID,
        sourceType: PlaylistSourceType,
        serverURL: String,
        username: String,
        password: String,
        serverTimezone: String?
    ) {
        self.id = id
        self.sourceType = sourceType
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.serverTimezone = serverTimezone
    }

    init(playlist: Playlist) {
        id = playlist.id
        sourceType = playlist.sourceType
        serverURL = playlist.serverURL
        username = playlist.username
        password = playlist.password
        serverTimezone = playlist.serverTimezone
    }
}

actor EPGLiveLoader {
    static let shared = EPGLiveLoader()

    private var client = XtreamClient(urlSession: XtreamClient.makeEPGImportSession())
    private var cache: [String: CachedEntry] = [:]
    private var inFlight: Set<String> = []
    private var didLogSample = false

    private static let ttl: TimeInterval = 10 * 60
    /// Short TTL for empty/failed fetches — long enough to stop a channel with
    /// no EPG from being re-requested on every scroll tick or reload trigger,
    /// but short enough that transient panel misses recover quickly. 3 minutes
    /// is the sweet spot with `maxConcurrent=2` + 200 ms stagger: even if every
    /// channel on screen retries, the panel sees at most ~10 req/min from the
    /// EPG path.
    private static let emptyTTL: TimeInterval = 3 * 60
    /// When the panel returns HTTP 5xx, back off briefly instead of re-hitting
    /// the same channel on every scroll tick (which keeps the panel overloaded).
    private static let serverErrorTTL: TimeInterval = 45
    /// Gentle on overloaded Xtream panels — 6 parallel was causing HTTP 502 storms.
    /// tvOS raises to 6 for the browse path because the store is often empty
    /// (deferred sync) and 2-concurrent makes initial page loads take minutes.
    /// The 502 issue was at 6+ during FULL sync (1600 channels sustained); for
    /// a short browse burst of 50 channels, 6 concurrent finishes in seconds
    /// without tripping panel rate limits.
    /// iOS now also uses 6 concurrent with no stagger — the previous 2-concurrent
    /// + 200ms stagger meant 24 channels took ~3 seconds best case, and the
    /// bottom half of a category (channels 25-50 in the background pass) could
    /// take 2-3 minutes. With 6 concurrent and no stagger, a full 50-channel
    /// page resolves in ~8-16 seconds.
    private static let maxConcurrent = 6
    /// No stagger — the concurrency limit already prevents panel overload for
    /// browse-sized bursts (50 channels). The cumulative stagger was adding
    /// unnecessary delay.
    private static let staggerBetweenStarts: UInt64 = 0
    /// Xtream default — current + next few slots. A high `limit` on some panels
    /// returns the oldest rows first (days of history), which is why we were
    /// seeing startDeltaMin ≈ -7000 with `limit=32`.
    private static let liveFetchLimit = 4
    private static let expandedFetchLimit = 8

    private struct CachedEntry {
        let programs: [EPGProgram]
        let fetchedAt: Date
        /// Panel returned HTTP 5xx — use a shorter backoff than a true empty guide.
        let serverFailure: Bool
    }

    private func entryTTL(_ entry: CachedEntry) -> TimeInterval {
        if entry.serverFailure { return Self.serverErrorTTL }
        return entry.programs.isEmpty ? Self.emptyTTL : Self.ttl
    }

    private func cacheKey(playlistID: UUID, streamId: Int) -> String {
        "\(playlistID.uuidString)-\(streamId)"
    }

    /// Clears all cached guide data (Settings → Sync Now for Xtream).
    func invalidateAll() {
        cache.removeAll()
        inFlight.removeAll()
        didLogSample = false
        Logger.database.info("EPG live cache cleared")
    }

    /// Returns warm, non-empty live-cache hits without hitting the network.
    ///
    /// Used by `EPGBrowseLoader` so a `forceGuideRefresh` after gap-fill paints
    /// from memory immediately — even if SwiftData persist is still in flight
    /// or briefly lost a race with a sync writer.
    func cachedPrograms(
        for snapshots: [EPGStreamSnapshot],
        credentials: EPGPlaylistCredentials,
        now: Date = Date()
    ) -> [String: [EPGProgram]] {
        guard credentials.sourceType == .xtream else { return [:] }
        var result: [String: [EPGProgram]] = [:]
        for snapshot in snapshots {
            let key = cacheKey(playlistID: credentials.id, streamId: snapshot.streamId)
            guard let entry = cache[key] else { continue }
            guard now.timeIntervalSince(entry.fetchedAt) < entryTTL(entry) else { continue }
            guard !entry.programs.isEmpty else { continue }
            result[snapshot.primaryEPGChannelId] = entry.programs
        }
        return result
    }

    /// Full programme list per channel for the guide grid and channel cards.
    func programs(
        for snapshots: [EPGStreamSnapshot],
        credentials: EPGPlaylistCredentials,
        now: Date = Date()
    ) async -> [String: [EPGProgram]] {
        guard credentials.sourceType == .xtream else { return [:] }
        guard !snapshots.isEmpty else { return [:] }

        var result: [String: [EPGProgram]] = [:]
        var toFetch: [EPGStreamSnapshot] = []

        for snapshot in snapshots {
            let key = cacheKey(playlistID: credentials.id, streamId: snapshot.streamId)
            if let entry = cache[key] {
                let ttl = entryTTL(entry)
                if now.timeIntervalSince(entry.fetchedAt) < ttl {
                    // Within TTL — use cached data. Even if stale (not
                    // airing/upcoming), don't refetch — avoids the lock-up loop
                    // where permanently stale channels get re-requested on every
                    // category switch.
                    if !entry.programs.isEmpty {
                        result[snapshot.primaryEPGChannelId] = entry.programs
                    }
                    continue
                }
                // Expired TTL — drop and refetch.
                cache.removeValue(forKey: key)
            }
            if inFlight.contains(key) { continue }
            toFetch.append(snapshot)
        }

        guard !toFetch.isEmpty else { return result }

        let timezone = credentials.serverTimezone
        await EPGBackgroundPrefetch.shared.setBrowseActive(true)
        defer { Task { await EPGBackgroundPrefetch.shared.setBrowseActive(false) } }

        await withTaskGroup(of: (key: String, channelId: String, programs: [EPGProgram], rawCount: Int, cacheResult: Bool, serverFailure: Bool).self) { group in
            var iterator = toFetch.makeIterator()
            var inFlightCount = 0
            var serverErrorCount = 0
            var startedCount = 0

            func schedule() {
                while inFlightCount < Self.maxConcurrent, let snapshot = iterator.next() {
                    let key = cacheKey(playlistID: credentials.id, streamId: snapshot.streamId)
                    inFlight.insert(key)
                    inFlightCount += 1
                    let streamId = snapshot.streamId
                    let channelId = snapshot.primaryEPGChannelId
                    let creds = credentials
                    let startDelay = startedCount
                    startedCount += 1
                    group.addTask { [client] in
                        if startDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(startDelay) * Self.staggerBetweenStarts)
                        }
                        do {
                            let fetched = try await Self.fetchLiveChannelEPG(
                                client: client,
                                serverURL: creds.serverURL,
                                username: creds.username,
                                password: creds.password,
                                streamId: streamId,
                                timezoneIdentifier: timezone,
                                now: now
                            )
                            return (key, channelId, fetched.programs, fetched.rawCount, true, false)
                        } catch {
                            // Scroll / .task restart cancels in-flight requests — normal, not an error.
                            if error is CancellationError { return (key, channelId, [], 0, false, false) }
                            if let xtream = error as? XtreamError, xtream.isCancellation {
                                return (key, channelId, [], 0, false, false)
                            }
                            if let urlError = error as? URLError, urlError.code == .cancelled {
                                return (key, channelId, [], 0, false, false)
                            }
                            let serverFailure = Self.isServerEPGFailure(error)
                            let transient = Self.isTransientNetworkFailure(error)
                            // Cache HTTP 5xx briefly so scroll ticks don't hammer an overloaded panel.
                            let shouldCache = serverFailure || !transient
                            return (key, channelId, [], 0, shouldCache, serverFailure)
                        }
                    }
                }
            }

            schedule()
            var rawTotal = 0
            var parsedTotal = 0
            for await item in group {
                inFlightCount -= 1
                inFlight.remove(item.key)
                if item.serverFailure {
                    serverErrorCount += 1
                }
                rawTotal += item.rawCount
                parsedTotal += item.programs.count
                // Cache empty/failed results too, but briefly (`emptyTTL`) — without
                // this, channels with no EPG get re-requested on every scroll tick
                // or reload trigger, flooding the panel with requests.
                // Skip caching transient failures (timeouts) so the next load retries.
                if item.cacheResult {
                    cache[item.key] = CachedEntry(
                        programs: item.programs,
                        fetchedAt: Date(),
                        serverFailure: item.serverFailure
                    )
                }
                if !item.programs.isEmpty {
                    result[item.channelId] = item.programs
                } else if item.rawCount > 0, !didLogSample {
                    didLogSample = true
                    Logger.database.warning(
                        "EPG live — \(item.rawCount) listings for \(item.channelId, privacy: .public) but 0 parsed (timestamp format?)"
                    )
                }
                schedule()
            }

            let alignedCount = result.values.filter { programs in
                programs.contains { $0.start <= now && now < $0.end } || programs.contains { $0.start > now }
            }.count
            if parsedTotal > 0, alignedCount == 0, let sample = result.values.first(where: { !$0.isEmpty })?.first {
                let deltaMin = Int(sample.start.timeIntervalSince(now) / 60)
                Logger.database.warning(
                    "EPG live — parsed \(parsedTotal) slots but none airing/upcoming; sample \"\(sample.title, privacy: .public)\" startDeltaMin=\(deltaMin)"
                )
            }
            Logger.database.warning(
                "EPG live — channels with data: \(result.count)/\(toFetch.count), listings: \(rawTotal), parsed: \(parsedTotal), airingOrUpcoming: \(alignedCount), panelErrors: \(serverErrorCount)"
            )
        }

        return result
    }

    /// Read from SwiftData when a local guide exists.
    ///
    /// Scoped to the requested channels' EPG ids. Returns shifted programs when
    /// stored data is stale (matching the shift applied during live API parse).
    nonisolated static func programsFromStore(
        container: ModelContainer,
        snapshots: [EPGStreamSnapshot],
        windowStart: Date,
        windowEnd: Date,
        now: Date = Date()
    ) -> [String: [EPGProgram]] {
        guard !snapshots.isEmpty else { return [:] }
        let epgIds = Set(snapshots.flatMap(\.epgLookupIDs))
        guard !epgIds.isEmpty else { return [:] }
        let context = ModelContext(container)
        let startBound = windowStart
        let endBound = windowEnd
        let descriptor = FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> {
                epgIds.contains($0.channelId) && $0.end > startBound && $0.start < endBound
            },
            sortBy: [SortDescriptor(\.start)]
        )
        let listings = (try? context.fetch(descriptor)) ?? []
        if listings.isEmpty, !snapshots.isEmpty {
            // Log diagnostic: why is the store empty for these channels?
            let sampleIds = Array(epgIds.prefix(5))
            Logger.database.warning("EPG store query returned 0 listings for \(snapshots.count) channels (epgIds sample: \(sampleIds.joined(separator: ", "), privacy: .public), window: \(startBound) to \(endBound))")
            // Check total EPGListing count to see if the store is populated at all
            let countDescriptor = FetchDescriptor<EPGListing>()
            let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0
            Logger.database.warning("EPG store total listing count: \(totalCount)")
            if totalCount > 0 {
                // Sample what channelIds ARE in the store
                var sampleDescriptor = FetchDescriptor<EPGListing>()
                sampleDescriptor.fetchLimit = 5
                let sampleListings = (try? context.fetch(sampleDescriptor)) ?? []
                let storeChannelIds = sampleListings.map(\.channelId)
                Logger.database.warning("EPG store sample channelIds: \(storeChannelIds.joined(separator: ", "), privacy: .public)")
            }
        }
        let grouped = Dictionary(grouping: listings, by: \.channelId)
        var result: [String: [EPGProgram]] = [:]
        for snapshot in snapshots {
            let rows = snapshot.epgListings(in: grouped)
            guard !rows.isEmpty else { continue }
            let programs = rows.map {
                EPGProgram(title: $0.title, description: $0.listingDescription, start: $0.start, end: $0.end)
            }
            let usable = programs.contains { $0.end > now.addingTimeInterval(-EPGRetention.pastGrace) }
            guard usable else { continue }
            result[snapshot.primaryEPGChannelId] = programs
        }
        return result
    }

    nonisolated private static func parse(
        _ listings: [XtreamShortEPG],
        timezoneIdentifier: String?,
        now: Date
    ) -> [EPGProgram] {
        if let nowPlaying = parseNowPlaying(listings, timezoneIdentifier: timezoneIdentifier, now: now) {
            return preferGuideWindow(nowPlaying, now: now)
        }

        var programs: [EPGProgram] = []
        programs.reserveCapacity(listings.count)
        var logged = false

        for item in listings {
            guard let times = item.programmeTimes(timezoneIdentifier: timezoneIdentifier, now: now) else {
                if !logged {
                    logged = true
                    Logger.database.warning(
                        "EPG live parse miss — start=\(item.startTimestamp ?? item.start ?? "nil", privacy: .public) end=\(item.endTimestamp ?? item.stopTimestamp ?? item.end ?? "nil", privacy: .public) title=\(item.title ?? "nil", privacy: .public)"
                    )
                }
                continue
            }
            let title = item.decodedTitle
            guard !title.isEmpty else { continue }

            programs.append(EPGProgram(
                title: title,
                description: item.decodedDescription,
                start: times.start,
                end: times.end
            ))
        }

        programs.sort { $0.start < $1.start }
        return preferGuideWindow(programs, now: now)
    }

    /// Panels mark the real on-air row with `now_playing` even when timestamps lag.
    nonisolated private static func parseNowPlaying(
        _ listings: [XtreamShortEPG],
        timezoneIdentifier: String?,
        now: Date
    ) -> [EPGProgram]? {
        let flagged = listings.filter { $0.nowPlaying == true }
        guard !flagged.isEmpty else { return nil }

        var programs: [EPGProgram] = []
        programs.reserveCapacity(flagged.count)
        for item in flagged {
            let title = item.decodedTitle
            guard !title.isEmpty else { continue }
            let interval = item.programmeTimes(timezoneIdentifier: timezoneIdentifier, now: now)
            let duration = interval.map { max($0.end.timeIntervalSince($0.start), 15 * 60) } ?? 3600
            let start = now.addingTimeInterval(-min(300, duration * 0.15))
            programs.append(EPGProgram(
                title: title,
                description: item.decodedDescription,
                start: start,
                end: start.addingTimeInterval(duration)
            ))
        }
        guard !programs.isEmpty else { return nil }
        programs.sort { $0.start < $1.start }
        return programs
    }

    /// Keeps slots that are relevant to the live guide. When all data is expired
    /// (stale provider), shifts each programme to TODAY at the same time-of-day.
    nonisolated private static func preferGuideWindow(_ programs: [EPGProgram], now: Date) -> [EPGProgram] {
        guard !programs.isEmpty else { return [] }
        let liveAndUpcoming = programs.filter { $0.end > now }
        if !liveAndUpcoming.isEmpty {
            return Array(liveAndUpcoming.prefix(16))
        }

        // All expired — shift each programme to today keeping time-of-day.
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        let shifted = programs.map { program -> EPGProgram in
            let programmeDay = calendar.startOfDay(for: program.start)
            let dayOffset = todayStart.timeIntervalSince(programmeDay)
            return EPGProgram(
                title: program.title,
                description: program.description,
                start: program.start.addingTimeInterval(dayOffset),
                end: program.end.addingTimeInterval(dayOffset)
            )
        }

        let relevant = shifted.filter { $0.end > now.addingTimeInterval(-3600) && $0.start < now.addingTimeInterval(6 * 3600) }
        if !relevant.isEmpty {
            return Array(relevant.sorted { $0.start < $1.start }.prefix(16))
        }
        return Array(shifted.sorted { $0.start < $1.start }.prefix(8))
    }

    private static func isServerEPGFailure(_ error: Error) -> Bool {
        if case let XtreamError.serverError(code) = error {
            return (500 ... 599).contains(code)
        }
        return false
    }

    /// Network blips worth one quick retry — not HTTP 5xx (panel overload).
    private static func isTransientNetworkFailure(_ error: Error) -> Bool {
        if isServerEPGFailure(error) { return false }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        if let xtream = error as? XtreamError {
            if case let .networkError(underlying) = xtream {
                return isTransientNetworkFailure(underlying)
            }
        }
        return false
    }

    private static func fetchChannelEPGWithRetry(
        client: XtreamClient,
        serverURL: String,
        username: String,
        password: String,
        streamId: Int,
        limit: Int
    ) async throws -> [XtreamShortEPG] {
        do {
            return try await client.getShortEPG(
                serverURL: serverURL,
                username: username,
                password: password,
                streamId: streamId,
                limit: limit
            )
        } catch {
            guard isTransientNetworkFailure(error) else { throw error }
            try await Task.sleep(for: .milliseconds(400))
            return try await client.getShortEPG(
                serverURL: serverURL,
                username: username,
                password: password,
                streamId: streamId,
                limit: limit
            )
        }
    }

    nonisolated static func makeChannelEPG(from programs: [EPGProgram], now: Date) -> ChannelEPG {
        guard !programs.isEmpty else {
            return ChannelEPG(current: nil, next: nil)
        }

        // Exact overlap: start <= now < end
        if let current = programs.first(where: { $0.start <= now && now < $0.end }) {
            let next = programs.first(where: { $0.start >= current.end })
                ?? programs.first(where: { $0.start > now && $0.id != current.id })
            return ChannelEPG(
                current: EPGSlot(title: current.title, start: current.start, end: current.end),
                next: next.map { EPGSlot(title: $0.title, start: $0.start, end: $0.end) }
            )
        }

        // No exact overlap — prefer the next upcoming programme as "current".
        // With stale/shifted EPG data, the schedule is approximate. Other IPTV
        // apps show the next upcoming programme rather than a recently-ended one,
        // because streams often start the next show slightly early.
        let upcoming = programs.filter { $0.start > now }.sorted { $0.start < $1.start }
        if let next = upcoming.first {
            let after = upcoming.count > 1 ? upcoming[1] : nil
            return ChannelEPG(
                current: EPGSlot(title: next.title, start: next.start, end: next.end),
                next: after.map { EPGSlot(title: $0.title, start: $0.start, end: $0.end) }
            )
        }

        // Nothing upcoming — show the most recently ended.
        let sorted = programs.sorted { $0.end > $1.end }
        let nearest = sorted[0]
        let next = sorted.count > 1 ? sorted[1] : nil

        return ChannelEPG(
            current: EPGSlot(title: nearest.title, start: nearest.start, end: nearest.end),
            next: next.map { EPGSlot(title: $0.title, start: $0.start, end: $0.end) }
        )
    }

    nonisolated static func isLiveOrUpcoming(_ program: EPGProgram, now: Date) -> Bool {
        (program.start <= now && now < program.end)
            || (program.start > now && program.start < now.addingTimeInterval(EPGRetention.futureHorizon))
    }

    nonisolated static func hasLiveOrUpcoming(_ programs: [EPGProgram], now: Date) -> Bool {
        programs.contains { isLiveOrUpcoming($0, now: now) }
    }

    private struct LiveChannelEPGFetchResult {
        let programs: [EPGProgram]
        let rawCount: Int
    }

    /// Fetches the current slot the way mainstream players do: `limit=4` short
    /// EPG first. If that doesn't cover now, try `limit=8`.
    /// Unlike earlier versions, this NEVER discards valid parsed data — other
    /// Apple IPTV apps (Chilli, SwipTV) show whatever the provider returns.
    /// On tvOS, skips the expanded second fetch to halve response time — the
    /// store (populated by external feeds) covers most channels; the live API is
    /// only for gap-fill where any data is better than a 2x delay.
    private static func fetchLiveChannelEPG(
        client: XtreamClient,
        serverURL: String,
        username: String,
        password: String,
        streamId: Int,
        timezoneIdentifier: String?,
        now: Date
    ) async throws -> LiveChannelEPGFetchResult {
        let primary = try await fetchChannelEPGWithRetry(
            client: client,
            serverURL: serverURL,
            username: username,
            password: password,
            streamId: streamId,
            limit: Self.liveFetchLimit
        )
        var programs = parse(primary, timezoneIdentifier: timezoneIdentifier, now: now)
        if hasLiveOrUpcoming(programs, now: now) || primary.contains(where: { $0.nowPlaying == true }) {
            return LiveChannelEPGFetchResult(programs: programs, rawCount: primary.count)
        }

        #if os(tvOS)
        // On tvOS, return whatever the first call got — even if not live/upcoming.
        // The store covers most channels; this path is only for gap-fill where
        // showing the nearest programme is better than doubling the wait time.
        if !programs.isEmpty {
            return LiveChannelEPGFetchResult(programs: programs, rawCount: primary.count)
        }
        #endif

        // Try expanded fetch — provider may return oldest first with small limits.
        let expanded = try await fetchChannelEPGWithRetry(
            client: client,
            serverURL: serverURL,
            username: username,
            password: password,
            streamId: streamId,
            limit: Self.expandedFetchLimit
        )
        let expandedPrograms = parse(expanded, timezoneIdentifier: timezoneIdentifier, now: now)
        if hasLiveOrUpcoming(expandedPrograms, now: now) || expanded.contains(where: { $0.nowPlaying == true }) {
            return LiveChannelEPGFetchResult(programs: expandedPrograms, rawCount: expanded.count)
        }

        // Even if nothing overlaps "now" exactly, return whatever we parsed.
        // Other apps (Chilli, SwipTV) surface the nearest programme rather than
        // showing a blank guide. The earlier "return empty" approach made the
        // guide look broken for providers whose schedules have small gaps or
        // slight timing drift relative to the device clock.
        let bestPrograms = expandedPrograms.isEmpty ? programs : expandedPrograms
        let totalRaw = primary.count + expanded.count

        if !bestPrograms.isEmpty {
            if let sample = bestPrograms.first {
                let delta = Int(sample.start.timeIntervalSince(now) / 60)
                Logger.database.info(
                    "EPG live — stream \(streamId) nearest \"\(sample.title, privacy: .public)\" startDeltaMin=\(delta) (returning \(bestPrograms.count) programmes)"
                )
            }
            return LiveChannelEPGFetchResult(programs: bestPrograms, rawCount: totalRaw)
        }

        return LiveChannelEPGFetchResult(programs: [], rawCount: totalRaw)
    }
}

/// Unified entry point for Live TV cards and the guide grid.
enum EPGBrowseLoader {
    /// All visible channels in a page load in the urgent pass. With 6 concurrent
    /// and no stagger, a full 50-channel page resolves in ~8-16 seconds — no need
    /// to split into urgent + background anymore.
    private static let synchronousFetchCap = 50

    /// Loads guide data for visible channels.
    /// Returns store data IMMEDIATELY — live API gap-fill runs in background
    /// and signals `refreshGeneration` when done (caller picks it up via
    /// `.onChange(of: epgSync.refreshGeneration)`).
    ///
    /// This is the key difference vs the old approach: other IPTV apps show
    /// whatever data they have instantly and fill gaps asynchronously. The old
    /// code awaited ALL channels (store + live API) before returning anything,
    /// so 42 instant-from-store channels were held hostage by 7 slow API calls.
    @MainActor
    static func load(
        container: ModelContainer,
        channels: [LiveStream],
        playlist: Playlist?,
        windowStart: Date? = nil,
        windowEnd: Date? = nil,
        now: Date = Date()
    ) async -> (channelEPG: [String: ChannelEPG], programs: [String: [EPGProgram]]) {
        let snapshots = channels.map(EPGStreamSnapshot.init(stream:))
        let start = windowStart ?? now.addingTimeInterval(-3600)
        let end = windowEnd ?? now.addingTimeInterval(48 * 3600)

        var programs: [String: [EPGProgram]] = [:]

        if let playlist, playlist.sourceType == .xtream {
            let credentials = EPGPlaylistCredentials(playlist: playlist)

            // Store first — this is the fast path (instant from SQLite).
            let stored = await Task.detached(priority: .userInitiated) {
                EPGLiveLoader.programsFromStore(
                    container: container,
                    snapshots: snapshots,
                    windowStart: start,
                    windowEnd: end,
                    now: now
                )
            }.value
            for (channelId, slots) in stored {
                programs[channelId] = slots
            }

            // Warm live cache next — gap-fill may already have programmes in
            // memory while persist / store re-read is still catching up. Without
            // this, forceGuideRefresh after a successful live fetch could still
            // paint blank rows (EPG.md rule 531: UI already has data in memory).
            let missingAfterStore = snapshots.filter { programs[$0.primaryEPGChannelId]?.isEmpty ?? true }
            if !missingAfterStore.isEmpty {
                let warm = await EPGLiveLoader.shared.cachedPrograms(
                    for: missingAfterStore,
                    credentials: credentials,
                    now: now
                )
                for (channelId, slots) in warm {
                    programs[channelId] = slots
                }
            }

            // Fire-and-forget: live API gap-fill runs in background for channels
            // not in the store or warm cache. The view updates when refreshGeneration bumps.
            let needsLive = snapshots.filter { programs[$0.primaryEPGChannelId]?.isEmpty ?? true }
            if !needsLive.isEmpty {
                Logger.database.warning("EPG browse — store had data for \(programs.count)/\(snapshots.count) channels; \(needsLive.count) need live API")
                if let sample = needsLive.first {
                    Logger.database.warning("EPG browse — sample needing live: name=\(sample.name, privacy: .public) epgId=\(sample.epgChannelId ?? "nil", privacy: .public) primaryId=\(sample.primaryEPGChannelId, privacy: .public)")
                }
                let bgCredentials = credentials
                let bgContainer = container
                let bgNow = now
                Task.detached(priority: .utility) {
                    let fetched = await EPGLiveLoader.shared.programs(
                        for: needsLive,
                        credentials: bgCredentials,
                        now: bgNow
                    )
                    if !fetched.isEmpty {
                        await EPGAPISync.persist(programsByChannel: fetched, container: bgContainer, now: bgNow)
                        // Force immediate UI update — no throttle. Browse gap-fill
                        // only fires once per category, not repeatedly like sync.
                        // Reload also pulls warm cache above, so rows appear even
                        // if the persist round-trip is still settling.
                        await MainActor.run {
                            EPGSyncService.shared.forceGuideRefresh()
                        }
                    }
                }
            }
        } else {
            programs = await Task.detached(priority: .userInitiated) {
                EPGLiveLoader.programsFromStore(
                    container: container,
                    snapshots: snapshots,
                    windowStart: start,
                    windowEnd: end,
                    now: now
                )
            }.value
        }

        if playlist == nil, !channels.isEmpty {
            Logger.database.warning("EPG browse — no playlist for \(channels.count) channels")
        }

        var channelEPG: [String: ChannelEPG] = [:]
        for (channelId, slots) in programs where !slots.isEmpty {
            channelEPG[channelId] = EPGLiveLoader.makeChannelEPG(from: slots, now: now)
        }
        return (channelEPG, programs)
    }

    private static func hasAiringOrUpcoming(_ programs: [EPGProgram]?, now: Date) -> Bool {
        guard let programs, !programs.isEmpty else { return false }
        return EPGLiveLoader.hasLiveOrUpcoming(programs, now: now)
    }
}
