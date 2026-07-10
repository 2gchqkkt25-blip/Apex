//
//  LiveStream+EPG.swift
//  Apex
//
//  EPG channel identity helpers. Xtream panels often leave `epg_channel_id`
//  empty while XMLTV keys programmes by `stream_id` or `custom_sid`.
//

import Foundation
import SwiftData

/// Pure, sendable EPG id logic — safe from background sync and XMLTV parsing.
enum EPGIdentity {
    nonisolated static func lookupIDs(
        epgChannelId: String?,
        customSid: String?,
        streamId: Int
    ) -> [String] {
        var ids: [String] = []
        func appendUnique(_ value: String?) {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            guard !ids.contains(trimmed) else { return }
            ids.append(trimmed)
            if let numeric = Int(trimmed), String(numeric) != trimmed {
                appendUnique(String(numeric))
            }
        }
        appendUnique(epgChannelId)
        appendUnique(customSid)
        appendUnique(String(streamId))
        return ids
    }

    nonisolated static func primaryID(
        epgChannelId: String?,
        customSid: String?,
        streamId: Int
    ) -> String {
        lookupIDs(epgChannelId: epgChannelId, customSid: customSid, streamId: streamId).first
            ?? String(streamId)
    }

    /// True when an XMLTV / listing channel key refers to the same logical channel
    /// as one of the playlist lookup ids (handles `08821` vs `8821`, case, etc.).
    nonisolated static func channelKeysMatch(_ lhs: String, candidates: [String]) -> Bool {
        let trimmed = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if candidates.contains(trimmed) || candidates.contains(trimmed.lowercased()) {
            return true
        }
        guard let leftNum = Int(trimmed) else { return false }
        return candidates.contains { candidate in
            guard let rightNum = Int(candidate) else { return false }
            return leftNum == rightNum
        }
    }
}

/// Lightweight channel row for EPG sync — avoids holding full `LiveStream`
/// graphs while building the channel catalog and XMLTV name matches.
struct EPGStreamSnapshot: Sendable, EPGChannelIdentity {
    let id: String
    let streamId: Int
    let name: String
    let epgChannelId: String?
    let customSid: String?

    @MainActor
    init(stream: LiveStream) {
        id = stream.id
        streamId = stream.streamId
        name = stream.name
        epgChannelId = stream.epgChannelId
        customSid = stream.customSid
    }

    @MainActor
    static func load(from container: ModelContainer) -> [EPGStreamSnapshot] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let streams = (try? context.fetch(FetchDescriptor<LiveStream>())) ?? []
        return streams.map(EPGStreamSnapshot.init(stream:))
    }

    nonisolated static func filter(playlistID: UUID?, in snapshots: [EPGStreamSnapshot]) -> [EPGStreamSnapshot] {
        guard let playlistID else { return snapshots }
        let prefix = "\(playlistID.uuidString)-live-"
        return snapshots.filter { $0.id.hasPrefix(prefix) }
    }
}

/// Exact normalized display-name lookup — used while scanning huge XMLTV channel
/// tables so fuzzy `contains` matching does not retain thousands of unrelated rows.
struct EPGStreamExactNameIndex: Sendable {
    private let exactNormalized: Set<String>

    nonisolated init<C: EPGChannelIdentity>(identities: [C]) {
        exactNormalized = Set(
            identities
                .map { EPGNameNormalizer.normalize($0.name) }
                .filter { $0.count >= 3 }
        )
    }

    nonisolated func matches(displayNames: [String]) -> Bool {
        for displayName in displayNames {
            let normalized = EPGNameNormalizer.normalize(displayName)
            if normalized.count >= 3, exactNormalized.contains(normalized) {
                return true
            }
        }
        return false
    }
}

/// Fast lookup for matching XMLTV `<display-name>` values to playlist channels
/// without retaining every channel row from a huge provider guide file.
struct EPGStreamNameIndex: Sendable {
    private let exactNormalized: Set<String>
    private let fuzzyNames: [String]

    nonisolated init<C: EPGChannelIdentity>(identities: [C]) {
        var exact = Set<String>()
        var fuzzy: [String] = []
        fuzzy.reserveCapacity(identities.count)
        for identity in identities {
            let normalized = EPGNameNormalizer.normalize(identity.name)
            if normalized.count >= 3 {
                exact.insert(normalized)
            }
            fuzzy.append(identity.name)
        }
        exactNormalized = exact
        fuzzyNames = fuzzy
    }

