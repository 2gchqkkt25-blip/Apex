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
}
