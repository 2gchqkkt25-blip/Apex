//
//  MediaServerDTOs.swift
//  Apex
//
//  Shared DTOs for Jellyfin / Emby (Emby-compatible API).
//

import Foundation

nonisolated struct MediaServerAuthResult: Sendable {
    let accessToken: String
    let userId: String
    let serverName: String?
}

nonisolated struct MediaServerLibrary: Sendable, Identifiable {
    let id: String
    let name: String
    let collectionType: String?
}

nonisolated struct MediaServerItemsPage: Sendable {
    let items: [MediaServerItem]
    let totalCount: Int?
}

nonisolated struct MediaServerItem: Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let overview: String?
    let imageTag: String?
    let backdropTag: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let parentBackdropItemId: String?
    let seriesId: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let userData: MediaServerUserData?
    let genres: [String]
    let people: [MediaServerPerson]
    /// TMDB id from Plex/Jellyfin provider metadata when available.
    let providerTMDBId: Int?
    /// IMDb id (e.g. `tt0111161`) from provider metadata when available.
    let providerIMDBId: String?
}

nonisolated struct MediaServerUserData: Sendable {
    let played: Bool
    let playCount: Int
    let playbackPositionTicks: Int64
    let lastPlayedDate: Date?
}

nonisolated struct MediaServerPerson: Sendable {
    let name: String
    let role: String?
    let imageTag: String?
}

nonisolated enum MediaServerPlaybackMethod: String, Sendable, Codable {
    case directPlay
    case directStream
    case transcode
}

nonisolated struct MediaServerStreamInfo: Sendable {
    let url: URL
    let method: MediaServerPlaybackMethod
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let videoBitrate: Int?
    /// Version name from the server, such as an AIOStreams addon result.
    let label: String?
    /// Jellyfin `MediaSource.Id`. Versions of one item share nothing else.
    let sourceID: String?
    /// Audio tracks in file order, used to prefer the chosen language.
    let audioTracks: [MediaServerAudioHint]
    /// Languages, size, and addon details for the version picker.
    let meta: StreamVersionMeta

    init(
        url: URL,
        method: MediaServerPlaybackMethod,
        container: String?,
        videoCodec: String?,
        audioCodec: String?,
        width: Int?,
        height: Int?,
        frameRate: Double?,
        videoBitrate: Int?,
        label: String? = nil,
        sourceID: String? = nil,
        audioTracks: [MediaServerAudioHint] = [],
        meta: StreamVersionMeta = StreamVersionMeta()
    ) {
        self.url = url
        self.method = method
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoBitrate = videoBitrate
        self.label = label
        self.sourceID = sourceID
        self.audioTracks = audioTracks
        self.meta = meta
    }
}

/// What the version picker shows under a stream's name.
nonisolated struct StreamVersionMeta: Sendable {
    var languages: [String] = []
    var resolution: String?
    var byteSize: Int64?
    var addon: String?
    var audio: String?
    var filename: String?
    var blurb: String?

    var detailLine: String {
        var parts: [String] = []
        let spoken = languages.filter { !$0.isEmpty && $0.caseInsensitiveCompare("Unknown") != .orderedSame }
        if !spoken.isEmpty { parts.append(spoken.joined(separator: ", ")) }
        if let resolution, !resolution.isEmpty, resolution.caseInsensitiveCompare("Unknown") != .orderedSame {
            parts.append(resolution)
        }
        if let audio, !audio.isEmpty { parts.append(audio) }
        if let size = Self.formattedSize(byteSize) { parts.append(size) }
        if let addon, !addon.isEmpty { parts.append(addon) }
        if parts.isEmpty, let blurb, !blurb.isEmpty { return blurb }
        return parts.joined(separator: " · ")
    }

    private static func formattedSize(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        guard mb >= 1 else { return nil }
        return String(format: "%.0f MB", mb)
    }
}

