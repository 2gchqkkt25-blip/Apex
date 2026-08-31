//
//  MediaLibraryBrowseView.swift
//  Apex
//
//  Full-grid browse for a connected media server library section.
//

import SwiftData
import SwiftUI

enum MediaBrowseSection: String, Hashable, Identifiable {
    case continueWatching
    case movies
    case tvShows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueWatching: "Continue Watching"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }
}

struct MediaLibraryBrowseView: View {
    let section: MediaBrowseSection
    let serverPrefix: String

    @Environment(\.modelContext) private var modelContext
    @Namespace private var animationNamespace

    @State private var movies: [Movie] = []
    @State private var series: [Series] = []
    @State private var canLoadMore = true
    @State private var isLoadingPage = false

    private let pageSize = MediaServerCatalogLimits.browsePageSize
    private let columns = [GridItem(.adaptive(minimum: PosterCardMetrics.gridMinimum), spacing: PosterCardMetrics.gridSpacing)]

    private var reachedLoadCeiling: Bool {
        guard let ceiling = DeviceMemoryTier.current.maxPaginatedBrowseItems else { return false }
        return max(movies.count, series.count) >= ceiling
    }

    var body: some View {
        ScrollView {
            #if os(tvOS)
                Text(section.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 40)
            #endif

            if isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyIcon,
                    description: Text(emptyDescription)
                )
                .padding(.top, 40)
            } else {
                switch section {
                case .movies, .continueWatching:
                    LazyVGrid(columns: columns, spacing: PosterCardMetrics.gridSpacing) {
                        ForEach(movies) { movie in
                            NavigationLink(value: movie) {
                                MovieCardView(movie: movie)
                                    .matchedTransitionSourceIfAvailable(id: movie.id, in: animationNamespace)
                            }
                            .posterCardButtonStyle()
                            .onAppear {
                                if movie.id == movies.last?.id { loadNextPageIfNeeded() }
                            }
                        }
                    }
                    .padding()
                case .tvShows:
                    LazyVGrid(columns: columns, spacing: PosterCardMetrics.gridSpacing) {
                        ForEach(series) { show in
                            NavigationLink(value: show) {
                                SeriesCardView(series: show)
                                    .matchedTransitionSourceIfAvailable(id: show.id, in: animationNamespace)
                            }
                            .posterCardButtonStyle()
                            .onAppear {
                                if show.id == series.last?.id { loadNextPageIfNeeded() }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        #if !os(tvOS)
            .navigationTitle(section.title)
        #endif
        .task(id: taskKey) {
            resetAndLoad()
        }
    }

    private var taskKey: String {
        "\(section.rawValue)-\(serverPrefix)"
    }

    private var isEmpty: Bool {
        switch section {
        case .movies, .continueWatching: movies.isEmpty
        case .tvShows: series.isEmpty
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch section {
        case .continueWatching: "Nothing In Progress"
        case .movies: "No Movies"
        case .tvShows: "No TV Shows"
        }
    }

    private var emptyIcon: String {
        switch section {
        case .continueWatching: "play.circle"
        case .movies: "film.stack"
        case .tvShows: "tv.fill"
        }
    }

    private var emptyDescription: LocalizedStringKey {
        switch section {
        case .continueWatching: "Start watching something to see it here"
        case .movies: "Sync your server to load movies"
        case .tvShows: "Sync your server to load TV shows"
        }
    }

    private func resetAndLoad() {
        movies = []
        series = []
        canLoadMore = true
        loadNextPageIfNeeded()
    }

    private func loadNextPageIfNeeded() {
        guard !isLoadingPage, !reachedLoadCeiling else { return }
        switch section {
        case .continueWatching:
            guard canLoadMore else { return }
            loadNextContinueWatchingPage()
        case .movies:
            guard canLoadMore else { return }
            loadNextMoviePage()
        case .tvShows:
            guard canLoadMore else { return }
            loadNextSeriesPage()
        }
    }

    private func loadNextContinueWatchingPage() {
        isLoadingPage = true
        defer { isLoadingPage = false }
        let prefix = "\(serverPrefix)-movie-"
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.starts(with: prefix) && $0.watchProgress > 0 && $0.isWatched == false },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = movies.count
        let page = (try? modelContext.fetch(descriptor)) ?? []
        movies.append(contentsOf: page)
        canLoadMore = page.count == pageSize
    }

    private func loadNextMoviePage() {
        isLoadingPage = true
        defer { isLoadingPage = false }
        let prefix = "\(serverPrefix)-movie-"
        let offset = movies.count
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.starts(with: prefix) },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset
        let page = (try? modelContext.fetch(descriptor)) ?? []
        movies.append(contentsOf: page)
        canLoadMore = page.count == pageSize
    }

    private func loadNextSeriesPage() {
        isLoadingPage = true
        defer { isLoadingPage = false }
        let prefix = "\(serverPrefix)-series-"
        let offset = series.count
        var descriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.id.starts(with: prefix) },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = offset
        let page = (try? modelContext.fetch(descriptor)) ?? []
        series.append(contentsOf: page)
        canLoadMore = page.count == pageSize
    }
}
