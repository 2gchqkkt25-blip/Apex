//
//  SeriesCardView.swift
//  Apex
//
//  Card view for displaying a series cover and title
//

import SwiftData
import SwiftUI

struct SeriesCardView: View {
    @Bindable var series: Series
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: PosterCardMetrics.titleSpacing) {
            // Cover
            CachedAsyncImage(url: URL(string: series.cover ?? ""), maxPixelSize: PosterCardMetrics.posterHeight) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(.fill.quaternary)
                        .overlay {
                            ProgressView()
                        }
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(.fill.quaternary)
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.secondary)
                                .font(.largeTitle)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: PosterCardMetrics.posterWidth, height: PosterCardMetrics.posterHeight)
            .posterRatingOverlay(PosterRatingDisplay.forSeries(series))
            .posterFavoriteOverlay(series.isFavorite)
            .clipShape(RoundedRectangle(cornerRadius: PosterCardMetrics.cornerRadius))
            // A shadow applied after clipShape forces an offscreen render pass per
            // card every frame. On tvOS the focus style already supplies depth and
            // a 2pt shadow is invisible on the 10-foot UI, so we skip it there.
            #if !os(tvOS)
                .shadow(radius: 2)
            #endif

            // Title
            Text(series.name)
                .font(PosterCardMetrics.titleFont)
                .lineLimit(2)
                .frame(width: PosterCardMetrics.posterWidth, alignment: .leading)
        }
        .task(id: needsPosterRating ? series.id : nil) {
            await loadPosterRatingIfNeeded()
        }
    }

    private var needsPosterRating: Bool {
        (Double(series.rating ?? "") ?? 0) <= 0
            && (Double(series.rating5Based ?? "") ?? 0) <= 0
            && series.externalRatings.first(where: { $0.source == .imdb }) == nil
    }

    private func loadPosterRatingIfNeeded() async {
        guard needsPosterRating, TMDBClient.shared.isConfigured else { return }
        guard let match = await PosterRatingResolver.shared.seriesRating(
            catalogID: series.id,
            tmdbID: series.tmdbId,
            title: series.name,
            releaseDate: series.releaseDate
        ), !Task.isCancelled, needsPosterRating else { return }

        series.tmdbId = match.tmdbID
        series.rating = String(format: "%.1f", match.score)
        PosterRatingSaveCoordinator.shared.schedule(context: modelContext)
    }
}

#Preview("Basic") {
    SeriesCardView(
        series: Series(
            id: "preview-1",
            seriesId: 1,
            name: "Sample Series"
        )
    )
}

#Preview("With Cover") {
    SeriesCardView(
        series: Series(
            id: "preview-2",
            seriesId: 2,
            name: "Breaking Bad",
            cover: "https://image.tmdb.org/t/p/w185/ggFHVNu6YYI5L9T5f7jFpBZdXl.jpg",
            rating: "9.5"
        )
    )
}

#Preview("With TMDB") {
    let series = Series(
        id: "preview-3",
        seriesId: 3,
        name: "Stranger Things",
        cover: "https://image.tmdb.org/t/p/w185/49WJfeN0m4b6B1JYbMqG0Y6j6aM.jpg",
        rating: "8.7"
    )
    series.tmdbId = 66732
    series.contentRating = "TV-14"
    return SeriesCardView(series: series)
}
