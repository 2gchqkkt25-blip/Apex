import Foundation

// MARK: - Server & User Info

struct XtreamAuthResponse: Decodable {
    let userInfo: XtreamUserInfo
    let serverInfo: XtreamServerInfo

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

struct XtreamUserInfo: Decodable {
    let username: String?
    let status: String?
    let expDate: String?
    let isTrial: String?
    let activeCons: String?
    let maxConnections: String?

    enum CodingKeys: String, CodingKey {
        case username, status
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
    }
}

struct XtreamServerInfo: Decodable {
    let url: String?
    let port: String?
    let httpsPort: String?
    let serverProtocol: String?
    let timezone: String?
    let timestampNow: Int?
    let timeNow: String?

    enum CodingKeys: String, CodingKey {
        case url, port, timezone
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
        case timestampNow = "timestamp_now"
        case timeNow = "time_now"
    }
}

// MARK: - Categories

struct XtreamCategory: Decodable {
    let categoryId: String
    let categoryName: String
    let parentId: Int?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }
}

// MARK: - Live Streams

struct XtreamLiveStream: Decodable {
    let num: Int?
    let name: String?
    let streamType: String?
    let streamId: Int?
    let streamIcon: String?
    let epgChannelId: String?
    let added: String?
    let isAdult: Int?
    let categoryId: String?
    let customSid: String?
    let tvArchive: Int?
    let tvArchiveDuration: Int?

    enum CodingKeys: String, CodingKey {
        case num, name
        case streamType = "stream_type"
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case added
        case isAdult = "is_adult"
        case categoryId = "category_id"
        case customSid = "custom_sid"
        case tvArchive = "tv_archive"
        case tvArchiveDuration = "tv_archive_duration"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        num = try? container.decodeIfPresent(Int.self, forKey: .num)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        streamType = try? container.decodeIfPresent(String.self, forKey: .streamType)
        streamId = try? container.decodeIfPresent(Int.self, forKey: .streamId)
        streamIcon = try? container.decodeIfPresent(String.self, forKey: .streamIcon)
        if let epgStr = try? container.decodeIfPresent(String.self, forKey: .epgChannelId) {
            epgChannelId = epgStr
        } else if let epgInt = try? container.decodeIfPresent(Int.self, forKey: .epgChannelId) {
            epgChannelId = String(epgInt)
        } else {
            epgChannelId = nil
        }
        added = try? container.decodeIfPresent(String.self, forKey: .added)

        if let isAdultInt = try? container.decodeIfPresent(Int.self, forKey: .isAdult) {
            isAdult = isAdultInt
        } else if let isAdultString = try? container.decodeIfPresent(String.self, forKey: .isAdult) {
            isAdult = Int(isAdultString)
        } else {
            isAdult = 0
        }

        if let catIdStr = try? container.decodeIfPresent(String.self, forKey: .categoryId) {
            categoryId = catIdStr
        } else if let catIdInt = try? container.decodeIfPresent(Int.self, forKey: .categoryId) {
            categoryId = String(catIdInt)
        } else {
            categoryId = nil
        }

        customSid = try? container.decodeIfPresent(String.self, forKey: .customSid)

        if let tvArchInt = try? container.decodeIfPresent(Int.self, forKey: .tvArchive) {
            tvArchive = tvArchInt
        } else if let tvArchStr = try? container.decodeIfPresent(String.self, forKey: .tvArchive) {
            tvArchive = Int(tvArchStr)
        } else {
            tvArchive = 0
        }

        if let tvArchDurInt = try? container.decodeIfPresent(Int.self, forKey: .tvArchiveDuration) {
            tvArchiveDuration = tvArchDurInt
        } else if let tvArchDurStr = try? container.decodeIfPresent(String.self, forKey: .tvArchiveDuration) {
            tvArchiveDuration = Int(tvArchDurStr)
        } else {
            tvArchiveDuration = 0
        }
    }
}

// MARK: - VOD Streams

struct XtreamVODStream: Decodable {
    let num: Int?
    let name: String?
    let streamType: String?
    let streamId: Int?
    let streamIcon: String?
    let rating: Double?
    let rating5Based: Double?
    let added: String?
    let isAdult: Int?
    let categoryId: String?
    let containerExtension: String?
    let tmdb: String?

