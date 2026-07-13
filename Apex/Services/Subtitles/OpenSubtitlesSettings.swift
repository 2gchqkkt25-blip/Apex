//
//  OpenSubtitlesSettings.swift
//  Apex
//
//  Settings keys and constants for OpenSubtitles integration.
//

import Foundation

enum OpenSubtitlesSettings {
    static let apiKeyKey = "opensubtitles.apiKey"
    static let languageKey = "opensubtitles.language"
    static let enabledKey = "opensubtitles.enabled"

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
