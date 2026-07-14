//
//  OpenSubtitlesSettings.swift
//  Apex
//
//  Settings keys and constants for subtitle integration (Wyzie Subs + OpenSubtitles).
//  Values sync via iCloud (NSUbiquitousKeyValueStore) so entering keys
//  on one device makes them available on all others.
//

import Foundation

/// Shared subtitle settings keys used by both Wyzie Subs (primary) and
/// OpenSubtitles (fallback). Language and enabled state are shared; each
/// provider has its own credentials.
enum SubtitleSettings {
    // Shared
    static let enabledKey = "opensubtitles.enabled"
    static let languageKey = "opensubtitles.language"

    // Wyzie Subs (primary)
    static let wyzieApiKeyKey = "subtitles.wyzie.apiKey"

    // OpenSubtitles (fallback)
    static let openSubsApiKeyKey = "opensubtitles.apiKey"
    static let openSubsUsernameKey = "opensubtitles.username"
    static let openSubsPasswordKey = "opensubtitles.password"
}

/// Legacy name kept so existing references compile without changes.
enum OpenSubtitlesSettings {
    static let apiKeyKey = SubtitleSettings.openSubsApiKeyKey
    static let languageKey = SubtitleSettings.languageKey
    static let enabledKey = SubtitleSettings.enabledKey
    static let usernameKey = SubtitleSettings.openSubsUsernameKey
    static let passwordKey = SubtitleSettings.openSubsPasswordKey

    // MARK: - iCloud Sync

    /// Writes all subtitle settings to iCloud so they sync across devices.
    static func syncToCloud() {
        let store = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard
        store.set(defaults.string(forKey: SubtitleSettings.wyzieApiKeyKey) ?? "", forKey: SubtitleSettings.wyzieApiKeyKey)
        store.set(defaults.string(forKey: apiKeyKey) ?? "", forKey: apiKeyKey)
        store.set(defaults.string(forKey: languageKey) ?? "en", forKey: languageKey)
        store.set(defaults.bool(forKey: enabledKey), forKey: enabledKey)
        store.set(defaults.string(forKey: usernameKey) ?? "", forKey: usernameKey)
        store.set(defaults.string(forKey: passwordKey) ?? "", forKey: passwordKey)
        store.synchronize()
    }

    /// Reads iCloud values and applies them locally if they exist.
    static func syncFromCloud() {
        let store = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.standard

        if let key = store.string(forKey: SubtitleSettings.wyzieApiKeyKey), !key.isEmpty {
            defaults.set(key, forKey: SubtitleSettings.wyzieApiKeyKey)
        }
        if let key = store.string(forKey: apiKeyKey), !key.isEmpty {
            defaults.set(key, forKey: apiKeyKey)
        }
        if let lang = store.string(forKey: languageKey), !lang.isEmpty {
            defaults.set(lang, forKey: languageKey)
        }
        if let username = store.string(forKey: usernameKey), !username.isEmpty {
            defaults.set(username, forKey: usernameKey)
        }
        if let password = store.string(forKey: passwordKey), !password.isEmpty {
            defaults.set(password, forKey: passwordKey)
        }
        // Only override local enabled if cloud has explicitly set it
        if store.object(forKey: enabledKey) != nil {
            defaults.set(store.bool(forKey: enabledKey), forKey: enabledKey)
        }
    }

    /// Supported subtitle languages (ISO 639-1 codes shared by both providers).
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
