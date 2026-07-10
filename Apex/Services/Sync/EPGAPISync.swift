//
//  EPGAPISync.swift
//  Apex
//
//  Xtream guide sync — same idea as Lume (fill `EPGListing` in SwiftData), but
//  sourced from per-channel `get_short_epg` / `get_simple_data_table` instead of
//  the often-stale worldwide `xmltv.php` dump.
//

import Foundation
import OSLog
import SwiftData

/// Serializes every on-demand `EPGListing` write and only inserts rows whose
/// unique `id` isn't already in the store.
///
/// SwiftData performs a unique-attribute "upsert" when you insert an object
/// whose `.unique` id collides with an existing row; that save path remaps the
/// persistent identifier and crashes with
/// "PersistentIdentifier ... was remapped to a temporary identifier during
/// save ... fatal logic error in DefaultStore". Two browse-triggered persists
/// racing on separate contexts (or a persist re-inserting an id already on
/// disk) hit this constantly. Funnelling all on-demand writes through one
/// actor — that first reads existing ids and only inserts genuinely new
/// rows — makes the collision impossible.
actor EPGListingWriter {
    static let shared = EPGListingWriter()

    @discardableResult
    func write(
        programsByChannel: [String: [EPGProgram]],
        container: ModelContainer,
        now: Date
    ) -> Int {
        guard !programsByChannel.isEmpty else { return 0 }
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Never insert an id that already exists — that is the exact case that
        // triggers SwiftData's crashing unique-upsert remap.
        let channelIds = Set(programsByChannel.keys)
        let existing = (try? context.fetch(FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { channelIds.contains($0.channelId) }
        ))) ?? []
        var knownIds = Set(existing.map(\.id))

        var inserted = 0
        for (channelId, programs) in programsByChannel {
            for program in programs {
                guard program.end > now.addingTimeInterval(-EPGRetention.pastGrace) else { continue }
                guard program.start < now.addingTimeInterval(EPGRetention.futureHorizon) else { continue }
                let listingId = "\(channelId)-\(Int(program.start.timeIntervalSince1970))-\(Int(program.end.timeIntervalSince1970))"
                guard knownIds.insert(listingId).inserted else { continue }
                context.insert(EPGListing(
                    id: listingId,
                    channelId: channelId,
                    title: program.title,
                    listingDescription: program.description,
                    start: program.start,
                    end: program.end
                ))
                inserted += 1
            }
        }
        guard inserted > 0 else { return 0 }
        try? context.save()
        return inserted
    }
}

enum EPGAPISync {
    struct Result: Sendable {
        let inserted: Int
        let channelsWithData: Int
        let upcoming: Int
        let channelsRequested: Int
    }

    // Matches `XtreamClient.makeEPGImportSession`'s connection pool. Do not
    // raise this — see that function's doc comment. A prior attempt at 12
    // exhausted the provider's connection limit and broke Live TV playback.
    private static let maxConcurrent = 6
    private static let listingsPerChannel = 12
    private static let progressInterval = 100
    /// Log a warning when a single channel's fetch exceeds this duration.
    private static let slowFetchThreshold: TimeInterval = 15