/// Resolved stream characteristics kept on `PlayableMedia` after a media-server
/// placeholder is swapped for a real playback URL.
nonisolated struct MediaServerStreamContext: Hashable, Codable, Sendable {
    let method: MediaServerPlaybackMethod
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let videoBitrate: Int?
    /// ISO 639-1 code from Settings → Media Servers. Nil on streams resolved before the setting existed.
    let preferredAudioLanguage: String?
    /// Server-reported audio tracks, in file order.
    let audioTracks: [MediaServerAudioHint]?

    init(from stream: MediaServerStreamInfo) {
        method = stream.method
        container = stream.container
        videoCodec = stream.videoCodec
        audioCodec = stream.audioCodec
        width = stream.width
        height = stream.height
        frameRate = stream.frameRate
        videoBitrate = stream.videoBitrate
        preferredAudioLanguage = MediaServerAudioLanguage.current.rawValue
        audioTracks = stream.audioTracks
    }

    var methodBadge: String {
        switch method {
        case .directPlay: String(localized: "Direct Play")
        case .directStream: String(localized: "Direct Stream")
        case .transcode: String(localized: "Transcode")
        }
    }

    var displayVideoCodec: String? {
        Self.displayCodec(videoCodec)
    }

    /// Width-based quality bucket — matches `PlayerVideoInfo.qualityTag`.
    var qualityTag: String {
        guard let width, width > 0 else {
            if let height, height > 0 { return Self.qualityTag(forHeight: height) }
            return ""
        }
        switch width {
        case 7680...: return "8K"
        case 3840 ..< 7680: return "4K"
        case 2560 ..< 3840: return "1440p"
        case 1920 ..< 2560: return "1080p"
        case 1280 ..< 1920: return "720p"
        case 854 ..< 1280: return "480p"
        case 1 ..< 854: return "SD"
        default: return ""
        }
    }

    nonisolated static func displayCodec(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "hevc", "h265", "hvc1", "hev1": return "HEVC"
        case "h264", "avc", "avc1", "avc3": return "H.264"
        case "av1", "av01": return "AV1"
        case "vp9", "vp09": return "VP9"
        case "mpeg4", "mp4v": return "MPEG-4"
        case "mpeg2video", "mpeg2": return "MPEG-2"
        default: return raw.uppercased()
        }
    }

    private static func qualityTag(forHeight height: Int) -> String {
        switch height {
        case 2160...: return "4K"
        case 1080 ..< 2160: return "1080p"
        case 720 ..< 1080: return "720p"
        case 480 ..< 720: return "480p"
        case 1 ..< 480: return "SD"
        default: return ""
        }
    }
}

nonisolated struct MediaServerPlaybackResult: Sendable {
    let streams: [MediaServerStreamInfo]
}

// MARK: - Jellyfin JSON

nonisolated struct JellyfinAuthResponse: Decodable, Sendable {
    let accessToken: String
    let user: JellyfinUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

nonisolated struct JellyfinUser: Decodable, Sendable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

nonisolated struct JellyfinViewsResponse: Decodable, Sendable {
    let items: [JellyfinBaseItem]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

nonisolated struct JellyfinItemsResponse: Decodable, Sendable {
    let items: [JellyfinBaseItem]
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

nonisolated struct JellyfinBaseItem: Decodable, Sendable {
    let id: String
    let name: String
    let type: String
    let overview: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let parentBackdropItemId: String?
    let seriesId: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let userData: JellyfinUserData?
    let genres: [String]?
    let people: [JellyfinPerson]?
    let providerIds: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case parentBackdropItemId = "ParentBackdropItemId"
        case seriesId = "SeriesId"
        case seasonId = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case userData = "UserData"
        case genres = "Genres"
        case people = "People"
        case providerIds = "ProviderIds"
    }

    private var parsedProviderIDs: (tmdb: Int?, imdb: String?) {
        JellyfinClient.parseProviderIDs(providerIds)
    }

    func asMediaItem() -> MediaServerItem {
        var ids = parsedProviderIDs
        if ids.tmdb == nil || ids.imdb == nil {
            let packed = JellyfinClient.packedProviderIDs(itemID: id)
            if ids.tmdb == nil { ids.tmdb = packed.tmdb }
            if ids.imdb == nil { ids.imdb = packed.imdb }
        }
        return MediaServerItem(
            id: id,
            name: name,
            type: type,
            overview: overview,
            imageTag: imageTags?["Primary"],
            backdropTag: backdropImageTags?.first,
            productionYear: productionYear,
            runTimeTicks: runTimeTicks,
            parentBackdropItemId: parentBackdropItemId,
            seriesId: seriesId,
            seasonId: seasonId,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            userData: userData?.asModel(),
            genres: genres ?? [],
            people: (people ?? []).map { $0.asModel() },
            providerTMDBId: ids.tmdb,
            providerIMDBId: ids.imdb
        )
    }
}

nonisolated struct JellyfinUserData: Decodable, Sendable {
    let played: Bool
    let playCount: Int
    let playbackPositionTicks: Int64
    let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case played = "Played"
        case playCount = "PlayCount"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case lastPlayedDate = "LastPlayedDate"
    }

    func asModel() -> MediaServerUserData {
        let lastPlayed: Date? = lastPlayedDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        return MediaServerUserData(
            played: played,
            playCount: playCount,
            playbackPositionTicks: playbackPositionTicks,
            lastPlayedDate: lastPlayed
        )
    }
}

nonisolated struct JellyfinPerson: Decodable, Sendable {
    let name: String
    let role: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case role = "Role"
        case primaryImageTag = "PrimaryImageTag"
    }

    func asModel() -> MediaServerPerson {
        MediaServerPerson(name: name, role: role, imageTag: primaryImageTag)
    }
}

