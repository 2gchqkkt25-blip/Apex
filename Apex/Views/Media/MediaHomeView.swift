//
//  MediaHomeView.swift
//  Apex
//
//  Dedicated home for Jellyfin / Emby / Plex libraries — separate from IPTV.
//

import SwiftData
import SwiftUI

struct MediaHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \MediaServer.sortOrder) private var servers: [MediaServer]
    @State private var continueRail: [Movie] = []
    @State private var movieRail: [Movie] = []
    @State private var seriesRail: [Series] = []
    @State private var totalMovieCount = 0
    @State private var totalSeriesCount = 0

    @AppStorage(MediaServerSelectionStore.key) private var selectedServerID: String = ""
    @State private var syncService = MediaServerSyncService.shared
    @State private var connectKind: MediaServerKind?
    @State private var showingSettings = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @Namespace private var animationNamespace

    private var activeServer: MediaServer? {
        servers.active(for: selectedServerID)
    }

    private var serverPrefix: String? {
        activeServer?.catalogPrefix
    }

    private let railPreviewLimit = MediaServerCatalogLimits.homeRailLimit

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if servers.isEmpty {
                    emptyState
                } else if activeServer == nil {
                    ContentUnavailableView(
                        "No Server Selected",
                        systemImage: "server.rack",
                        description: Text("Choose a media server in Settings")
                    )
                } else {
                    libraryContent
                }
            }
            .navigationTitle("Media")
            .navigationDestination(for: Movie.self) { movie in
                #if os(tvOS)
                TVMovieDetailView(movie: movie)
                #else
                MediaMovieDetailView(movie: movie, server: activeServer)
                #endif
            }
            .navigationDestination(for: Series.self) { series in
                #if os(tvOS)
                TVSeriesDetailView(series: series)
                #else
                MediaSeriesDetailView(series: series, server: activeServer)
                #endif
            }
            .navigationDestination(for: MediaBrowseSection.self) { section in
                if let prefix = serverPrefix, activeServer != nil {
                    MediaLibraryBrowseView(section: section, serverPrefix: prefix)
                } else {
                    ContentUnavailableView(
                        "Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Choose a media server and try again.")
                    )
                }
            }
            .toolbar { toolbarContent }
            #if os(tvOS)
                .navigationDestination(item: $connectKind) { kind in
                    MediaConnectSheet(kind: kind, onConnected: onServerConnected)
                }
            #else
                .sheet(item: $connectKind) { kind in
                    MediaConnectSheet(kind: kind, onConnected: onServerConnected)
                }
            #endif
            #if !os(tvOS)
                .sheet(isPresented: $showingSettings) {
                    MediaServersManageSheet()
                }
            #endif
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task(id: servers.map(\.id)) {
                settleServerSelection()
            }
        }
    }

    private var emptyState: some View {
        MediaConnectEmptyState { kind in
            connectKind = kind
        }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                #if os(iOS)
                    mediaServerControls
                #endif

                if syncService.isSyncing, syncService.syncingServerID == activeServer?.id {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Syncing library…")
                                .font(.subheadline.weight(.medium))
                            if !syncService.progressDetail.isEmpty {
                                Text(syncService.progressDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !syncService.isSyncing {
                    if !continueRail.isEmpty {
                        mediaRail(
                            title: "Continue Watching",
                            browseSection: .continueWatching,
                            showAll: continueRail.count >= railPreviewLimit,
                            items: continueRail.map { .movie($0) }
                        )
                    }

                    if !movieRail.isEmpty {
                        mediaRail(
                            title: "Movies",
                            browseSection: .movies,
                            showAll: totalMovieCount > railPreviewLimit,
                            items: movieRail.map { .movie($0) }
                        )
                    }

                    if !seriesRail.isEmpty {
                        mediaRail(
                            title: "TV Shows",
                            browseSection: .tvShows,
                            showAll: totalSeriesCount > railPreviewLimit,
                            items: seriesRail.map { .series($0) }
                        )
                    }
                }

                if movieRail.isEmpty, seriesRail.isEmpty, continueRail.isEmpty, !syncService.isSyncing {
                    ContentUnavailableView(
                        "Library Empty",
                        systemImage: "film.stack",
                        description: Text(libraryEmptyHint)
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            if let server = activeServer {
                await syncServer(server)
            }
        }
        .task(id: activeServer?.id) {
            reloadCatalog()
            guard let server = activeServer else { return }
            if MediaServerCatalogLimits.autoSyncLibraryOnConnect, server.lastSyncDate == nil {
                await syncServer(server)
            }
        }
        .onChange(of: syncService.isSyncing) { _, syncing in
            guard !syncing else { return }
            Task { @MainActor in
                // Let the final sync save merge finish before repainting rails.
                try? await Task.sleep(for: .milliseconds(300))
                reloadCatalog()
            }
        }
    }

    #if os(iOS)
        private var mediaServerControls: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Media Server")
                    .font(.headline)

                HStack(spacing: 12) {
                    Menu {
                        ForEach(servers) { server in
                            Button {
                                selectServer(server)
                            } label: {
                                if server.id == activeServer?.id {
                                    Label(server.name, systemImage: "checkmark")
                                } else {
                                    Text(server.name)
                                }
                            }
                        }
                    } label: {
                        Label(activeServer?.name ?? "Choose Server", systemImage: "server.rack")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Manage", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                }

                if let server = activeServer {
                    HStack(spacing: 8) {
                        Text(server.kind.displayName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await syncServer(server) }
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(syncService.isSyncing)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    #endif

    private func reloadCatalog() {
        guard let prefix = serverPrefix else {
            continueRail = []
            movieRail = []
            seriesRail = []
            totalMovieCount = 0
            totalSeriesCount = 0
            return
        }
        let moviePrefix = "\(prefix)-movie-"
        let seriesPrefix = "\(prefix)-series-"

        var continueDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate {
                $0.id.starts(with: moviePrefix) && $0.watchProgress > 0 && $0.isWatched == false
            },
            sortBy: [SortDescriptor(\.lastWatchedDate, order: .reverse)]
        )
        continueDescriptor.fetchLimit = railPreviewLimit
        continueRail = (try? modelContext.fetch(continueDescriptor)) ?? []

        var movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.starts(with: moviePrefix) },
            sortBy: [SortDescriptor(\.name)]
        )
        movieDescriptor.fetchLimit = railPreviewLimit
        movieRail = (try? modelContext.fetch(movieDescriptor)) ?? []

        var seriesDescriptor = FetchDescriptor<Series>(
            predicate: #Predicate { $0.id.starts(with: seriesPrefix) },
            sortBy: [SortDescriptor(\.name)]
        )
        seriesDescriptor.fetchLimit = railPreviewLimit
        seriesRail = (try? modelContext.fetch(seriesDescriptor)) ?? []

        totalMovieCount = (try? modelContext.fetchCount(FetchDescriptor<Movie>(
            predicate: #Predicate { $0.id.starts(with: moviePrefix) }
        ))) ?? 0
        totalSeriesCount = (try? modelContext.fetchCount(FetchDescriptor<Series>(
            predicate: #Predicate { $0.id.starts(with: seriesPrefix) }
        ))) ?? 0
    }

    private enum MediaItem: Identifiable {
        case movie(Movie)
        case series(Series)

        var id: String {
            switch self {
            case let .movie(m): m.id
            case let .series(s): s.id
            }
        }
    }

    @ViewBuilder
    private func mediaRail(
        title: String,
        browseSection: MediaBrowseSection,
        showAll: Bool,
        items: [MediaItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    #if os(tvOS)
                    .font(.title2.weight(.bold))
                    #else
                    .font(.title3.weight(.semibold))
                    #endif

                Spacer()

                if showAll || browseSection != .continueWatching {
                    NavigationLink(value: browseSection) {
                        Text("Show All")
                            .font(.subheadline)
                    }
                    #if os(tvOS)
                        .tint(.primary)
                    #endif
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: PosterCardMetrics.railSpacing) {
                    ForEach(items) { item in
                        switch item {
                        case let .movie(movie):
                            NavigationLink(value: movie) {
                                MovieCardView(movie: movie)
                                    .matchedTransitionSourceIfAvailable(id: movie.id, in: animationNamespace)
                            }
                            .posterCardButtonStyle()
                        case let .series(series):
                            NavigationLink(value: series) {
                                SeriesCardView(series: series)
                                    .matchedTransitionSourceIfAvailable(id: series.id, in: animationNamespace)
                            }
                            .posterCardButtonStyle()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, PosterCardMetrics.railVerticalPadding)
            }
            .scrollClipDisabled()
            .frame(height: PosterCardMetrics.rowHeight)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if servers.count > 1, activeServer != nil {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(servers) { server in
                        Button {
                            selectServer(server)
                        } label: {
                            if server.id.uuidString == selectedServerID {
                                Label(server.name, systemImage: "checkmark")
                            } else {
                                Text(server.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeServer?.name ?? "Media")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }

        #if os(iOS)
        ToolbarItemGroup(placement: .topBarTrailing) {
            trailingToolbarItems
        }
        #elseif os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            trailingToolbarItems
        }
        #else
        ToolbarItemGroup(placement: .automatic) {
            trailingToolbarItems
        }
        #endif
    }

    @ViewBuilder
    private var trailingToolbarItems: some View {
        if activeServer != nil {
            Button {
                Task {
                    if let server = activeServer {
                        await syncServer(server)
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .disabled(syncService.isSyncing)
        }

        Menu {
            ForEach(MediaServerKind.allCases) { kind in
                Button {
                    connectKind = kind
                } label: {
                    Label("Add \(kind.displayName)", systemImage: kind.systemImage)
                }
            }
            #if !os(tvOS)
                Button {
                    showingSettings = true
                } label: {
                    Label("Manage Servers", systemImage: "gear")
                }
            #endif
        } label: {
            Image(systemName: "plus")
        }
    }

    private var libraryEmptyHint: LocalizedStringKey {
        #if os(tvOS)
        "Tap Sync in the toolbar. Apple TV imports about 250 titles per pass — tap Sync again until your library is complete."
        #else
        "Sync to load your media"
        #endif
    }

    private func onServerConnected(_ server: MediaServer) {
        selectServer(server)
        guard MediaServerCatalogLimits.autoSyncLibraryOnConnect else { return }
        Task { await syncServer(server) }
    }

    private func selectServer(_ server: MediaServer) {
        navigationPath = NavigationPath()
        selectedServerID = server.id.uuidString
        reloadCatalog()
    }

    private func settleServerSelection() {
        guard let server = activeServer else { return }
        if selectedServerID != server.id.uuidString {
            selectedServerID = server.id.uuidString
        }
        reloadCatalog()
    }

    private func syncServer(_ server: MediaServer) async {
        do {
            try await syncService.sync(server: server, container: modelContext.container)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MediaServersManageSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MediaServersSettingsView()
                #if os(macOS)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                #endif
                #if os(iOS) || os(macOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 600)
        #endif
    }
}
