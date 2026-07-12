//
//  StremioDTOs.swift
//  Apex
//
//  Decodable types for the Stremio addon protocol (v4/v5).
//  Spec: https://github.com/Stremio/stremio-addon-sdk
//

import Foundation

// MARK: - Manifest

/// A manifest `resources` entry — either a plain string (`"stream"`) or an object
/// with per-resource type/idPrefix filters (Torrentio, Cinemeta stream, etc.).
enum StremioResource: Decodable, Sendable {
    case simple(String)
    case defined(StremioResourceDef)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self = .simple(name)
            return
        }
        self = .defined(try StremioResourceDef(from: decoder))
    }

    var name: String {
        switch self {
        case .simple(let name): name
        case .defined(let def): def.name
        }
    }
}

struct StremioResourceDef: Decodable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

/// Top-level manifest returned by `GET /manifest.json`.
struct StremioManifest: Decodable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let types: [String]
    let catalogs: [StremioCatalogDef]
    let resources: [StremioResource]
    let idPrefixes: [String]?
    let behaviorHints: StremioBehaviorHints?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        types = try container.decodeIfPresent([String].self, forKey: .types) ?? []
        catalogs = try container.decodeIfPresent([StremioCatalogDef].self, forKey: .catalogs) ?? []
        resources = try container.decodeIfPresent([StremioResource].self, forKey: .resources) ?? []
        idPrefixes = try container.decodeIfPresent([String].self, forKey: .idPrefixes)
        behaviorHints = try container.decodeIfPresent(StremioBehaviorHints.self, forKey: .behaviorHints)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, description, types, catalogs, resources, idPrefixes, behaviorHints
    }

    /// Whether this addon supports the catalog resource.
    var hasCatalogs: Bool { resources.contains { $0.name == "catalog" } }
    /// Whether this addon supports on-demand stream resolution.
    var hasStreams: Bool { resources.contains { $0.name == "stream" } }
    /// Whether this addon supports metadata enrichment.
    var hasMeta: Bool { resources.contains { $0.name == "meta" } }
}

struct StremioCatalogDef: Decodable {
    let type: String
    let id: String
    let name: String
    let extra: [StremioExtraProp]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        extra = try container.decodeIfPresent([StremioExtraProp].self, forKey: .extra)
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, extra
    }
}

struct StremioExtraProp: Decodable {
    let name: String
    let isRequired: Bool?
    let options: [String]?

    enum CodingKeys: String, CodingKey {
        case name, isRequired = "required", options
    }
}

struct StremioBehaviorHints: Decodable {
    let adult: Bool?
    let configurable: Bool?
}

// MARK: - Catalog

/// Paginated catalog response from `GET /catalog/{type}/{id}.json`.
struct StremioCatalog: Decodable {
    let metas: [StremioMetaPreview]
}

/// Lightweight preview item returned in catalog listings.
struct StremioMetaPreview: Decodable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let posterShape: String?
}

// MARK: - Meta

/// Full metadata response from `GET /meta/{type}/{id}.json`.
struct StremioMetaResponse: Decodable {
    let meta: StremioMeta
}

struct StremioMeta: Decodable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let year: String?
    let imdbRating: String?
    let genres: [String]?
    let director: [String]?
    let cast: [String]?
    let runtime: String?
    let country: String?
    let language: String?
    let awards: String?
    let website: String?
    /// Episodes/videos for series — each has a season, episode, and stream id.
    let videos: [StremioVideo]?
}

/// A single episode/video in a Stremio series metadata response.
struct StremioVideo: Decodable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let released: String?
    let thumbnail: String?
    let overview: String?
}

// MARK: - Stream

/// Stream response from `GET /stream/{type}/{id}.json`.
struct StremioStreamResponse: Decodable {
    let streams: [StremioStream]
}

struct StremioStream: Decodable {
    let url: String?
    let externalUrl: String?
    let infoHash: String?
    let title: String?
    let name: String?
    let description: String?
    let behaviorHints: StremioStreamHints?

    /// Best available URL — external URLs (YouTube etc.) take precedence for
    /// compatibility, then direct stream URLs.
    var bestURL: URL? {
        if let external = externalUrl ?? url, let u = URL(string: external) {
            return u
        }
        return nil
    }

    var displayTitle: String {
        title ?? name ?? description ?? "Stream"
    }
}

struct StremioStreamHints: Decodable {
    let notWebReady: Bool?
    let bingeGroup: String?
    let countryWhitelist: [String]?
}
