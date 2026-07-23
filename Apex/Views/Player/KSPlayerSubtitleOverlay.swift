//
//  KSPlayerSubtitleOverlay.swift
//  Apex
//
//  Renders KSPlayer's `SubtitleModel` over the video surface. The stock
//  `KSVideoPlayerView` includes `VideoSubtitleView`, but Apex drives playback
//  through the lower-level `KSVideoPlayer` representable plus custom controls,
//  so this overlay is required for selected subtitles to actually appear.
//

import KSPlayer
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct KSPlayerSubtitleOverlay: View {
    @ObservedObject var model: SubtitleModel
    var controlsVisible = false

    private let appearance = SubtitleAppearance.current

    var body: some View {
        ZStack {
            ForEach(model.parts) { part in
                partView(part)
            }
        }
        .allowsHitTesting(false)
    }

    private func partView(_ part: SubtitlePart) -> some View {
        VStack {
            if let image = part.image {
                Spacer()
                subtitleImage(image)
                    .padding()
            } else if let text = part.text {
                SubtitleOverlayLayout(appearance: appearance, controlsVisible: controlsVisible) {
                    Text(AttributedString(text))
                        .font(.system(size: appearance.fontSize, weight: .medium))
                        .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                        .foregroundStyle(appearance.textColor)
                        .italic(SubtitleModel.textItalic)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(.black.opacity(appearance.backgroundOpacity), in: RoundedRectangle(cornerRadius: 6))
                    #if !os(tvOS)
                        .textSelection(.enabled)
                    #endif
                }
            } else {
                Text("")
            }
        }
    }

    @ViewBuilder
    private func subtitleImage(_ image: UIImage) -> some View {
        #if canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        #elseif canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        #endif
    }
}
