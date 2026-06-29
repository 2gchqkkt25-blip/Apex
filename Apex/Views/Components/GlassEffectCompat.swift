//
//  GlassEffectCompat.swift
//  Apex
//
//  Liquid Glass degrades gracefully below the OS versions that introduced
//  `glassEffect` (iOS 26 / tvOS 26 / macOS 26 / visionOS 26). Earlier systems
//  fall back to a system material in the same shape so player controls stay
//  legible on iOS 18 / tvOS 18 / macOS 15 / visionOS 2.
//
//  On tvOS < 26, `Material` styles create a `_UIReplicantView` inside
//  UIHostingController.view, which the framework warns against. A solid
//  semi-transparent fill reads identically on Apple TV's always-dark canvas.
//

import SwiftUI

/// The glass treatment a control wants, expressed without referencing the
/// iOS 26-only `Glass` type so it can be used from code that deploys to iOS 18.
enum GlassEffectStyle {
    /// Non-interactive regular glass.
    case regular
    /// Regular glass that lenses and lifts under interaction.
    case regularInteractive
    /// Interactive glass tinted toward `color` (e.g. the tvOS focus state).
    case tintedInteractive(Color)
}

// MARK: - Platform-appropriate Material fallbacks

/// Shape-style substitutes for `Material` that avoid the tvOS `< 26`
/// `_UIReplicantView` warning while reading identically on an always-dark canvas.
enum GlassFallback {
    #if os(tvOS)
        static let thin: AnyShapeStyle = AnyShapeStyle(Color.white.opacity(0.06))
        static let regular: AnyShapeStyle = AnyShapeStyle(Color.white.opacity(0.08))
    #else
        static let thin: AnyShapeStyle = AnyShapeStyle(Material.ultraThinMaterial)
        static let regular: AnyShapeStyle = AnyShapeStyle(Material.regularMaterial)
    #endif
}

extension View {
    /// Applies a Liquid Glass effect on OS 26+, falling back to a platform-
    /// appropriate fill on earlier systems. On tvOS < 26 the fallback is a
    /// semi-transparent solid (avoiding `_UIReplicantView`); on iOS / macOS
    /// < 26 it's still a system material. A tinted style always falls back
    /// to a solid fill of the tint colour.
    @ViewBuilder
    func glassEffectCompat(_ style: GlassEffectStyle = .regular, in shape: some Shape) -> some View {
        if #available(iOS 26, tvOS 26, macOS 26, visionOS 26, *) {
            glassEffect(style.resolvedGlass, in: shape)
        } else {
            switch style {
            case let .tintedInteractive(color):
                background(color, in: shape)
            case .regular, .regularInteractive:
                background(GlassFallback.regular, in: shape)
            }
        }
    }
}

@available(iOS 26, tvOS 26, macOS 26, visionOS 26, *)
private extension GlassEffectStyle {
    var resolvedGlass: Glass {
        switch self {
        case .regular: .regular
        case .regularInteractive: .regular.interactive()
        case let .tintedInteractive(color): .regular.tint(color).interactive()
        }
    }
}
