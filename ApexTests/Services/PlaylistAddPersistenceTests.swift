import Foundation
@testable import Apex
import SwiftData
import Testing

@MainActor
struct PlaylistAddPersistenceTests {
    @Test func `persisting a second playlist keeps the first`() async throws {
        let container = try makeTestContainer()
        let first = PlaylistAddPersistence.Draft(
            name: "Amethyst",
            serverURL: "http://amethyst.example:8080",
            username: "a",
            password: "a"
        )
        let second = PlaylistAddPersistence.Draft(
            name: "Mama",
            serverURL: "http://mama.example:8080",
            username: "m",
            password: "m"
        )

        try await Task.detached {
            try PlaylistAddPersistence.persist(first, in: container)
        }.value
        try await Task.detached {
            try PlaylistAddPersistence.persist(second, in: container)
        }.value

        let context = ModelContext(container)
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(Set(playlists.map(\.name)) == ["Amethyst", "Mama"])
        #expect(playlists.count == 2)

        let sources = try context.fetch(FetchDescriptor<EPGSource>())
        #expect(sources.count == 2)
        #expect(Set(sources.compactMap(\.playlistID)) == [first.id, second.id])
    }

    @Test func `draft preserves identity and xtream account fields`() throws {
        let id = UUID()
        let draft = PlaylistAddPersistence.Draft(
            id: id,
            name: "Mama",
            serverURL: "http://mama.example:8080",
            username: "m",
            password: "secret",
            serverTimezone: "Europe/London",
            userStatus: "Active",
            maxConnections: "2",
            activeConnections: "1",
            expDate: "1893456000"
        )

        let playlist = draft.makePlaylist()
        #expect(playlist.id == id)
        #expect(playlist.name == "Mama")
        #expect(playlist.sourceTypeRaw == "xtream")
        #expect(playlist.serverTimezone == "Europe/London")
        #expect(playlist.userStatus == "Active")
        #expect(playlist.maxConnections == "2")
        #expect(playlist.password == "secret")
    }

    @Test func `m3u draft keeps the guide url`() throws {
        let draft = PlaylistAddPersistence.Draft(
            name: "List",
            serverURL: "http://host/list.m3u",
            sourceTypeRaw: "m3u",
            epgURL: "http://host/guide.xml"
        )
        let playlist = draft.makePlaylist()
        #expect(playlist.sourceTypeRaw == "m3u")
        #expect(playlist.epgURL == "http://host/guide.xml")
        #expect(EPGSourceReconciler.guideURL(for: playlist) == "http://host/guide.xml")
    }
}
