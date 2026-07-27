//
//  StremioTests.swift
//  ApexTests
//
//  Stremio manifest decoding and URL normalization.
//

import Foundation
@testable import Apex
import Testing

struct StremioTests {
    private let streamAddonManifest = """
    {
      "id": "com.example.streamaddon",
      "version": "0.0.15",
      "name": "StreamHub",
      "description": "Provides HTTP stream sources",
      "catalogs": [],
      "resources": [
        { "name": "stream", "types": ["movie", "series", "anime"], "idPrefixes": ["tt", "kitsu"] }
      ],
      "types": ["movie", "series", "anime", "other"]
    }
    """

    private let cinemetaManifest = """
    {
      "id": "com.linvo.cinemeta",
      "version": "3.0.14",
      "name": "Cinemeta",
      "resources": ["catalog", "meta", "addon_catalog"],
      "types": ["movie", "series"],
      "catalogs": [
        { "type": "movie", "id": "top", "name": "Popular" }
      ]
    }
    """

    private let minimalCatalogManifest = """
    {
      "id": "org.stremio.example",
      "version": "0.0.1",
      "name": "Example Addon",
      "resources": ["catalog", "stream"],
      "types": ["movie"],
      "catalogs": [{ "type": "movie", "id": "moviecatalog" }]
    }
    """

    @Test func `manifest decodes string resources`() throws {
        let manifest = try JSONDecoder().decode(StremioManifest.self, from: Data(cinemetaManifest.utf8))
        #expect(manifest.name == "Cinemeta")
        #expect(manifest.hasCatalogs)
        #expect(manifest.hasMeta)
        #expect(!manifest.hasStreams)
    }

    @Test func `manifest decodes object resources`() throws {
        let manifest = try JSONDecoder().decode(StremioManifest.self, from: Data(streamAddonManifest.utf8))
        #expect(manifest.name == "StreamHub")
        #expect(manifest.hasStreams)
        #expect(!manifest.hasCatalogs)
    }

    @Test func `catalog name defaults to id when omitted`() throws {
        let manifest = try JSONDecoder().decode(StremioManifest.self, from: Data(minimalCatalogManifest.utf8))
        #expect(manifest.catalogs.first?.name == "moviecatalog")
    }

    @Test func `normalize strips manifest json suffix`() {
        let url = StremioURL.normalize("https://streams.example.addon/manifest.json")
        #expect(url?.absoluteString == "https://streams.example.addon")
    }

    @Test func `normalize handles configured addon path`() {
        let url = StremioURL.normalize("https://streams.example.addon/qualityfilter=1080p/manifest.json")
        #expect(url?.absoluteString == "https://streams.example.addon/qualityfilter=1080p")
    }

    @Test func `manifest url appends manifest json to base`() {
        let base = URL(string: "https://streams.example.addon")!
        #expect(StremioURL.manifestURL(base: base).absoluteString == "https://streams.example.addon/manifest.json")
    }

    @Test func `manifest url keeps legacy stremio v1 endpoint`() {
        let base = URL(string: "https://example.com/stremio/v1")!
        #expect(StremioURL.manifestURL(base: base).absoluteString == "https://example.com/stremio/v1")
    }
}
