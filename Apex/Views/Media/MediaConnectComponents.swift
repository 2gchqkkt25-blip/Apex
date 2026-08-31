//
//  MediaConnectComponents.swift
//  Apex
//
//  Shared connect / empty-state UI for Jellyfin, Emby, and Plex on every platform.
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

// MARK: - Metrics

enum MediaConnectMetrics {
    static var horizontalPadding: CGFloat {
        #if os(tvOS)
        20
        #elseif os(macOS)
        28
        #else
        20
        #endif
    }

    static var verticalPadding: CGFloat {
        #if os(tvOS)
        48
        #else
        32
        #endif
    }

    static var sectionSpacing: CGFloat {
        #if os(tvOS)
        32
        #else
        28
        #endif
    }

    static var titleFontSize: CGFloat {
        #if os(tvOS)
        42
        #elseif os(macOS)
        34
        #else
        28
        #endif
    }

    static var secondaryFontSize: CGFloat {
        #if os(tvOS)
        20
        #else
        15
        #endif
    }

    static var rowFontSize: CGFloat {
        #if os(tvOS)
        26
        #else
        17
        #endif
    }

    static var labelFontSize: CGFloat {
        #if os(tvOS)
        18
        #else
        13
        #endif
    }

    static var pinFontSize: CGFloat {
        #if os(tvOS)
        56
        #else
        36
        #endif
    }

    static var contentMaxWidth: CGFloat {
        #if os(tvOS)
        760
        #else
        560
        #endif
    }

    static var rowCornerRadius: CGFloat {
        #if os(tvOS)
        10
        #else
        12
        #endif
    }
}

// MARK: - Empty state

struct MediaConnectEmptyState: View {
    let onSelect: (MediaServerKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MediaConnectMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect Your Media")
                        .font(.system(size: MediaConnectMetrics.titleFontSize, weight: .bold))
                    Text("Link Jellyfin, Emby, or Plex to browse movies and TV from your home network.")
                        .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, MediaConnectMetrics.horizontalPadding)

                MediaConnectSectionLabel("Choose a Service")
                VStack(spacing: 12) {
                    ForEach(MediaServerKind.allCases) { kind in
                        Button {
                            onSelect(kind)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: kind.systemImage)
                                    .frame(width: 28)
                                Text(kind.displayName)
                                Spacer(minLength: 16)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: MediaConnectMetrics.secondaryFontSize, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(MediaConnectRowButtonStyle())
                    }
                }
                .padding(.horizontal, MediaConnectMetrics.horizontalPadding)

                Text(footerHint)
                    .font(.system(size: MediaConnectMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
            }
            .padding(.vertical, MediaConnectMetrics.verticalPadding)
            .frame(maxWidth: MediaConnectMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .mediaConnectScreenBackground()
    }

    private var footerHint: LocalizedStringKey {
        #if os(tvOS)
        "Media libraries are separate from your IPTV playlists. After connecting, use Sync to import titles."
        #else
        "Media libraries stay separate from your IPTV playlists."
        #endif
    }
}

// MARK: - Section label

struct MediaConnectSectionLabel: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: MediaConnectMetrics.labelFontSize, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
            .padding(.bottom, 4)
    }
}

// MARK: - Field

enum MediaConnectFieldKind {
    case plain
    case url
    case username
    case password
    case name
}

