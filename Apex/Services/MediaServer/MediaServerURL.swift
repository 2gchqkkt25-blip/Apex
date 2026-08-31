//
//  MediaServerURL.swift
//  Apex
//

import Foundation

enum MediaServerURL {
    static func normalize(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://\(trimmed)"
        }
        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url
    }
}
