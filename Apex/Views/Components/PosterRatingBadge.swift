//
//  PosterRatingBadge.swift
//  Apex
//
//  Compact star-rating pill overlaid on VOD poster cards. Prefers IMDb (when
//  OMDb enrichment has run), then provider/TMDB scores synced with the playlist.
//

import SwiftUI

/// The best available score to show on a browse poster, normalised for display.
struct PosterRatingDisplay: Equatable {
    /// One-decimal value shown beside the star (typically on a 0…10 scale).
    let value: String

    static func forMovie(_ movie: Movie) -> PosterRatingDisplay? {
        if let imdb = movie.externalRatings.first(where: { $0.source == .imdb }) {
            return PosterRatingDisplay(value: imdb.compactValue)
        }
        if let normalized = normalized10(movie.rating5Based > 0 ? movie.rating5Based * 2 : movie.rating) {
            return PosterRatingDisplay(value: normalized)
        }
        return nil
    }

    static func forSeries(_ series: Series) -> PosterRatingDisplay? {
        if let imdb = series.externalRatings.first(where: { $0.source == .imdb }) {
            return PosterRatingDisplay(value: imdb.compactValue)
        }
        if let raw = series.rating5Based, let five = Double(raw), five > 0,
           let normalized = normalized10(five * 2)
        {
            return PosterRatingDisplay(value: normalized)
        }
        if let raw = series.rating, let ten = Double(raw),
           let normalized = normalized10(ten)
        {
            return PosterRatingDisplay(value: normalized)
        }
        return nil
    }

    private static func normalized10(_ score: Double) -> String? {
        guard score > 0 else { return nil }
        return String(format: "%.1f", min(score, 10))
    }
}

/// A small pill pinned to the top-trailing corner of a poster.
struct PosterRatingBadge: View {
    let display: PosterRatingDisplay

    var body: some View {
        HStack(spacing: badgeSpacing) {
            Image(systemName: "star.fill")
                .font(.system(size: starSize, weight: .semibold))
            Text(display.value)
                .font(.system(size: textSize, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(badgeInset)
    }

    #if os(tvOS)
        private var starSize: CGFloat {
            18
        }

        private var textSize: CGFloat {
            22
        }

        private var horizontalPadding: CGFloat {
            12
        }

        private var verticalPadding: CGFloat {
            6
        }

        private var badgeInset: CGFloat {
            10
        }

        private var badgeSpacing: CGFloat {
            6
        }
    #else
        private var starSize: CGFloat {
            9
        }

        private var textSize: CGFloat {
            11
        }

        private var horizontalPadding: CGFloat {
            6
        }

        private var verticalPadding: CGFloat {
            3
        }

        private var badgeInset: CGFloat {
            6
        }

        private var badgeSpacing: CGFloat {
            3
        }
    #endif
}

/// High-contrast favorite marker shared by movie and series posters. A fixed
/// dark plate remains legible on bright artwork and avoids material rendering
/// disappearing inside lazily rendered/focused poster cards.
struct PosterFavoriteBadge: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: heartSize, weight: .bold))
            .foregroundStyle(.red)
            .frame(width: plateSize, height: plateSize)
            .background(.black.opacity(0.78), in: Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .padding(badgeInset)
            .accessibilityLabel("Favorite")
    }

    #if os(tvOS)
        private var heartSize: CGFloat {
            24
        }

        private var plateSize: CGFloat {
            48
        }

        private var badgeInset: CGFloat {
            10
        }
    #else
        private var heartSize: CGFloat {
            13
        }

        private var plateSize: CGFloat {
            28
        }

        private var badgeInset: CGFloat {
            6
        }
    #endif
}

extension View {
    /// Overlays a rating pill when `display` is non-nil.
    func posterRatingOverlay(_ display: PosterRatingDisplay?) -> some View {
        overlay(alignment: .topTrailing) {
            if let display {
                PosterRatingBadge(display: display)
            }
        }
    }

    /// Overlays the shared heart marker for favorited movie and series cards.
    func posterFavoriteOverlay(_ isFavorite: Bool) -> some View {
        overlay(alignment: .topLeading) {
            if isFavorite {
                PosterFavoriteBadge()
            }
        }
    }
}
