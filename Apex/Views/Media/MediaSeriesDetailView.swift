//
//  MediaSeriesDetailView.swift
//  Apex
//

import SwiftData
import SwiftUI
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

struct MediaSeriesDetailView: View {
    let series: Series
    let server: MediaServer?

    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @State private var playingMedia: PlayableMedia?
    @State private var isLoadingEpisodes = false
    @State private var isLoadingDetails = true
    @State private var loadError: String?

    private var episodes: [Episode] {
        series.episodes.sorted {
            if $0.seasonNum != $1.seasonNum { return $0.seasonNum < $1.seasonNum }
            return $0.episodeNum < $1.episodeNum
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DetailMetrics.sectionSpacing) {
                    DetailHero(
                        title: series.name,
                        backdropURL: TMDBClient.backdropURL(series.backdropPath),
                        posterFallbackURL: series.cover.flatMap { URL(string: $0) },
                        logoURL: TMDBClient.logoURL(series.logoPath),
                        tagline: series.tagline,
                        metadata: metadata,
                        height: DetailMetrics.heroHeight(for: proxy.size),
                        fallbackSymbol: "tv"
                    )

                    if let plot = series.plot, !plot.isEmpty {
                        ExpandableText(text: plot)
                            .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if !series.externalRatings.isEmpty {
                        ExternalRatingsView(ratings: series.externalRatings)
                            .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if let trailer = series.youtubeTrailer, !trailer.isEmpty {
                        Button {
                            openTrailer(trailer)
                        } label: {
                            Label("Watch Trailer", systemImage: "play.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if !series.orderedCast.isEmpty {
                        section(title: "Cast") {
                            CastRow(cast: series.orderedCast)
                        }
                    }

                    section(title: "Episodes") {
                        if isLoadingEpisodes {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading episodes…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, DetailMetrics.contentPadding)
                        } else if episodes.isEmpty {
                            Text(loadError ?? "No episodes loaded yet.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DetailMetrics.contentPadding)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(episodes) { episode in
                                    Button {
                                        startPlayback(for: episode)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text("S\(episode.seasonNum) E\(episode.episodeNum)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 64, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(episode.title)
                                                    .font(.body)
                                                    .lineLimit(1)
                                                if let plot = episode.plot, !plot.isEmpty {
                                                    Text(plot)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            if episode.isWatched {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Image(systemName: "play.circle")
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                        .padding(.horizontal, DetailMetrics.contentPadding)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, DetailMetrics.contentPadding)
                                }
                            }
                        }
                    }

                    if isLoadingDetails {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading details…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, DetailMetrics.contentPadding)
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle(series.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: series.id) {
            isLoadingDetails = true
            await MediaServerDetailEnrichment.enrichSeriesIfNeeded(series, context: modelContext)
            isLoadingDetails = false
        }
        .task(id: series.id) {
            await loadEpisodesIfNeeded()
        }
        #if os(iOS) || os(tvOS)
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
        #endif
    }

    private var metadata: DetailMetadata {
        DetailMetadata(
            genre: series.genre,
            year: series.releaseDate,
            seasonInfo: episodes.isEmpty ? nil : "\(Set(episodes.map(\.seasonNum)).count) seasons",
            rating: series.rating.flatMap(Double.init),
            contentRating: series.contentRating
        )
    }

    private func section(title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: title)
                .padding(.horizontal, DetailMetrics.contentPadding)
            content()
        }
    }

    private func startPlayback(for episode: Episode) {
        guard let media = PlayableMedia.fromMediaServerEpisode(episode) else { return }
        #if os(macOS)
            openWindow(id: "player", value: media)
        #else
            playingMedia = media
        #endif
    }

    private func loadEpisodesIfNeeded() async {
        guard episodes.isEmpty, let server else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            try await MediaServerSyncService.shared.loadEpisodes(
                for: series,
                server: server,
                container: modelContext.container
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func openTrailer(_ trailer: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(trailer)") else { return }
        #if os(iOS)
            UIApplication.shared.open(url)
        #elseif os(macOS)
            NSWorkspace.shared.open(url)
        #endif
    }
}
