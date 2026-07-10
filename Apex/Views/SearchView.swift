//
//  SearchView.swift
//  Apex
//
//  Global search across all content
//

import SwiftData
import SwiftUI

struct SearchView: View {
    @Namespace private var animationNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(ThemeManager.self) private var themeManager
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @Query private var playlists: [Playlist]
    @Query(filter: #Predicate<Category> { $0.typeRaw == "vod" && $0.isHidden == false })
    private var movieCategoriesQuery: [Category]
    @Query(filter: #Predicate<Category> { $0.typeRaw == "series" && $0.isHidden == false })
    private var seriesCategoriesQuery: [Category]

    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    @AppStorage(SortStorageKey.movieCategories) private var movieCategorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SortStorageKey.seriesCategories) private var seriesCategorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SearchSettings.searchAllPlaylistsKey)
    private var searchAllPlaylists = SearchSettings.searchAllPlaylistsDefault
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedFilter: ContentFilter = .all
    @State private var results: [SearchResult] = []
    @State private var playingMedia: PlayableMedia?
    #if os(tvOS)
        @State private var categoryArtwork: [String: URL] = [:]
    #endif
    @State private var movieGenres: [String] = []
    @State private var seriesGenres: [String] = []

    /// Max matches fetched per content type. Keeps the result set bounded so the
    /// list stays responsive even when a playlist holds tens of thousands of items.
    private let resultLimit = 50

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var movieCategorySort: CategorySortOption {
        CategorySortOption(rawValue: movieCategorySortRaw) ?? .playlist
    }

    private var seriesCategorySort: CategorySortOption {
        CategorySortOption(rawValue: seriesCategorySortRaw) ?? .playlist
    }

    private var playlistPrefix: String {
        activePlaylist.map { "\($0.id.uuidString)-" } ?? ""
    }

    /// Genre browse only runs when the search field is empty — typing a query
    /// shouldn't kick a 5K-row genre sample fetch on every keystroke's cancel.
    private var genreBrowseTaskKey: String {
        "\(playlistPrefix)|empty-\(trimmedQuery.isEmpty)"
    }

    private var sortedMovieCategories: [Category] {
        guard let playlistId = activePlaylist?.id else { return [] }
        let prefix = "\(playlistId.uuidString)-"
        return movieCategorySort.sort(
            movieCategoriesQuery.filter { $0.id.hasPrefix(prefix) && !restriction.hides(categoryID: $0.id) }
        )
    }

    private var sortedSeriesCategories: [Category] {
        guard let playlistId = activePlaylist?.id else { return [] }
        let prefix = "\(playlistId.uuidString)-"
        return seriesCategorySort.sort(
            seriesCategoriesQuery.filter { $0.id.hasPrefix(prefix) && !restriction.hides(categoryID: $0.id) }
        )
    }