    enum CodingKeys: String, CodingKey {
        case num, name
        case streamType = "stream_type"
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case rating
        case rating5Based = "rating_5based"
        case added
        case isAdult = "is_adult"
        case categoryId = "category_id"
        case containerExtension = "container_extension"
        case tmdb
        case tmdbId = "tmdb_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        num = try? container.decodeIfPresent(Int.self, forKey: .num)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        streamType = try? container.decodeIfPresent(String.self, forKey: .streamType)
        streamId = try? container.decodeIfPresent(Int.self, forKey: .streamId)
        streamIcon = try? container.decodeIfPresent(String.self, forKey: .streamIcon)
        rating = Self.decodeDouble(from: container, forKey: .rating) ?? 0
        rating5Based = Self.decodeDouble(from: container, forKey: .rating5Based) ?? 0
        added = try? container.decodeIfPresent(String.self, forKey: .added)
        isAdult = Self.decodeInt(from: container, forKey: .isAdult) ?? 0
        categoryId = Self.decodeCategoryID(from: container, forKey: .categoryId)
        containerExtension = try? container.decodeIfPresent(String.self, forKey: .containerExtension)
        tmdb = Self.decodeTMDB(from: container)
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        } else if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(str)
        }
        return nil
    }

    private static func decodeInt(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        } else if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(str)
        }
        return nil
    }

    private static func decodeCategoryID(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            return str
        } else if let int = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(int)
        }
        return nil
    }

    private static func decodeTMDB(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let str = try? container.decodeIfPresent(String.self, forKey: .tmdb) {
            return str
        } else if let int = try? container.decodeIfPresent(Int.self, forKey: .tmdb) {
            return String(int)
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .tmdbId) {
            return str
        } else if let int = try? container.decodeIfPresent(Int.self, forKey: .tmdbId) {
            return String(int)
        }
        return nil
    }
}

// MARK: - VOD Info

struct XtreamVODInfo: Decodable {
    let info: XtreamVODMetadata?
    let movieData: XtreamVODStreamData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
}

struct XtreamVODMetadata: Decodable {
    let tmdbId: String?
    let name: String?
    let movieImage: String?
    let releaseDate: String?
    let durationSecs: Int?
    let youtubeTrailer: String?
    let director: String?
    let actors: String?
    let description: String?
    let plot: String?
    let genre: String?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case name
        case movieImage = "movie_image"
        case releaseDate = "releasedate"
        case durationSecs = "duration_secs"
        case youtubeTrailer = "youtube_trailer"
        case director, actors, description, plot, genre
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        movieImage = try? container.decodeIfPresent(String.self, forKey: .movieImage)
        releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
        youtubeTrailer = try? container.decodeIfPresent(String.self, forKey: .youtubeTrailer)
        director = try? container.decodeIfPresent(String.self, forKey: .director)
        actors = try? container.decodeIfPresent(String.self, forKey: .actors)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        plot = try? container.decodeIfPresent(String.self, forKey: .plot)
        genre = try? container.decodeIfPresent(String.self, forKey: .genre)

        if let tmdbStr = try? container.decodeIfPresent(String.self, forKey: .tmdbId) {
            tmdbId = tmdbStr
        } else if let tmdbInt = try? container.decodeIfPresent(Int.self, forKey: .tmdbId) {
            tmdbId = String(tmdbInt)
        } else {
            tmdbId = nil
        }

        if let durInt = try? container.decodeIfPresent(Int.self, forKey: .durationSecs) {
            durationSecs = durInt
        } else if let durStr = try? container.decodeIfPresent(String.self, forKey: .durationSecs) {
            durationSecs = Int(durStr)
        } else {
            durationSecs = nil
        }
    }
}

struct XtreamVODStreamData: Decodable {
    let streamId: Int?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case containerExtension = "container_extension"
    }
}

// MARK: - Series

struct XtreamSeries: Decodable {
    let num: Int?
    let name: String?
    let seriesId: Int?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let lastModified: String?
    let rating: String?
    let rating5Based: String?
    let categoryId: String?
    let tmdb: String?