    nonisolated func mightMatch(displayNames: [String]) -> Bool {
        for displayName in displayNames {
            let normalized = EPGNameNormalizer.normalize(displayName)
            if normalized.count >= 3, exactNormalized.contains(normalized) {
                return true
            }
            if fuzzyNames.contains(where: { EPGNameNormalizer.namesMatch($0, displayName) }) {
                return true
            }
        }
        return false
    }
}

/// Shared EPG identity fields for background-safe snapshots.
protocol EPGChannelIdentity: Sendable {
    var streamId: Int { get }
    var name: String { get }
    var epgChannelId: String? { get }
    var customSid: String? { get }
}

extension EPGChannelIdentity {
    nonisolated var epgLookupIDs: [String] {
        EPGIdentity.lookupIDs(epgChannelId: epgChannelId, customSid: customSid, streamId: streamId)
    }

    nonisolated var primaryEPGChannelId: String {
        EPGIdentity.primaryID(epgChannelId: epgChannelId, customSid: customSid, streamId: streamId)
    }
}

extension EPGStreamSnapshot {
    nonisolated func epgListings(in grouped: [String: [EPGListing]]) -> [EPGListing] {
        for key in epgLookupIDs {
            if let listings = grouped[key], !listings.isEmpty {
                return listings.sorted { $0.start < $1.start }
            }
            let lower = key.lowercased()
            if let listings = grouped[lower], !listings.isEmpty {
                return listings.sorted { $0.start < $1.start }
            }
        }
        for (key, listings) in grouped where !listings.isEmpty {
            if EPGIdentity.channelKeysMatch(key, candidates: epgLookupIDs) {
                return listings.sorted { $0.start < $1.start }
            }
        }
        return []
    }
}

extension LiveStream {
    /// Playlist that owns this stream (`{playlistUUID}-live-{streamId}`).
    var owningPlaylistID: UUID? {
        guard let range = id.range(of: "-live-") else { return nil }
        return UUID(uuidString: String(id[..<range.lowerBound]))
    }

    var epgLookupIDs: [String] {
        EPGIdentity.lookupIDs(epgChannelId: epgChannelId, customSid: customSid, streamId: streamId)
    }

    var primaryEPGChannelId: String {
        EPGIdentity.primaryID(epgChannelId: epgChannelId, customSid: customSid, streamId: streamId)
    }

    /// Listings for this stream from a channel-id keyed guide table.
    func epgListings(in grouped: [String: [EPGListing]]) -> [EPGListing] {
        for key in epgLookupIDs {
            if let listings = grouped[key], !listings.isEmpty {
                return listings
            }
            let lower = key.lowercased()
            if let listings = grouped[lower], !listings.isEmpty {
                return listings
            }
        }
        for (key, listings) in grouped where !listings.isEmpty {
            if EPGIdentity.channelKeysMatch(key, candidates: epgLookupIDs) {
                return listings
            }
        }
        return []
    }
}

/// Channel ids and display names from an XMLTV `<channel>` table.
struct XMLTVChannelIndex: Sendable {
    let idToDisplayNames: [String: [String]]

    nonisolated static let empty = XMLTVChannelIndex(idToDisplayNames: [:])
}

/// Maps every provider/XMLTV channel id variant to the canonical id used in
/// `EPGListing` rows and UI lookups.
struct EPGChannelCatalog: Sendable {
    let knownIDs: Set<String>
    let normalize: [String: String]

    init(snapshots: [EPGStreamSnapshot]) {
        self.init(identities: snapshots)
    }

