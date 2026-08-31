//
//  TVSeriesDetailView.swift
//  Apex
//
//  tvOS series detail screen. Shares the hero / about / ratings / cast / related
//  layout with TVMovieDetailView, adding a focusable season selector and a
//  horizontal rail of large episode cards (the prominent scrolled content, per
//  the Figma template). Episodes and TMDB enrichment load lazily on appear.
//

#if os(tvOS)

    import OSLog
    import SwiftData
    import SwiftUI

    struct TVSeriesDetailView: View {
        @Bindable var series: Series

        @Environment(\.modelContext) private var modelContext
        @Query private var playlists: [Playlist]
        @Query(sort: \MediaServer.sortOrder) private var mediaServers: [MediaServer]

        @State private var selectedSeason: Int = 1
        @State private var isLoadingEpisodes = false
        @State private var playingMedia: PlayableMedia?
        @State private var similar: [HomeMediaItem] = []
        @State private var otherSources: [HomeMediaItem] = []
        @State private var refreshToken: UUID = .init()
        @State private var isLoadingTMDB: Bool
        @State private var showYouTubeUnavailable = false

        private enum FocusTarget: Hashable {
            case play
            case season(Int)
            case episode(String)
        }

        @FocusState private var focus: FocusTarget?

        init(series: Series) {
            self.series = series
            _isLoadingTMDB = State(initialValue: false)
        }

        private var detailWorkToken: String {
            "\(series.id)-\(playingMedia?.id ?? "idle")"
        }

        private var tmdbEnrichmentToken: String {
            "\(series.tmdbId ?? 0)-\(playingMedia?.id ?? "idle")"
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
                    Color.black.ignoresSafeArea()
                } else if isLoadingTMDB {
                    TVDetailLoadingView(title: series.name)
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
                withAnimation(detailFadeAnimation) {
                    isLoadingTMDB = false
                }
                await loadEpisodesIfNeeded()
                guard playingMedia == nil else { return }
                maybeAutoplay()
                await enrichIfNeeded()
                guard playingMedia == nil else { return }
                await enrichSeriesRatingsIfNeeded(series, context: modelContext)
                if !series.isMediaServerCatalogItem {
                    resolveSimilar()
                    resolveOtherSources()
                }
                focus = .play
            }
            .onChange(of: series.similarTMDBIds) { resolveSimilar() }
            .onChange(of: refreshToken) { resolveSimilar() }
            // ContentIndexer may set tmdbId after the view is already displayed
            // (background indexing runs after sync). tmdbEnrichmentToken embeds
            // tmdbId, so this re-runs when it lands — and unlike a plain
            // `.onChange { Task { … } }`, SwiftUI cancels it automatically when
            // the view disappears or the id changes again, so it can't leak a
            // background Task after the user navigates away.
            .task(id: tmdbEnrichmentToken) {
                guard playingMedia == nil else { return }
                guard series.tmdbId != nil else { return }
                for attempt in 0 ..< 2 {
                    guard !Task.isCancelled else { return }
                    if await enrichIfNeeded() { break }
                    guard attempt == 0 else { break }
                    Logger.network.info("[TMDBEnrich] Retrying enrichment for series \(series.id) in 5 s")
                    try? await Task.sleep(for: .seconds(5))
                }
                if series.tmdbEnrichedAt != nil {
                    await enrichSeriesRatingsIfNeeded(series, context: modelContext)
                    if !series.isMediaServerCatalogItem {
                        resolveSimilar()
                        resolveOtherSources()
                    }
                }
            }
        }

        private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TVDetailMetrics.sectionSpacing) {
                    hero

                    episodesSection

                    aboutSection

                    if !series.orderedCast.isEmpty {
                        TVRail(title: "Cast", items: series.orderedCast) { member in
                            TVCastCard(member: member)
                        }
                    }

                    if !series.trailers.isEmpty {
                        TVRail(title: "Videos", items: series.trailers) { video in
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
                title: series.name,
                backdropURL: TMDBClient.backdropURL(series.backdropPath),
                posterFallbackURL: URL(string: series.cover ?? ""),
                logoURL: TMDBClient.logoURL(series.logoPath),
                tagline: series.tagline,
                rating: rating5,
                badge: series.contentRating,
                metaItems: heroMetaItems,
                fallbackSymbol: "tv"
            ) {
                TVPlayButton(
                    title: playTitle,
                    isEnabled: canPlaySeries,
                    action: { if let episode = nextEpisode { playEpisode(episode) } }
                )
                .focused($focus, equals: .play)

                HStack(spacing: 18) {
                    TVSecondaryActionButton(
                        title: series.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: series.isFavorite ? "heart.fill" : "heart",
                        action: toggleFavorite
                    )
                    Spacer(minLength: 0)
                }
            }
        }

        // MARK: - Episodes

        private var episodesSection: some View {
            VStack(alignment: .leading, spacing: 22) {
                TVSectionHeader(title: "Episodes")
                    .padding(.horizontal, TVDetailMetrics.horizontalInset)

                if availableSeasons.count > 1 {
                    seasonSelector
                }

                if series.episodes.isEmpty {
                    episodesPlaceholder
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: TVDetailMetrics.railSpacing) {
                            ForEach(seasonEpisodes) { episode in
                                TVEpisodeCard(
                                    episode: episode,
                                    onPlay: { playEpisode(episode) },
                                    onPlayFromBeginning: { playEpisodeFromBeginning(episode) },
                                    onToggleWatched: { toggleWatched(episode) },
                                    onMarkPreviousWatched: { markPreviousWatched(episode) },
                                    onMarkFollowingUnwatched: { markFollowingUnwatched(episode) }
                                )
                                .focused($focus, equals: .episode(episode.id))
                            }
                        }
                        .padding(.horizontal, TVDetailMetrics.horizontalInset)
                        .padding(.vertical, 24)
                    }
                    .scrollClipDisabled()
                    // When focus moves INTO the rail (e.g. down from Play), the
                    // enclosing focus section would otherwise pick the card
                    // nearest the SECTION's center — mid-rail, not the first
                    // episode. `.userInitiated` re-applies this default on
                    // user-driven entry, not just on appearance.
                    .defaultFocus(
                        $focus,
                        .episode(seasonEpisodes.first?.id ?? ""),
                        priority: .userInitiated
                    )
                }
            }
            .focusSection()
        }

        private var seasonSelector: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(availableSeasons, id: \.self) { season in
                        Button("Season \(season)") {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedSeason = season }
                        }
                        .buttonStyle(TVChipButtonStyle(isSelected: season == selectedSeason))
                        .focused($focus, equals: .season(season))
                    }
                }
                .padding(.horizontal, TVDetailMetrics.horizontalInset)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .focusSection()
            // Entering the selector lands on the CURRENT season's chip, not
            // whichever chip the focus section's center-pick would choose.
            .defaultFocus($focus, .season(selectedSeason), priority: .userInitiated)
        }

        @ViewBuilder
        private var episodesPlaceholder: some View {
            if isLoadingEpisodes {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading episodes…")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 16) {
                    Text("No episodes available")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Retry") { Task { await loadEpisodes() } }
                        .buttonStyle(TVChipButtonStyle(isSelected: false))
                }
            }
        }

        // MARK: - About / ratings / information

        private var aboutSection: some View {
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 22) {
                    TVSectionHeader(title: "About")
                    if let plot = series.plot, !plot.isEmpty {
                        TVAboutText(text: plot)
                    } else {
                        Text("No description available.")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if !series.externalRatings.isEmpty {
                        TVExternalRatingsView(ratings: series.externalRatings)
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

        private var rating5: Double {
            if let raw = series.rating5Based, let value = Double(raw), value > 0 { return min(value, 5) }
            if let raw = series.rating, let value = Double(raw), value > 0 { return min(value / 2, 5) }
            return 0
        }

        private var heroMetaItems: [TVMetaItem] {
            var items: [TVMetaItem] = []
            if let date = DetailFormat.date(from: series.releaseDate)
                ?? DetailFormat.year(from: series.releaseDate)
            {
                items.append(TVMetaItem(label: "Released", value: date))
            }
            if let genre = series.genre, !genre.isEmpty {
                items.append(TVMetaItem(label: "Genre", value: shortGenre(genre)))
            }
            if !availableSeasons.isEmpty {
                items.append(TVMetaItem(label: "Seasons", value: seasonCountLabel))
            }
            return items
        }

        private var informationItems: [TVMetaItem] {
            var items: [TVMetaItem] = []
            items.append(TVMetaItem(label: "Playlist Title", value: series.name))
            if let director = series.director, !director.isEmpty {
                items.append(TVMetaItem(label: "Creator", value: director))
            }
            if let genre = series.genre, !genre.isEmpty {
                items.append(TVMetaItem(label: "Genre", value: genre))
            }
            if let cast = series.cast, !cast.isEmpty, series.orderedCast.isEmpty {
                items.append(TVMetaItem(label: "Cast", value: cast))
            }
            if let cert = series.contentRating, !cert.isEmpty {
                items.append(TVMetaItem(label: "Rated", value: cert))
            }
            return items
        }

        private func shortGenre(_ genre: String) -> String {
            genre.split(separator: ",").prefix(2)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: ", ")
        }

        private var seasonCountLabel: String {
            availableSeasons.count == 1 ? "1 Season" : "\(availableSeasons.count) Seasons"
        }

        private var availableSeasons: [Int] {
            Set(series.episodes.map(\.seasonNum)).sorted()
        }

        private func determineDefaultSeason() -> Int {
            let seasons = availableSeasons
            guard !seasons.isEmpty else { return 1 }

            // Open on the season of the furthest point reached in the series, so
            // progress in a later season always wins over progress in an earlier
            // one — regardless of which was watched more recently.
            let target = SeriesResume.episode(in: series)
            if let target, seasons.contains(target.seasonNum) {
                return target.seasonNum
            }

            return seasons.first ?? 1
        }

        private var seasonEpisodes: [Episode] {
            series.episodes
                .filter { $0.seasonNum == selectedSeason }
                .sorted { $0.episodeNum < $1.episodeNum }
        }

        /// The furthest partially-watched (not completed) episode in the
        /// series, ordered by season then episode.
        private var furthestInProgressEpisode: Episode? {
            series.episodes
                .filter { $0.watchProgress > 1 && !$0.isWatched }
                .max { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) }
        }

        /// The furthest episode with any watch progress, including completed.
        private var furthestProgressEpisode: Episode? {
            series.episodes
                .filter { $0.watchProgress > 0 || $0.isWatched }
                .max { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) }
        }

        /// The furthest fully-watched episode in the series.
        private var furthestWatchedEpisode: Episode? {
            series.episodes
                .filter(\.isWatched)
                .max { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) }
        }

        private var nextEpisode: Episode? {
            SeriesResume.episode(in: series)
        }

        private var playTitle: LocalizedStringKey {
            guard let episode = nextEpisode else { return "Play" }
            if !episode.isWatched, episode.watchProgress > 1 {
                return "Resume S\(episode.seasonNum) E\(episode.episodeNum)"
            }
            return "Play S\(episode.seasonNum) E\(episode.episodeNum)"
        }

        private var seriesPlaylist: Playlist? {
            playlists.first { series.id.hasPrefix($0.id.uuidString) } ?? playlists.first
        }

        private var mediaServer: MediaServer? {
            guard let parsed = MediaServerIdentity.parseCatalogID(series.id) else { return nil }
            return mediaServers.first { $0.id == parsed.serverUUID }
        }

        private var canPlaySeries: Bool {
            guard let episode = nextEpisode else { return false }
            if series.isMediaServerCatalogItem {
                return PlayableMedia.fromMediaServerEpisode(episode) != nil
            }
            return seriesPlaylist != nil
        }

        // MARK: - Loading & enrichment

        private func loadEpisodesIfNeeded() async {
            if series.episodes.isEmpty {
                SeriesResume.attachStoredEpisodes(to: series, in: modelContext)
            }
            if series.episodes.isEmpty {
                await loadEpisodes()
            }
            selectedSeason = determineDefaultSeason()
        }

        private func loadEpisodes() async {
            guard !isLoadingEpisodes else { return }

            if series.isMediaServerCatalogItem {
                guard let server = mediaServer else { return }
                isLoadingEpisodes = true
                defer { isLoadingEpisodes = false }
                do {
                    try await MediaServerSyncService.shared.loadEpisodes(
                        for: series,
                        server: server,
                        container: modelContext.container
                    )
                } catch {
                    Logger.network.error("Media server episode load failed: \(error.localizedDescription, privacy: .public)")
                }
                selectedSeason = determineDefaultSeason()
                return
            }

            guard let playlist = seriesPlaylist else { return }
            isLoadingEpisodes = true
            defer { isLoadingEpisodes = false }
            let manager = ContentSyncManager(modelContainer: modelContext.container)
            let parsed = await (try? manager.fetchEpisodes(
                seriesId: series.seriesId,
                seriesElementId: series.id,
                playlist: playlist
            )) ?? []
            // Insert through the view's own context so the episodes relationship
            // updates reactively. Batched saves + yields keep the main thread
            // responsive even for series with hundreds of episodes (tvOS watchdog).
            await series.insertEpisodes(parsed, into: modelContext)
            selectedSeason = determineDefaultSeason()
        }

        @discardableResult
        private func resolveTMDBIdIfNeeded() async -> Int? {
            if let tmdbId = series.tmdbId { return tmdbId }
            guard TMDBClient.shared.isConfigured else { return nil }
            let query = ContentIndexText.searchQuery(for: series.name)
            let year = ContentIndexText.year(fromReleaseDate: series.releaseDate) ?? query.year
            let client = TMDBClient.shared
            if let id = try? await client.searchTVID(query: query.title, year: year) {
                series.tmdbId = id
                try? modelContext.save()
                return id
            }
            guard year != nil else { return nil }
            if let id = try? await client.searchTVID(query: query.title, year: nil) {
                series.tmdbId = id
                try? modelContext.save()
                return id
            }
            return nil
        }

        @discardableResult
        private func enrichIfNeeded() async -> Bool {
            if series.isMediaServerCatalogItem {
                await MediaServerDetailEnrichment.enrichSeriesIfNeeded(series, context: modelContext)
                if series.tmdbEnrichedAt != nil {
                    refreshToken = UUID()
                    return true
                }
                return series.tmdbId != nil
            }
            guard let tmdbId = await resolveTMDBIdIfNeeded() else { return false }
            if let enrichedAt = series.tmdbEnrichedAt,
               Date().timeIntervalSince(enrichedAt) < 14 * 24 * 3600
            {
                return true // already enriched recently
            }
            let manager = ContentSyncManager(modelContainer: modelContext.container)
            guard let details = try? await manager.fetchTMDBTVDetails(tmdbId: tmdbId) else {
                return false
            }
            applySeriesDetails(details, to: series, context: modelContext)
            try? modelContext.save()
            if series.tmdbEnrichedAt != nil {
                refreshToken = UUID()
                return true
            }
            return false
        }
    }

    // MARK: - Actions & related titles

    private extension TVSeriesDetailView {
        func playEpisode(_ episode: Episode) {
            let media: PlayableMedia?
            if series.isMediaServerCatalogItem {
                media = PlayableMedia.fromMediaServerEpisode(episode)
            } else if let playlist = seriesPlaylist {
                media = PlayableMedia.from(episode: episode, playlist: playlist)
            } else {
                media = nil
            }
            guard let media else { return }
            if ExternalPlayback.open(media) { return }
            playingMedia = media
        }

        func maybeAutoplay() {
            guard DeepLinkAutoplay.consume(seriesTMDBId: series.tmdbId),
                  let episode = nextEpisode
            else { return }
            playEpisode(episode)
        }

        func playEpisodeFromBeginning(_ episode: Episode) {
            let media: PlayableMedia?
            if series.isMediaServerCatalogItem {
                media = PlayableMedia.fromMediaServerEpisode(episode, resumeFromProgress: false)
            } else if let playlist = seriesPlaylist {
                media = PlayableMedia.from(episode: episode, playlist: playlist, resumeFromProgress: false)
            } else {
                media = nil
            }
            guard let media else { return }
            if ExternalPlayback.open(media) { return }
            playingMedia = media
        }

        func toggleFavorite() {
            series.isFavorite.toggle()
            series.addedToWatchlistDate = series.isFavorite ? Date() : nil
        }

        func toggleWatched(_ episode: Episode) {
            episode.setWatched(!episode.isWatched)
            TraktService.shared.syncWatched(episode: episode, watched: episode.isWatched)
            try? modelContext.save()
        }

        func markPreviousWatched(_ episode: Episode) {
            episode.markEarlierEpisodesWatched()
            try? modelContext.save()
        }

        func markFollowingUnwatched(_ episode: Episode) {
            episode.markLaterEpisodesUnwatched()
            try? modelContext.save()
        }

        func resolveSimilar() {
            let ids = series.similarTMDBIds
            guard !ids.isEmpty else { similar = []; return }

            let playlistPrefix = series.id.components(separatedBy: "-series-").first
            func owned(_ id: String) -> Bool {
                guard let prefix = playlistPrefix else { return true }
                return id.hasPrefix(prefix)
            }

            var resolved: [HomeMediaItem] = []
            for tmdbId in ids {
                let seriesMatches = (try? modelContext.fetch(
                    FetchDescriptor<Series>(predicate: #Predicate { $0.tmdbId == tmdbId })
                )) ?? []
                if let match = seriesMatches.first(where: { owned($0.id) && $0.id != series.id }) {
                    resolved.append(.series(match))
                    continue
                }
                let movieMatches = (try? modelContext.fetch(
                    FetchDescriptor<Movie>(predicate: #Predicate { $0.tmdbId == tmdbId })
                )) ?? []
                if let match = movieMatches.first(where: { owned($0.id) }) {
                    resolved.append(.movie(match))
                }
            }
            similar = Array(resolved.prefix(12))
        }

        func resolveOtherSources() {
            otherSources = OtherSources.resolve(for: series, in: modelContext)
        }
    }

    // MARK: - Season chip style

    /// A focusable selectable pill used by the season selector and small
    /// secondary actions.
    struct TVChipButtonStyle: ButtonStyle {
        var isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(configuration: configuration, isSelected: isSelected)
        }

        struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let isSelected: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                let highlighted = isFocused || isSelected
                configuration.label
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(highlighted ? .black : .white)
                    .padding(.horizontal, 28)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fill)
                    )
                    .scaleEffect(isFocused ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.18), value: isFocused)
                    .animation(.easeOut(duration: 0.18), value: isSelected)
            }

            private var fill: AnyShapeStyle {
                if isFocused { return AnyShapeStyle(.white) }
                if isSelected { return AnyShapeStyle(.white.opacity(0.85)) }
                return GlassFallback.regular
            }
        }
    }

    #Preview("TV Series") {
        let container = previewContainer()
        let series = PreviewData.sampleSeries
        series.backdropPath = "/abc123backdrop.jpg"
        series.tagline = "All Hail the King."
        series.contentRating = "TV-MA"
        return NavigationStack {
            TVSeriesDetailView(series: series)
        }
        .modelContainer(container)
    }

#endif