    enum CodingKeys: String, CodingKey {
        case num, name
        case seriesId = "series_id"
        case cover, plot, cast, director, genre
        case releaseDate
        case lastModified = "last_modified"
        case rating
        case rating5Based = "rating_5based"
        case categoryId = "category_id"
        case tmdb
        case tmdbId = "tmdb_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        num = try? container.decodeIfPresent(Int.self, forKey: .num)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        seriesId = try? container.decodeIfPresent(Int.self, forKey: .seriesId)
        cover = try? container.decodeIfPresent(String.self, forKey: .cover)
        plot = try? container.decodeIfPresent(String.self, forKey: .plot)
        cast = try? container.decodeIfPresent(String.self, forKey: .cast)
        director = try? container.decodeIfPresent(String.self, forKey: .director)
        genre = try? container.decodeIfPresent(String.self, forKey: .genre)
        releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
        lastModified = try? container.decodeIfPresent(String.self, forKey: .lastModified)
        rating = try? container.decodeIfPresent(String.self, forKey: .rating)
        rating5Based = try? container.decodeIfPresent(String.self, forKey: .rating5Based)

        if let catIdStr = try? container.decodeIfPresent(String.self, forKey: .categoryId) {
            categoryId = catIdStr
        } else if let catIdInt = try? container.decodeIfPresent(Int.self, forKey: .categoryId) {
            categoryId = String(catIdInt)
        } else {
            categoryId = nil
        }

        // Some playlists use "tmdb", others "tmdb_id"; accept either as String or Int.
        if let tmdbStr = try? container.decodeIfPresent(String.self, forKey: .tmdb) {
            tmdb = tmdbStr
        } else if let tmdbInt = try? container.decodeIfPresent(Int.self, forKey: .tmdb) {
            tmdb = String(tmdbInt)
        } else if let tmdbStr = try? container.decodeIfPresent(String.self, forKey: .tmdbId) {
            tmdb = tmdbStr
        } else if let tmdbInt = try? container.decodeIfPresent(Int.self, forKey: .tmdbId) {
            tmdb = String(tmdbInt)
        } else {
            tmdb = nil
        }
    }
}

// MARK: - Series Info

struct XtreamSeriesInfoResponse: Decodable {
    let info: XtreamSeriesInfo?
    let episodes: [String: [XtreamEpisode]]?
}

struct XtreamSeriesInfo: Decodable {
    let name: String?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let lastModified: String?
    let rating: String?
    let tmdb: String?

    enum CodingKeys: String, CodingKey {
        case name, cover, plot, cast, director, genre
        case releaseDate
        case lastModified = "last_modified"
        case rating, tmdb
    }
}

struct XtreamEpisode: Decodable {
    let id: String?
    let episodeNum: Int?
    let title: String?
    let containerExtension: String?
    let customSid: String?
    let added: String?
    let season: Int?
    let directSource: String?
    let info: XtreamEpisodeInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case customSid = "custom_sid"
        case added, season
        case directSource = "direct_source"
        case info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeNum = try? container.decodeIfPresent(Int.self, forKey: .episodeNum)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        containerExtension = try? container.decodeIfPresent(String.self, forKey: .containerExtension)
        customSid = try? container.decodeIfPresent(String.self, forKey: .customSid)
        added = try? container.decodeIfPresent(String.self, forKey: .added)

        if let sInt = try? container.decodeIfPresent(Int.self, forKey: .season) {
            season = sInt
        } else if let sStr = try? container.decodeIfPresent(String.self, forKey: .season) {
            season = Int(sStr)
        } else {
            season = nil
        }

        directSource = try? container.decodeIfPresent(String.self, forKey: .directSource)
        info = try? container.decodeIfPresent(XtreamEpisodeInfo.self, forKey: .info)

        if let idStr = try? container.decodeIfPresent(String.self, forKey: .id) {
            id = idStr
        } else if let idInt = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = nil
        }
    }
}

struct XtreamEpisodeInfo: Decodable {
    let airDate: String?
    let movieImage: String?
    let durationSecs: Int?
    let rating: Double?
    let plot: String?