    #if os(tvOS)
    private var categoryArtworkTaskKey: String {
        let ids = (sortedMovieCategories + sortedSeriesCategories).map(\.id).joined(separator: ",")
        return "\(playlistPrefix)|\(movieCategorySortRaw)|\(seriesCategorySortRaw)|\(ids)"
    }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    #if os(tvOS)
                    tvOSCategoryBrowse
                    #else
                    categoryBrowse
                    #endif
                } else {
                    searchResultsList
                }
            }
            .platformNavigationTitle("Search")
            #if !os(tvOS)
                .scrollContentBackground(.hidden)
            #endif
            .background(themeManager.colors.background)
            .searchable(text: $searchText, prompt: "Movies, Series, Live TV...")
            #if os(iOS)
                .searchToolbarMinimizeIfAvailable()
            #endif
                .navigationDestination(for: Movie.self) { movie in
                    MovieDetailView(movie: movie, animationNamespace: animationNamespace)
                    #if os(iOS)
                        .navigationTransition(.zoom(sourceID: movie.id, in: animationNamespace))
                    #endif
                }
                .navigationDestination(for: Series.self) { series in
                    SeriesDetailView(series: series, animationNamespace: animationNamespace)
                    #if os(iOS)
                        .navigationTransition(.zoom(sourceID: series.id, in: animationNamespace))
                    #endif
                }
                .navigationDestination(for: Category.self) { category in
                    switch category.type {
                    case .vod:
                        MovieCategoryView(category: category, animationNamespace: animationNamespace)
                    case .series:
                        SeriesCategoryView(category: category, animationNamespace: animationNamespace)
                    case .live:
                        EmptyView()
                    }
                }
                .navigationDestination(for: GenreSelection.self) { selection in
                    switch selection.type {
                    case .vod:
                        MovieGenreView(genre: selection.genre, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)
                    case .series:
                        SeriesGenreView(genre: selection.genre, playlistPrefix: playlistPrefix, animationNamespace: animationNamespace)
                    case .live:
                        EmptyView()
                    }
                }
                .task(id: searchText) {
                    // Debounce raw keystrokes. .task(id:) cancels the in-flight task
                    // (including this sleep) the instant searchText changes, so the
                    // fetch below only fires once typing actually pauses.
                    let trimmed = trimmedQuery
                    guard !trimmed.isEmpty else {
                        debouncedSearchText = ""
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = trimmed
                }
                .task(id: SearchKey(text: debouncedSearchText, filter: selectedFilter, allPlaylists: searchAllPlaylists)) {
                    // Re-run whenever the settled query or the filter changes.
                    // Filter changes are instant (no debounce on the segmented control).
                    await updateResults()
                }
                #if os(tvOS)
                    .task(id: categoryArtworkTaskKey) {
                        let categories = sortedMovieCategories + sortedSeriesCategories
                        guard !categories.isEmpty else {
                            categoryArtwork = [:]
                            return
                        }
                        categoryArtwork = await CategoryArtwork.posterURLs(
                            for: categories,
                            in: modelContext.container
                        )
                    }
                #endif
                .task(id: genreBrowseTaskKey) {
                    guard trimmedQuery.isEmpty else {
                        movieGenres = []
                        seriesGenres = []
                        return
                    }
                    async let movies = GenreDerivation.movieGenres(in: modelContext.container, playlistPrefix: playlistPrefix, restriction: restriction)
                    async let series = GenreDerivation.seriesGenres(in: modelContext.container, playlistPrefix: playlistPrefix, restriction: restriction)
                    movieGenres = await movies
                    seriesGenres = await series
                }
        }
        #if os(iOS)
        .fullScreenCover(item: $playingMedia) { media in
            FullScreenPlayerView(media: media)
        }
        #endif
    }

    #if os(tvOS)
        @ViewBuilder
        private var tvOSCategoryBrowse: some View {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "magnifyingglass",
                    description: Text("Add a playlist in Settings to browse categories")
                )
            } else if sortedMovieCategories.isEmpty, sortedSeriesCategories.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Search for movies, series, or live TV channels")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 56) {
                        if !sortedMovieCategories.isEmpty {
                            CategoryPosterGridSection(
                                title: "Movie Categories",
                                categories: sortedMovieCategories,
                                artwork: categoryArtwork
                            )
                        }
                        if !sortedSeriesCategories.isEmpty {
                            CategoryPosterGridSection(
                                title: "Series Categories",
                                categories: sortedSeriesCategories,
                                artwork: categoryArtwork
                            )
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 40)
                }
            }
        }
    #endif

    #if !os(tvOS)
    @ViewBuilder
    private var categoryBrowse: some View {
        if playlists.isEmpty {
            ContentUnavailableView(
                "No Playlists",
                systemImage: "magnifyingglass",
                description: Text("Add a playlist to browse categories and genres")
            )
        } else if sortedMovieCategories.isEmpty, sortedSeriesCategories.isEmpty, movieGenres.isEmpty, seriesGenres.isEmpty {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("Search for movies, series, or live TV channels")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !movieGenres.isEmpty {
                        GenreGridSection(genres: movieGenres, type: .vod)
                    }

                    if !sortedMovieCategories.isEmpty {
                        CategoryGridSection(title: "Movie Categories", categories: sortedMovieCategories)
                    }

                    if !seriesGenres.isEmpty {
                        GenreGridSection(genres: seriesGenres, type: .series)
                    }

                    if !sortedSeriesCategories.isEmpty {
                        CategoryGridSection(title: "Series Categories", categories: sortedSeriesCategories)
                    }
                }
                .padding(.vertical)
            }
        }
    }
    #endif

    @ViewBuilder
    private var searchResultsList: some View {
        List {
            if trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Search for movies, series, or live TV channels")
                )
            } else {
                    // Filter Picker
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(ContentFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    // Results — only show "No Results" once a query has actually
                    // been run, so it doesn't flash while the input is debouncing.
                    if results.isEmpty {
                        if !debouncedSearchText.isEmpty {
                            ContentUnavailableView.search
                        }
                    } else {
                        Section {
                            ForEach(results) { result in
                                switch result {
                                case let .movie(movie):
                                    NavigationLink(value: movie) {
                                        SearchResultRow(result: result)
                                            .matchedTransitionSourceIfAvailable(id: movie.id, in: animationNamespace)
                                    }
                                case let .series(series):
                                    NavigationLink(value: series) {
                                        SearchResultRow(result: result)
                                            .matchedTransitionSourceIfAvailable(id: series.id, in: animationNamespace)
                                    }
                                case let .liveStream(stream):
                                    Button {
                                        playChannel(stream)
                                    } label: {
                                        SearchResultRow(result: result)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Text("\(results.count) Results")
                        }
                    }
            }
        }
    }

    // MARK: - Playback

    private var activePlaylist: Playlist? {
        playlists.active(for: selectedPlaylistID)
    }

    private func playChannel(_ stream: LiveStream) {
        guard let playlist = activePlaylist,
              let media = PlayableMedia.from(stream: stream, playlist: playlist) else { return }
        if ExternalPlayback.open(media) { return }
        #if os(macOS)
            openWindow(id: "player", value: media)
        #else
            playingMedia = media
        #endif
    }

    // MARK: - Searching

    /// Runs the search against SwiftData using bounded, predicate-based fetches.
    ///
    /// Filtering happens in SQLite (via `localizedStandardContains`) — but even a
    /// bounded `LIKE '%q%'` scan can't use an index, so on a large library it has
    /// real cost. The fetch runs on a background context (returning only the
    /// matched rows' identifiers, which are `Sendable`); the view context then
    /// hydrates just those rows by id. Combined with the debounce above, typing
    /// never blocks the main thread no matter how large the library is.
    private func updateResults() async {
        let query = debouncedSearchText
        guard !query.isEmpty else {
            results = []
            return
        }

        // Unless the user has opted into cross-playlist search, scope results to
        // the active playlist. Every category id is prefixed with its playlist's
        // UUID (see Category.id), and that UUID appears nowhere else, so matching
        // it within categoryId limits results to the active playlist's content.
        let playlistID = activePlaylist?.id.uuidString ?? ""
        let restrictToPlaylist = !searchAllPlaylists && activePlaylist != nil
        let filter = selectedFilter
        let limit = resultLimit
        let container = modelContext.container

        let request = SearchRequest(
            query: query,
            playlistID: playlistID,
            restrictToPlaylist: restrictToPlaylist,
            wantMovies: filter == .all || filter == .movies,
            wantSeries: filter == .all || filter == .series,
            wantLive: filter == .all || filter == .liveTV,
            limit: limit
        )
        let hits = await Task.detached(priority: .userInitiated) {
            SearchFetcher.fetch(container: container, request: request)
        }.value

        guard !Task.isCancelled else { return }

        // Hydrate the matched rows in the view context (a cheap by-identifier
        // lookup) and drop any in a restricted category for the active profile.
        var matches: [SearchResult] = []
        for id in hits.movies {
            if let movie = modelContext.model(for: id) as? Movie, !restriction.hides(categoryID: movie.categoryId) {
                matches.append(.movie(movie))
            }
        }
        for id in hits.series {
            if let series = modelContext.model(for: id) as? Series, !restriction.hides(categoryID: series.categoryId) {
                matches.append(.series(series))
            }
        }
        for id in hits.streams {
            if let stream = modelContext.model(for: id) as? LiveStream, !restriction.hides(categoryID: stream.categoryId) {
                matches.append(.liveStream(stream))
            }
        }

        results = matches
    }
}

// MARK: - Off-main search fetch

/// The matched rows' persistent identifiers, grouped by type. Plain value type
/// so it can cross back from the background fetch context.
private nonisolated struct SearchHits {
    var movies: [PersistentIdentifier] = []
    var series: [PersistentIdentifier] = []
    var streams: [PersistentIdentifier] = []
}

/// The settled query and the per-type toggles, bundled so the off-main fetch
/// takes a single `Sendable` value.
private nonisolated struct SearchRequest {
    let query: String
    let playlistID: String
    let restrictToPlaylist: Bool
    let wantMovies: Bool
    let wantSeries: Bool
    let wantLive: Bool
    let limit: Int
}

/// Runs the bounded `localizedStandardContains` fetches on a background
/// `ModelContext` and returns only identifiers — never managed objects, which
/// can't cross actor boundaries.
private nonisolated enum SearchFetcher {
    static func fetch(container: ModelContainer, request: SearchRequest) -> SearchHits {
        let query = request.query
        let playlistID = request.playlistID
        let restrictToPlaylist = request.restrictToPlaylist
        let limit = request.limit
        let context = ModelContext(container)
        var hits = SearchHits()

        if request.wantMovies {
            var descriptor = FetchDescriptor<Movie>(
                predicate: #Predicate { movie in
                    movie.name.localizedStandardContains(query)
                        && (!restrictToPlaylist || (movie.categoryId?.localizedStandardContains(playlistID) ?? false))
                },
                sortBy: [SortDescriptor(\.name)]
            )
            descriptor.fetchLimit = limit
            hits.movies = ((try? context.fetch(descriptor)) ?? []).map(\.persistentModelID)
        }

        if request.wantSeries {
            var descriptor = FetchDescriptor<Series>(
                predicate: #Predicate { series in
                    series.name.localizedStandardContains(query)
                        && (!restrictToPlaylist || (series.categoryId?.localizedStandardContains(playlistID) ?? false))
                },
                sortBy: [SortDescriptor(\.name)]
            )
            descriptor.fetchLimit = limit
            hits.series = ((try? context.fetch(descriptor)) ?? []).map(\.persistentModelID)
        }

        if request.wantLive {
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { stream in
                    stream.name.localizedStandardContains(query)
                        && (!restrictToPlaylist || (stream.categoryId?.localizedStandardContains(playlistID) ?? false))
                },
                sortBy: [SortDescriptor(\.name)]
            )
            descriptor.fetchLimit = limit
            hits.streams = ((try? context.fetch(descriptor)) ?? []).map(\.persistentModelID)
        }

        return hits
    }
}

