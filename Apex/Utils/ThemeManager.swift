//
//  ThemeManager.swift
//  Apex
//
//  Central theme authority.  Persists the user's choice to UserDefaults and
//  syncs via iCloud (NSUbiquitousKeyValueStore) so the theme follows across
//  devices. Publishes changes so every view re-renders with the new palette
//  instantly.
//

import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private static let storageKey = "app.theme"
    private static let cloudKey = "app.theme"

    /// The currently selected theme.  Use `selectTheme(_:)` to change it — that
    /// method guarantees both persistence and observation fire.
    private(set) var theme: AppTheme = .system

    func selectTheme(_ newTheme: AppTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        UserDefaults.standard.set(newTheme.rawValue, forKey: Self.storageKey)
        // Sync to iCloud so theme follows across devices.
        NSUbiquitousKeyValueStore.default.set(newTheme.rawValue, forKey: Self.cloudKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// The active semantic colour tokens.
    var colors: ThemeColors { theme.colors }

    private init() {
        // Prefer cloud value (most recently set on any device) over local.
        if let cloudRaw = NSUbiquitousKeyValueStore.default.string(forKey: Self.cloudKey),
           let cloudTheme = AppTheme(rawValue: cloudRaw)
        {
            theme = cloudTheme
            // Keep local in sync.
            UserDefaults.standard.set(cloudRaw, forKey: Self.storageKey)
        } else if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
                  let stored = AppTheme(rawValue: raw)
        {
            theme = stored
            // Seed cloud with local choice so other devices pick it up.
            NSUbiquitousKeyValueStore.default.set(raw, forKey: Self.cloudKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }

        // Observe remote changes from other devices.
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleCloudChange(notification)
            }
        }
        // Kick initial sync.
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func handleCloudChange(_ notification: Notification) {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
              changedKeys.contains(Self.cloudKey) else { return }
        guard let raw = NSUbiquitousKeyValueStore.default.string(forKey: Self.cloudKey),
              let newTheme = AppTheme(rawValue: raw),
              newTheme != theme else { return }
        theme = newTheme
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
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
