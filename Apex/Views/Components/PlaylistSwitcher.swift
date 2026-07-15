//
//  PlaylistSwitcher.swift
//  Apex
//
//  The playlist selection is a single global setting shared by Home, Movies,
//  Series and Live TV. It is persisted as the selected playlist's UUID string
//  in UserDefaults so the choice survives launches and stays in sync across
//  every tab.
//

import SwiftUI

// MARK: - Selection store

enum PlaylistSelectionStore {
    /// `@AppStorage` key holding the selected playlist's `id.uuidString`.
    /// An empty value means "no explicit choice yet" — callers fall back to a
    /// preferred catalog playlist (Xtream / M3U / Stalker before Stremio).
    static let key = "apex.selectedPlaylistID"
}

extension [Playlist] {
    /// Lower is preferred when choosing a default after CloudKit restore or
    /// first launch with an empty `apex.selectedPlaylistID`.
    ///
    /// Stremio addons must not win the default slot ahead of Xtream/M3U/Stalker
    /// — a fresh Apple TV install otherwise opens on Stremio while Live TV and
    /// Movies look empty until the user manually selects (and syncs) Xtream.
    static func defaultSelectionPriority(of playlist: Playlist) -> Int {
        switch playlist.sourceType {
        case .xtream: 0
        case .m3u: 1
        case .stalker: 2
        case .stremio: 3
        }
    }

    /// Best playlist to use when no explicit selection is stored.
    func preferredDefault() -> Playlist? {
        self.min { lhs, rhs in
            let left = Self.defaultSelectionPriority(of: lhs)
            let right = Self.defaultSelectionPriority(of: rhs)
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Catalog providers first, then Stremio — used for auto-sync cover order
    /// so Xtream populates before addon sync on a multi-playlist restore.
    func orderedForAutoSync() -> [Playlist] {
        sorted { lhs, rhs in
            let left = Self.defaultSelectionPriority(of: lhs)
            let right = Self.defaultSelectionPriority(of: rhs)
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Resolves the stored selection to a concrete playlist, falling back to
    /// `preferredDefault()` when the stored id is empty or no longer exists
    /// (e.g. the selected playlist was deleted).
    func active(for storedID: String) -> Playlist? {
        first(where: { $0.id.uuidString == storedID }) ?? preferredDefault()
    }
}

// MARK: - Switcher

/// Toolbar menu that switches the global active playlist. Drop one into any
/// view's toolbar and bind it to the shared `@AppStorage` selection.
struct PlaylistSwitcher: View {
    let playlists: [Playlist]
    @Binding var selectedPlaylistID: String
    /// Optional so previews (and any host that doesn't inject it) still switch
    /// instantly; when present, the switch routes through the blocking overlay.
    @Environment(PlaylistSwitchModel.self) private var switchModel: PlaylistSwitchModel?

    var body: some View {
        if !playlists.isEmpty {
            Menu {
                ForEach(playlists) { playlist in
                    Button {
                        select(playlist)
                    } label: {
                        Label(
                            playlist.name,
                            systemImage: playlist.id.uuidString == effectiveID ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                HStack {
                    Text(effectiveName)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
        }
    }

    /// Switches the global selection to `playlist`, surfacing the re-render as a
    /// blocking overlay when a switch model is available.
    private func select(_ playlist: Playlist) {
        let id = playlist.id.uuidString
        guard id != effectiveID else { return }
        if let switchModel {
            switchModel.switchTo(name: playlist.name) { selectedPlaylistID = id }
        } else {
            selectedPlaylistID = id
        }
    }

    /// The id that is actually in effect, accounting for the empty-default /
    /// deleted-playlist fallback to the preferred catalog playlist.
    private var effectiveID: String {
        playlists.active(for: selectedPlaylistID)?.id.uuidString ?? ""
    }

    private var effectiveName: String {
        playlists.active(for: selectedPlaylistID)?.name ?? ""
    }
}

#Preview("Multiple Playlists") {
    let playlist1 = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "user", password: "pass")
    let playlist2 = Playlist(name: "Backup", serverURL: "http://backup.com:8080", username: "user2", password: "pass2")
    PlaylistSwitcher(playlists: [playlist1, playlist2], selectedPlaylistID: .constant(playlist1.id.uuidString))
}

#Preview("Single Playlist") {
    let playlist = Playlist(name: "My IPTV", serverURL: "http://example.com:8080", username: "user", password: "pass")
    PlaylistSwitcher(playlists: [playlist], selectedPlaylistID: .constant(playlist.id.uuidString))
}

#Preview("Empty") {
    PlaylistSwitcher(playlists: [], selectedPlaylistID: .constant(""))
}
