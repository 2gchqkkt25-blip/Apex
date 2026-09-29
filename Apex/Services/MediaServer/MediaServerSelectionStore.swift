//
//  MediaServerSelectionStore.swift
//  Apex
//
//  Global active media server for the Media tab. Separate from IPTV playlist
//  selection so Live TV / Movies / Series stay on the IPTV catalog.
//

import Foundation

enum MediaServerSelectionStore {
    static let key = "apex.selectedMediaServerID"
}

extension [MediaServer] {
    func active(for storedID: String) -> MediaServer? {
        let enabled = filter(\.syncEnabled).sorted { $0.sortOrder < $1.sortOrder }
        if let match = enabled.first(where: { $0.id.uuidString == storedID }) {
            return match
        }
        return enabled.first
    }

    func firstEnabled() -> MediaServer? {
        sorted { $0.sortOrder < $1.sortOrder }.first { $0.syncEnabled }
    }
}