struct MediaConnectField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure: Bool = false
    var kind: MediaConnectFieldKind = .plain

    #if os(tvOS)
        @State private var showClipboardActions = false

        private var canCopy: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var canPaste: Bool {
            ApexTextClipboard.shared.canPaste
        }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: MediaConnectMetrics.labelFontSize, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MediaConnectMetrics.horizontalPadding)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: MediaConnectMetrics.rowFontSize))
            #if os(iOS)
            .textInputAutocapitalization(isSecure || kind == .url ? .never : .sentences)
            .keyboardType(kind == .url ? .URL : .default)
            .autocorrectionDisabled()
            .textContentType(uiContentType)
            #elseif os(tvOS)
            .textContentType(uiContentType)
            #endif
            .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
            .padding(.vertical, fieldVerticalPadding)
            #if os(tvOS)
            .onLongPressGesture(minimumDuration: 0.4) {
                guard canCopy || canPaste || !text.isEmpty else { return }
                showClipboardActions = true
            }
            .confirmationDialog("Copy or Paste", isPresented: $showClipboardActions, titleVisibility: .visible) {
                if canCopy {
                    Button("Copy") { ApexTextClipboard.shared.copy(text) }
                }
                if canPaste {
                    Button("Paste") {
                        if let pasted = ApexTextClipboard.shared.paste() {
                            text = pasted
                        }
                    }
                }
                if !text.isEmpty {
                    Button("Clear", role: .destructive) { text = "" }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("In-app only — Apple TV has no system clipboard.")
            }
            #else
            .background(fieldBackground, in: RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius))
            .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
            #endif
        }
    }

    private var fieldVerticalPadding: CGFloat {
        #if os(tvOS)
        0
        #else
        10
        #endif
    }

    private var fieldBackground: some ShapeStyle {
        AnyShapeStyle(MediaConnectColors.rowFill)
    }

    #if canImport(UIKit)
    private var uiContentType: UITextContentType? {
        switch kind {
        case .plain: nil
        case .url: .URL
        case .username: .username
        case .password: .password
        case .name: .name
        }
    }
    #endif
}

// MARK: - Colors

enum MediaConnectColors {
    static var rowFill: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(tvOS)
        Color.clear
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

// MARK: - Button styles

struct MediaConnectRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MediaConnectRowButtonStyleBody(configuration: configuration)
    }

    private struct MediaConnectRowButtonStyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            #if os(tvOS)
            configuration.label
                .font(.system(size: MediaConnectMetrics.rowFontSize))
                .foregroundStyle(isFocused ? .black : .white)
                .padding(.horizontal, MediaConnectMetrics.horizontalPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .fill(isFocused ? Color.white.opacity(0.95) : Color.white.opacity(0.05))
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
            #else
            configuration.label
                .font(.system(size: MediaConnectMetrics.rowFontSize))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .fill(MediaConnectColors.rowFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), lineWidth: 1)
                )
            #endif
        }
    }
}

struct MediaConnectPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MediaConnectPrimaryButtonStyleBody(configuration: configuration)
    }

    private struct MediaConnectPrimaryButtonStyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            #if os(tvOS)
            configuration.label
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isFocused ? .black : .white)
                .opacity(isEnabled ? 1 : 0.4)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .fill(isFocused ? AnyShapeStyle(Color.white.opacity(0.95)) : AnyShapeStyle(Color.white.opacity(0.16)))
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
            #else
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .frame(minWidth: 120)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .opacity(isEnabled ? 1 : 0.5)
                .background(.tint, in: RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius))
                .foregroundStyle(.white)
            #endif
        }
    }
}

struct MediaConnectSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MediaConnectSecondaryButtonStyleBody(configuration: configuration)
    }

    private struct MediaConnectSecondaryButtonStyleBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            #if os(tvOS)
            configuration.label
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isFocused ? .black : .white)
                .opacity(isEnabled ? 1 : 0.4)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .fill(isFocused ? AnyShapeStyle(Color.white.opacity(0.95)) : AnyShapeStyle(Color.white.opacity(0.06)))
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
            #else
            configuration.label
                .font(.system(size: 17, weight: .medium))
                .frame(minWidth: 120)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .opacity(isEnabled ? 1 : 0.5)
                .background(
                    RoundedRectangle(cornerRadius: MediaConnectMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
            #endif
        }
    }
}

// MARK: - Screen chrome

extension View {
    @ViewBuilder
    func mediaConnectScreenBackground() -> some View {
        #if os(tvOS)
        tvSettingsBackground()
        #else
        background(Color.platformSurface)
        #endif
    }

    func mediaConnectContentWidth() -> some View {
        padding(.vertical, MediaConnectMetrics.verticalPadding)
            .frame(maxWidth: MediaConnectMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension MediaServerKind {
    var connectBlurb: String {
        switch self {
        case .jellyfin:
            "Browse movies and TV from your Jellyfin library in the Media tab — separate from IPTV playlists."
        case .emby:
            "Browse movies and TV from your Emby library in the Media tab — separate from IPTV playlists."
        case .plex:
            "Sign in with Plex, choose your media server, and sync your libraries into the Media tab."
        }
    }
}
