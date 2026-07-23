//
//  MoviesView.swift
//  Apex
//
//  Main view for browsing movies. Each category shows a preview row;
//  "Show All" navigates to the full category view.
//

import SwiftData
import SwiftUI

struct MoviesView: View {
    @Namespace private var animationNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(ThemeManager.self) private var themeManager
    // Optional so previews (which don't inject it) fall back to a local path.
    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
    @State private var fallbackPath = NavigationPath()
    @Query private var playlists: [Playlist]
    @Query(filter: #Predicate<Category> { $0.typeRaw == "vod" && $0.isHidden == false })
    private var categories: [Category]

    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    @State private var showingSync = false
    @State private var showingSettings = false

    @AppStorage(SortStorageKey.movieCategories) private var categorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SortStorageKey.movieContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue

    private var categorySort: CategorySortOption {
        CategorySortOption(rawValue: categorySortRaw) ?? .playlist
    }

    private var contentSort: ContentSortOption {
        ContentSortOption(rawValue: contentSortRaw) ?? .playlist
    }

    /// How many movies to render inline per category. The full list is reachable
    /// via the per-row "Show All" link.
    private let previewLimit = 20

    // How many categories render as full inline preview rows. Each preview row
    // carries its own live `@Query`, so capping them keeps the browse screen
    // fast; the remaining categories surface as lightweight name tiles below.
    #if os(iOS)
        private let previewCategoryLimit = 4
    #else
        private let previewCategoryLimit = 4
    #endif

    var body: some View {
        // Resolve once per render — `sortedCategories` filters + sorts every
        // playlist's categories, so reading it three times (the emptiness check
        // plus the preview/remaining splits) tripled that work.
        let sorted = sortedCategories
        NavigationStack(path: navigationPath) {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "film.stack",
                        description: Text("Add a playlist in Settings to start browsing movies")
                    )
                } else if sorted.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Movies",
                            systemImage: "film.stack",
                            description: Text("Sync your playlist to load movies")
                        )
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                            if movieCount > 0 {
                                Text("\(movieCount) Movies")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            }
                            MovieCollectionRow(kind: .recentlyWatched, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)
                            MovieCollectionRow(kind: .favorites, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)
                            MovieCollectionRow(kind: .recentlyAdded, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)

                            ForEach(sorted.prefix(previewCategoryLimit)) { category in
                                MovieCategoryPreview(category: category, limit: previewLimit, sort: contentSort, animationNamespace: animationNamespace)
                                    .id("\(category.id)-\(contentSort.rawValue)")
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(themeManager.colors.background)
            .platformNavigationTitle("Movies")
            .profileMenuToolbar()
            .libraryToolbar(config: LibraryToolbarConfiguration(
                playlists: playlists,
                selectedPlaylistID: $selectedPlaylistID,
                categorySortRaw: $categorySortRaw,
                contentSortRaw: $contentSortRaw,
                showingSync: $showingSync,
                showingSettings: $showingSettings,
                activePlaylist: activePlaylist
            ))
            .navigationDestination(for: Category.self) { category in
                MovieCategoryView(category: category, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: LibraryCollection.self) { collection in
                MovieCollectionView(kind: collection.kind, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie, animationNamespace: animationNamespace)
                #if os(iOS)
                    .navigationTransition(.zoom(sourceID: movie.id, in: animationNamespace))
                #endif
            }
        }
    }

    /// Drives the stack from the shared `DeepLinkRouter` so an `onOpenURL` push
    /// lands here; falls back to a local path in previews where no router exists.
    private var navigationPath: Binding<NavigationPath> {
        guard let router else { return $fallbackPath }
        return Binding(get: { router.moviesPath }, set: { router.moviesPath = $0 })
    }

    /// The playlist whose content is currently shown, resolved from the global
    /// selection. Falls back to the first playlist until the user picks one.
    private var activePlaylist: Playlist? {
        playlists.active(for: selectedPlaylistID)
    }

    /// The id prefix every Movie/Category of the active playlist shares. Used to
    /// scope the cross-category collection rows in-memory.
    private var playlistPrefix: String {
        activePlaylist.map { "\($0.id.uuidString)-" } ?? ""
    }

    /// Counts directly in SQLite instead of hydrating the entire movie catalog.
    /// The previous unbounded `@Query` existed only for this label and could
    /// freeze tvOS when a provider exposed tens of thousands of VOD entries.
    private var movieCount: Int {
        let prefix = playlistPrefix
        guard !prefix.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.starts(with: prefix) }
        )
        var count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if restriction.isActive {
            for categoryID in restriction.restrictedCategoryIDs {
                let hidden = FetchDescriptor<Movie>(
                    predicate: #Predicate {
                        $0.id.starts(with: prefix) && $0.categoryId == categoryID
                    }
                )
                count -= (try? modelContext.fetchCount(hidden)) ?? 0
            }
        }
        return max(count, 0)
    }

    /// Categories scoped to the active playlist. The `@Query` fetches every
    /// playlist's categories (SwiftData can't parameterize a `@Query` on view
    /// state), so we isolate by the playlist-prefixed category `id` here.
    private var sortedCategories: [Category] {
        guard let playlistId = activePlaylist?.id else { return [] }
        let prefix = "\(playlistId.uuidString)-"
        return categorySort.sort(categories.filter { $0.id.hasPrefix(prefix) && !restriction.hides(categoryID: $0.id) })
    }
}

#Preview("Empty") {
    MoviesView()
        .modelContainer(for: Playlist.self, inMemory: true)
}

#Preview("With Data") {
    MoviesView()
        .modelContainer(previewContainer())
}
