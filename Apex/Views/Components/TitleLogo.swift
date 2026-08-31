//
//  TitleLogo.swift
//  Apex
//
//  Shows a title's TMDB wordmark logo in place of its text title, used by the
//  home hero carousel and the movie/series detail heroes (iOS, macOS, tvOS).
//

import SwiftUI

/// Shows a title's TMDB wordmark logo when one is available, gracefully falling
/// back to a styled text title while the logo loads, fails, or is absent. The
/// logo keeps its aspect ratio, capped to `maxWidth` × `maxHeight`, so it sits
/// where the text title would.
struct TitleLogo<Fallback: View>: View {
    let url: URL?
    let title: String
    var maxWidth: CGFloat = .infinity
    var maxHeight: CGFloat = 96
    var alignment: Alignment = .leading
    @ViewBuilder var fallback: () -> Fallback

    /// `CachedAsyncImage`'s cap applies to the *longest* edge, and a wordmark is
    /// far wider than it is tall, so deriving this from `maxHeight` alone would
    /// over-shrink it. The display width is the real bound; fall back to a
    /// generous 5:1 wordmark when it's unbounded. Without any cap the pipeline
    /// decodes the original TMDB asset at full resolution — often 2000-3840 px
    /// wide with an alpha channel, so ~12 MB of pixels — to draw a strip under
    /// 150 pt tall, on every hero and every detail screen.
    private var logoMaxPixelSize: CGFloat {
        maxWidth.isFinite ? max(maxWidth, maxHeight) : maxHeight * 5
    }

    var body: some View {
        if let url {
            CachedAsyncImage(url: url, maxPixelSize: logoMaxPixelSize) { phase in
                switch phase {
                case .empty:
                    // Reserve the logo's vertical space without flashing the
                    // text title first, then swapping it for the artwork.
                    Color.clear.frame(height: maxHeight)
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
                        .accessibilityLabel(title)
                case .failure:
                    fallback()
                @unknown default:
                    fallback()
                }
            }
            .frame(maxWidth: maxWidth, alignment: alignment)
        } else {
            fallback()
        }
    }
}