    /// Fetches guide data for every live stream and writes airing/upcoming rows.
    ///
    /// Collects all results from the network phase first, then inserts + saves
    /// **once** at the end. This avoids intermediate saves that each post a
    /// change notification the main context must merge — the cause of "device
    /// freezing" during Sync Now. Other IPTV apps do the same: gather all data,
    /// commit once.
    ///
    /// - Parameter onProgress: Called periodically (throttled) with the number
    ///   of channels processed so far in this call, for a "Sync Now" progress
    ///   indicator. Not called on every single channel to avoid excessive
    ///   actor hops across ~1.6K channels.
    static func sync<C: EPGChannelIdentity>(
        credentials: EPGPlaylistCredentials,
        identities: [C],
        container: ModelContainer,
        client: XtreamClient,
        now: Date = Date(),
        concurrencyLimit: Int? = nil,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> Result {
        guard credentials.sourceType == .xtream, !identities.isEmpty else {
            return Result(inserted: 0, channelsWithData: 0, upcoming: 0, channelsRequested: 0)
        }
        let concurrency = min(max(concurrencyLimit ?? Self.maxConcurrent, 1), Self.maxConcurrent)

        Logger.database.warning(
            "EPG API sync START — \(identities.count) channels, tz=\(credentials.serverTimezone ?? "nil", privacy: .public)"
        )
        let syncStart = Date()

        var channelsWithData = 0
        var completed = 0
        var rawTotal = 0
        var parsedTotal = 0
        var errorTotal = 0
        /// One-shot ground-truth probe. We can't hit the panel directly, so this
        /// is how we tell whether a provider's feed is actually current: it logs
        /// the first real programme's timestamps vs `now`. `deltaMinutes` near 0
        /// means the data is live; a large positive value means the provider's
        /// EPG genuinely lags (no client fix — an external EPG source is needed).
        var loggedRawSample = false
        /// Collect all (channelId, programs) from the network phase first, then
        /// insert + save once at the end. One save = one notification = one
        /// main-context merge, instead of dozens of merges that each stall the UI.
        var collected: [(channelId: String, programs: [EPGProgram])] = []
        collected.reserveCapacity(identities.count)
        let timezone = credentials.serverTimezone

        await withTaskGroup(of: (String, [EPGProgram], Int, Bool).self) { group in
            var iterator = identities.makeIterator()
            var inFlight = 0

            func schedule() {
                while inFlight < concurrency, let ref = iterator.next() {
                    inFlight += 1
                    let streamId = ref.streamId
                    let channelId = ref.primaryEPGChannelId
                    group.addTask {
                        let fetchStart = Date()
                        do {
                            let listings = try await client.fetchChannelEPG(
                                serverURL: credentials.serverURL,
                                username: credentials.username,
                                password: credentials.password,
                                streamId: streamId,
                                limit: listingsPerChannel,
                                thorough: false
                            )
                            let elapsed = Date().timeIntervalSince(fetchStart)
                            if elapsed > slowFetchThreshold {
                                Logger.database.warning(
                                    "EPG slow fetch — stream \(streamId) took \(Int(elapsed))s, returned \(listings.count) listings"
                                )
                            }
                            let programs = parse(listings, timezoneIdentifier: timezone, now: now)
                            return (channelId, programs, listings.count, false)
                        } catch {
                            let elapsed = Date().timeIntervalSince(fetchStart)
                            let cancelled = error is CancellationError
                                || (error as? XtreamError)?.isCancellation == true
                                || (error as? URLError)?.code == .cancelled
                            if !cancelled, elapsed > slowFetchThreshold {
                                Logger.database.warning(
                                    "EPG slow fail — stream \(streamId) errored after \(Int(elapsed))s: \(error.localizedDescription, privacy: .public)"
                                )
                            }
                            return (channelId, [], 0, !cancelled)
                        }
                    }
                }
            }

            schedule()
            for await item in group {
                inFlight -= 1
                completed += 1
                let (channelId, programs, rawCount, hadError) = item
                rawTotal += rawCount
                parsedTotal += programs.count
                if hadError { errorTotal += 1 }

                if completed == 1 || completed.isMultiple(of: progressInterval) || completed == identities.count {
                    Logger.database.warning(
                        "EPG API sync progress — \(completed)/\(identities.count) parsed=\(parsedTotal) raw=\(rawTotal) errors=\(errorTotal)"
                    )
                }
                if completed.isMultiple(of: 5) || completed == identities.count {
                    onProgress?(completed)
                }

                if !programs.isEmpty {
                    channelsWithData += 1
                    collected.append((channelId, programs))
                    if !loggedRawSample {
                        loggedRawSample = true
                        let first = programs[0]
                        let deltaMinutes = Int(first.start.timeIntervalSince(now) / 60)
                        Logger.database.warning(
                            "EPG raw sample — channel \(channelId, privacy: .public) first \"\(first.title, privacy: .public)\" start \(first.start, privacy: .public) end \(first.end, privacy: .public) now \(now, privacy: .public) startDeltaMinutes=\(deltaMinutes)"
                        )
                    }
                }
                schedule()
            }
        }

        // ── Commit: one serialized, de-duplicated write ───────────────────
        // Route through `EPGListingWriter` so this never races an on-demand
        // browse persist on a second context (unique-upsert remap crash).
        var byChannel: [String: [EPGProgram]] = [:]
        for (channelId, programs) in collected {
            byChannel[channelId, default: []].append(contentsOf: programs)
        }
        let inserted = await EPGListingWriter.shared.write(
            programsByChannel: byChannel,
            container: container,
            now: now
        )

        let upcoming = countUpcoming(in: container, now: now)
        let duration = Int(Date().timeIntervalSince(syncStart))
        Logger.database.warning(
            "EPG API sync DONE — \(duration)s, inserted=\(inserted) upcoming=\(upcoming) channelsWithData=\(channelsWithData)/\(identities.count) raw=\(rawTotal) parsed=\(parsedTotal) errors=\(errorTotal)"
        )
        return Result(
            inserted: inserted,
            channelsWithData: channelsWithData,
            upcoming: upcoming,
            channelsRequested: identities.count
        )
    }

    /// Persists on-demand programmes so the guide survives process restarts.
    ///
    /// Serialized through `EPGListingWriter` (never races another writer) and
    /// skipped while the external XMLTV sync owns the store on iOS/macOS — that
    /// pass clears and rebuilds `EPGListing`, so writing on-demand rows into it
    /// at the same time is both wasted work and a cross-context unique-upsert
    /// crash risk.
    ///
    /// On tvOS the bundled sync *preserves* existing rows (Build 19+) and only
    /// inserts new ids — no destructive rebuild — so on-demand persists are safe
    /// and essential: without them, data browsed while the deferred guide sync
    /// runs is never stored, causing the "data disappears on category switch" bug.
    static func persist(
        programsByChannel: [String: [EPGProgram]],
        container: ModelContainer,
        now: Date = Date()
    ) async {
        #if os(tvOS)
        // tvOS bundled sync preserves existing rows — on-demand persists are
        // safe and keep category-switch data in the store.
        #else
        guard !EPGSyncGate.isActive else { return }
        #endif
        await EPGListingWriter.shared.write(
            programsByChannel: programsByChannel,
            container: container,
            now: now
        )
    }

    nonisolated static func parse(
        _ listings: [XtreamShortEPG],
        timezoneIdentifier: String?,
        now: Date
    ) -> [EPGProgram] {
        var programs: [EPGProgram] = []
        programs.reserveCapacity(listings.count)

        for item in listings {
            guard let times = item.programmeTimes(timezoneIdentifier: timezoneIdentifier, now: now) else {
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
        return programs
    }

    private static func countUpcoming(in container: ModelContainer, now: Date) -> Int {
        let context = ModelContext(container)
        let nowBound = now
        return (try? context.fetch(FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { $0.end > nowBound }
        )))?.count ?? 0
    }
}