nonisolated struct JellyfinPlaybackInfoResponse: Decodable, Sendable {
    let mediaSources: [JellyfinMediaSource]
    let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

nonisolated struct JellyfinMediaSource: Decodable, Sendable {
    let id: String
    let name: String?
    let type: String?
    let path: String?
    let container: String?
    let bitrate: Int?
    let directStreamUrl: String?
    let transcodingUrl: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let mediaStreams: [JellyfinMediaStream]?
    /// AIOStreams addon details. Absent on a normal Jellyfin file.
    let aiostreams: AiostreamsReleaseInfo?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case path = "Path"
        case container = "Container"
        case bitrate = "Bitrate"
        case directStreamUrl = "DirectStreamUrl"
        case transcodingUrl = "TranscodingUrl"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case mediaStreams = "MediaStreams"
        case aiostreams
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        path = try values.decodeIfPresent(String.self, forKey: .path)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        bitrate = try values.decodeIfPresent(Int.self, forKey: .bitrate)
        directStreamUrl = try values.decodeIfPresent(String.self, forKey: .directStreamUrl)
        transcodingUrl = try values.decodeIfPresent(String.self, forKey: .transcodingUrl)
        supportsDirectPlay = try values.decodeIfPresent(Bool.self, forKey: .supportsDirectPlay)
        supportsDirectStream = try values.decodeIfPresent(Bool.self, forKey: .supportsDirectStream)
        supportsTranscoding = try values.decodeIfPresent(Bool.self, forKey: .supportsTranscoding)
        mediaStreams = try values.decodeIfPresent([JellyfinMediaStream].self, forKey: .mediaStreams)
        // A mismatched addon payload must not drop the playable source.
        aiostreams = try? values.decodeIfPresent(AiostreamsReleaseInfo.self, forKey: .aiostreams)
    }
}

/// Addon fields AIOStreams attaches to a Jellyfin media source. Each field is
/// optional so one unexpected shape does not hide the rest of the version.
nonisolated struct AiostreamsReleaseInfo: Decodable, Sendable {
    var name: String?
    var summary: String?
    var addon: String?
    var resolution: String?
    var quality: String?
    var languages: [String]
    var audioTags: [String]
    var audioChannels: String?
    var size: Int64?
    var filename: String?

    enum CodingKeys: String, CodingKey {
        case name, summary = "description", addon, resolution, quality, languages, audioTags, audioChannels, size, filename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = Self.text(container, .name)
        summary = Self.text(container, .summary)
        addon = Self.text(container, .addon)
        resolution = Self.text(container, .resolution)
        quality = Self.text(container, .quality)
        languages = Self.texts(container, .languages)
        audioTags = Self.texts(container, .audioTags)
        audioChannels = Self.text(container, .audioChannels)
        size = Self.bytes(container, .size)
        filename = Self.text(container, .filename)
    }

    private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            let joined = values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func texts(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return []
    }

    private static func bytes(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int64(value) }
        return nil
    }
}

nonisolated struct JellyfinMediaStream: Decodable, Sendable {
    let type: String
    let codec: String?
    let width: Int?
    let height: Int?
    let bitRate: Int?
    let averageFrameRate: Double?
    let realFrameRate: Double?
    let index: Int?
    let language: String?
    let displayTitle: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
        case width = "Width"
        case height = "Height"
        case bitRate = "BitRate"
        case averageFrameRate = "AverageFrameRate"
        case realFrameRate = "RealFrameRate"
        case index = "Index"
        case language = "Language"
        case displayTitle = "DisplayTitle"
    }
}

