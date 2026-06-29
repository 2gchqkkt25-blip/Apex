//
//  HomeRows.swift
//  Apex
//
//  The horizontal rails on the Home screen (Recently Watched, Trending, etc.)
//  and the poster cards they contain. Extracted from `HomeView` to keep that
//  file focused on data loading and screen composition.
//

import SwiftUI

// MARK: - Row

struct HomeRow: View {
    let title: LocalizedStringKey
    let items: [HomeMediaItem]
    let onPlayLive: (LiveStream) -> Void
    /// When set, each card gains a "Remove from Recently Watched" context menu.
    /// Only the Recently Watched row passes this; the others leave it nil.
    var onRemove: ((HomeMediaItem) -> Void)?
    /// When set, each card gains up/down vote actions. Only the "For You" row
    /// passes this; the others leave it nil.
    var onVote: ((HomeMediaItem, RecommendationVote) -> Void)?
    var animationNamespace: Namespace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: PosterCardMetrics.railSpacing) {
                    ForEach(items) { item in
                        HomeItemCell(item: item, onPlayLive: onPlayLive, onRemove: onRemove, onVote: onVote, animationNamespace: animationNamespace)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, PosterCardMetrics.railVerticalPadding)
            }
            .scrollClipDisabled()
            .frame(height: PosterCardMetrics.rowHeight)
        }
    }
}

private struct HomeItemCell: View {
    let item: HomeMediaItem
    let onPlayLive: (LiveStream) -> Void
    var onRemove: ((HomeMediaItem) -> Void)?
    var onVote: ((HomeMediaItem, RecommendationVote) -> Void)?
    var animationNamespace: Namespace.ID?

    var body: some View {
        Group {
            switch item {
            case let .movie(movie):
                NavigationLink(value: movie) {
                    HomePosterCard(
                        title: item.title,
                        imageURL: item.imageURL,
                        progress: item.progress,
                        rating: item.posterRating
                    )
                        .matchedTransitionSourceIfAvailable(id: movie.id, in: animationNamespace)
                }
                .posterCardButtonStyle()
            case let .series(series):
                NavigationLink(value: series) {
                    HomePosterCard(
                        title: item.title,
                        imageURL: item.imageURL,
                        progress: item.progress,
                        rating: item.posterRating
                    )
                        .matchedTransitionSourceIfAvailable(id: series.id, in: animationNamespace)
                }
                .posterCardButtonStyle()
            case let .live(stream):
                Button {
                    onPlayLive(stream)
                } label: {
                    HomePosterCard(title: item.title, imageURL: item.imageURL, isLive: true)
                }
                .posterCardButtonStyle()
            }
        }
        .recentlyWatchedRemoveMenu(onRemove.map { action in { action(item) } })
        .recommendationVoteMenu(onVote.map { action in { vote in action(item, vote) } })
    }
}

// MARK: - For You row

/// The "For You" rail. Unlike the other rows it always renders when
/// recommendations are enabled: while the first list is still being computed it
/// shows a progress placeholder, and when there's nothing to suggest yet it
/// nudges the user toward the actions that seed recommendations.
struct ForYouRow: View {
    let items: [HomeMediaItem]
    let isLoading: Bool
    let onPlayLive: (LiveStream) -> Void
    let onVote: (HomeMediaItem, RecommendationVote) -> Void
    var animationNamespace: Namespace.ID?

    var body: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("For You")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                placeholder
                    .padding(.horizontal)
            }
        } else {
            HomeRow(title: "For You", items: items, onPlayLive: onPlayLive, onVote: onVote, animationNamespace: animationNamespace)
        }
    }

    private var placeholder: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("Finding recommendations…")
            } else {
                Image(systemName: "sparkles")
                Text("Watch, favorite, or rate titles and we'll suggest more here.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Recommendation vote menu

extension View {
    /// Attaches thumbs up / thumbs down actions for a "For You" recommendation
    /// when an action is provided, otherwise leaves the view untouched. Surfaced
    /// by the same secondary-action gesture as the remove menu (long-press on
    /// iOS/tvOS, right-click on macOS).
    @ViewBuilder
    func recommendationVoteMenu(_ vote: ((RecommendationVote) -> Void)?) -> some View {
        if let vote {
            contextMenu {
                Button {
                    vote(.upvote)
                } label: {
                    Label("More Like This", systemImage: "hand.thumbsup")
                }
                Button(role: .destructive) {
                    vote(.downvote)
                } label: {
                    Label("Not Interested", systemImage: "hand.thumbsdown")
                }
            }
        } else {
            self
        }
    }
}

// MARK: - Poster card

/// A poster-style card used across all home rows. Shows artwork with an
/// optional resume progress bar and a "Live" badge.
///
/// Live channel logos are mostly transparent PNGs, so unlike movie/series
/// posters they can't fill the card themselves. They get a full card treatment
/// instead: a neutral dark gradient plate (consistent next to poster artwork in
/// any color scheme) and an inset so the logo never touches the edges.
private struct HomePosterCard: View {
    let title: String
    let imageURL: URL?
    var progress: Double?
    var rating: PosterRatingDisplay?
    var isLive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: PosterCardMetrics.titleSpacing) {
            ZStack(alignment: .bottomLeading) {
                if isLive {
                    ChannelLogoView(
                        url: imageURL,
                        width: PosterCardMetrics.posterWidth,
                        height: PosterCardMetrics.posterHeight,
                        cornerRadius: PosterCardMetrics.cornerRadius,
                        contentPadding: PosterCardMetrics.liveLogoInset
                    )
                } else {
                    posterArtwork
                }

                if isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .padding(6)
                }

                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: PosterCardMetrics.posterWidth, height: PosterCardMetrics.posterHeight)
            .posterRatingOverlay(rating)
            .clipShape(RoundedRectangle(cornerRadius: PosterCardMetrics.cornerRadius))
            .shadow(radius: 2)

            Text(title)
                .font(PosterCardMetrics.titleFont)
                .lineLimit(2)
                .frame(width: PosterCardMetrics.posterWidth, alignment: .leading)
        }
    }

    private var posterArtwork: some View {
        CachedAsyncImage(url: imageURL, maxPixelSize: PosterCardMetrics.posterHeight) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay { ProgressView() }
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(Color.secondary)
                            .font(.largeTitle)
                    }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: PosterCardMetrics.posterWidth, height: PosterCardMetrics.posterHeight)
    }
}
