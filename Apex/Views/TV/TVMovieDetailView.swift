//
//  TVMovieDetailView.swift
//  Apex
//
//  tvOS movie detail screen styled after the Apple TV App Store product page
//  (Figma "TV App Asset Template"): a full-bleed backdrop hero with a
//  three-column info band, an "About" block with a ratings readout and an
//  Information card, then cast / related / collection rails. TMDB enrichment
//  is fetched lazily on appear and persisted, so revisits are instant.
//

#if os(tvOS)

    import OSLog
    import SwiftData
    import SwiftUI

    struct TVMovieDetailView: View {
        @Bindable var movie: Movie

        @Environment(\.modelContext) private var modelContext
        @Query private var playlists: [Playlist]

        @State private var playingMedia: PlayableMedia?
        @State private var similar: [HomeMediaItem] = []
        @State private var collectionMovies: [HomeMediaItem] = []
        @State private var otherSources: [HomeMediaItem] = []
        @State private var refreshToken: UUID = .init()
        @State private var isLoadingTMDB: Bool
        @State private var showYouTubeUnavailable = false

        private enum FocusTarget: Hashable { case play }
        @FocusState private var focus: FocusTarget?

        init(movie: Movie) {
            self.movie = movie
            _isLoadingTMDB = State(initialValue: false)
        }

        /// Changes when playback starts so enrichment tasks cancel and free memory.
        private var detailWorkToken: String {
            "\(movie.id)-\(playingMedia?.id ?? "idle")"
        }

        private var tmdbEnrichmentToken: String {
            "\(movie.tmdbId ?? 0)-\(playingMedia?.id ?? "idle")"
        }

        private var detailTransition: AnyTransition {
            DeviceMemoryTier.current.allowsFullScreenCrossFade ? .opacity : .identity
        }

        private var detailFadeAnimation: Animation? {
            DeviceMemoryTier.current.allowsFullScreenCrossFade ? .easeInOut(duration: 0.3) : nil
        }

        var body: some View {
            Group {
                if playingMedia != nil {
                    // Drop the hero/backdrop/rails while fullScreenCover is up — they stay
                    // in the hierarchy under the cover and hold decoded images on Apple TV HD.
                    Color.black.ignoresSafeArea()
                } else if isLoadingTMDB {
                    TVDetailLoadingView(title: movie.name)
                        .transition(detailTransition)
                } else {
                    content
                        .transition(detailTransition)
                        .onAppear { focus = .play }
                }
            }
            .background(Color.black)
            .ignoresSafeArea()
            .onChange(of: playingMedia) { _, media in
                guard media != nil else { return }
                similar = []
                collectionMovies = []
                otherSources = []
            }
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
            .alert("YouTube Unavailable", isPresented: $showYouTubeUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Install the YouTube app on your Apple TV to watch trailers.")
            }
            .task(id: detailWorkToken) {
                guard playingMedia == nil else { return }
                await enrichIfNeeded()
                guard playingMedia == nil else { return }
                await enrichMovieRatingsIfNeeded(movie, context: modelContext)
                if !movie.isMediaServerCatalogItem {
                    resolveSimilar()
                    resolveOtherSources()
                }
                withAnimation(detailFadeAnimation) {
                    isLoadingTMDB = false
                }
            }
            .onChange(of: movie.similarTMDBIds) { resolveSimilar() }
            // Covers both the first pass and a `collectionId` that background
            // indexing fills in later. A plain `.onChange { Task { … } }` kept
            // running after the user navigated back, then wrote view state from
            // a dismissed screen; `.task(id:)` is cancelled for us.
            .task(id: movie.collectionId) {
                guard !movie.isMediaServerCatalogItem else { return }
                await resolveCollection()
            }
            .onChange(of: refreshToken) { resolveSimilar() }
            // ContentIndexer may set tmdbId after the view is already displayed
            // (background indexing runs after sync). tmdbEnrichmentToken embeds
            // tmdbId, so this re-runs when it lands — and unlike a plain
            // `.onChange { Task { … } }`, SwiftUI cancels it automatically when
            // the view disappears or the id changes again, so it can't leak a
            // background Task after the user navigates away.
            .task(id: tmdbEnrichmentToken) {
                guard playingMedia == nil else { return }
                guard movie.tmdbId != nil else { return }
                // Retry once if enrichment fails (network blip, rate limit, etc.)
                for attempt in 0 ..< 2 {
                    guard !Task.isCancelled else { return }
                    if await enrichIfNeeded() { break }
                    guard attempt == 0 else { break }
                    Logger.network.info("[TMDBEnrich] Retrying enrichment for movie \(movie.id) in 5 s")
                    try? await Task.sleep(for: .seconds(5))
                }
                if movie.tmdbEnrichedAt != nil {
                    await enrichMovieRatingsIfNeeded(movie, context: modelContext)
                    if !movie.isMediaServerCatalogItem {
                        resolveSimilar()
                        await resolveCollection()
                        resolveOtherSources()
                    }
                }
            }
        }

        private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TVDetailMetrics.sectionSpacing) {
                    hero

                    aboutSection

                    if !movie.orderedCast.isEmpty {
                        TVRail(title: "Cast", items: movie.orderedCast) { member in
                            TVCastCard(member: member)
                        }
                    }

                    if !movie.trailers.isEmpty {
                        TVRail(title: "Videos", items: movie.trailers) { video in
                            TVVideoCard(video: video) {
                                openVideo(video) { showYouTubeUnavailable = true }
                            }
                        }
                    }

                    if !similar.isEmpty {
                        TVRail(title: "You May Also Like", items: similar) { item in
                            posterLink(for: item)
                        }
                    }

                    if !collectionMovies.isEmpty, let name = movie.collectionName {
                        TVRail(title: "\(name) Collection", items: collectionMovies) { item in
                            posterLink(for: item)
                        }
                    }

                    if !otherSources.isEmpty {
                        TVRail(title: "Other Sources", items: otherSources) { item in
                            posterLink(for: item)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollClipDisabled()
            .defaultFocus($focus, .play)
        }

        // MARK: - Hero

        private var hero: some View {
            TVDetailHero(
                title: movie.name,
                backdropURL: TMDBClient.backdropURL(movie.backdropPath),
                posterFallbackURL: movie.iconURL,
                logoURL: TMDBClient.logoURL(movie.logoPath),
                tagline: movie.tagline,
                rating: rating5,
                badge: movie.contentRating,
                metaItems: heroMetaItems,
                fallbackSymbol: "film"
            ) {
                VStack(spacing: 16) {
                    TVPlayButton(
                        title: movie.watchProgress > 1 ? "Resume" : "Play",
                        isEnabled: canPlayMovie,
                        action: startPlayback
                    )
                    .focused($focus, equals: .play)

                    if movie.watchProgress > 1 {
                        TVPlayButton(
                            title: "Start from Beginning",
                            systemImage: "gobackward",
                            isEnabled: canPlayMovie,
                            action: startPlaybackFromBeginning
                        )
                    }

                    HStack(spacing: 18) {
                        TVSecondaryActionButton(
                            title: movie.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: movie.isFavorite ? "heart.fill" : "heart",
                            action: toggleFavorite
                        )

                        TVSecondaryActionButton(
                            title: movie.isWatched ? "Mark as Unwatched" : "Mark as Watched",
                            systemImage: movie.isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                            action: toggleWatched
                        )
                    }
                }
            }
        }

        // MARK: - About / ratings / information

        private var aboutSection: some View {
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 22) {
                    TVSectionHeader(title: "About")
                    if let plot = movie.plot, !plot.isEmpty {
                        TVAboutText(text: plot)
                    } else {
                        Text("No description available.")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if !movie.externalRatings.isEmpty {
                        TVExternalRatingsView(ratings: movie.externalRatings)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !informationItems.isEmpty {
                    TVInfoCard(title: "Information", items: informationItems)
                        .frame(width: 560)
                }
            }
            .padding(.horizontal, TVDetailMetrics.horizontalInset)
            .focusSection()
        }

        // MARK: - Rail items

        @ViewBuilder
        private func posterLink(for item: HomeMediaItem) -> some View {
            switch item {
            case let .movie(movie):
                NavigationLink(value: movie) {
                    TVPosterCard(title: item.title, imageURL: item.imageURL, rating: item.posterRating, isFavorite: movie.isFavorite)
                }
                .buttonStyle(TVCardButtonStyle())
            case let .series(series):
                NavigationLink(value: series) {
                    TVPosterCard(title: item.title, imageURL: item.imageURL, rating: item.posterRating, isFavorite: series.isFavorite)
                }
                .buttonStyle(TVCardButtonStyle())
            case .live:
                EmptyView()
            }
        }

        // MARK: - Derived data

        /// A 0…5 rating, preferring TMDB's 5-based value, falling back to the
        /// 10-based rating halved.
        private var rating5: Double {
            if movie.rating5Based > 0 { return min(movie.rating5Based, 5) }
            if movie.rating > 0 { return min(movie.rating / 2, 5) }
            return 0
        }

        private var heroMetaItems: [TVMetaItem] {
            var items: [TVMetaItem] = []
            if let date = DetailFormat.date(from: movie.releaseDate)
                ?? DetailFormat.year(from: movie.releaseDate)
            {
                items.append(TVMetaItem(label: "Released", value: date))
            }
            if let genre = movie.genre, !genre.isEmpty {
                items.append(TVMetaItem(label: "Genre", value: shortGenre(genre)))
            }
            if let duration = DetailFormat.duration(movie.durationSecs) {
                items.append(TVMetaItem(label: "Runtime", value: duration))
            }
            return items
        }

        private var informationItems: [TVMetaItem] {
            var items: [TVMetaItem] = []
            items.append(TVMetaItem(label: "Playlist Title", value: movie.name))
            if let director = movie.director, !director.isEmpty {
                items.append(TVMetaItem(label: "Director", value: director))
            }
            if let genre = movie.genre, !genre.isEmpty {
                items.append(TVMetaItem(label: "Genre", value: genre))
            }
            if let actors = movie.actors, !actors.isEmpty, movie.orderedCast.isEmpty {
                items.append(TVMetaItem(label: "Cast", value: actors))
            }
            if let cert = movie.contentRating, !cert.isEmpty {
                items.append(TVMetaItem(label: "Rated", value: cert))
            }
            return items
        }

        private func shortGenre(_ genre: String) -> String {
            genre.split(separator: ",").prefix(2)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: ", ")
        }

        /// The playlist this movie actually belongs to (ids are `"<playlistUUID>-…"`),
        /// so playback uses the correct credentials. Falls back to the first.
        private var moviePlaylist: Playlist? {
            playlists.first { movie.id.hasPrefix($0.id.uuidString) } ?? playlists.first
        }

        private var canPlayMovie: Bool {
            if movie.isMediaServerCatalogItem {
                return PlayableMedia.fromMediaServerMovie(movie) != nil
            }
            return moviePlaylist != nil
        }

        // MARK: - Enrichment

        /// Resolves a TMDB id by title when the provider didn't supply one.
        private func resolveTMDBIdIfNeeded() async -> Int? {
            if let tmdbId = movie.tmdbId { return tmdbId }
            guard TMDBClient.shared.isConfigured else { return nil }
            let query = ContentIndexText.searchQuery(for: movie.name)
            let year = ContentIndexText.year(fromReleaseDate: movie.releaseDate) ?? query.year
            let client = TMDBClient.shared
            if let id = try? await client.searchMovieID(query: query.title, year: year) {
                movie.tmdbId = id
                try? modelContext.save()
                return id
            }
            guard year != nil else { return nil }
            if let id = try? await client.searchMovieID(query: query.title, year: nil) {
                movie.tmdbId = id
                try? modelContext.save()
                return id
            }
            return nil
        }

        @discardableResult
        private func enrichIfNeeded() async -> Bool {
            if movie.isMediaServerCatalogItem {
                await MediaServerDetailEnrichment.enrichMovieIfNeeded(movie, context: modelContext)
                if movie.tmdbEnrichedAt != nil {
                    refreshToken = UUID()
                    return true
                }
                return movie.tmdbId != nil
            }
            guard let tmdbId = await resolveTMDBIdIfNeeded() else { return false }
            if let enrichedAt = movie.tmdbEnrichedAt,
               Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
            {
                return true // already enriched recently
            }
            let manager = ContentSyncManager(modelContainer: modelContext.container)
            // Fetch off-thread, then apply on the view's own context — same pattern
            // as MovieDetailView on iOS. Background-context enrichment auto-merges on
            // iOS but tvOS detail screens often stay stale until navigating away.
            guard let details = try? await manager.fetchTMDBMovieDetails(tmdbId: tmdbId) else {
                return false
            }
            applyMovieDetails(details, to: movie, context: modelContext)
            try? modelContext.save()
            if movie.tmdbEnrichedAt != nil {
                refreshToken = UUID()
                return true
            }
            return false
        }

        private func resolveSimilar() {
            let ids = movie.similarTMDBIds
            guard !ids.isEmpty else { similar = []; return }

            let playlistPrefix = movie.id.components(separatedBy: "-movie-").first
            func owned(_ id: String) -> Bool {
                guard let prefix = playlistPrefix else { return true }
                return id.hasPrefix(prefix)
            }

            var resolved: [HomeMediaItem] = []
            for tmdbId in ids {
                let movieMatches = (try? modelContext.fetch(
                    FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
                )) ?? []
                if let match = movieMatches.first(where: { owned($0.id) && $0.id != movie.id }) {
                    resolved.append(.movie(match))
                    continue
                }
                let seriesMatches = (try? modelContext.fetch(
                    FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
                )) ?? []
                if let match = seriesMatches.first(where: { owned($0.id) }) {
                    resolved.append(.series(match))
                }
            }
            similar = Array(resolved.prefix(12))
        }

        private func resolveCollection() async {
            guard let collectionId = movie.collectionId else {
                collectionMovies = []
                return
            }

            let manager = ContentSyncManager(modelContainer: modelContext.container)
            let partIDs: [Int]
            do {
                partIDs = try await manager.fetchTMDBCollectionMovieIDs(collectionId: collectionId)
            } catch {
                collectionMovies = []
                return
            }

            let playlistPrefix = movie.id.components(separatedBy: "-movie-").first
            func owned(_ id: String) -> Bool {
                guard let prefix = playlistPrefix else { return true }
                return id.hasPrefix(prefix)
            }

            var resolved: [HomeMediaItem] = []
            for tmdbId in partIDs {
                let movieMatches = (try? modelContext.fetch(
                    FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
                )) ?? []
                if let match = movieMatches.first(where: { owned($0.id) && $0.id != movie.id }) {
                    resolved.append(.movie(match))
                }
            }
            collectionMovies = resolved
        }

        private func resolveOtherSources() {
            otherSources = OtherSources.resolve(for: movie, in: modelContext)
        }

        // MARK: - Actions

        private func startPlayback() {
            if movie.isMediaServerCatalogItem {
                guard let media = PlayableMedia.fromMediaServerMovie(movie) else { return }
                if ExternalPlayback.open(media) { return }
                playingMedia = media
                return
            }
            guard let playlist = moviePlaylist,
                  let media = PlayableMedia.from(movie: movie, playlist: playlist) else { return }
            if ExternalPlayback.open(media) { return }
            playingMedia = media
        }

        private func startPlaybackFromBeginning() {
            if movie.isMediaServerCatalogItem {
                guard let media = PlayableMedia.fromMediaServerMovie(movie, resumeFromProgress: false) else { return }
                if ExternalPlayback.open(media) { return }
                playingMedia = media
                return
            }
            guard let playlist = moviePlaylist,
                  let media = PlayableMedia.from(movie: movie, playlist: playlist, resumeFromProgress: false) else { return }
            if ExternalPlayback.open(media) { return }
            playingMedia = media
        }

        private func toggleFavorite() {
            movie.isFavorite.toggle()
            movie.addedToWatchlistDate = movie.isFavorite ? Date() : nil
        }

        private func toggleWatched() {
            movie.isWatched.toggle()
            if movie.isWatched {
                movie.watchProgress = Double(movie.durationSecs ?? 0)
            }
            TraktService.shared.syncWatched(movie: movie, watched: movie.isWatched)
        }
    }

    #Preview("TV Movie") {
        let container = previewContainer()
        let movie = PreviewData.sampleMovie
        movie.plot = "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers."
        movie.genre = "Action, Sci-Fi"
        movie.releaseDate = "1999-03-31"
        movie.durationSecs = 8160
        movie.director = "Lana Wachowski, Lilly Wachowski"
        movie.backdropPath = "/fNG7i7RqM1T0sP1vQmRIqRnW.jpg"
        movie.tagline = "Welcome to the Real World."
        movie.contentRating = "R"
        return NavigationStack {
            TVMovieDetailView(movie: movie)
        }
        .modelContainer(container)
    }

#endif
