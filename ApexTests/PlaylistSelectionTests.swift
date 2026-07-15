//
//  PlaylistSelectionTests.swift
//  ApexTests
//
//  Default playlist resolution after CloudKit restore — Xtream/M3U/Stalker must
//  win over Stremio when no explicit apex.selectedPlaylistID is stored.
//

import Foundation
@testable import Apex
import Testing

struct PlaylistSelectionTests {
    @Test func `empty selection prefers xtream over stremio even when stremio is first`() {
        let stremio = Playlist(name: "Addon", stremioURL: "https://example.com/manifest.json")
        let xtream = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "u", password: "p")
        let playlists = [stremio, xtream]

        let active = playlists.active(for: "")
        #expect(active?.id == xtream.id)
        #expect(playlists.preferredDefault()?.id == xtream.id)
    }

    @Test func `explicit selection still wins`() {
        let stremio = Playlist(name: "Addon", stremioURL: "https://example.com/manifest.json")
        let xtream = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "u", password: "p")
        let playlists = [stremio, xtream]

        let active = playlists.active(for: stremio.id.uuidString)
        #expect(active?.id == stremio.id)
    }

    @Test func `orphaned selection falls back to preferred catalog playlist`() {
        let m3u = Playlist(name: "M3U", m3uURL: "http://example.com/list.m3u")
        let stremio = Playlist(name: "Addon", stremioURL: "https://example.com/manifest.json")
        let playlists = [stremio, m3u]

        let active = playlists.active(for: UUID().uuidString)
        #expect(active?.id == m3u.id)
    }

    @Test func `auto-sync order puts catalog providers ahead of stremio`() {
        let stremio = Playlist(name: "Addon", stremioURL: "https://example.com/manifest.json")
        let xtream = Playlist(name: "Xtream", serverURL: "http://example.com:8080", username: "u", password: "p")
        let m3u = Playlist(name: "M3U", m3uURL: "http://example.com/list.m3u")
        let ordered = [stremio, m3u, xtream].orderedForAutoSync()

        #expect(ordered.map(\.sourceType) == [.xtream, .m3u, .stremio])
    }

    @Test func `stremio alone can still be the default`() {
        let stremio = Playlist(name: "Addon", stremioURL: "https://example.com/manifest.json")
        #expect([stremio].active(for: "")?.id == stremio.id)
    }
}
