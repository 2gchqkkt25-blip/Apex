//
//  ContentProvider.swift
//  TopShelfExtension
//
//  Provides content for the Apple TV Top Shelf when Apex is on the top row
//  of the home screen. Reads the user's chosen content type from shared
//  UserDefaults (App Group) and returns matching items.
//

import TVServices
import Foundation

class ContentProvider: TVTopShelfContentProvider {

    /// Shared App Group suite for reading the user's Top Shelf preference.
    private let defaults = UserDefaults(suiteName: SharedTopShelfConstants.appGroupID)

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let mode = SharedTopShelfConstants.ContentMode(
            rawValue: defaults?.string(forKey: SharedTopShelfConstants.contentModeKey) ?? ""
        ) ?? .recentlyWatched

        let items = loadItems(for: mode)
        guard !items.isEmpty else { return nil }

        let section = TVTopShelfItemCollection(items: items)
        section.title = mode.displayTitle
        return TVTopShelfSectionedContent(sections: [section])
    }

    private func loadItems(for mode: SharedTopShelfConstants.ContentMode) -> [TVTopShelfSectionedItem] {
        guard let data = defaults?.data(forKey: SharedTopShelfConstants.itemsDataKey),
              let cached = try? JSONDecoder().decode([SharedTopShelfItem].self, from: data)
        else { return [] }

        let filtered = cached.filter { $0.category == mode.rawValue }
        let items = filtered.prefix(20)

        return items.compactMap { item in
            guard let imageURL = URL(string: item.imageURL) else { return nil }
            let tsItem = TVTopShelfSectionedItem(identifier: item.id)
            tsItem.title = item.title
            tsItem.setImageURL(imageURL, for: .screenScale1x)
            tsItem.setImageURL(imageURL, for: .screenScale2x)
            tsItem.imageShape = .poster
            if let deepLink = URL(string: "apex://\(item.type)/\(item.contentId)") {
                tsItem.playAction = TVTopShelfAction(url: deepLink)
                tsItem.displayAction = TVTopShelfAction(url: deepLink)
            }
            return tsItem
        }
    }
}

// MARK: - Shared types (mirrored from main app's TopShelfSettings)

private enum SharedTopShelfConstants {
    static let appGroupID = "group.com.streaminfinity.apex"
    static let contentModeKey = "topShelf.contentMode"
    static let itemsDataKey = "topShelf.items"

    enum ContentMode: String {
        case recentlyWatched = "recentlyWatched"
        case favorites = "favorites"
        case trending = "trending"
        case continueWatching = "continueWatching"

        var displayTitle: String {
            switch self {
            case .recentlyWatched: "Recently Watched"
            case .favorites: "Favorites"
            case .trending: "Trending"
            case .continueWatching: "Continue Watching"
            }
        }
    }
}

private struct SharedTopShelfItem: Decodable {
    let id: String
    let title: String
    let imageURL: String
    let type: String
    let contentId: String
    let category: String
}
