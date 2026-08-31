//
//  DeepLink.swift
//  Apex
//
//  Custom URL-scheme deep links. `lume://movie/{tmdbId}` and
//  `lume://series/{tmdbId}` open a title's detail screen directly.
//

import Foundation

/// A parsed `lume://` deep link. Parsing is pure (it never touches the catalog)
/// so it can be unit-tested in isolation; resolving the link to a catalog item
/// and driving navigation happens in `MainTabView`.
nonisolated enum DeepLink: Equatable {
    case movie(tmdbId: Int, play: Bool = false)
    case series(tmdbId: Int, play: Bool = false)

    /// The app's registered URL scheme (see `CFBundleURLTypes` in Info.plist).
    static let scheme = "apex"

    /// Parses `apex://movie/{tmdbId}` and `apex://series/{tmdbId}`. `?play=1`
    /// means Top Shelf Play should resume instead of only opening details.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        guard let idComponent = url.pathComponents.first(where: { $0 != "/" }),
              let tmdbId = Int(idComponent)
        else { return nil }
        let play = url.shouldAutoplay
        switch url.host()?.lowercased() {
        case "movie": self = .movie(tmdbId: tmdbId, play: play)
        case "series": self = .series(tmdbId: tmdbId, play: play)
        default: return nil
        }
    }
}

private extension URL {
    var shouldAutoplay: Bool {
        guard let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { $0.name.lowercased() == "play" && ["1", "true", "yes"].contains($0.value?.lowercased()) }
    }
}

/// The main tab bar's selectable tabs. Hoisted out of `MainTabView` so a deep
/// link can switch tabs through `DeepLinkRouter`.
nonisolated enum AppTab: Hashable {
    case search, home, movies, series, liveTV, media, settings
}
