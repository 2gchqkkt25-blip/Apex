//
//  ChannelLogoView.swift
//  Apex
//
//  Live TV channel logos use a plain `UIImage(data:)` loader (see
//  `ChannelLogoLoader`) — the same approach every other IPTV app uses.
//

import SwiftUI

struct ChannelLogoView: View {
    let url: URL?
    var size: CGFloat = 60
    var width: CGFloat?
    var height: CGFloat?
    var cornerRadius: CGFloat = 8
    var contentPadding: CGFloat = 8

    var body: some View {
        ChannelLogoContent(
            url: url,
            size: size,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            contentPadding: contentPadding
        )
        // Reset load state when a `List` cell is recycled for another channel.
        .id(url?.absoluteString ?? "nil")
    }
}

// MARK: - Content

private struct ChannelLogoContent: View {
    let url: URL?
    let size: CGFloat
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    @State private var loadedImage: PlatformImage?
    @State private var failed = false

    private var frameWidth: CGFloat { width ?? size }
    private var frameHeight: CGFloat { height ?? size }

    /// Memory/disk hit available synchronously — critical for long category lists
    /// where SwiftUI cancels `.task` before async loads finish.
    private var resolvedImage: PlatformImage? {
        loadedImage ?? url.flatMap { ChannelLogoLoader.cachedImage(for: $0) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(logoPlate)

            if let resolvedImage {
                // `UIImageView` via `PlatformImageView` — SwiftUI `Image(uiImage:)`
                // often draws blank inside `LazyVStack` / `ScrollView` on iOS.
                PlatformImageView(image: resolvedImage)
                    .frame(
                        width: max(frameWidth - contentPadding * 2, 1),
                        height: max(frameHeight - contentPadding * 2, 1)
                    )
            } else if failed || url == nil {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: min(frameWidth, frameHeight) * 0.34))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url?.absoluteString) { await loadIfNeeded() }
    }

    private var logoPlate: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.30), Color(white: 0.14)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadIfNeeded() async {
        failed = url == nil
        guard let url else {
            loadedImage = nil
            return
        }

        if let cached = ChannelLogoLoader.cachedImage(for: url) {
            loadedImage = cached
            return
        }

        loadedImage = nil
        let target = url
        do {
            let image = try await ChannelLogoLoader.image(for: target)
            guard target == url else { return }
            loadedImage = image
        } catch is CancellationError {
            // List scrolled — keep showing the sync cache via `resolvedImage`.
        } catch {
            failed = true
        }
    }
}