    enum CodingKeys: String, CodingKey {
        case airDate = "air_date"
        case releaseDate
        case movieImage = "movie_image"
        case durationSecs = "duration_secs"
        case rating
        case plot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let adStr = try? container.decodeIfPresent(String.self, forKey: .airDate) {
            airDate = adStr
        } else if let rdStr = try? container.decodeIfPresent(String.self, forKey: .releaseDate) {
            airDate = rdStr
        } else {
            airDate = nil
        }

        movieImage = try? container.decodeIfPresent(String.self, forKey: .movieImage)
        plot = try? container.decodeIfPresent(String.self, forKey: .plot)

        if let rDouble = try? container.decodeIfPresent(Double.self, forKey: .rating) {
            rating = rDouble
        } else if let rString = try? container.decodeIfPresent(String.self, forKey: .rating) {
            rating = Double(rString)
        } else {
            rating = nil
        }

        if let durInt = try? container.decodeIfPresent(Int.self, forKey: .durationSecs) {
            durationSecs = durInt
        } else if let durStr = try? container.decodeIfPresent(String.self, forKey: .durationSecs) {
            durationSecs = Int(durStr)
        } else {
            durationSecs = nil
        }
    }
}

// MARK: - EPG text helpers

/// Xtream panels often base64-encode programme titles and use unix timestamps.
enum XtreamEPGText {
    nonisolated static func decode(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let data = Data(base64Encoded: trimmed),
           let decoded = String(data: data, encoding: .utf8),
           !decoded.isEmpty
        {
            return decoded
        }
        return trimmed
    }

    /// Parses Xtream EPG time fields. Panels emit any of:
    /// - unix seconds (`"1751569200"` / `1751569200`)
    /// - unix milliseconds (`"1751569200000"`)
    /// - SQL wall clock (`"2026-07-03 15:00:00"`)
    /// - XMLTV compact (`"20260703150000"`) — must NOT be treated as unix
    nonisolated static func parseTimestamp(_ value: String?, timezoneIdentifier: String? = nil) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let zone = wallClockZone(timezoneIdentifier)

