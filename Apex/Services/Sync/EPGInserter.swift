//
//  EPGInserter.swift
//  Apex
//
//  Nonisolated XMLTV → SwiftData insert pipeline. Runs off the sync actor so
//  XMLParser delegate callbacks can insert without Swift 6 actor hops.
//
//  MEMORY-SAFE TWO-PASS DESIGN (tvOS jetsam-safe):
//  ─────────────────────────────────────────────────
//  Pass 1 (Strategy Selection): Lightweight SAX scan that only tracks match
//  counts and timestamp deltas per strategy. Memory footprint is O(1) — a few
//  integers regardless of feed size. Selects the best timestamp strategy.
//
//  Pass 2 (Streaming Insert): Re-parses with the winning strategy and inserts
//  directly into SwiftData in batches. No ChannelBuffer accumulation. Peak
//  memory = one batch (500 programmes) + dedup set + SwiftData context.
//  This enables parsing ~73MB+ external feeds on Apple TV without jetsam kills.
//

import Foundation
import OSLog
import SwiftData

/// Maximum number of channel-table entries retained during streaming parse.
/// Matches the cap in XMLTVGuideImporter to prevent unbounded growth on
/// feeds with thousands of matching channels.
private let epgMaxChannelTableEntries = 2_500

/// Maximum length for programme title/description text during streaming parse.
private let epgMaxTextLength = 512

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

        // Log sample playlist channel names for debugging EPG matching.
        let sampleNames = identities.prefix(5).map { "\($0.name) [epgId=\($0.epgChannelId ?? "nil")]" }
        Logger.database.warning("EPG playlist sample channels: \(sampleNames.joined(separator: ", "), privacy: .public)")

        Logger.database.warning(
            "EPG XMLTV import — \(fileSize) bytes, two-pass streaming, server tz: \(timezone?.identifier ?? "nil", privacy: .public), effective tz: \(effectiveTZ.identifier, privacy: .public)"
        )

        return importProgrammes(
            fileURL: fileURL,
            container: container,
            catalog: catalog,
            identities: identities,
            channelTableSize: 0,
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

    /// Lightweight stats collected during Pass 1 (strategy selection).
    /// Memory footprint is O(1) — no programme buffering.
    private struct StrategyStats {
        var matchedCount: Int = 0
        var importableEstimate: Int = 0
        var maxEndDeltaMin: Int = Int.min
        var minEndDeltaMin: Int = Int.max
        var maxStartDeltaMin: Int = Int.min
        var newestMatchedEnd: Date?
        var sampleStartDeltaMin: Int = 0
        var sampleEndDeltaMin: Int = 0
        var loggedSample: Bool = false
    }

    // MARK: - Minimal Timestamp-Only SAX Scanner (Pass 1)

    /// A truly O(1)-memory SAX delegate that reads ONLY `<programme start="" stop="">`
    /// attributes and parses timestamps. Does NOT build a channel table, does NOT
    /// retain titles/descriptions, does NOT match against identities. This exists
    /// solely so Pass 1 can evaluate timestamp strategies without the multi-gigabyte
    /// channel-table overhead of `XMLTVParser.importGuide`.
    private final class TimestampProbeScanner: NSObject, XMLParserDelegate {
        let timezone: TimeZone?
        let treatExplicitZeroOffsetAsLocal: Bool
        let interpretZeroOffsetIn: TimeZone?
        let importNow: Date
        let onTimestamp: (_ start: Date, _ end: Date) -> Void

        private var currentStart: String?
        private var currentStop: String?
        var totalProgrammes = 0

        init(
            timezone: TimeZone?,
            treatExplicitZeroOffsetAsLocal: Bool,
            interpretZeroOffsetIn: TimeZone?,
            importNow: Date,
            onTimestamp: @escaping (_ start: Date, _ end: Date) -> Void
        ) {
            self.timezone = timezone
            self.treatExplicitZeroOffsetAsLocal = treatExplicitZeroOffsetAsLocal
            self.interpretZeroOffsetIn = interpretZeroOffsetIn
            self.importNow = importNow
            self.onTimestamp = onTimestamp
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "programme" else { return }
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"]
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "programme",
                  let startStr = currentStart,
                  let stopStr = currentStop
            else { return }

            totalProgrammes += 1

            guard let start = XMLTVDate.parseEPG(
                startStr,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
            ),
            let end = XMLTVDate.parseEPG(
                stopStr,
                timezone: timezone,
                treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: interpretZeroOffsetIn
            ) else {
                currentStart = nil
                currentStop = nil
                return
            }

            onTimestamp(start, end)
            currentStart = nil
            currentStop = nil
        }
    }

    /// Runs a minimal SAX scan over an XMLTV file, yielding only parsed
    /// `(start, end)` timestamp pairs. No channel table, no title/desc parsing,
    /// no identity matching. Peak memory is O(1) regardless of file size.
    private static func probeTimestamps(
        fileURL: URL,
        timezone: TimeZone?,
        treatExplicitZeroOffsetAsLocal: Bool,
        interpretZeroOffsetIn: TimeZone?,
        importNow: Date,
        onTimestamp: @escaping (_ start: Date, _ end: Date) -> Void
    ) -> Int {
        guard let stream = InputStream(url: fileURL) else { return 0 }
        let parser = XMLParser(stream: stream)

        let scanner = TimestampProbeScanner(
            timezone: timezone,
            treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
            interpretZeroOffsetIn: interpretZeroOffsetIn,
            importNow: importNow,
            onTimestamp: onTimestamp
        )
        parser.delegate = scanner
        parser.parse()
        return scanner.totalProgrammes
    }

    // MARK: - Streaming Insert SAX Parser (Pass 2)

    /// A SAX delegate that parses XMLTV channels + programmes and yields
    /// matched programmes in batches directly to a callback. Unlike
    /// `XMLTVGuideImporter`, this parser does NOT retain a full channel table
    /// for all channels — it only keeps channels that match the catalog,
    /// capped at 2500 entries. Programme text (title/desc) is discarded
    /// immediately after yielding. Peak memory = channel table (capped) +
    /// one batch (500 programmes).
    private final class StreamingInsertParser<C: EPGChannelIdentity>: NSObject, XMLParserDelegate {
        private let catalog: EPGChannelCatalog
        private let identities: [C]
        private let exactNameIndex: EPGStreamExactNameIndex
        private let timezone: TimeZone?
        private let treatExplicitZeroOffsetAsLocal: Bool
        private let interpretZeroOffsetIn: TimeZone?
        private let batchSize: Int
        private let onBatch: (EPGChannelCatalog, [ParsedProgramme]) -> Void

        private var channelTable: [String: [String]] = [:]
        private var enrichedCatalog: EPGChannelCatalog?
        private var batch: [ParsedProgramme] = []

        private(set) var totalProgrammes = 0
        private(set) var matchedProgrammes = 0
        private(set) var parseFailures = 0
        private var loggedRawTimestamp = false

        private var currentChannelID: String?
        private var currentChannelNames: [String] = []
        private var currentDisplayName: String?
        private var currentStart: String?
        private var currentStop: String?
        private var currentProgrammeChannel: String?
        private var currentTitle: String?
        private var currentDesc: String?
        private var currentText = ""


        init(
            catalog: EPGChannelCatalog,
            identities: [C],
            timezone: TimeZone?,
            treatExplicitZeroOffsetAsLocal: Bool,
            interpretZeroOffsetIn: TimeZone?,
            batchSize: Int,
            onBatch: @escaping (EPGChannelCatalog, [ParsedProgramme]) -> Void
        ) {
            self.catalog = catalog
            self.identities = identities
            self.exactNameIndex = EPGStreamExactNameIndex(identities: identities)
            self.timezone = timezone
            self.treatExplicitZeroOffsetAsLocal = treatExplicitZeroOffsetAsLocal
            self.interpretZeroOffsetIn = interpretZeroOffsetIn
            self.batchSize = batchSize
            self.onBatch = onBatch
        }

        private func flushBatch() {
            guard !batch.isEmpty else { return }
            let cat = enrichedCatalog ?? catalog
            onBatch(cat, batch)
            batch.removeAll(keepingCapacity: true)
        }

        private func ensureCatalog() {
            guard enrichedCatalog == nil else { return }
            let index = XMLTVChannelIndex(idToDisplayNames: channelTable)
            enrichedCatalog = catalog.enriching(with: index, identities: identities)
        }

        func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
            currentText = ""
            switch elementName {
            case "channel":
                currentChannelID = attributeDict["id"]
                currentChannelNames = []
                currentDisplayName = nil
            case "programme":
                currentStart = attributeDict["start"]
                currentStop = attributeDict["stop"] ?? attributeDict["end"]
                currentProgrammeChannel = attributeDict["channel"]
                currentTitle = nil
                currentDesc = nil
            default:
                break
            }
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            guard currentText.count < epgMaxTextLength else { return }
            let remaining = epgMaxTextLength - currentText.count
            currentText += String(string.prefix(remaining))
        }

        private func commitChannelIfRelevant() {
            guard let channelID = currentChannelID else { return }
            guard !currentChannelNames.isEmpty else { return }
            let idMatch = catalog.matches(channelID)
            let nameMatch = exactNameIndex.matches(displayNames: currentChannelNames)
            guard idMatch || nameMatch else { return }
            guard idMatch || channelTable.count < epgMaxChannelTableEntries else { return }
            channelTable[channelID] = currentChannelNames
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
            switch elementName {
            case "display-name":
                if currentChannelID != nil {
                    let name = (currentDisplayName ?? "") + currentText
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        currentChannelNames.append(trimmed)
                    }
                    currentDisplayName = name
                }
            case "channel":
                commitChannelIfRelevant()
                currentChannelID = nil
                currentChannelNames = []
                currentDisplayName = nil
            case "programme":
                defer {
                    currentStart = nil
                    currentStop = nil
                    currentProgrammeChannel = nil
                    currentTitle = nil
                    currentDesc = nil
                }
                guard let channel = currentProgrammeChannel,
                      let title = currentTitle, !title.isEmpty
                else { return }
                totalProgrammes += 1

                var activeCatalog = enrichedCatalog
                if activeCatalog == nil {
                    if catalog.matches(channel) {
                        activeCatalog = catalog
                    } else {
                        ensureCatalog()
                        activeCatalog = enrichedCatalog
                    }
                }
                guard let activeCatalog, activeCatalog.matches(channel) else { return }

                if !loggedRawTimestamp {
                    loggedRawTimestamp = true
                    Logger.database.warning(
                        "EPG XMLTV raw timestamp — start: \(self.currentStart ?? "nil", privacy: .public), stop: \(self.currentStop ?? "nil", privacy: .public)"
                    )
                }
                guard let times = XMLTVDate.parseProgrammeTimes(
                    start: currentStart,
                    stop: currentStop,
                    timezone: timezone,
                    treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
                    interpretZeroOffsetIn: interpretZeroOffsetIn
                ) else {
                    parseFailures += 1
                    return
                }
                matchedProgrammes += 1
                batch.append(ParsedProgramme(
                    channelId: channel,
                    title: String(title.prefix(epgMaxTextLength)),
                    description: String((currentDesc ?? "").prefix(epgMaxTextLength)),
                    start: times.start,
                    end: times.end
                ))
                if batch.count >= batchSize {
                    flushBatch()
                }
            case "title":
                currentTitle = (currentTitle ?? "") + currentText
            case "desc":
                currentDesc = (currentDesc ?? "") + currentText
            default:
                break
            }
            currentText = ""
        }

        func parserDidEndDocument(_: XMLParser) {
            flushBatch()
        }
    }

    /// Runs a streaming SAX parse over an XMLTV file, yielding matched
    /// programmes in batches. The channel table is built incrementally and
    /// capped at 2500 entries. Peak memory is constant regardless of file size.
    private static func streamParseAndInsert<C: EPGChannelIdentity>(
        fileURL: URL,
        catalog: EPGChannelCatalog,
        identities: [C],
        timezone: TimeZone?,
        treatExplicitZeroOffsetAsLocal: Bool,
        interpretZeroOffsetIn: TimeZone?,
        batchSize: Int = 500,
        onBatch: @escaping (EPGChannelCatalog, [ParsedProgramme]) -> Void
    ) -> (totalProgrammes: Int, matchedProgrammes: Int, parseFailures: Int) {
        guard let stream = InputStream(url: fileURL) else {
            return (0, 0, 0)
        }
        let parser = XMLParser(stream: stream)

        let delegate = StreamingInsertParser(
            catalog: catalog,
            identities: identities,
            timezone: timezone,
            treatExplicitZeroOffsetAsLocal: treatExplicitZeroOffsetAsLocal,
            interpretZeroOffsetIn: interpretZeroOffsetIn,
            batchSize: batchSize,
            onBatch: onBatch
        )
        parser.delegate = delegate
        parser.parse()
        return (delegate.totalProgrammes, delegate.matchedProgrammes, delegate.parseFailures)
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

        // ── Build strategy list ──
        var strategies: [TimestampStrategy] = []
        if xtreamStyleTimestamps {
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

        // ════════════════════════════════════════════════════════════════════
        // PASS 1: Lightweight strategy selection (O(1) memory)
        // ════════════════════════════════════════════════════════════════════
        // Parse once per strategy but do NOT buffer programmes. Only track
        // match counts and timestamp deltas to select the best strategy.
        // This replaces the old ChannelBuffer accumulation that held all
        // matched programmes in memory simultaneously.

        var bestStrategyIndex = 0
        var bestImportable = 0
        var bestMatched = 0
        var bestMaxEndDeltaMin: Int?
        var bestStats = XMLTVParser.ImportStats(
            totalProgrammes: 0,
            matchedProgrammes: 0,
            channelTableSize: channelTableSize,
            parseFailures: 0
        )

        for (index, strategy) in strategies.enumerated() {
            var stats = StrategyStats()

            // Use the minimal timestamp-only scanner instead of
            // XMLTVParser.importGuide. The full parser builds a channel table
            // ([String: [String]]) that consumes gigabytes for large feeds.
            // This scanner reads ONLY <programme start="" stop=""> attributes
            // and keeps O(1) memory regardless of file size.
            let totalProgrammes = probeTimestamps(
                fileURL: fileURL,
                timezone: strategy.timezone,
                treatExplicitZeroOffsetAsLocal: strategy.treatExplicitZeroOffsetAsLocal,
                interpretZeroOffsetIn: strategy.interpretZeroOffsetIn,
                importNow: importNow
            ) { start, end in
                if !stats.loggedSample {
                    stats.loggedSample = true
                    stats.sampleStartDeltaMin = Int(start.timeIntervalSince(importNow) / 60)
                    stats.sampleEndDeltaMin = Int(end.timeIntervalSince(importNow) / 60)
                }
                stats.newestMatchedEnd = max(stats.newestMatchedEnd ?? end, end)

                let endDelta = Int(end.timeIntervalSince(importNow) / 60)
                let startDelta = Int(start.timeIntervalSince(importNow) / 60)
                stats.maxEndDeltaMin = max(stats.maxEndDeltaMin, endDelta)
                stats.minEndDeltaMin = min(stats.minEndDeltaMin, endDelta)
                stats.maxStartDeltaMin = max(stats.maxStartDeltaMin, startDelta)

                // Estimate importable count using retention filter
                if EPGRetention.shouldImport(start: start, end: end, now: importNow) {
                    stats.importableEstimate += 1
                }
                stats.matchedCount += 1
            }

            if stats.maxEndDeltaMin != Int.min {
                Logger.database.warning(
                    "EPG schedule probe [\(strategy.label, privacy: .public)] — minEndDeltaMin=\(stats.minEndDeltaMin) maxEndDeltaMin=\(stats.maxEndDeltaMin) maxStartDeltaMin=\(stats.maxStartDeltaMin)"
                )
            }
            Logger.database.warning(
                "EPG XMLTV mode \(strategy.label, privacy: .public) — sample startDeltaMin=\(stats.sampleStartDeltaMin) endDeltaMin=\(stats.sampleEndDeltaMin)"
            )
            Logger.database.warning(
                "EPG XMLTV mode \(strategy.label, privacy: .public) — total \(totalProgrammes), importable \(stats.importableEstimate)"
            )

            let isBetter = stats.importableEstimate > bestImportable
                || (stats.importableEstimate == bestImportable && totalProgrammes > bestMatched)
            if isBetter {
                bestImportable = stats.importableEstimate
                bestMatched = totalProgrammes
                bestStrategyIndex = index
                bestStats = XMLTVParser.ImportStats(
                    totalProgrammes: totalProgrammes,
                    matchedProgrammes: stats.matchedCount,
                    channelTableSize: 0,
                    parseFailures: 0
                )
                bestMaxEndDeltaMin = stats.maxEndDeltaMin != Int.min ? stats.maxEndDeltaMin : nil
            }

            // Early exit: if this strategy found importable programmes, use it
            if stats.importableEstimate > 0 { break }
        }

        let winningStrategy = strategies[bestStrategyIndex]
        Logger.database.warning(
            "EPG selected strategy: \(winningStrategy.label, privacy: .public) (importable=\(bestImportable), matched=\(bestMatched))"
        )

        // ── Stale detection from Pass 1 stats ──
        let isStale: Bool = {
            guard let maxEndDelta = bestMaxEndDeltaMin else { return false }
            return maxEndDelta < -120
        }()

        // Compute day-shift offset for stale feeds (same logic as original saveBuffers)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: importNow)

        // ════════════════════════════════════════════════════════════════════
        // PASS 2: Streaming insert with winning strategy (constant memory)
        // ════════════════════════════════════════════════════════════════════
        // Re-parse with the winning strategy. Instead of buffering everything
        // in ChannelBuffer, insert directly into SwiftData in batches.
        // Peak memory = one batch (500 programmes) + dedup set + context.

        // Build preferred sources map (same as original)
        var preferredSourcesByPrimary: [String: Set<String>] = [:]
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            if let epgId = identity.epgChannelId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !epgId.isEmpty {
                preferredSourcesByPrimary[primary, default: []].insert(epgId.lowercased())
            }
        }

        // Streaming insert state.
        // IMPORTANT: We create a fresh ModelContext for each batch of inserts
        // rather than using a single long-lived context. SwiftData's ModelContext
        // retains every inserted managed object in memory until the context is
        // deallocated — there is no reset() equivalent. For a 76MB feed with
        // ~200K programmes, a single context would accumulate gigabytes of
        // tracked objects even after save(). Per-batch contexts ensure inserted
        // EPGListings are released immediately after each save+flush.
        var seen = Set<String>()
        var inserted = 0
        var skippedCap = 0
        // Track per-channel insert counts for cap enforcement
        var channelInsertCounts: [String: Int] = [:]
        // For stale feeds: track newest day per channel to filter correctly
        var channelNewestDay: [String: Date] = [:]

        // For stale feeds, we need a two-sub-pass approach within Pass 2:
        // First sub-pass finds the newest day per channel, second sub-pass
        // inserts only that day's programmes shifted to today.
        // However, to avoid double-parsing, we buffer per-channel during
        // streaming and flush when we have enough data or at end.
        // This is still bounded memory because we flush frequently.
        let flushBatchSize = 2000 // Flush to SwiftData every N programmes per channel

        // Per-channel mini-buffer for stale feed handling (bounded by flushBatchSize)
        var staleChannelBuffers: [String: [ParsedProgramme]] = [:]

        // Use the streaming SAX parser instead of XMLTVParser.importGuide.
        // The full parser builds a channel table ([String: [String]]) that
        // consumes gigabytes for large feeds (e.g. US National 2 at 76MB).
        // StreamingInsertParser caps the channel table at 2500 entries and
        // yields batches directly, keeping peak memory constant.
        let parseResult = streamParseAndInsert(
            fileURL: fileURL,
            catalog: catalog,
            identities: identities,
            timezone: winningStrategy.timezone,
            treatExplicitZeroOffsetAsLocal: winningStrategy.treatExplicitZeroOffsetAsLocal,
            interpretZeroOffsetIn: winningStrategy.interpretZeroOffsetIn,
            batchSize: 500
        ) { activeCatalog, batch in
            autoreleasepool {
                // Accumulate validated listings for this parser batch.
                // We create a fresh ModelContext per flush so that inserted
                // EPGListing managed objects are released when the context
                // deallocates after save. SwiftData has no reset() equivalent.
                var pendingListings: [EPGListing] = []

                for programme in batch {
                    let channelId = activeCatalog.primaryID(for: programme.channelId)

                    // Retention filter
                    guard EPGRetention.shouldImport(start: programme.start, end: programme.end, now: importNow) else { continue }

                    // Per-channel cap enforcement
                    let currentCount = channelInsertCounts[channelId, default: 0]
                    guard currentCount < EPGRetention.maxListingsPerChannel else {
                        skippedCap += 1
                        continue
                    }

                    if isStale {
                        // For stale feeds: buffer per-channel, track newest day,
                        // and flush when buffer exceeds threshold
                        staleChannelBuffers[channelId, default: []].append(programme)

                        // Update newest day tracking
                        let programmeDay = calendar.startOfDay(for: programme.start)
                        let existing = channelNewestDay[channelId]
                        if existing == nil || programmeDay > existing! {
                            channelNewestDay[channelId] = programmeDay
                        }

                        // Flush if buffer is getting large
                        if staleChannelBuffers[channelId]!.count >= flushBatchSize {
                            let flushed = flushStaleChannelToListings(
                                channelId: channelId,
                                programmes: staleChannelBuffers[channelId]!,
                                newestDay: channelNewestDay[channelId]!,
                                todayStart: todayStart,
                                importNow: importNow,
                                preferredSourceIDs: preferredSourcesByPrimary[channelId] ?? [],
                                seen: &seen,
                                calendar: calendar
                            )
                            pendingListings.append(contentsOf: flushed.listings)
                            skippedCap += flushed.skipped
                            channelInsertCounts[channelId, default: 0] += flushed.listings.count
                            staleChannelBuffers[channelId]?.removeAll()
                        }
                    } else {
                        // Non-stale: direct insert with preferred source check
                        let preferred = preferredSourcesByPrimary[channelId] ?? []
                        let rawChannelId = programme.channelId.lowercased()

                        // Preferred source filtering: skip non-preferred if preferred exists
                        if !preferred.isEmpty && !preferred.contains(rawChannelId) {
                            let listingId = "\(channelId)-\(Int(programme.start.timeIntervalSince1970))-\(Int(programme.end.timeIntervalSince1970))"
                            if seen.contains(listingId) { continue }
                        }

                        #if os(tvOS)
                        // On tvOS, external XMLTV feeds cannot be parsed due to
                        // Foundation XMLParser memory buffering. The provider's
                        // xmltv.php is the ONLY stored source of past programmes.
                        // Extend the past grace window to 24 hours so historical
                        // data from xmltv.php is retained for the guide's "what
                        // was on" display. iOS uses the standard 1-hour grace
                        // since external feeds provide full history.
                        let effectivePastGrace: TimeInterval = 24 * 3600
                        #else
                        let effectivePastGrace = EPGRetention.pastGrace
                        #endif
                        guard programme.end > importNow.addingTimeInterval(-effectivePastGrace) else { continue }
                        guard programme.start < importNow.addingTimeInterval(EPGRetention.futureHorizon) else { continue }

                        let listingId = "\(channelId)-\(Int(programme.start.timeIntervalSince1970))-\(Int(programme.end.timeIntervalSince1970))"
                        guard seen.insert(listingId).inserted else { continue }

                        pendingListings.append(EPGListing(
                            id: listingId,
                            channelId: channelId,
                            title: programme.title,
                            listingDescription: programme.description,
                            start: programme.start,
                            end: programme.end
                        ))
                        channelInsertCounts[channelId, default: 0] += 1
                    }
                }

                // Flush accumulated listings to SwiftData using a fresh context.
                // The context is deallocated at the end of this scope, releasing
                // all managed objects and preventing unbounded memory growth.
                if !pendingListings.isEmpty {
                    let ctx = ModelContext(container)
                    ctx.autosaveEnabled = false
                    for listing in pendingListings {
                        ctx.insert(listing)
                    }
                    try? ctx.save()
                    inserted += pendingListings.count
                    // ctx goes out of scope here → all EPGListing objects released
                }
            }
        }

        // Flush remaining stale channel buffers
        if isStale {
            var staleFlushListings: [EPGListing] = []
            for (channelId, programmes) in staleChannelBuffers where !programmes.isEmpty {
                guard let newestDay = channelNewestDay[channelId] else { continue }
                let flushed = flushStaleChannelToListings(
                    channelId: channelId,
                    programmes: programmes,
                    newestDay: newestDay,
                    todayStart: todayStart,
                    importNow: importNow,
                    preferredSourceIDs: preferredSourcesByPrimary[channelId] ?? [],
                    seen: &seen,
                    calendar: calendar
                )
                staleFlushListings.append(contentsOf: flushed.listings)
                skippedCap += flushed.skipped
                channelInsertCounts[channelId, default: 0] += flushed.listings.count
            }
            if !staleFlushListings.isEmpty {
                let ctx = ModelContext(container)
                ctx.autosaveEnabled = false
                for listing in staleFlushListings {
                    ctx.insert(listing)
                }
                try? ctx.save()
                inserted += staleFlushListings.count
            }
        }

        // No final save needed — each batch already saved via its own context.

        let upcomingCount = countUpcoming(in: container, now: importNow)

        Logger.database.warning(
            "EPG insert done — mode: \(winningStrategy.label, privacy: .public), parsed: \(parseResult.totalProgrammes), matched: \(parseResult.matchedProgrammes), parseFailed: \(parseResult.parseFailures), inserted: \(inserted), upcoming: \(upcomingCount), skippedCap: \(skippedCap), isStale: \(isStale)"
        )

        return Result(
            inserted: inserted,
            upcoming: upcomingCount,
            totalProgrammes: parseResult.totalProgrammes,
            matchedProgrammes: parseResult.matchedProgrammes,
            parseFailures: parseResult.parseFailures,
            channelTableSize: 0,
            skippedCap: skippedCap,
            timestampMode: winningStrategy.label,
            maxEndDeltaMinutes: bestMaxEndDeltaMin
        )
    }

    /// Flushes a stale channel's buffered programmes: filters to the newest day,
    /// shifts to today, applies dedup and retention, returns EPGListing objects.
    /// Does NOT insert into any ModelContext — the caller batches listings and
    /// inserts them via a fresh per-batch context to prevent memory accumulation.
    private static func flushStaleChannelToListings(
        channelId: String,
        programmes: [ParsedProgramme],
        newestDay: Date,
        todayStart: Date,
        importNow: Date,
        preferredSourceIDs: Set<String>,
        seen: inout Set<String>,
        calendar: Calendar
    ) -> (listings: [EPGListing], skipped: Int) {
        var listings: [EPGListing] = []

        // Filter to newest day only (same logic as original saveBuffers)
        let oneDayBefore = newestDay.addingTimeInterval(-86400)
        let filtered: [ParsedProgramme]
        if !preferredSourceIDs.isEmpty {
            let preferred = programmes.filter { preferredSourceIDs.contains($0.channelId.lowercased()) }
            let source = preferred.isEmpty ? programmes : preferred
            filtered = source.filter { $0.start >= oneDayBefore }.sorted { $0.start < $1.start }
        } else {
            filtered = programmes.filter { $0.start >= oneDayBefore }.sorted { $0.start < $1.start }
        }

        for programme in filtered {
            let programmeDay = calendar.startOfDay(for: programme.start)
            let dayOffset = todayStart.timeIntervalSince(programmeDay)
            let start = programme.start.addingTimeInterval(dayOffset)
            let end = programme.end.addingTimeInterval(dayOffset)

            guard end > importNow.addingTimeInterval(-EPGRetention.pastGrace) else { continue }
            guard start < importNow.addingTimeInterval(EPGRetention.futureHorizon) else { continue }

            let listingId = "\(channelId)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
            guard seen.insert(listingId).inserted else { continue }

            listings.append(EPGListing(
                id: listingId,
                channelId: channelId,
                title: programme.title,
                listingDescription: programme.description,
                start: start,
                end: end
            ))
        }

        let skipped = programmes.count - filtered.count
        return (listings: listings, skipped: skipped)
    }

    private static func countUpcoming(in container: ModelContainer, now: Date) -> Int {
        let context = ModelContext(container)
        let nowBound = now
        return (try? context.fetch(FetchDescriptor<EPGListing>(
            predicate: #Predicate<EPGListing> { $0.end > nowBound }
        )))?.count ?? 0
    }
}
