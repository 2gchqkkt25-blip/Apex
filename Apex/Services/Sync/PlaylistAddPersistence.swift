//
//  PlaylistAddPersistence.swift
//  Apex
//
//  Background insert for a newly added playlist so the add sheet never
//  blocks MainActor on `ModelContext.save()`.
//

import Foundation
import SwiftData

/// Inserts a newly added playlist on a background `ModelContext`.
///
/// The add-playlist sheet used to `insert` + `save()` on the view context
/// (MainActor). When playlist 1 is still catalog-syncing, that save can block
/// the store — and because the connection-test timeout also has to resume on
/// MainActor, the sheet spins forever. Persisting here keeps the UI thread free
/// so a second playlist can be added while the first one syncs.
nonisolated enum PlaylistAddPersistence {
    /// Sendable snapshot of the row the add sheet is about to insert. `@Model`
    /// `Playlist` is not safe to hop onto a detached task.
    struct Draft: Sendable {
        var id: UUID
        var name: String
        var serverURL: String
        var username: String
        var password: String
        var sourceTypeRaw: String
        var epgURL: String?
        var macAddress: String?
        var serverTimezone: String?
        var userStatus: String?
        var maxConnections: String?
        var activeConnections: String?
        var expDate: String?

        init(
            id: UUID = UUID(),
            name: String,
            serverURL: String,
            username: String = "",
            password: String = "",
            sourceTypeRaw: String = "xtream",
            epgURL: String? = nil,
            macAddress: String? = nil,
            serverTimezone: String? = nil,
            userStatus: String? = nil,
            maxConnections: String? = nil,
            activeConnections: String? = nil,
            expDate: String? = nil
        ) {
            self.id = id
            self.name = name
            self.serverURL = serverURL
            self.username = username
            self.password = password
            self.sourceTypeRaw = sourceTypeRaw
            self.epgURL = epgURL
            self.macAddress = macAddress
            self.serverTimezone = serverTimezone
            self.userStatus = userStatus
            self.maxConnections = maxConnections
            self.activeConnections = activeConnections
            self.expDate = expDate
        }

        @MainActor
        init(_ playlist: Playlist) {
            self.init(
                id: playlist.id,
                name: playlist.name,
                serverURL: playlist.serverURL,
                username: playlist.username,
                password: playlist.password,
                sourceTypeRaw: playlist.sourceTypeRaw,
                epgURL: playlist.epgURL,
                macAddress: playlist.macAddress,
                serverTimezone: playlist.serverTimezone,
                userStatus: playlist.userStatus,
                maxConnections: playlist.maxConnections,
                activeConnections: playlist.activeConnections,
                expDate: playlist.expDate
            )
        }

        func makePlaylist() -> Playlist {
            let playlist = Playlist(
                name: name,
                serverURL: serverURL,
                username: username,
                password: password
            )
            playlist.id = id
            playlist.sourceTypeRaw = sourceTypeRaw
            playlist.epgURL = epgURL
            playlist.macAddress = macAddress
            playlist.serverTimezone = serverTimezone
            playlist.userStatus = userStatus
            playlist.maxConnections = maxConnections
            playlist.activeConnections = activeConnections
            playlist.expDate = expDate
            return playlist
        }
    }

    static func persist(_ draft: Draft, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let playlist = draft.makePlaylist()
        context.insert(playlist)
        EPGSourceReconciler.reconcile(playlist, in: context)
        try context.save()
    }
}