// MARK: - Plex JSON

nonisolated struct PlexPinResponse: Decodable, Sendable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case code = "code"
        case authToken = "authToken"
    }
}

nonisolated struct PlexResource: Decodable, Sendable {
    let name: String
    let clientIdentifier: String
    let provides: String?
    let connections: [PlexConnection]

    enum CodingKeys: String, CodingKey {
        case name
        case clientIdentifier
        case provides
        case connections
    }
}

nonisolated struct PlexConnection: Decodable, Sendable {
    let uri: String
    let local: Bool
    let relay: Bool?

    enum CodingKeys: String, CodingKey {
        case uri
        case local
        case relay
    }
}

nonisolated struct PlexLibrarySections: Decodable, Sendable {
    let mediaContainer: PlexMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexMediaContainer: Decodable, Sendable {
    let directory: [PlexDirectory]?
    let metadata: [PlexMetadata]?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case directory = "Directory"
        case metadata = "Metadata"
        case size
    }
}

nonisolated struct PlexDirectory: Decodable, Sendable {
    let key: String
    let title: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case type
    }
}

nonisolated struct PlexMetadata: Decodable, Sendable {
    let ratingKey: String
    let key: String
    let title: String
    let type: String
    let summary: String?
    let thumb: String?
    let art: String?
    let year: Int?
    let duration: Int?
    let viewOffset: Int?
    let viewCount: Int?
    let lastViewedAt: Int?
    let parentIndex: Int?
    let index: Int?
    let grandparentKey: String?
    let parentKey: String?
    let guid: [PlexGuid]?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case title
        case type
        case summary
        case thumb
        case art
        case year
        case duration
        case viewOffset
        case viewCount
        case lastViewedAt
        case parentIndex
        case index
        case grandparentKey
        case parentKey
        case guid = "Guid"
        case media = "Media"
    }
}

nonisolated struct PlexGuid: Decodable, Sendable {
    let id: String
}

nonisolated struct PlexMedia: Decodable, Sendable {
    let videoCodec: String?
    let audioCodec: String?
    let videoResolution: String?
    let videoFrameRate: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let part: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case videoCodec
        case audioCodec
        case videoResolution
        case videoFrameRate
        case bitrate
        case width
        case height
        case part = "Part"
    }

    /// Plex often reports `videoResolution` (e.g. `"1080"`) instead of pixel width.
    var parsedHeight: Int? {
        if let height, height > 0 { return height }
        guard let videoResolution else { return nil }
        let lower = videoResolution.lowercased()
        if lower.contains("4k") || lower == "2160" { return 2160 }
        if lower.contains("1080") || lower == "1080" { return 1080 }
        if lower.contains("720") || lower == "720" { return 720 }
        if lower.contains("480") || lower == "480" { return 480 }
        let digits = videoResolution.filter(\.isNumber)
        if let value = Int(digits), value > 0, value <= 2160 { return value }
        return nil
    }

    var parsedWidth: Int? {
        if let width, width > 0 { return width }
        guard let height = parsedHeight else { return nil }
        return Int((Double(height) * 16.0 / 9.0).rounded())
    }

    var parsedFrameRate: Double? {
        guard let videoFrameRate else { return nil }
        let trimmed = videoFrameRate.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("p"), let value = Double(trimmed.dropLast()) { return value }
        return Double(trimmed)
    }
}

nonisolated struct PlexPart: Decodable, Sendable {
    let key: String
    let file: String?
}

//
//  MediaServerAudioLanguage.swift
//  Apex
//
//  Preferred audio language for Jellyfin, Emby, Plex, and AIOStreams playback.
//

import Foundation

