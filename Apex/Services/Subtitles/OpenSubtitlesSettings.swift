//
//  OpenSubtitlesSettings.swift
//  Apex
//
//  Settings keys and constants for OpenSubtitles integration.
//  Values sync via iCloud (NSUbiquitousKeyValueStore) so entering the API key
//  on one device makes it available on all others.
//

import Foundation

enum OpenSubtitlesSettings {
    static let apiKeyKey = "opensubtitles.apiKey"
    static let languageKey = "opensubtitles.language"
    static let enabledKey = "opensubtitles.enabled"

    // MARK: - iCloud Sync

    /// Writes all OpenSubtitles settings to iCloud so they sync across devices.
    static func syncToCloud() {
        let store = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard
        store.set(defaults.string(forKey: apiKeyKey) ?? "", forKey: apiKeyKey)
        store.set(defaults.string(forKey: languageKey) ?? "en", forKey: languageKey)
        store.set(defaults.bool(forKey: enabledKey), forKey: enabledKey)
        store.synchronize()
    }

    /// Reads iCloud values and applies them locally if they exist.
    static func syncFromCloud() {
        let store = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard

        if let key = store.string(forKey: apiKeyKey), !key.isEmpty {
            defaults.set(key, forKey: apiKeyKey)
        }
        if let lang = store.string(forKey: languageKey), !lang.isEmpty {
            defaults.set(lang, forKey: languageKey)
        }
        // Only override local enabled if cloud has explicitly set it
        if store.object(forKey: enabledKey) != nil {
            defaults.set(store.bool(forKey: enabledKey), forKey: enabledKey)
        }
    }

    /// Supported subtitle languages (ISO 639-1 codes used by OpenSubtitles API).
    static let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ro", "Romanian"),
        ("tr", "Turkish"),
        ("ar", "Arabic"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("hi", "Hindi"),
        ("ru", "Russian"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hu", "Hungarian"),
        ("cs", "Czech"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]
}