    nonisolated init<C: EPGChannelIdentity>(identities: [C]) {
        var known = Set<String>()
        var map: [String: String] = [:]
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            for key in identity.epgLookupIDs {
                Self.register(key: key, primary: primary, known: &known, map: &map)
            }
        }
        knownIDs = known
        normalize = map
    }

    nonisolated private static func register(
        key: String,
        primary: String,
        known: inout Set<String>,
        map: inout [String: String]
    ) {
        known.insert(key)
        map[key] = primary
        let lower = key.lowercased()
        known.insert(lower)
        // Only register the lowercase mapping if it doesn't already point to a
        // DIFFERENT primary. Two streams may have `epg_channel_id` values that
        // differ only in case (e.g. "hbodrama.us" vs "HBODrama.us") — each is a
        // distinct stream with distinct EPG data. Letting the last `register` win
        // causes ALL XMLTV programmes to land in one buffer while the other stays
        // empty. When there's a conflict, the exact-case key in `map[key]` still
        // works; the lowercase path just won't resolve (falls through to the
        // raw channelId, which is the right thing).
        if map[lower] == nil || map[lower] == primary {
            map[lower] = primary
        }
        // else: conflict — leave the lowercase entry pointing to whichever
        // primary was registered first. The exact-case entries handle lookups.
        if let numeric = Int(key) {
            let canonical = String(numeric)
            known.insert(canonical)
            if map[canonical] == nil || map[canonical] == primary {
                map[canonical] = primary
            }
        }
    }

    nonisolated init(knownIDs: Set<String>, normalize: [String: String]) {
        self.knownIDs = knownIDs
        self.normalize = normalize
    }

    nonisolated var isEmpty: Bool { knownIDs.isEmpty }

    nonisolated func matches(_ rawChannelId: String) -> Bool {
        let trimmed = rawChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if knownIDs.contains(trimmed) || knownIDs.contains(trimmed.lowercased()) { return true }
        if let numeric = Int(trimmed) {
            return knownIDs.contains(String(numeric))
        }
        return false
    }

    nonisolated func primaryID(for rawChannelId: String) -> String {
        let trimmed = rawChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = normalize[trimmed] ?? normalize[trimmed.lowercased()] {
            return mapped
        }
        if let numeric = Int(trimmed), let mapped = normalize[String(numeric)] {
            return mapped
        }
        return trimmed
    }

    nonisolated func enriching<C: EPGChannelIdentity>(
        with channelIndex: XMLTVChannelIndex,
        identities: [C]
    ) -> EPGChannelCatalog {
        guard !channelIndex.idToDisplayNames.isEmpty, !identities.isEmpty else { return self }
        var aliases: [String: String] = [:]

        var primaryByNormalizedName: [String: String] = [:]
        var fuzzyCandidates: [(name: String, primary: String)] = []
        fuzzyCandidates.reserveCapacity(identities.count)
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            primaryByNormalizedName[EPGNameNormalizer.normalize(identity.name)] = primary
            fuzzyCandidates.append((identity.name, primary))
        }

        for (xmltvID, displayNames) in channelIndex.idToDisplayNames {
            if matches(xmltvID) { continue }
            for displayName in displayNames {
                let normalized = EPGNameNormalizer.normalize(displayName)
                guard normalized.count >= 3 else { continue }
                if let primary = primaryByNormalizedName[normalized] {
                    aliases[xmltvID] = primary
                    break
                }
                if let primary = fuzzyCandidates.first(where: { EPGNameNormalizer.namesMatch($0.name, displayName) })?.primary {
                    aliases[xmltvID] = primary
                    break
                }
            }
        }

        return merging(aliases: aliases)
    }

    nonisolated func merging(aliases: [String: String]) -> EPGChannelCatalog {
        guard !aliases.isEmpty else { return self }
        var known = knownIDs
        var map = normalize
        for (alias, primary) in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            known.insert(trimmed)
            map[trimmed] = primary
            let lower = trimmed.lowercased()
            known.insert(lower)
            map[lower] = primary
        }
        return EPGChannelCatalog(knownIDs: known, normalize: map)
    }

    /// Builds a catalog that maps external EPG channel IDs to playlist streams
    /// by matching display names. This is how TiviMate/Dion match external EPG
    /// data to provider channels.
    /// Also returns westMappings: base primaryID → [west/pacific primaryIDs]
    /// for channels that should get the same data with a +3h time offset.
    nonisolated static func fromExternalEPG<C: EPGChannelIdentity>(
        xmltvChannels: XMLTVChannelIndex,
        identities: [C]
    ) -> (catalog: EPGChannelCatalog, westMappings: [String: [String]]) {
        var known = Set<String>()
        var map: [String: String] = [:]

        // Build normalized name -> primaryEPGChannelId lookup from playlist streams
        var primaryByNormalizedName: [String: String] = [:]
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            let normalized = EPGNameNormalizer.normalize(identity.name)
            if normalized.count >= 3 {
                primaryByNormalizedName[normalized] = primary
            }
        }

        // For each external EPG channel, try to match its display-name to a playlist stream
        for (xmltvID, displayNames) in xmltvChannels.idToDisplayNames {
            for displayName in displayNames {
                let normalized = EPGNameNormalizer.normalize(displayName)
                guard normalized.count >= 3 else { continue }
                if let primary = primaryByNormalizedName[normalized] {
                    known.insert(xmltvID)
                    map[xmltvID] = primary
                    let lower = xmltvID.lowercased()
                    known.insert(lower)
                    map[lower] = primary
                    break
                }
                if let match = primaryByNormalizedName.first(where: {
                    EPGNameNormalizer.namesMatch($0.key, normalized)
                }) {
                    known.insert(xmltvID)
                    map[xmltvID] = match.value
                    let lower = xmltvID.lowercased()
                    known.insert(lower)
                    map[lower] = match.value
                    break
                }
            }
        }

        // Build west/pacific offset mappings for a +3h insert pass.
        //
        // SAFETY: match on the provider-issued `epgChannelId`, not the playlist
        // display name. Names collapse local affiliates that share a network
        // prefix (e.g. every "CBS ..." stream normalises to something starting
        // with "cbs"), which pairs unrelated stations. Provider IDs are stable
        // and follow a "<base><west|pacific>.<tld>" convention when they really
        // are shifted variants ("hbowest.us" ↔ "hbo.us"). We require:
        //   1. Playlist stream name contains "west" or "pacific" (cheap filter).
        //   2. `epgChannelId` (minus TLD) contains a `west`/`pacific` token.
        //   3. Stripping that token from the west ID yields the exact
        //      `epgChannelId` (minus TLD) of a matched East channel.
        // This correctly accepts "hbowest.us" ↔ "hbo.us" and rejects
        // "mtv2west.us" ↔ "mtv.us" ("mtv2" ≠ "mtv") and any pairing whose IDs
        // don't share the "<base>west" structure.
        var westMappings: [String: [String]] = [:]
        let matchedPrimaries = Set(map.values)
        for identity in identities {
            let primary = identity.primaryEPGChannelId
            guard !matchedPrimaries.contains(primary) else { continue }
            let nameLower = identity.name.lowercased()
            guard nameLower.contains("west") || nameLower.contains("pacific") else { continue }
            guard let westEPGID = identity.epgChannelId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !westEPGID.isEmpty else { continue }
            let westCore = Self.stripTLD(westEPGID.lowercased())
            let westStripped = westCore.replacingOccurrences(
                of: #"(west|pacific)"#, with: "", options: .regularExpression
            )
            // Reject when the ID has no "west"/"pacific" token — the name flag
            // alone is not enough (e.g. "KOVR West" has a geographic "West" but
            // the provider-issued ID is a specific station code, not a shifted
            // variant of any other channel).
            guard westStripped != westCore, !westStripped.isEmpty else { continue }

            let basePrimary = identities.first { other -> Bool in
                guard other.primaryEPGChannelId != primary else { return false }
                guard matchedPrimaries.contains(other.primaryEPGChannelId) else { return false }
                guard let baseEPGID = other.epgChannelId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !baseEPGID.isEmpty else { return false }
                return Self.stripTLD(baseEPGID.lowercased()) == westStripped
            }?.primaryEPGChannelId

            if let basePrimary {
                westMappings[basePrimary, default: []].append(primary)
            }
        }

        return (EPGChannelCatalog(knownIDs: known, normalize: map), westMappings)
    }

    nonisolated private static func stripTLD(_ id: String) -> String {
        id.replacingOccurrences(of: #"\.[a-z]{2,4}$"#, with: "", options: .regularExpression)
    }
}

