//
//  TopShelfSettings.swift
//  Apex
//
//  Shared constants and types for Top Shelf configuration.
//  Used by both the main app (writes data) and the extension (reads data).
//

import Foundation

enum TopShelfSettings {
    /// The App Group identifier shared between the main app and the Top Shelf
    /// extension. Must match the App Group entitlement on both targets.
    static let appGroupID = "group.com.streaminfinity.apex"

    /// UserDefaults key for the user's chosen content mode.
    static let contentModeKey = "topShelf.contentMode"

    /// UserDefaults key for the cached Top Shelf item data (JSON-encoded).
    static let itemsDataKey = "topShelf.items"

    /// What content the Top Shelf displays.
    enum ContentMode: String, CaseIterable, Identifiable {
        case recentlyWatched = "recentlyWatched"
        case favorites = "favorites"
        case trending = "trending"
        case continueWatching = "continueWatching"

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .recentlyWatched: "Recently Watched"
            case .favorites: "Favorites"
            case .trending: "Trending"
            case .continueWatching: "Continue Watching"
            }
        }

        var description: String {
            switch self {
            case .recentlyWatched: "Shows your most recently watched movies and shows"
            case .favorites: "Shows your favorited content"
            case .trending: "Shows trending movies and series"
            case .continueWatching: "Shows movies and series you haven't finished"
            }
        }

        var systemImage: String {
            switch self {
            case .recentlyWatched: "clock.arrow.circlepath"
            case .favorites: "heart.fill"
            case .trending: "chart.line.uptrend.xyaxis"
            case .continueWatching: "play.circle"
            }
        }
    }
}

/// Lightweight data model for Top Shelf items, persisted as JSON in the shared
/// App Group UserDefaults so the extension can read it without SwiftData access.
struct TopShelfItemData: Codable {
    let id: String
    let title: String
    let imageURL: String
    let type: String        // "movie" or "series"
    let contentId: String   // TMDB id or internal id for deep linking
    let category: String    // matches ContentMode.rawValue
}
