import SwiftUI

struct LibraryToolbarModifier: ViewModifier {
    let playlists: [Playlist]
    @Binding var selectedPlaylistID: String
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingSettings: Bool
    /// When set, Home (and any other screen that hosts Search) shows the
    /// magnifying-glass button in the same trailing group as Settings.
    var showingSearch: Binding<Bool>?
    let activePlaylist: Playlist?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if playlists.count > 1 {
                    ToolbarItem(placement: playlistPlacement) {
                        PlaylistSwitcher(playlists: playlists, selectedPlaylistID: $selectedPlaylistID)
                    }
                }

                // One trailing group keeps Sort / Sync / Settings / Search
                // visible on iPad. Separate `.automatic` items were collapsing
                // into the overflow menu, so Settings and Search disappeared.
                ToolbarItemGroup(placement: trailingPlacement) {
                    SortMenu(categorySortRaw: $categorySortRaw, contentSortRaw: $contentSortRaw)

                    Button {
                        showingSync = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Sync")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Settings")

                    if let showingSearch {
                        Button {
                            showingSearch.wrappedValue = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Search")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSync) {
                if let playlist = activePlaylist {
                    SyncProgressView(playlist: playlist)
                }
            }
            .modifier(LibrarySearchSheet(showingSearch: showingSearch))
    }

    #if os(iOS)
        private var playlistPlacement: ToolbarItemPlacement {
            .topBarLeading
        }

        private var trailingPlacement: ToolbarItemPlacement {
            .topBarTrailing
        }
    #else
        private var playlistPlacement: ToolbarItemPlacement {
            .automatic
        }

        private var trailingPlacement: ToolbarItemPlacement {
            .automatic
        }
    #endif
}

/// Presents Search only when the host opted into the magnifying-glass button.
private struct LibrarySearchSheet: ViewModifier {
    var showingSearch: Binding<Bool>?

    func body(content: Content) -> some View {
        if let showingSearch {
            content.sheet(isPresented: showingSearch) {
                SearchView()
            }
        } else {
            content
        }
    }
}

struct LibraryToolbarConfiguration {
    let playlists: [Playlist]
    @Binding var selectedPlaylistID: String
    @Binding var categorySortRaw: String
    @Binding var contentSortRaw: String
    @Binding var showingSync: Bool
    @Binding var showingSettings: Bool
    var showingSearch: Binding<Bool>? = nil
    let activePlaylist: Playlist?
}

extension View {
    func libraryToolbar(config: LibraryToolbarConfiguration) -> some View {
        #if os(tvOS)
            // tvOS surfaces sync/settings/sorting through the Settings tab.
            // The Sync Now button lives in PlaylistDetailView at the top of
            // the playlist settings pane.
            return self
        #else
            return modifier(LibraryToolbarModifier(
                playlists: config.playlists,
                selectedPlaylistID: config.$selectedPlaylistID,
                categorySortRaw: config.$categorySortRaw,
                contentSortRaw: config.$contentSortRaw,
                showingSync: config.$showingSync,
                showingSettings: config.$showingSettings,
                showingSearch: config.showingSearch,
                activePlaylist: config.activePlaylist
            ))
        #endif
    }
}
