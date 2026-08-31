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

    init(from stream: MediaServerStreamInfo) {
        method = stream.method
        container = stream.container
        videoCodec = stream.videoCodec
        audioCodec = stream.audioCodec
        width = stream.width
        height = stream.height
        frameRate = stream.frameRate
        videoBitrate = stream.videoBitrate
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
        let ids = parsedProviderIDs
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
    let container: String?
    let directStreamUrl: String?
    let transcodingUrl: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let mediaStreams: [JellyfinMediaStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case directStreamUrl = "DirectStreamUrl"
        case transcodingUrl = "TranscodingUrl"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case mediaStreams = "MediaStreams"
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

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
        case width = "Width"
        case height = "Height"
        case bitRate = "BitRate"
        case averageFrameRate = "AverageFrameRate"
        case realFrameRate = "RealFrameRate"
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
