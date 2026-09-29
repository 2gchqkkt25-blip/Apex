//
//  StreamVersionPickerView.swift
//  Apex
//
//  Shown when a Jellyfin server (AIOStreams) returns more than one playable
//  version for the item the viewer just chose. Each row is one addon stream.
//  The list is a small floating window, not a full-screen page.
//

import SwiftUI

struct StreamVersionPickerView: View {
    let title: String
    let choices: [StreamVersionChoice]
    let onSelect: (StreamVersionChoice) -> Void
    let onClose: () -> Void

    #if os(tvOS)
        @FocusState private var focusedID: String?
    #endif

    var body: some View {
        ZStack {
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()

            window
        }
        #if os(tvOS)
        .onAppear { focusedID = choices.first?.id }
        .onExitCommand(perform: onClose)
        #endif
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            FittingScrollView(maxHeight: listMaxHeight) {
                VStack(spacing: 8) {
                    ForEach(choices) { choice in
                        versionButton(choice)
                    }
                }
            }
        }
        .padding(panelPadding)
        .frame(maxWidth: windowWidth)
        #if os(tvOS)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        #else
        .glassEffectCompat(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        #endif
        .padding(.horizontal, 28)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a source")
                    .font(headingFont)
                    .foregroundStyle(.white)
                if !title.isEmpty {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Text("\(MediaServerAudioLanguage.current.title) audio is marked")
                    .font(captionFont)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            closeButton
        }
    }

    @ViewBuilder
    private func versionButton(_ choice: StreamVersionChoice) -> some View {
        Button {
            onSelect(choice)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if choice.matchesLanguage {
                        Image(systemName: "checkmark.circle.fill")
                            .font(badgeFont)
                    }
                    Text(choice.label)
                        .font(rowFont)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                if !choice.detail.isEmpty {
                    Text(choice.detail)
                        .font(detailFont)
                        .opacity(0.75)
                        .multilineTextAlignment(.leading)
                        .lineLimit(detailLineLimit)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(tvOS)
        .buttonStyle(CompactVersionButtonStyle())
        .focused($focusedID, equals: choice.id)
        #else
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        #endif
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(closeFont)
                .frame(width: closeSize, height: closeSize)
                .background(.white.opacity(0.14), in: Circle())
        }
        #if os(tvOS)
        .buttonStyle(CompactCloseButtonStyle())
        #else
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        #endif
    }

    #if os(tvOS)
        private var panelPadding: CGFloat { 16 }
        private var scrimOpacity: Double { 0.72 }
        private var windowWidth: CGFloat { 620 }
        private var listMaxHeight: CGFloat { 340 }
        private var headingFont: Font { .system(size: 26, weight: .bold) }
        private var titleFont: Font { .system(size: 18, weight: .medium) }
        private var captionFont: Font { .system(size: 15, weight: .medium) }
        private var rowFont: Font { .system(size: 20, weight: .semibold) }
        private var detailFont: Font { .system(size: 15, weight: .regular) }
        private var badgeFont: Font { .system(size: 16, weight: .semibold) }
        private var closeFont: Font { .system(size: 16, weight: .bold) }
        private var closeSize: CGFloat { 36 }
        private var detailLineLimit: Int { 2 }
    #else
        private var panelPadding: CGFloat { 18 }
        private var scrimOpacity: Double { 0.35 }
        private var windowWidth: CGFloat { 480 }
        private var listMaxHeight: CGFloat { 360 }
        private var headingFont: Font { .headline }
        private var titleFont: Font { .subheadline }
        private var captionFont: Font { .caption }
        private var rowFont: Font { .subheadline.weight(.semibold) }
        private var detailFont: Font { .caption }
        private var badgeFont: Font { .caption.weight(.semibold) }
        private var closeFont: Font { .caption.weight(.bold) }
        private var closeSize: CGFloat { 28 }
        private var detailLineLimit: Int { 4 }
    #endif
}

/// Scrolls only once the rows are taller than `maxHeight`. Shorter lists stay
/// as tall as their content, so the window does not stretch to fill the player.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(maxHeight: maxHeight)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if os(tvOS)
    private struct CompactCloseButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            CompactBody(configuration: configuration)
        }

        private struct CompactBody: View {
            let configuration: ButtonStyleConfiguration
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .background(isFocused ? Color.white : Color.clear, in: Circle())
            }
        }
    }

    private struct CompactVersionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            CompactBody(configuration: configuration)
        }

        private struct CompactBody: View {
            let configuration: ButtonStyleConfiguration
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isFocused ? Color.white : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
        }
    }
#endif
