import Foundation

enum ExternalEPGSources {
    /// Known-good external EPG sources with current schedule data.
    /// These are tried as primary sources when a provider's own xmltv.php is stale.
    ///
    /// Coverage rationale:
    /// - US1/US2: national cable + satellite channels
    /// - US_LOCALS1-4: broadcast affiliates (ABC/NBC/CBS/FOX/CW/etc.) — biggest
    ///   source of West/Pacific callsigns (KABC, KNBC, KTLA, KTVU, ...)
    /// - US_SPORTS1: ESPN family, RSNs, league networks
    /// - US_MOVIES1: HBO/Showtime/Starz/premium movie tiers
    /// - UK1/UK2: UK terrestrial + Sky
    /// - CA1/CA2: Canadian broadcast + specialty
    /// - IE1: Irish channels (RTE, Virgin Media)
    /// - AU1: Australian free-to-air + Foxtel
    ///
    /// Missing sources are logged as warnings and skipped — safe to include
    /// URLs that may not exist for a given provider's channel lineup.
    /// Ordered for sync: national + specialty feeds first so the guide fills in
    /// quickly; US_LOCALS1 is last — it is ~500MB+ with low match yield.
    static let sources: [(name: String, url: String, region: String)] = [
        ("US National 2", "https://epgshare01.online/epgshare01/epg_ripper_US2.xml.gz", "US"),
        ("US National 1", "https://epgshare01.online/epgshare01/epg_ripper_US1.xml.gz", "US"),
        ("US Sports", "https://epgshare01.online/epgshare01/epg_ripper_US_SPORTS1.xml.gz", "US"),
        ("US Movies", "https://epgshare01.online/epgshare01/epg_ripper_US_MOVIES1.xml.gz", "US"),
        ("US Locals 2", "https://epgshare01.online/epgshare01/epg_ripper_US_LOCALS2.xml.gz", "US"),
        ("US Locals 3", "https://epgshare01.online/epgshare01/epg_ripper_US_LOCALS3.xml.gz", "US"),
        ("US Locals 4", "https://epgshare01.online/epgshare01/epg_ripper_US_LOCALS4.xml.gz", "US"),
        ("US Locals 1", "https://epgshare01.online/epgshare01/epg_ripper_US_LOCALS1.xml.gz", "US"),
        ("UK 1", "https://epgshare01.online/epgshare01/epg_ripper_UK1.xml.gz", "UK"),
        ("UK 2", "https://epgshare01.online/epgshare01/epg_ripper_UK2.xml.gz", "UK"),
        ("Canada 1", "https://epgshare01.online/epgshare01/epg_ripper_CA1.xml.gz", "CA"),
        ("Canada 2", "https://epgshare01.online/epgshare01/epg_ripper_CA2.xml.gz", "CA"),
        ("Ireland", "https://epgshare01.online/epgshare01/epg_ripper_IE1.xml.gz", "IE"),
        ("Australia", "https://epgshare01.online/epgshare01/epg_ripper_AU1.xml.gz", "AU"),
    ]

    /// Combined source covering all regions (large file, ~50MB+)
    static let allSourcesURL = "https://epgshare01.online/epgshare01/epg_ripper_ALL_SOURCES1.xml.gz"

    /// Full 14-feed pass (Settings → Sync Now, background refresh).
    static func urlsForFullSync() -> [String] {
        sources.map(\.url)
    }

    /// US feeds only — used during playlist refresh to avoid 6 international
    /// downloads that rarely match a US-centric lineup. Excludes the heavy
    /// ~500MB `US_LOCALS1` feed: it must never download on the routine playlist
    /// path (it drove memory warnings even on iPhone). Full Settings → Sync Now
    /// still includes it where appropriate.
    static func urlsForBundledSync() -> [String] {
        sources
            .filter { $0.region == "US" && !isHeavyLowYieldSource(url: $0.url) }
            .map(\.url)
    }

    /// tvOS inline sync during playlist refresh — only the 3 lightest feeds that
    /// cover the most popular channels (~30MB total vs ~200MB for full bundled).
    /// US National 1 (~20MB) covers most cable/satellite. US Sports (~8MB) covers
    /// ESPN family and RSNs. US Movies (~5MB) covers HBO/Showtime/Starz.
    /// Small enough to parse inside the sync sheet without jetsam risk.
    static func urlsForTVOSQuickSync() -> [String] {
        let quickFeedNames = Set(["US National 1", "US Sports", "US Movies"])
        return sources
            .filter { quickFeedNames.contains($0.name) }
            .map(\.url)
    }

    /// Returns appropriate external EPG URLs based on sync mode.
    static func urlsForPlaylist(channelNames: [String], bundled: Bool = false, mode: EPGSyncMode = .full) -> [String] {
        switch mode {
        case .tvOSQuick: return urlsForTVOSQuickSync()
        case .withPlaylist: return urlsForBundledSync()
        case .full: return urlsForFullSync()
        }
    }

    /// Very large file with low incremental match yield — safe to skip once
    /// national/sports/movies feeds already cover most of the playlist.
    static func isHeavyLowYieldSource(url: String) -> Bool {
        url.contains("US_LOCALS1")
    }
}
