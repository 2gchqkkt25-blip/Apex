//
//  ApexBrandColors.swift
//  Apex
//
//  Logo-matched palette — electric blue → vivid purple/magenta gradient.
//

import SwiftUI

enum ApexBrandColors {
    static let blue = Color(hex: "0070FF")
    static let purple = Color(hex: "A020F0")
    static let magenta = Color(hex: "C020E0")

    static var logoGradient: LinearGradient {
        LinearGradient(
            colors: [blue, purple, magenta],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var heroGlow: RadialGradient {
        RadialGradient(
            colors: [blue.opacity(0.28), purple.opacity(0.14), .clear],
            center: .top,
            startRadius: 24,
            endRadius: 440
        )
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "04040A"),
                Color(hex: "0A0A14"),
                Color(hex: "100818"),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
