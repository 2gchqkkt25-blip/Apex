//
//  ApexTextClipboard.swift
//  Apex
//
//  Session-only in-app text clipboard for tvOS. Apple TV has no UIPasteboard,
//  so URL / credential fields copy and paste through this store instead —
//  long-press Select on a `TVSettingsField` to copy or paste within Apex.
//

#if os(tvOS)

    import Foundation
    import Observation

    /// In-app clipboard shared by tvOS settings / Add Playlist text fields.
    /// Contents live only for the app process — not Keychain, CloudKit, or the
    /// system pasteboard (which does not exist on tvOS).
    @MainActor
    @Observable
    final class ApexTextClipboard {
        static let shared = ApexTextClipboard()

        private(set) var contents: String?

        var canPaste: Bool {
            guard let contents else { return false }
            return !contents.isEmpty
        }

        private init() {}

        func copy(_ string: String) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            contents = trimmed
        }

        func paste() -> String? {
            contents
        }

        func clearClipboard() {
            contents = nil
        }
    }

#endif
