//
//  AppearanceSettingsView.swift
//  Apex
//
//  Theme picker with live preview cards.  Selecting a theme updates the
//  global accent and surface colours immediately.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        #if os(tvOS)
            tvBody
        #else
            standardBody
        #endif
    }

    #if os(tvOS)
        private var tvBody: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Theme")

                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    ThemeRow(
                        theme: theme,
                        isSelected: themeManager.theme == theme,
                        onSelect: { themeManager.selectTheme(theme) }
                    )
                }

                Text("The System theme follows your device Light / Dark appearance. Custom themes use their own accent colour palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    #else
        private var standardBody: some View {
            Form {
                Section {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        ThemeRow(
                            theme: theme,
                            isSelected: themeManager.theme == theme,
                            onSelect: { themeManager.selectTheme(theme) }
                        )
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    Text("The System theme follows your device Light / Dark appearance. Custom themes use their own accent colour palette.")
                }
            }
            .navigationTitle("Appearance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    #endif
}

// MARK: - Theme row

private struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ThemePreview(theme: theme, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(theme.colors.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.vertical, 6)
        }
        #if os(tvOS)
            .buttonStyle(TVSettingsRowButtonStyle())
        #else
            .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Theme preview card

struct ThemePreview: View {
    let theme: AppTheme
    var size: CGFloat = 64

    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            // Background
            themeBackgroundView

            VStack(spacing: size * 0.1) {
                // Accent swatches
                HStack(spacing: size * 0.08) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                            .fill(theme.colors.accent)
                            .frame(width: size * 0.2, height: size * 0.2)
                    }
                }

                // Sample text bars
                RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                    .fill(theme == .system ? .secondary : theme.colors.textPrimary.opacity(0.8))
                    .frame(width: size * 0.7, height: size * 0.12)

                RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                    .fill(theme == .system ? .secondary.opacity(0.5) : theme.colors.textSecondary.opacity(0.5))
                    .frame(width: size * 0.5, height: size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var themeBackgroundView: some View {
        if theme == .system {
            #if os(tvOS)
                Color(white: 0.09)
            #elseif os(macOS)
                Color(nsColor: .windowBackgroundColor)
            #else
                Color(uiColor: .systemGroupedBackground)
            #endif
        } else if theme.colors.prefersGlass {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(GlassFallback.regular)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.colors.surface)
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        NavigationStack {
            AppearanceSettingsView()
                .environment(ThemeManager.shared)
        }
    }
#endif