enum EPGNameNormalizer {
    nonisolated static func normalize(_ name: String) -> String {
        var trimmed = name
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        // Strip prefix before ":" (e.g. "4K : HBO Drama" → "HBO Drama")
        if let colon = trimmed.firstIndex(of: ":"), colon != trimmed.startIndex {
            trimmed = String(trimmed[trimmed.index(after: colon)...])
        }
        // Strip prefix before "|" (e.g. "USA | HBO Drama" → "HBO Drama")
        if let pipe = trimmed.firstIndex(of: "|"), pipe != trimmed.startIndex {
            trimmed = String(trimmed[trimmed.index(after: pipe)...])
        }
        // Remove common quality / country tokens that differ between sources.
        // Country codes double as XMLTV TLD suffixes (`.us`, `.uk`, ...) — the
        // trailing `\b` matches after the `.` since it's a non-word char.
        //
        // Region words (`east`, `central`, `mountain`, `atlantic`) are
        // intentionally NOT stripped: they mark distinct local feeds with
        // distinct schedules, and collapsing them causes local affiliates
        // ("ABC WSB Atlanta" vs "ABC KTRK Houston") to share a normalised key
        // and pair up incorrectly in the West/Pacific offset pass. The
        // East-feed matching case is instead handled by the fuzzy
        // `namesMatch` substring check and by epgshare01 usually publishing
        // both "HBO" and "HBO East" as separate `<display-name>` entries on
        // the same channel row.
        let stripped = trimmed
            .replacingOccurrences(of: #"\b(hd|fhd|uhd|4k|sd|hevc|h265|h\.265)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(us|usa|uk|gb|ca|au|nz|ie|de|fr|es|it|nl|pt|br|mx|ar|in|ph|tr|pl|ro|se|no|dk|fi)\b"#, with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    nonisolated static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        guard left.count >= 3, right.count >= 3 else { return left == right }
        return left == right || left.contains(right) || right.contains(left)
    }
}
