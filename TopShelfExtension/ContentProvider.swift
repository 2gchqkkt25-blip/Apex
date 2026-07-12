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
    private let defaults = UserDefaults(suiteName: TopShelfSettings.appGroupID)

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let mode = TopShelfSettings.ContentMode(
            rawValue: defaults?.string(forKey: TopShelfSettings.contentModeKey) ?? ""
        ) ?? .recentlyWatched

        let items = loadItems(for: mode)
        guard !items.isEmpty else { return nil }

        // Use sectioned content (multiple rows)
        let section = TVTopShelfItemCollection(items: items)
        section.title = mode.displayTitle
        return TVTopShelfSectionedContent(sections: [section])
    }

    private func loadItems(for mode: TopShelfSettings.ContentMode) -> [TVTopShelfSectionedItem] {
        // Read from the shared App Group container where the main app persists
        // Top Shelf data after each sync.
        guard let data = defaults?.data(forKey: TopShelfSettings.itemsDataKey),
              let cached = try? JSONDecoder().decode([TopShelfItemData].self, from: data)
        else { return [] }

        // Filter by the selected mode
        let filtered = cached.filter { $0.category == mode.rawValue }
        let items = filtered.prefix(20)

        return items.compactMap { item in
            guard let imageURL = URL(string: item.imageURL) else { return nil }
            let tsItem = TVTopShelfSectionedItem(identifier: item.id)
            tsItem.title = item.title
            tsItem.setImageURL(imageURL, for: .screenScale1x)
            tsItem.setImageURL(imageURL, for: .screenScale2x)
            tsItem.imageShape = .poster
            // Deep link into the app when tapped
            if let deepLink = URL(string: "apex://\(item.type)/\(item.contentId)") {
                tsItem.playAction = TVTopShelfAction(url: deepLink)
                tsItem.displayAction = TVTopShelfAction(url: deepLink)
            }
            return tsItem
        }
    }
}
