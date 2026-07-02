//
//  Theme.swift
//  Apex
//
//  Semantic color tokens for every app theme.  Each theme defines accent,
//  background, surface, and text colours plus a glass‑effect preference so
//  views can stay colour‑agnostic while the user switches themes at runtime.
//

import SwiftUI

// MARK: - Theme enum

enum AppTheme: String, CaseIterable, Codable {
    case system
    case frostedGlass
    case midnight
    case sunset
    case ocean

    var displayName: String {
        switch self {
        case .system: "System"
        case .frostedGlass: "Frosted Glass"
        case .midnight: "Midnight"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .frostedGlass: "sparkles"
        case .midnight: "moon.stars"
        case .sunset: "sunset"
        case .ocean: "water.waves"
        }
    }

    /// The semantic colour tokens for this theme.
    var colors: ThemeColors {
        switch self {
        case .system: ThemeColors.system
        case .frostedGlass: ThemeColors.frostedGlass
        case .midnight: ThemeColors.midnight
        case .sunset: ThemeColors.sunset
        case .ocean: ThemeColors.ocean
        }
    }
}

// MARK: - Semantic colour tokens

struct ThemeColors: Sendable {
    /// Primary brand colour — buttons, links, toggles, active states.
    let accent: Color
    /// Main screen background.
    let background: Color
    /// Card / section / grouped‑row background.
    let surface: Color
    /// Primary body text.
    let textPrimary: Color
    /// Secondary captions / metadata.
    let textSecondary: Color
    /// Whether glass‑material surfaces are preferred over solid fills.
    let prefersGlass: Bool
    /// True for all custom themes — they all use dark backgrounds that need light text.
    let isDark: Bool
    /// A short description shown in the theme picker.
    let description: String

    // MARK: - Pre‑built themes

    static let system = ThemeColors(
        accent: .platformAccent,
        background: .platformBackground,
        surface: .platformSurface,
        textPrimary: .primary,
        textSecondary: .secondary,
        prefersGlass: false,
        isDark: false,
        description: "Follows your device Light / Dark appearance."
    )

    static let frostedGlass = ThemeColors(
        accent: Color(hex: "6B7AFF"),
        background: .clear,
        surface: .clear,
        textPrimary: .white,
        textSecondary: .white.opacity(0.65),
        prefersGlass: true,
        isDark: true,
        description: "Translucent glass surfaces with a cool blue‑purple glow."
    )

    static let midnight = ThemeColors(
        accent: Color(hex: "5B5EA6"),
        background: Color(hex: "0D0D1A"),
        surface: Color(hex: "1A1A2E"),
        textPrimary: Color(hex: "EDEDF5"),
        textSecondary: Color(hex: "8E8E9A"),
        prefersGlass: false,
        isDark: true,
        description: "Deep indigo night — easy on the eyes in the dark."
    )

    static let sunset = ThemeColors(
        accent: Color(hex: "FF8C42"),
        background: Color(hex: "1A1410"),
        surface: Color(hex: "2A1F16"),
        textPrimary: Color(hex: "FFF0E6"),
        textSecondary: Color(hex: "B8A397"),
        prefersGlass: false,
        isDark: true,
        description: "Warm amber and gold — like golden hour, all day."
    )

    static let ocean = ThemeColors(
        accent: Color(hex: "00B4D8"),
        background: Color(hex: "0A1628"),
        surface: Color(hex: "0F2340"),
        textPrimary: Color(hex: "E0F0FF"),
        textSecondary: Color(hex: "7B9BB8"),
        prefersGlass: false,
        isDark: true,
        description: "Deep ocean blues with a bright teal accent."
    )
}

// MARK: - Platform helpers

extension Color {
    /// The system background for the current platform — used by the System theme.
    static var platformBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
            Color(white: 0.09)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }

    /// The system grouped‑surface colour for the current platform.
    static var platformSurface: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #elseif os(tvOS)
            Color(white: 0.13)
        #else
            Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Creates a Color from a 6‑character hex string (e.g. `"6B7AFF"`).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// A visible accent colour for the current platform.  On iOS / macOS /
    /// tvOS we use the standard system blue so selection indicators, tab bars,
    /// and other system chrome reliably render legible text on the accent fill.
    /// A custom `AccentColor` asset overrides `Color.accentColor` app-wide and
    /// breaks contrast on iPadOS where system controls read the asset directly.
    static var platformAccent: Color {
        Color.blue
    }
}

// MARK: - Glass helpers

extension View {
    /// Applies the active theme's background — glass material when the Frosted Glass
    /// theme is active, solid colour otherwise.  Use this for full‑screen backgrounds.
    @ViewBuilder
    /// Applies the active theme's background colour, extending under the safe
    /// area so the entire screen is filled.
    func themeBackground() -> some View {
        let fill = ThemeManager.shared.colors.prefersGlass
            ? Color.clear
            : ThemeManager.shared.colors.background
        return background(fill).ignoresSafeArea()
    }

    /// Makes a List or Form background transparent so the theme background
    /// shows through.  Call this on any scrollable content surface.
    func transparentListBackground() -> some View {
        #if os(iOS)
            scrollContentBackground(.hidden)
        #else
            self
        #endif
    }

    /// Applies `glassEffectCompat` when the active theme prefers glass,
    /// otherwise falls back to the given solid colour.
    @ViewBuilder
    func glassBackgroundIfFrosted(
        _ style: GlassEffectStyle = .regular,
        fallback: Color,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: 16)
    ) -> some View {
        if ThemeManager.shared.colors.prefersGlass {
            glassEffectCompat(style, in: shape)
        } else {
            background(fallback, in: shape)
        }
    }
}