        // Digits-only: distinguish unix seconds / millis from XMLTV `YYYYMMDDHHMMSS`.
        if trimmed.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) {
            if trimmed.count == 14 {
                return XMLTVDate.parseEPG(trimmed, timezone: zone)
            }
            if let interval = TimeInterval(trimmed) {
                // Milliseconds (13 digits around now).
                if trimmed.count >= 12 {
                    return Date(timeIntervalSince1970: interval / 1000)
                }
                // Seconds since ~2001 (9–11 digits). Reject tiny numbers.
                if interval > 1_000_000_000 {
                    return Date(timeIntervalSince1970: interval)
                }
            }
        }

        if let sql = parseWallClock(trimmed, timezone: zone) {
            return sql
        }

        // ISO-8601 fallback (`2026-07-03T15:00:00Z`, `2026-07-03T15:00:00+00:00`).
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        // Last resort: XMLTV with optional ` +0000` suffix.
        return XMLTVDate.parseEPG(trimmed, timezone: zone)
    }

    /// Wall-clock zone for SQL / XMLTV digits. Xtream often reports `GMT` while
    /// stamping local wall-clock times — prefer the device zone in that case.
    nonisolated private static func wallClockZone(_ timezoneIdentifier: String?) -> TimeZone {
        let server = timezoneIdentifier.flatMap { TimeZone(identifier: $0) }
            ?? timezoneIdentifier.flatMap { XMLTVDate.timezone(from: $0) }
        return XMLTVDate.resolveWallClockTimezone(server: server, detected: nil)
    }

    /// Picks the `(start, end)` pair that best matches "now"
    /// conflicting `start`/`end` wall clock and `start_timestamp`/`stop_timestamp`
    /// unix fields (common when the bulk EPG DB is stale but short EPG is live).
    nonisolated static func pickBestProgrammeInterval(
        _ candidates: [(start: Date, end: Date)],
        now: Date,
        nowPlaying: Bool = false
    ) -> (start: Date, end: Date)? {
        guard !candidates.isEmpty else { return nil }

        var unique: [(start: Date, end: Date)] = []
        unique.reserveCapacity(candidates.count)
        for candidate in candidates where candidate.end > candidate.start {
            if unique.contains(where: {
                abs($0.start.timeIntervalSince(candidate.start)) < 1
                    && abs($0.end.timeIntervalSince(candidate.end)) < 1
            }) { continue }
            unique.append(candidate)
        }
        guard !unique.isEmpty else { return nil }

        if nowPlaying {
            let basis = unique.min(by: {
                abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now))
            })!
            var start = basis.start
            var end = basis.end
            if start > now { start = now }
            if end <= now { end = max(now.addingTimeInterval(60), start.addingTimeInterval(30 * 60)) }
            return (start, end)
        }

        if let airing = unique.first(where: { $0.start <= now && now < $0.end }) {
            return airing
        }
        let relevant = unique.filter { $0.end > now.addingTimeInterval(-EPGRetention.pastGrace) }
        if !relevant.isEmpty {
            if let upcoming = relevant.filter({ $0.start >= now }).min(by: { $0.start < $1.start }) {
                return upcoming
            }
            return relevant.max(by: { $0.end < $1.end })
        }
        return unique.min(by: {
            abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now))
        })
    }

    private nonisolated static func parseWallClock(_ value: String, timezone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        if let date = formatter.date(from: value) { return date }
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

// MARK: - EPG

struct XtreamShortEPG: Decodable {
    let start: String?
    let end: String?
    let stop: String?
    let startTimestamp: String?
    let endTimestamp: String?
    let stopTimestamp: String?
    let title: String?
    let description: String?
    /// `1` when the panel marks this row as the live slot (`now_playing`).
    let nowPlaying: Bool?

    enum CodingKeys: String, CodingKey {
        case start, end, stop, title, description
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case stopTimestamp = "stop_timestamp"
        case nowPlaying = "now_playing"
    }

    init(
        start: String? = nil,
        end: String? = nil,
        stop: String? = nil,
        startTimestamp: String? = nil,
        endTimestamp: String? = nil,
        stopTimestamp: String? = nil,
        title: String? = nil,
        description: String? = nil,
        nowPlaying: Bool? = nil
    ) {
        self.start = start
        self.end = end
        self.stop = stop
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.stopTimestamp = stopTimestamp
        self.title = title
        self.description = description
        self.nowPlaying = nowPlaying
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = Self.flexString(container, key: .start)
        end = Self.flexString(container, key: .end)
        stop = Self.flexString(container, key: .stop)
        startTimestamp = Self.flexString(container, key: .startTimestamp)
        endTimestamp = Self.flexString(container, key: .endTimestamp)
        stopTimestamp = Self.flexString(container, key: .stopTimestamp)
        title = Self.flexString(container, key: .title)
        description = Self.flexString(container, key: .description)
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .nowPlaying) {
            nowPlaying = flag
        } else if let intFlag = try? container.decodeIfPresent(Int.self, forKey: .nowPlaying) {
            nowPlaying = intFlag != 0
        } else {
            nowPlaying = nil
        }
    }

    private static func flexString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return String(Int(value)) }
        return nil
    }

    nonisolated var decodedTitle: String {
        XtreamEPGText.decode(title)
    }

    nonisolated var decodedDescription: String {
        XtreamEPGText.decode(description)
    }

    nonisolated func startDate(timezoneIdentifier: String?) -> Date? {
        programmeTimes(timezoneIdentifier: timezoneIdentifier)?.start
    }

    nonisolated func endDate(timezoneIdentifier: String?) -> Date? {
        programmeTimes(timezoneIdentifier: timezoneIdentifier)?.end
    }

    /// Resolves start/end from the available timestamp fields.
    ///
    /// Priority order (same as Chilli, SwipTV, TiviMate):
    /// 1. Unix `start_timestamp`/`stop_timestamp` — if within 48h of now (current data)
    /// 2. SQL wall-clock `start`/`end`/`stop` — interpreted in the server timezone
    /// 3. Unix timestamps even if stale — still better than nothing
    ///
    /// When `now_playing` is true, the programme is on air regardless of timestamps.
    nonisolated func programmeTimes(
        timezoneIdentifier: String?,
        now: Date = Date()
    ) -> (start: Date, end: Date)? {
        // Parse unix pair.
        let endTimestampRaw = endTimestamp ?? stopTimestamp
        let unixStart = XtreamEPGText.parseTimestamp(startTimestamp)
        let unixEnd = XtreamEPGText.parseTimestamp(endTimestampRaw)
        let unixPair: (start: Date, end: Date)? = {
            guard let s = unixStart, let e = unixEnd, e > s else { return nil }
            return (s, e)
        }()

        // Parse wall-clock pair.
        let endRaw = end ?? stop
        let wallStart = XtreamEPGText.parseTimestamp(start, timezoneIdentifier: timezoneIdentifier)
        let wallEnd = XtreamEPGText.parseTimestamp(endRaw, timezoneIdentifier: timezoneIdentifier)
        let wallPair: (start: Date, end: Date)? = {
            guard let s = wallStart, let e = wallEnd, e > s else { return nil }
            return (s, e)
        }()

        // now_playing: trust whatever we have, prefer the one overlapping now.
        if nowPlaying == true {
            if let wall = wallPair, wall.start <= now && now < wall.end {
                return wall
            }
            if let unix = unixPair, unix.start <= now && now < unix.end {
                return unix
            }
            // Neither overlaps now — stretch the closest one to cover now.
            let basis = wallPair ?? unixPair
            if let basis {
                let adjustedStart = min(basis.start, now)
                let adjustedEnd = max(basis.end, now.addingTimeInterval(60))
                return (adjustedStart, adjustedEnd)
            }
            return nil
        }

        // Both available — pick the one closer to now (handles stale unix + live wall-clock).
        if let unix = unixPair, let wall = wallPair {
            let unixDistToNow = min(abs(unix.start.timeIntervalSince(now)), abs(unix.end.timeIntervalSince(now)))
            let wallDistToNow = min(abs(wall.start.timeIntervalSince(now)), abs(wall.end.timeIntervalSince(now)))

            // If one overlaps now and the other doesn't, prefer the live one.
            let unixLive = unix.start <= now && now < unix.end
            let wallLive = wall.start <= now && now < wall.end
            if unixLive && !wallLive { return unix }
            if wallLive && !unixLive { return wall }

            // Both or neither live — prefer the one closest to now.
            return wallDistToNow < unixDistToNow ? wall : unix
        }

        // Only one available — use it.
        if let unix = unixPair { return unix }
        if let wall = wallPair { return wall }

        // Mixed: unix start + wall-clock end (rare but seen on some panels).
        if let s = unixStart, let e = wallEnd, e > s { return (s, e) }

        return nil
    }
}

