import Foundation

/// Catalog ids embed the owning playlist UUID (`{uuid}-movie-123`). Watch
/// history in `UserContentState` is keyed by that full id, so deleting a
/// playlist and adding it back produced new ids and looked like a blank slate.
/// The suffix after the playlist UUID is stable for the same provider item.
enum ContentIdentity {
    /// `{playlistUUID}-movie-42` → `movie-42`. Nil when `id` has no UUID prefix.
    static func stableKey(for id: String) -> String? {
        guard id.count > 37 else { return nil }
        let split = id.index(id.startIndex, offsetBy: 36)
        guard id[split] == "-", UUID(uuidString: String(id[..<split])) != nil else { return nil }
        let key = String(id[id.index(after: split)...])
        return key.isEmpty ? nil : key
    }

    /// Marker inserted after the playlist UUID so a hidden category's cloud id
    /// (`{uuid}-category-live-5`) cannot collide with a live stream (`{uuid}-live-5`).
    private static let categoryMarker = "category-"

    /// Cloud `UserContentState.contentId` for a local `Category.id`.
    static func categoryCloudId(forCategoryId id: String) -> String? {
        guard let key = stableKey(for: id) else { return nil }
        return "\(id.prefix(36))-\(categoryMarker)\(key)"
    }

    /// Local `Category.id` recovered from a category cloud content id.
    static func categoryId(fromCloudContentId id: String) -> String? {
        guard let key = stableKey(for: id), key.hasPrefix(categoryMarker) else { return nil }
        let rest = String(key.dropFirst(categoryMarker.count))
        guard !rest.isEmpty else { return nil }
        return "\(id.prefix(36))-\(rest)"
    }

    /// `live-5` from a category cloud stable key `category-live-5`.
    static func categoryLocalStableKey(fromCloudStableKey key: String) -> String? {
        guard key.hasPrefix(categoryMarker) else { return nil }
        let rest = String(key.dropFirst(categoryMarker.count))
        return rest.isEmpty ? nil : rest
    }
}