/// Languages offered in Settings → Media Servers. Stored as an ISO 639-1 code.
nonisolated enum MediaServerAudioLanguage: String, CaseIterable, Identifiable, Sendable {
    static let storageKey = "mediaServerPreferredAudioLanguage"

    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    case hindi = "hi"
    case arabic = "ar"
    case russian = "ru"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case swedish = "sv"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: String(localized: "English")
        case .spanish: String(localized: "Spanish")
        case .french: String(localized: "French")
        case .german: String(localized: "German")
        case .portuguese: String(localized: "Portuguese")
        case .italian: String(localized: "Italian")
        case .japanese: String(localized: "Japanese")
        case .korean: String(localized: "Korean")
        case .chinese: String(localized: "Chinese")
        case .hindi: String(localized: "Hindi")
        case .arabic: String(localized: "Arabic")
        case .russian: String(localized: "Russian")
        case .dutch: String(localized: "Dutch")
        case .polish: String(localized: "Polish")
        case .turkish: String(localized: "Turkish")
        case .swedish: String(localized: "Swedish")
        }
    }

    /// The language chosen in Settings. Missing or unknown values stay on English.
    static var current: MediaServerAudioLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? english.rawValue
        return MediaServerAudioLanguage(rawValue: raw) ?? .english
    }

    /// ISO codes and English names that identify this language in a version label or track name.
    var aliases: Set<String> {
        switch self {
        case .english: ["en", "eng", "english"]
        case .spanish: ["es", "spa", "esp", "spanish", "espanol", "castilian"]
        case .french: ["fr", "fra", "fre", "french", "francais"]
        case .german: ["de", "deu", "ger", "german", "deutsch"]
        case .portuguese: ["pt", "por", "portuguese", "portugues", "brazilian", "brazil", "brasil"]
        case .italian: ["it", "ita", "italian", "italiano"]
        case .japanese: ["ja", "jpn", "japanese"]
        case .korean: ["ko", "kor", "korean"]
        case .chinese: ["zh", "zho", "chi", "chinese", "mandarin", "cantonese"]
        case .hindi: ["hi", "hin", "hindi"]
        case .arabic: ["ar", "ara", "arabic"]
        case .russian: ["ru", "rus", "russian"]
        case .dutch: ["nl", "nld", "dut", "dutch"]
        case .polish: ["pl", "pol", "polish"]
        case .turkish: ["tr", "tur", "turkish"]
        case .swedish: ["sv", "swe", "swedish"]
        }
    }

    /// True when `text` names this language as its own word or code, such as `eng` or `English`.
    func matches(_ text: String) -> Bool {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let tokens = folded.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return tokens.contains { aliases.contains($0) }
    }

    /// Versions whose label or audio tracks name this language come first. The rest keep server order.
    func preferring(_ streams: [MediaServerStreamInfo]) -> [MediaServerStreamInfo] {
        streams.enumerated()
            .sorted { lhs, rhs in
                let left = matches(lhs.element)
                let right = matches(rhs.element)
                if left != right { return left }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func matches(_ stream: MediaServerStreamInfo) -> Bool {
        let spoken = stream.meta.languages.filter { !$0.isEmpty }
        if !spoken.isEmpty { return spoken.contains(where: matches) }
        if stream.audioTracks.contains(where: { matches($0.label) }) { return true }
        if let label = stream.label, matches(label) { return true }
        if let filename = stream.meta.filename, matches(filename) { return true }
        return false
    }
}

/// One audio track reported by a media server, in file order.
nonisolated struct MediaServerAudioHint: Hashable, Codable, Sendable {
    /// Zero-based index among audio tracks, matching the order players expose.
    let index: Int
    /// Language code and display title joined, for example `eng English`.
    let label: String
}

enum PreferredAudioTrack {
    /// `wait` means the demuxer has not published language names yet, so the current track stays.
    enum Decision: Equatable {
        case select(Int)
        case unavailable
        case wait
    }

    static func decision(
        matching languageCode: String?,
        labels: [String],
        hints: [MediaServerAudioHint]
    ) -> Decision {
        guard let languageCode, let language = MediaServerAudioLanguage(rawValue: languageCode) else {
            return .unavailable
        }
        guard !labels.isEmpty else { return .wait }
        if let found = labels.firstIndex(where: { language.matches($0) }) {
            return .select(found)
        }
        if let hint = hints.first(where: { language.matches($0.label) }) {
            return labels.indices.contains(hint.index) ? .select(hint.index) : .wait
        }
        if labels.contains(where: isLanguageLabel) { return .unavailable }
        if hints.contains(where: { isLanguageLabel($0.label) }) { return .unavailable }
        return .wait
    }

    /// Index of the track that should play, or nil when nothing names the preferred language.
    static func index(
        matching languageCode: String?,
        labels: [String],
        hints: [MediaServerAudioHint]
    ) -> Int? {
        if case .select(let index) = decision(matching: languageCode, labels: labels, hints: hints) {
            return index
        }
        return nil
    }

    private static func isLanguageLabel(_ text: String) -> Bool {
        MediaServerAudioLanguage.allCases.contains { $0.matches(text) }
    }
}