// MARK: - Bulk EPG (get_simple_data_table)

struct XtreamDataTableEPG: Decodable {
    let epgId: String?
    let title: String?
    let description: String?
    let startTimestamp: String?
    let endTimestamp: String?
    let start: String?
    let end: String?
    let channelId: String?
    let streamId: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case epgId = "epg_id"
        case title, description
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case start, end
        case channelId = "channel_id"
        case streamId = "stream_id"
        case id
    }

    var decodedTitle: String { XtreamEPGText.decode(title) }
    var decodedDescription: String { XtreamEPGText.decode(description) }

    var startDate: Date? {
        XtreamEPGText.parseTimestamp(startTimestamp)
            ?? XtreamEPGText.parseTimestamp(start)
    }

    var endDate: Date? {
        XtreamEPGText.parseTimestamp(endTimestamp)
            ?? XtreamEPGText.parseTimestamp(end)
    }

    func startDate(timezoneIdentifier: String?) -> Date? {
        XtreamEPGText.parseTimestamp(startTimestamp)
            ?? XtreamEPGText.parseTimestamp(start, timezoneIdentifier: timezoneIdentifier)
    }

    func endDate(timezoneIdentifier: String?) -> Date? {
        XtreamEPGText.parseTimestamp(endTimestamp)
            ?? XtreamEPGText.parseTimestamp(end, timezoneIdentifier: timezoneIdentifier)
    }
}
