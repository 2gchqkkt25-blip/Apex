//
//  ThemeManager.swift
//  Apex
//
//  Central theme authority.  Persists the user's choice to UserDefaults and
//  publishes changes so every view re-renders with the new palette instantly.
//

import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private static let storageKey = "app.theme"

    /// The currently selected theme.  Use `selectTheme(_:)` to change it — that
    /// method guarantees both persistence and observation fire.
    private(set) var theme: AppTheme = .system

    func selectTheme(_ newTheme: AppTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        UserDefaults.standard.set(newTheme.rawValue, forKey: Self.storageKey)
    }

    /// The active semantic colour tokens.
    var colors: ThemeColors { theme.colors }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppTheme(rawValue: raw)
        {
            theme = stored
        }
    }
}

// MARK: - Environment helper

private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager = .shared
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}
