//
//  OpenSubtitlesSettings.swift
//  Apex
//
//  Settings keys and constants for subtitle integration (Wyzie Subs + OpenSubtitles).
//  Values sync via iCloud (NSUbiquitousKeyValueStore) so entering keys
//  on one device makes them available on all others.
//

import Foundation
import SwiftUI

/// Shared subtitle settings keys used by both Wyzie Subs (primary) and
/// OpenSubtitles (fallback). Language and enabled state are shared; each
/// provider has its own credentials.
enum SubtitleSettings {
    // Shared
    static let enabledKey = "opensubtitles.enabled"
    static let languageKey = "opensubtitles.language"

    /// Wyzie Subs (primary)
    static let wyzieApiKeyKey = "subtitles.wyzie.apiKey"

    // OpenSubtitles (fallback)
    static let openSubsApiKeyKey = "opensubtitles.apiKey"
    static let openSubsUsernameKey = "opensubtitles.username"
    static let openSubsPasswordKey = "opensubtitles.password"

    // Appearance
    static let fontSizeKey = "subtitles.appearance.fontSize"
    static let textColorKey = "subtitles.appearance.textColor"
    static let backgroundOpacityKey = "subtitles.appearance.backgroundOpacity"
    static let bottomOffsetKey = "subtitles.appearance.bottomOffset"
    static let positionKey = "subtitles.appearance.position"
}

// MARK: - Subtitle Position

enum SubtitlePosition: String, CaseIterable {
    case bottom
    case center
}

// MARK: - Subtitle Appearance

/// Centralized subtitle appearance, read from UserDefaults and applied by every
/// subtitle overlay (KSPlayer, External SRT, and AVPlayer-macOS). All values
/// have platform-aware defaults — tvOS uses a larger font and bottom offset.
struct SubtitleAppearance {
    var fontSize: CGFloat
    var textColor: Color
    var backgroundOpacity: Double
    var bottomOffset: CGFloat
    var position: SubtitlePosition

    /// Read on demand so a change made in Settings is reflected the next time
    /// an overlay is created without requiring an app relaunch.
    static var current: SubtitleAppearance {
        let defaults = UserDefaults.standard
        let baseFont: CGFloat = {
            #if os(tvOS)
                28
            #else
                17
            #endif
        }()
        let baseOffset: CGFloat = {
            #if os(tvOS)
                60
            #else
                40
            #endif
        }()
        let fontSize = defaults.double(forKey: SubtitleSettings.fontSizeKey)
        let textColorHex = defaults.string(forKey: SubtitleSettings.textColorKey) ?? ""
        let hasBackgroundOpacity = defaults.object(forKey: SubtitleSettings.backgroundOpacityKey) != nil
        let backgroundOpacity = defaults.double(forKey: SubtitleSettings.backgroundOpacityKey)
        let hasBottomOffset = defaults.object(forKey: SubtitleSettings.bottomOffsetKey) != nil
        let bottomOffset = defaults.double(forKey: SubtitleSettings.bottomOffsetKey)
        let positionRaw = defaults.string(forKey: SubtitleSettings.positionKey) ?? ""
        let position = SubtitlePosition(rawValue: positionRaw) ?? .bottom

        return SubtitleAppearance(
            fontSize: fontSize > 0 ? fontSize : baseFont,
            textColor: textColorHex.isEmpty ? .white : Color(hex: textColorHex) ?? .white,
            backgroundOpacity: hasBackgroundOpacity ? backgroundOpacity : 0.6,
            bottomOffset: hasBottomOffset ? bottomOffset : baseOffset,
            position: position
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(fontSize, forKey: SubtitleSettings.fontSizeKey)
        defaults.set(textColor.hexString, forKey: SubtitleSettings.textColorKey)
        defaults.set(backgroundOpacity, forKey: SubtitleSettings.backgroundOpacityKey)
        defaults.set(bottomOffset, forKey: SubtitleSettings.bottomOffsetKey)
        defaults.set(position.rawValue, forKey: SubtitleSettings.positionKey)
    }
}

/// Places subtitle text against the full video canvas. Center is the true
/// geometric center (including landscape safe-area regions); bottom observes
/// both the viewer's offset and the device home-indicator/title-bar inset.
struct SubtitleOverlayLayout<Content: View>: View {
    let appearance: SubtitleAppearance
    var controlsVisible = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing) + 24
            let restingInset = max(appearance.bottomOffset, proxy.safeAreaInsets.bottom + minimumEdgeMargin)
            let bottomInset = controlsVisible
                ? max(restingInset, controlsClearance(for: proxy.size))
                : restingInset

            Group {
                switch appearance.position {
                case .center:
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content()
                            .frame(maxWidth: max(0, proxy.size.width - horizontalInset * 2))
                        Spacer(minLength: 0)
                    }
                case .bottom:
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content()
                            .frame(maxWidth: max(0, proxy.size.width - horizontalInset * 2))
                            .padding(.bottom, bottomInset)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.22), value: controlsVisible)
    }

    private var minimumEdgeMargin: CGFloat {
        #if os(tvOS)
            36
        #else
            16
        #endif
    }

    /// Keeps the complete subtitle box above each platform's bottom controls.
    /// These are absolute clearances from the bottom edge, not additions to the
    /// viewer-selected resting offset, so custom settings remain predictable.
    private func controlsClearance(for size: CGSize) -> CGFloat {
        #if os(tvOS)
            // The Apple TV overlay includes title, progress, and a large focus
            // row. Roughly the lower third is occupied while it is visible.
            max(300, size.height * 0.30)
        #elseif os(iOS)
            // Landscape has less vertical room, while portrait can comfortably
            // clear the taller title/scrubber stack by a little more.
            size.width > size.height ? 120 : 150
        #elseif os(macOS)
            140
        #else
            140
        #endif
    }
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
        ("vi", "Vietnamese")
    ]
}