// MARK: - Search Key

/// Identity for the fetch task: re-run when the settled query text, the active
/// content filter, or the cross-playlist search preference changes.
private struct SearchKey: Equatable {
    let text: String
    let filter: ContentFilter
    let allPlaylists: Bool
}

// MARK: - Search Settings

enum SearchSettings {
    /// When enabled, search spans every configured playlist. Off by default, so
    /// results stay scoped to the active playlist unless the user opts in.
    static let searchAllPlaylistsKey = "search.allPlaylists"
    static let searchAllPlaylistsDefault = false
}

// MARK: - Content Filter

enum ContentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"
    case series = "Series"
    case liveTV = "Live TV"

    var id: String {
        rawValue
    }

    var label: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

// MARK: - Search Result

enum SearchResult: Identifiable, Hashable {
    case movie(Movie)
    case series(Series)
    case liveStream(LiveStream)

    var id: String {
        switch self {
        case let .movie(movie):
            "movie-\(movie.id)"
        case let .series(series):
            "series-\(series.id)"
        case let .liveStream(stream):
            "live-\(stream.id)"
        }
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: categoryIcon)
                    Text(LocalizedStringKey(categoryName))
                }
                .font(.caption2)
                .foregroundStyle(.blue)
            }

            Spacer()
        }
    }

    private var thumbnailURL: URL? {
        switch result {
        case let .movie(movie):
            movie.iconURL
        case let .series(series):
            URL(string: series.cover ?? "")
        case let .liveStream(stream):
            stream.iconURL
        }
    }

    private var title: String {
        switch result {
        case let .movie(movie):
            movie.name
        case let .series(series):
            series.name
        case let .liveStream(stream):
            stream.name
        }
    }

    private var subtitle: String {
        switch result {
        case let .movie(movie):
            movie.genre ?? movie.releaseDate ?? ""
        case let .series(series):
            series.genre ?? series.releaseDate ?? ""
        case .liveStream:
            "Live"
        }
    }

    private var categoryName: String {
        switch result {
        case .movie:
            "Movie"
        case .series:
            "Series"
        case .liveStream:
            "Live TV"
        }
    }

    private var categoryIcon: String {
        switch result {
        case .movie:
            "film"
        case .series:
            "tv"
        case .liveStream:
            "antenna.radiowaves.left.and.right"
        }
    }

    private var iconName: String {
        switch result {
        case .movie:
            "film"
        case .series:
            "tv"
        case .liveStream:
            "antenna.radiowaves.left.and.right"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch result {
        case .liveStream:
            ChannelLogoView(url: thumbnailURL, width: 60, height: 90, cornerRadius: 8, contentPadding: 8)
        default:
            CachedAsyncImage(url: thumbnailURL, maxPixelSize: 90) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(.fill.quaternary)
                        .overlay { ProgressView() }
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(.fill.quaternary)
                        .overlay {
                            Image(systemName: iconName)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview("Empty") {
    SearchView()
        .modelContainer(for: Playlist.self, inMemory: true)
}

#Preview("With Data") {
    SearchView()
        .modelContainer(previewContainer())
}
