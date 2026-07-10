//
//  EPGInserter.swift
//  Apex
//
//  Nonisolated XMLTV → SwiftData insert pipeline. Runs off the sync actor so
//  XMLParser delegate callbacks can insert without Swift 6 actor hops.
//

import Foundation
import OSLog
import SwiftData

nonisolated enum EPGInserter {
    struct Result: Sendable {
        let inserted: Int
        let upcoming: Int
        let totalProgrammes: Int
        let matchedProgrammes: Int
        let parseFailures: Int
        let channelTableSize: Int
        let skippedCap: Int
        let timestampMode: String
        /// Minutes between `now` and the newest programme end in the parse buffers.
        /// Large negative values mean the bulk dump is historical/stale.
        let maxEndDeltaMinutes: Int?
        /// Matched rows exist but every programme already ended — typical when
        /// `xmltv.php` lags days behind the live `get_short_epg` API.
        var isStaleBulkFeed: Bool {
            guard let maxEndDeltaMinutes, matchedProgrammes > 0, inserted == 0 else { return false }
            return maxEndDeltaMinutes < -120
        }
    }

    static func importFile<C: EPGChannelIdentity>(
        fileURL: URL,
        fileSize: Int64,
        container: ModelContainer,
        catalog: EPGChannelCatalog,
        identities: [C],
        timezone: TimeZone? = nil,
        alignLatestToNow: Bool = false,
        xtreamStyleTimestamps: Bool = false
    ) -> Result {
        let effectiveTZ = XMLTVDate.resolveWallClockTimezone(server: timezone, detected: nil)

        var activeCatalog = catalog
        var channelTableSize = 0

        // Log sample playlist channel names for debugging EPG matching.
        let sampleNames = identities.prefix(5).map { "\($0.name) [epgId=\($0.epgChannelId ?? "nil")]" }
        Logger.database.warning("EPG playlist sample channels: \(sampleNames.joined(separator: ", "), privacy: .public)")

        if let channelFile = XMLTVChannelDiskCache.collect(
            fileURL: fileURL,
            catalog: catalog,
            identities: identities
        ) {
            defer { try? FileManager.default.removeItem(at: channelFile) }
            let index = XMLTVChannelDiskCache.loadIndex(from: channelFile)
            channelTableSize = index.idToDisplayNames.count
            activeCatalog = catalog.enriching(with: index, identities: identities)
            Logger.database.warning(
                "EPG XMLTV import — \(fileSize) bytes, channel aliases: \(channelTableSize), server tz: \(timezone?.identifier ?? "nil", privacy: .public), effective tz: \(effectiveTZ.identifier, privacy: .public)"
            )
        } else {
            Logger.database.warning(
                "EPG XMLTV import — \(fileSize) bytes, direct id match, server tz: \(timezone?.identifier ?? "nil", privacy: .public), effective tz: \(effectiveTZ.identifier, privacy: .public)"
            )
        }

        return importProgrammes(
            fileURL: fileURL,
            container: container,
            catalog: activeCatalog,
            identities: identities,
            channelTableSize: channelTableSize,
            serverTimezone: timezone,
            effectiveTimezone: effectiveTZ,
            alignLatestToNow: alignLatestToNow,
            xtreamStyleTimestamps: xtreamStyleTimestamps
        )
    }

    private struct TimestampStrategy: Equatable {
        let label: String
        let timezone: TimeZone?
        let treatExplicitZeroOffsetAsLocal: Bool
        let interpretZeroOffsetIn: TimeZone?
    }

    /// Buffers matched programmes per channel, then writes the rows nearest to
    /// `now` so file-order caps do not fill the store with week-old slots.
    private struct ChannelBuffer {
        private var programmes: [ParsedProgramme] = []

        mutating func add(_ programme: ParsedProgramme, softCap: Int) {
            programmes.append(programme)
            guard programmes.count > softCap * 4 else { return }
            programmes.sort { $0.start < $1.start }
            programmes = Array(programmes.suffix(softCap * 3))
        }

        var bufferedCount: Int { programmes.count }
        var allProgrammes: [ParsedProgramme] { programmes }

        func pick(limit: Int, now: Date) -> [ParsedProgramme] {
            programmes
                .filter { EPGRetention.shouldImport(start: $0.start, end: $0.end, now: now) }
                .sorted { $0.start < $1.start }
                .prefix(limit)
                .map { $0 }
        }

        func pick(limit: Int, now: Date, preferredSourceIDs: Set<String>) -> [ParsedProgramme] {
            guard !preferredSourceIDs.isEmpty else {
                return pick(limit: limit, now: now)
            }
            let preferred = programmes
                .filter { preferredSourceIDs.contains($0.channelId.lowercased()) }
                .filter { EPGRetention.shouldImport(start: $0.start, end: $0.end, now: now) }
                .sorted { $0.start < $1.start }
                .prefix(limit)
                .map { $0 }
            if !preferred.isEmpty {
                return preferred
            }
            return pick(limit: limit, now: now)
        }
    }

    private static func importProgrammes<C: EPGChannelIdentity>(
        fileURL: URL,
        container: ModelContainer,
        catalog: EPGChannelCatalog,
        identities: [C],
        channelTableSize: Int,
        serverTimezone: TimeZone?,
        effectiveTimezone: TimeZone,
        alignLatestToNow: Bool,
        xtreamStyleTimestamps: Bool
    ) -> Result {
        let importNow = Date()
        _ = alignLatestToNow

        var strategies: [TimestampStrategy] = []
        if xtreamStyleTimestamps {
            // Literal first — fastest way to measure match count and whether the
            // bulk dump is days behind the live per-channel API.
            strategies.append(TimestampStrategy(
                label: "literal-offset",
                timezone: effectiveTimezone,
                treatExplicitZeroOffsetAsLocal: false,
                interpretZeroOffsetIn: nil
            ))
            strategies.append(TimestampStrategy(
                label: "xtream-local-+0000",
                timezone: effectiveTimezone,
                treatExplicitZeroOffsetAsLocal: true,
                interpretZeroOffsetIn: nil
            ))
            if let serverTimezone, !XMLTVDate.isZeroOffset(serverTimezone) {
                strategies.append(TimestampStrategy(
                    label: "server-zone-+0000",
                    timezone: serverTimezone,
                    treatExplicitZeroOffsetAsLocal: false,
                    interpretZeroOffsetIn: serverTimezone
                ))
            }
        } else {
            strategies.append(TimestampStrategy(
                label: "standard",
                timezone: effectiveTimezone,
                treatExplicitZeroOffsetAsLocal: false,
                interpretZeroOffsetIn: nil
            ))
        }

        var bestStats = XMLTVParser.ImportStats(
            totalProgrammes: 0,
            matchedProgrammes: 0,
            channelTableSize: channelTableSize,
            parseFailures: 0
        )
        var bestBuffers: [String: ChannelBuffer] = [:]
        var bestInserted = 0
        var bestMatched = 0
        var bestMode = strategies[0].label
        var bestMaxEndDeltaMinutes: Int?

        for strategy in strategies {
            var buffers: [String: ChannelBuffer] = [:]
            var sampleStartDeltaMin = 0
            var sampleEndDeltaMin = 0
            var loggedSample = false
            var newestMatchedEnd: Date?
            let staleCutoff = importNow.addingTimeInterval(-120 * 60)
            let abortBox = StaleAbortBox()
            var matchedSoFar = 0

            let stats = XMLTVParser.importGuide(
                fileURL: fileURL,
                baseCatalog: catalog,
                identities: identities,
                timezone: strategy.timezone,
                treatExplicitZeroOffsetAsLocal: strategy.treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: strategy.interpretZeroOffsetIn,
                batchSize: 500,
                shouldAbort: { abortBox.shouldAbort }
            ) { activeCatalog, batch in
                autoreleasepool {
                    for programme in batch {
                        if !loggedSample {
                            loggedSample = true
                            sampleStartDeltaMin = Int(programme.start.timeIntervalSince(importNow) / 60)
                            sampleEndDeltaMin = Int(programme.end.timeIntervalSince(importNow) / 60)
                        }
                        newestMatchedEnd = max(newestMatchedEnd ?? programme.end, programme.end)
                        let channelId = activeCatalog.primaryID(for: programme.channelId)
                        buffers[channelId, default: ChannelBuffer()].add(
                            programme,
                            softCap: EPGRetention.maxListingsPerChannel
                        )
                    }
                    matchedSoFar += batch.count
                    // Do NOT abort early. The XMLTV file may have stale data at
                    // the top and current data further in. A 58MB file with
                    // current programmes deep inside was being cut off after 500
                    // matches, which is why the guide appeared empty while other
                    // apps (Dion, Chilli) that parse the whole file had data.
                }
            }

            let schedule = scheduleDiagnostics(buffers, now: importNow)
            if let schedule {
                Logger.database.warning(
                    "EPG schedule probe [\(strategy.label, privacy: .public)] — minEndDeltaMin=\(schedule.minEndDeltaMin) maxEndDeltaMin=\(schedule.maxEndDeltaMin) maxStartDeltaMin=\(schedule.maxStartDeltaMin)"
                )
            }
            Logger.database.warning(
                "EPG XMLTV mode \(strategy.label, privacy: .public) — sample startDeltaMin=\(sampleStartDeltaMin) endDeltaMin=\(sampleEndDeltaMin)"
            )

            let importable = countImportable(buffers, now: importNow)
            Logger.database.warning(
                "EPG XMLTV mode \(strategy.label, privacy: .public) — matched \(stats.matchedProgrammes), importable \(importable)"
            )

            let isBetter = importable > bestInserted
                || (importable == bestInserted && stats.matchedProgrammes > bestMatched)
            if isBetter {
                bestInserted = importable
                bestMatched = stats.matchedProgrammes
                bestBuffers = buffers
                bestStats = stats
                bestMode = strategy.label
                bestMaxEndDeltaMinutes = schedule?.maxEndDeltaMin
            }

            if importable > 0 { break }
        }

        // Build a map: primaryID → Set<lowercase XMLTV channel IDs that streams prefer>
        var preferredSourcesByPrimary: [String: Set<String>] = [:]
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            if let epgId = identity.epgChannelId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !epgId.isEmpty {
                preferredSourcesByPrimary[primary, default: []].insert(epgId.lowercased())
            }
        }

        let saved = saveBuffers(bestBuffers, into: container, importNow: importNow, preferredSources: preferredSourcesByPrimary)
        let upcomingCount = countUpcoming(in: container, now: importNow)
        let skippedCap = bestBuffers.values.reduce(0) { partial, buffer in
            partial + max(0, buffer.bufferedCount - buffer.pick(limit: EPGRetention.maxListingsPerChannel, now: importNow).count)
        }

        Logger.database.warning(
            "EPG insert done — mode: \(bestMode, privacy: .public), parsed: \(bestStats.totalProgrammes), matched: \(bestStats.matchedProgrammes), parseFailed: \(bestStats.parseFailures), inserted: \(saved), upcoming: \(upcomingCount), skippedCap: \(skippedCap), channelBuffers: \(bestBuffers.count), channelTable: \(bestStats.channelTableSize)"
        )

        return Result(
            inserted: saved,
            upcoming: upcomingCount,
            totalProgrammes: bestStats.totalProgrammes,
            matchedProgrammes: bestStats.matchedProgrammes,
            parseFailures: bestStats.parseFailures,
            channelTableSize: bestStats.channelTableSize,
            skippedCap: skippedCap,
            timestampMode: bestMode,
            maxEndDeltaMinutes: bestMaxEndDeltaMinutes
        )
    }

    private struct ScheduleDiagnostics: Sendable {
        let minEndDeltaMin: Int
        let maxEndDeltaMin: Int
        let maxStartDeltaMin: Int
    }

    private final class StaleAbortBox: @unchecked Sendable {
        var shouldAbort = false
    }

    private static func scheduleDiagnostics(
        _ buffers: [String: ChannelBuffer],
        now: Date
    ) -> ScheduleDiagnostics? {
        var maxEndDeltaMin = Int.min
        var minEndDeltaMin = Int.max
        var maxStartDeltaMin = Int.min
        for (_, buffer) in buffers {
            for programme in buffer.allProgrammes {
                let endDelta = Int(programme.end.timeIntervalSince(now) / 60)
                let startDelta = Int(programme.start.timeIntervalSince(now) / 60)
                maxEndDeltaMin = max(maxEndDeltaMin, endDelta)
                minEndDeltaMin = min(minEndDeltaMin, endDelta)
                maxStartDeltaMin = max(maxStartDeltaMin, startDelta)
            }
        }
        guard maxEndDeltaMin != Int.min else { return nil }
        return ScheduleDiagnostics(
            minEndDeltaMin: minEndDeltaMin,
            maxEndDeltaMin: maxEndDeltaMin,
            maxStartDeltaMin: maxStartDeltaMin
        )
    }

    private static func countImportable(
        _ buffers: [String: ChannelBuffer],
        now: Date
    ) -> Int {
        var count = 0
        for (_, buffer) in buffers {
            count += buffer.pick(limit: EPGRetention.maxListingsPerChannel, now: now).count
        }
        return count
    }

    private static func saveBuffers(
        _ buffers: [String: ChannelBuffer],
        into container: ModelContainer,
        importNow: Date,
        preferredSources: [String: Set<String>]
    ) -> Int {
        // Detect stale bulk feed. Shift each programme to today at same time-of-day.
        let isStale: Bool = {
            guard let diagnostics = scheduleDiagnostics(buffers, now: importNow) else { return false }
            return diagnostics.maxEndDeltaMin < -120
        }()

        var inserted = 0
        let insertContext = ModelContext(container)
        insertContext.autosaveEnabled = false
        var seen = Set<String>()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: importNow)

        for (channelId, buffer) in buffers {
            let picks: [ParsedProgramme]
            let preferred = preferredSources[channelId] ?? []
            if isStale {
                // When stale, shift the MOST RECENT day's schedule to today.
                // The XMLTV may have multiple days of data for each channel. If
                // we shift ALL days to today, programmes from different days land
                // on the same time slots — the dedup keeps the first (oldest/wrong)
                // one. Other apps show the newest day's schedule, so filter to the
                // latest day's programmes before shifting.
                let allSorted: [ParsedProgramme]
                if !preferred.isEmpty {
                    let filtered = buffer.allProgrammes.filter { preferred.contains($0.channelId.lowercased()) }
                    allSorted = (filtered.isEmpty ? buffer.allProgrammes : filtered).sorted { $0.start < $1.start }
                } else {
                    allSorted = buffer.allProgrammes.sorted { $0.start < $1.start }
                }
                // Find the most recent day in the data and only keep that day.
                if let newest = allSorted.last {
                    let newestDay = calendar.startOfDay(for: newest.start)
                    let oneDayBefore = newestDay.addingTimeInterval(-86400)
                    picks = allSorted.filter { $0.start >= oneDayBefore }
                } else {
                    picks = allSorted
                }
            } else {
                picks = buffer.pick(limit: EPGRetention.maxListingsPerChannel, now: importNow, preferredSourceIDs: preferred)
            }
            for programme in picks {
                let start: Date
                let end: Date
                if isStale {
                    let programmeDay = calendar.startOfDay(for: programme.start)
                    let dayOffset = todayStart.timeIntervalSince(programmeDay)
                    start = programme.start.addingTimeInterval(dayOffset)
                    end = programme.end.addingTimeInterval(dayOffset)
                } else {
                    start = programme.start
                    end = programme.end
                }
                guard end > importNow.addingTimeInterval(-EPGRetention.pastGrace) else { continue }
                guard start < importNow.addingTimeInterval(EPGRetention.futureHorizon) else { continue }
                let listingId = "\(channelId)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
                guard seen.insert(listingId).inserted else { continue }
                insertContext.insert(EPGListing(
                    id: listingId,
                    channelId: channelId,
                    title: programme.title,
                    listingDescription: programme.description,
                    start: start,
                    end: end
                ))
                inserted += 1
            }
        }
        if inserted > 0 {
            try? insertContext.save()
        }

        // ── DIAGNOSTIC: log first 5 channels' stored data so we can see ──
        // what titles are being matched and at what shifted times.
        var diagCount = 0
        for (channelId, buffer) in buffers where diagCount < 5 {
            let programmes = buffer.allProgrammes.sorted { $0.start < $1.start }
            guard let first = programmes.first else { continue }
            let originalStart = first.start
            let shiftedDay = calendar.startOfDay(for: first.start)
            let dayOffset = todayStart.timeIntervalSince(shiftedDay)
            let shifted = first.start.addingTimeInterval(dayOffset)
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            df.timeZone = .current
            Logger.database.warning(
                "EPG DIAG — ch=\(channelId, privacy: .public) xmltvCh=\(first.channelId, privacy: .public) title=\"\(first.title, privacy: .public)\" origStart=\(originalStart, privacy: .public) shiftedToday=\(df.string(from: shifted), privacy: .public) bufferSize=\(programmes.count) isStale=\(isStale)"
            )
            diagCount += 1
        }

        return inserted
    }

    private static func logScheduleDiagnostics(
        _ buffers: [String: ChannelBuffer],
        now: Date,
        mode: String
    ) {
        guard let schedule = scheduleDiagnostics(buffers, now: now) else { return }
        Logger.database.warning(
            "EPG schedule probe [\(mode, privacy: .public)] — minEndDeltaMin=\(schedule.minEndDeltaMin) maxEndDeltaMin=\(schedule.maxEndDeltaMin) maxStartDeltaMin=\(schedule.maxStartDeltaMin)"
        )
    }

    private static func countUpcoming(in container: ModelContainer, now: Date) -> Int {
        let context = ModelContext(container)
        let nowBound = now
        return (try? context.fetch(FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { $0.end > nowBound }
        )))?.count ?? 0
    }
}
