//
//  StremioDTOs.swift
//  Apex
//
//  Decodable types for the Stremio addon protocol (v4/v5).
//  Spec: https://github.com/Stremio/stremio-addon-sdk
//

import Foundation

// MARK: - Manifest

/// Top-level manifest returned by `GET /manifest.json`.
struct StremioManifest: Decodable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let types: [String]
    let catalogs: [StremioCatalogDef]
    let resources: [String]
    let idPrefixes: [String]?
    let behaviorHints: StremioBehaviorHints?

    /// Whether this addon supports the catalog resource.
    var hasCatalogs: Bool { resources.contains("catalog") }
    /// Whether this addon supports on-demand stream resolution.
    var hasStreams: Bool { resources.contains("stream") }
    /// Whether this addon supports metadata enrichment.
    var hasMeta: Bool { resources.contains("meta") }
}

struct StremioCatalogDef: Decodable {
    let type: String
    let id: String
    let name: String
    let extra: [StremioExtraProp]?
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
