//
//  MediaMovieDetailView.swift
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

struct MediaMovieDetailView: View {
    let movie: Movie
    let server: MediaServer?

    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @State private var playingMedia: PlayableMedia?
    @State private var isLoadingDetails = true

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DetailMetrics.sectionSpacing) {
                    DetailHero(
                        title: movie.name,
                        backdropURL: TMDBClient.backdropURL(movie.backdropPath),
                        posterFallbackURL: movie.iconURL,
                        logoURL: TMDBClient.logoURL(movie.logoPath),
                        tagline: movie.tagline,
                        metadata: metadata,
                        height: DetailMetrics.heroHeight(for: proxy.size),
                        fallbackSymbol: "film"
                    )

                    VStack(spacing: 12) {
                        PrimaryPlayButton(
                            title: movie.watchProgress > 1 && !movie.isWatched ? "Resume" : "Play",
                            isEnabled: PlayableMedia.fromMediaServerMovie(movie) != nil,
                            action: { startPlayback() }
                        )
                        if movie.watchProgress > 1, !movie.isWatched {
                            Button {
                                startPlayback(fromBeginning: true)
                            } label: {
                                Label("Start from Beginning", systemImage: "gobackward")
                                    .font(.body.weight(.medium))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, DetailMetrics.contentPadding)

                    if let plot = movie.plot, !plot.isEmpty {
                        ExpandableText(text: plot)
                            .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if !movie.externalRatings.isEmpty {
                        ExternalRatingsView(ratings: movie.externalRatings)
                            .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if let trailer = movie.youtubeTrailer, !trailer.isEmpty {
                        Button {
                            openTrailer(trailer)
                        } label: {
                            Label("Watch Trailer", systemImage: "play.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, DetailMetrics.contentPadding)
                    }

                    if !movie.orderedCast.isEmpty {
                        section(title: "Cast") {
                            CastRow(cast: movie.orderedCast)
                        }
                    }

                    if !movie.trailers.isEmpty {
                        section(title: "Videos") {
                            VideoRow(videos: movie.trailers) { video in
                                openVideo(video)
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
        .navigationTitle(movie.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
        #elseif os(tvOS)
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
        #endif
        .task(id: movie.id) {
            isLoadingDetails = true
            await MediaServerDetailEnrichment.enrichMovieIfNeeded(movie, context: modelContext)
            isLoadingDetails = false
        }
    }

    private var metadata: DetailMetadata {
        DetailMetadata(
            genre: movie.genre,
            year: movie.releaseDate,
            duration: formattedDuration,
            rating: movie.rating > 0 ? movie.rating : nil,
            contentRating: movie.contentRating
        )
    }

    private var formattedDuration: String? {
        guard let secs = movie.durationSecs, secs > 0 else { return nil }
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func section(title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(title: title)
                .padding(.horizontal, DetailMetrics.contentPadding)
            content()
        }
    }

    private func startPlayback(fromBeginning: Bool = false) {
        guard let media = PlayableMedia.fromMediaServerMovie(movie, resumeFromProgress: !fromBeginning) else { return }
        #if os(macOS)
            openWindow(id: "player", value: media)
        #else
            playingMedia = media
        #endif
    }

    private func openTrailer(_ trailer: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(trailer)") else { return }
        #if os(iOS)
            UIApplication.shared.open(url)
        #elseif os(macOS)
            NSWorkspace.shared.open(url)
        #endif
    }

    private func openVideo(_ video: TitleVideo) {
        openTrailer(video.key)
    }
}
